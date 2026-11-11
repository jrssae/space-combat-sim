class_name EncounterPlan
extends RefCounted
## When free-flight encounters come and what each one is (architecture §18 D58, Q3, Q12): pure and seeded. Event `i` comes
## at `time_of(i)` of encounter time (an interval apart, within a quarter interval of its slot), and `event(i)` draws its
## kind by weight and its ships. Every draw is a hash of the seed, the event index and what is drawn, never a stepped
## generator, so an event is the same whatever was asked before it (`CLAUDE.md`).
##
## - Raid: 2-6 raiders jumping in 6-12 km from their target (beyond the AI's 5 km sensors), flying at it; half the raids
##   go for a civilian near the player when there is one.
## - Patrol: 2, 4 or 6 allied Starfuries abreast on a straight route through the area, from 26-30 km out (past the
##   player's 25 km radar) to as far out on the other side.
## - Traffic: 1-3 civilian hulls of any of the nine on a straight route passing 2-10 km from the player, from 26-30 km out.

const KINDS: Array[StringName] = [&"raid", &"patrol", &"traffic"]
const DEFAULT_WEIGHTS: Dictionary = {&"raid": 0.4, &"patrol": 0.25, &"traffic": 0.35}
const DEFAULT_INTERVAL_S: float = 120.0
## How far an event may stray from its slot, as a share of the interval: gaps of half to one and a half intervals.
const JITTER: float = 0.25

const RAID_MIN: int = 2
const RAID_MAX: int = 6
## The jump point's range from the target, kept inside 6-12 km with room for the group around it.
const RAID_RANGE_M: Vector2 = Vector2(6200.0, 11800.0)
const RAID_SPEED_MPS: float = 120.0
## Raiders spread around the jump point on a grid this wide.
const RAID_SLOT_M: float = 60.0
const RAID_AT_CIVILIAN_SHARE: float = 0.5
const PATROL_SIZES: Array[int] = [2, 4, 6]
const PATROL_CRUISE_MPS: float = 220.0
const PATROL_PASS_M: Vector2 = Vector2(500.0, 5000.0)
const PATROL_SPACING_M: float = 250.0
const TRAFFIC_MIN: int = 1
const TRAFFIC_MAX: int = 3
const TRAFFIC_CRUISE_MPS: float = 120.0
const TRAFFIC_PASS_M: Vector2 = Vector2(2000.0, 10000.0)
const TRAFFIC_SPACING_M: float = 1000.0
## Where patrols and traffic come in from, and go out to.
const CRUISE_IN_M: Vector2 = Vector2(26100.0, 29900.0)
## Routes and jump points stay within this of the player's horizontal plane.
const MAX_ELEVATION_DEG: float = 30.0
const BOKMAI: StringName = &"brakiri_bokmai"
const MAX_PODS: int = 3

# What each hash draws, so no two draws of one event share a value.
enum Salt { TIME, KIND, COUNT, RANGE, AZIMUTH, ELEVATION, ROLL, PASS, AT_CIVILIAN, PICK, TYPE = 100, PODS = 200, GATE = 300 }
## Ways an event may use the jumpgate (M6-T14): its ships come out of it, or fly out through it.
const GATE_ARRIVE: StringName = &"arrive"
const GATE_DEPART: StringName = &"depart"

var seed_value: int = 0
var interval_s: float = DEFAULT_INTERVAL_S
var weights: Dictionary = DEFAULT_WEIGHTS
## The pools file's `gate` table (M6-T14): {"arrive": {kind: share 0..1}, "depart": {kind: share}}. Empty: no event uses the gate,
## so a file without it plans exactly as before (the gate's draw has its own salt).
var gate_shares: Dictionary = {}


func _init(p_seed: int = 0, p_interval_s: float = DEFAULT_INTERVAL_S, p_weights: Dictionary = DEFAULT_WEIGHTS) -> void:
	seed_value = p_seed
	interval_s = maxf(p_interval_s, 1.0)
	weights = p_weights


## Encounter time (s since encounters started) at which event `index` is due.
func time_of(index: int) -> float:
	return interval_s * (float(index) + 1.0 + JITTER * (2.0 * _unit(index, Salt.TIME) - 1.0))


## How many events are due by `now_s`: the first index not yet due.
func count_due(now_s: float) -> int:
	# Every event before this one is due for certain, so only a few are tested.
	var k: int = maxi(0, floori(now_s / interval_s - 1.0 - JITTER))
	while time_of(k) <= now_s:
		k += 1
	return k


## Event `index`, of the kind its weights draw or of `kind` when given (the console's `force`).
func event(index: int, kind: StringName = &"") -> EncounterEvent:
	var e := EncounterEvent.new()
	e.index = index
	e.time_s = time_of(index)
	e.kind = kind if KINDS.has(kind) else _draw_kind(index)
	match e.kind:
		&"raid":
			_plan_raid(e)
		&"patrol":
			_plan_cruise(e, ShipPool.ALLY_TYPE, PATROL_SIZES[mini(floori(_unit(index, Salt.COUNT) * 3.0), 2)],
					PATROL_PASS_M, PATROL_SPACING_M, PATROL_CRUISE_MPS)
		_:
			_plan_cruise(e, &"", TRAFFIC_MIN + mini(floori(_unit(index, Salt.COUNT) * 3.0), TRAFFIC_MAX - TRAFFIC_MIN),
					TRAFFIC_PASS_M, TRAFFIC_SPACING_M, TRAFFIC_CRUISE_MPS)
	return e


## Ships of an event of `wanted` that may start now with `alive` of the encounters' ships in play under `cap`: all of them
## when they fit, none (it waits) when they do not, and an event bigger than the whole cap trimmed to it once nothing
## else is in play, so it cannot wait for ever.
static func admit(alive: int, wanted: int, cap: int) -> int:
	if alive + wanted <= cap:
		return wanted
	if wanted > cap and alive == 0:
		return maxi(cap, 0)
	return 0


func _draw_kind(index: int) -> StringName:
	var total: float = 0.0
	for kind: StringName in KINDS:
		total += maxf(float(weights.get(kind, 0.0)), 0.0)
	if total <= 0.0:
		return KINDS[0]
	var pick: float = _unit(index, Salt.KIND) * total
	for kind: StringName in KINDS:
		var w: float = maxf(float(weights.get(kind, 0.0)), 0.0)
		if pick < w:
			return kind
		pick -= w
	for i: int in range(KINDS.size() - 1, -1, -1):  # the rounding's last sliver goes to the last weighted kind
		if float(weights.get(KINDS[i], 0.0)) > 0.0:
			return KINDS[i]
	return KINDS[0]


# The raiders around one jump point, each flying at the target.
func _plan_raid(e: EncounterEvent) -> void:
	var i: int = e.index
	var n: int = RAID_MIN + mini(floori(_unit(i, Salt.COUNT) * float(RAID_MAX - RAID_MIN + 1)), RAID_MAX - RAID_MIN)
	var dir: Vector3 = _direction(i)
	var centre: Vector3 = dir * lerpf(RAID_RANGE_M.x, RAID_RANGE_M.y, _unit(i, Salt.RANGE))
	var side: Vector3 = _perpendicular(dir, 0.0)
	var up: Vector3 = dir.cross(side)
	e.jumps = true
	e.anchor = EncounterEvent.ANCHOR_TARGET
	e.at_civilian = _unit(i, Salt.AT_CIVILIAN) < RAID_AT_CIVILIAN_SHARE
	e.target_pick = _unit(i, Salt.PICK)
	e.cruise_mps = RAID_SPEED_MPS
	for k: int in n:
		var at: Vector3 = centre + side * float(k % 3 - 1) * RAID_SLOT_M + up * float(k / 3) * RAID_SLOT_M
		e.types.append(ShipPool.DEFAULT_TYPE)
		e.cargo_pods.append(-1)
		e.positions.append(at)
		e.velocities.append(-at.normalized() * RAID_SPEED_MPS)
		e.routes.append(PackedVector3Array())


# Ships on parallel straight routes: each passes the player at its own distance (spaced out from the first), starting and
# ending the same distance out on either side, already at cruise along the route. `type` empty: a civilian hull a ship.
func _plan_cruise(e: EncounterEvent, type: StringName, n: int, pass_m: Vector2, spacing_m: float, cruise_mps: float) -> void:
	var i: int = e.index
	var heading: Vector3 = _direction(i)
	var out: Vector3 = _perpendicular(heading, TAU * _unit(i, Salt.ROLL))
	var first_pass: float = lerpf(pass_m.x, pass_m.y - spacing_m * float(n - 1), _unit(i, Salt.PASS))
	var far: float = lerpf(CRUISE_IN_M.x, CRUISE_IN_M.y, _unit(i, Salt.RANGE))
	e.cruise_mps = cruise_mps
	for k: int in n:
		var closest: Vector3 = out * (first_pass + spacing_m * float(k))
		var half: float = sqrt(far * far - closest.length_squared())
		var ship_type: StringName = type
		var pods: int = -1
		if ship_type == &"":
			var types: Array[StringName] = ShipCatalog.CIVILIAN_TYPES
			ship_type = types[mini(floori(_unit(i, Salt.TYPE + k) * float(types.size())), types.size() - 1)]
			if ship_type == BOKMAI:
				pods = mini(floori(_unit(i, Salt.PODS + k) * float(MAX_PODS + 1)), MAX_PODS)
		e.types.append(ship_type)
		e.cargo_pods.append(pods)
		e.positions.append(closest - heading * half)
		e.velocities.append(heading * cruise_mps)
		e.routes.append(PackedVector3Array([closest, closest + heading * half]))


# A direction no steeper than `MAX_ELEVATION_DEG`, even over the band.
func _direction(index: int) -> Vector3:
	var azimuth: float = TAU * _unit(index, Salt.AZIMUTH)
	var elevation: float = asin((2.0 * _unit(index, Salt.ELEVATION) - 1.0) * sin(deg_to_rad(MAX_ELEVATION_DEG)))
	return Vector3(cos(elevation) * sin(azimuth), sin(elevation), cos(elevation) * cos(azimuth))


# A unit vector square to `dir`, turned `angle` about it.
static func _perpendicular(dir: Vector3, angle: float) -> Vector3:
	var helper: Vector3 = Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT
	var a: Vector3 = dir.cross(helper).normalized()
	var b: Vector3 = dir.cross(a).normalized()
	return a * cos(angle) + b * sin(angle)


## Whether event `index` of `kind` uses the gate: `GATE_ARRIVE`, `GATE_DEPART` or &"" (the shares are tried in that order on one
## draw, so an arrive share of 0.3 and a depart share of 0.2 split the events 30/20/50). Raids never depart: they came to fight.
func gate_use(index: int, kind: StringName) -> StringName:
	if gate_shares.is_empty():
		return &""
	var arrive: float = clampf(float((gate_shares.get(GATE_ARRIVE, {}) as Dictionary).get(kind, 0.0)), 0.0, 1.0)
	var depart: float = 0.0 if kind == &"raid" else clampf(float((gate_shares.get(GATE_DEPART, {}) as Dictionary).get(kind, 0.0)), 0.0, 1.0)
	var u: float = _unit(index, Salt.GATE)
	if u < arrive:
		return GATE_ARRIVE
	if u < arrive + depart:
		return GATE_DEPART
	return &""


## Reads the pools file's `gate` table into `gate_shares` form; anything malformed counts as 0.
static func parse_gate_shares(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (raw is Dictionary):
		return out
	for way: StringName in [GATE_ARRIVE, GATE_DEPART]:
		var table: Variant = (raw as Dictionary).get(String(way))
		if not (table is Dictionary):
			continue
		var shares: Dictionary = {}
		for kind: StringName in KINDS:
			var v: Variant = (table as Dictionary).get(String(kind), 0.0)
			shares[kind] = clampf(float(v), 0.0, 1.0) if (v is float or v is int) else 0.0
		out[way] = shares
	return out


# 0..1 from the seed, the event and what is drawn.
func _unit(index: int, salt: int) -> float:
	return float(hash([seed_value, index, salt])) / 4294967296.0
