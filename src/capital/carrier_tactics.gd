class_name CarrierTactics
extends RefCounted
## What a weaponless carrier decides in a raid (M12-T19, Q30; the retreat rules of M8-T08, D83): it hangs back at a
## stand-off and shows an attacker its stern; its fighters go home when few of the raid are left, or one by one when badly
## hurt; it flees when it has taken its share of damage, when its raid is over or when every surviving fighter has docked.
## Fleeing is a jump through its own point once its drive has recharged, else a run for the jumpgate. Pure: numbers in, a
## decision out; `CarrierJumps` flies it.

## Options a raid's `carrier` data may set, with their defaults. A faction's doctrine (`CapitalData.doctrine`) comes
## between the two.
const DEFAULTS: Dictionary = {
	"arrival": "beside",  # how its fighters come in: "docked" on its cradles, or "beside" it out of its point (Q29)
	"standoff_m": 2500.0,  # it keeps this far from the nearest enemy
	"recall_left": 3,  # its fighters all go home once this few of the raid are left in the fight (D83)
	"fighter_return_hull": 0.2,  # a fighter under this share of its hull goes home alone (D83)
	"retreat_hull": 0.5,  # it flees once its hull is down to this share (D83)
	"wait_s": 90.0,  # once it flees, fighters not docked within this long are left behind (Q27, Q30)
	"raid_s": 0.0,  # the raid is over after this long; 0: no time limit
	"flee_mps": 60.0,  # its speed while it runs with its drive still recharging
	"grid_margin_m": 2000.0,  # it keeps this far outside the reach of a hostile station's guns
	"wing_keepout_m": 4000.0,  # and this far from a group of hostile fighters:
	"wing_size": 2,  # this many of them
	"wing_span_m": 1500.0,  # within this of one another,
	"watch_m": 15000.0,  # seen within this of the carrier
	"weave_mps": 12.0,  # it never sits still: the speed of its weave,
	"weave_period_s": 90.0,  # and how long one turn of it takes
	"attack_memory_s": 15.0,  # hit within this long, it is under attack
	"danger_weight": 4.0,  # on a run, a second inside a keep-out counts as this many seconds of flying
}
const ARRIVAL_DOCKED: StringName = &"docked"
const ARRIVAL_BESIDE: StringName = &"beside"
## It starts to move off this share of the stand-off before an enemy reaches it, and is at full speed at that share inside.
const EASE_SHARE: float = 0.25

## Why a carrier flees (`flee_reason`); empty while it stays.
const STAYS: StringName = &""
const FLEE_HURT: StringName = &"hurt"
const FLEE_RAID_OVER: StringName = &"raid_over"
const FLEE_ALL_DOCKED: StringName = &"all_docked"
## What a fleeing carrier does now (`flee_move`).
const MOVE_WAIT: StringName = &"wait"
const MOVE_JUMP: StringName = &"jump"
const MOVE_GATE: StringName = &"gate"
const MOVE_RUN: StringName = &"run"
## Inside a keep-out it is pushed out at no less than this share of its speed (more the deeper it is).
const KEEP_OUT_MIN: float = 0.5
## Its weave's direction wobbles this many radians about its steady turn, over this share of the weave's period.
const WEAVE_WOBBLE: float = 0.5
const WEAVE_WOBBLE_SHARE: float = 0.61
## A run looks at this many ways round each keep-out, passing at this share of its radius, and takes a way round only when
## it saves at least this many seconds of cost (so it does not flip between two near-equal routes).
const ROUND_WAYS: int = 8
const ROUND_SHARE: float = 1.15
const ROUTE_GAIN_S: float = 5.0
## A carrier running for a gate from beside or behind it keeps this many mouth radii off its axis until it is in front,
## and counts as on the run-in within `GATE_AXIS_RADII` of the axis.
const GATE_CLEAR_RADII: float = 2.5
const GATE_AXIS_RADII: float = 0.4


## The raid's options: `given` over the faction's `doctrine` over the defaults, numbers kept in range. Unknown keys are
## kept for the caller.
static func options(given: Dictionary, doctrine: Dictionary = {}) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate()
	for layer: Dictionary in [doctrine, given]:
		for key: Variant in layer:
			out[key] = layer[key]
	out["arrival"] = String(ARRIVAL_DOCKED) if String(out["arrival"]) == String(ARRIVAL_DOCKED) else String(ARRIVAL_BESIDE)
	out["standoff_m"] = maxf(float(out["standoff_m"]), 0.0)
	out["recall_left"] = maxi(int(out["recall_left"]), 0)
	out["retreat_hull"] = clampf(float(out["retreat_hull"]), 0.0, 1.0)
	out["wait_s"] = maxf(float(out["wait_s"]), 0.0)
	out["raid_s"] = maxf(float(out["raid_s"]), 0.0)
	out["fighter_return_hull"] = clampf(float(out["fighter_return_hull"]), 0.0, 1.0)
	out["flee_mps"] = maxf(float(out["flee_mps"]), 0.0)
	for key: String in ["grid_margin_m", "wing_keepout_m", "wing_span_m", "watch_m", "weave_mps", "attack_memory_s", "danger_weight"]:
		out[key] = maxf(float(out[key]), 0.0)
	out["wing_size"] = maxi(int(out["wing_size"]), 1)
	out["weave_period_s"] = maxf(float(out["weave_period_s"]), 1.0)
	return out


## The velocity the carrier holds against the frame's rest: none while the nearest enemy (`threat`, the vector to it) is
## outside the stand-off, away from it at up to `speed_mps` once it is inside.
static func cruise(threat: Vector3, has_threat: bool, standoff_m: float, speed_mps: float) -> Vector3:
	if not has_threat or standoff_m <= 0.0:
		return Vector3.ZERO
	var distance: float = threat.length()
	var band: float = maxf(EASE_SHARE * standoff_m, 1.0)
	var push: float = clampf((standoff_m - distance) / band, 0.0, 1.0)
	if push <= 0.0 or distance < 1e-3:
		return Vector3.ZERO
	return -threat / distance * speed_mps * push


## The way the bow should point: away from an enemy inside the stand-off (its stern to the attacker), else zero (it keeps
## the heading it has).
static func heading(threat: Vector3, has_threat: bool, standoff_m: float) -> Vector3:
	if not has_threat or threat.length() >= standoff_m or threat.length() < 1e-3:
		return Vector3.ZERO
	return -threat.normalized()


## Whether a raid's fighters all go home (D83): only `recall_left` of them are left in the fight. A raid that came with no
## more than that is not called back on arrival: it goes home at its first loss.
static func recall_all(brought: int, fighting: int, recall_left: int) -> bool:
	return fighting > 0 and fighting <= recall_left and fighting < brought


## Whether one fighter goes home alone (D83): its hull is under its share.
static func fighter_goes_home(hull_fraction: float, fighter_return_hull: float) -> bool:
	return hull_fraction < fighter_return_hull


## Whether the raid is over: ended by its script, or past its time limit.
static func raid_over(ended: bool, elapsed_s: float, raid_s: float) -> bool:
	return ended or (raid_s > 0.0 and elapsed_s >= raid_s)


## Why the carrier flees now (D83), or `STAYS`: it has taken its share of damage, its raid is over, or every surviving
## fighter of the `brought` has docked (none `fighting`, none `returning`).
static func flee_reason(hull_fraction: float, retreat_hull: float, over: bool, brought: int, fighting: int,
		returning: int) -> StringName:
	if hull_fraction <= retreat_hull:
		return FLEE_HURT
	if over:
		return FLEE_RAID_OVER
	if brought > 0 and fighting + returning <= 0:
		return FLEE_ALL_DOCKED
	return STAYS


## Whether the carrier stops waiting for its fighters: nobody is still on the way back, or their time is up.
static func should_leave(returning: int, waited_s: float, wait_s: float) -> bool:
	return returning <= 0 or waited_s >= wait_s


## What a fleeing carrier does now (D83): with its drive recharged it waits for its fighters, up to their limit, and jumps
## through its own point; with the drive still recharging it runs for the jumpgate, which needs no drive, or with no gate
## away from the enemy until the drive is ready.
static func flee_move(drive_ready: bool, has_gate: bool, returning: int, waited_s: float, wait_s: float) -> StringName:
	if drive_ready:
		return MOVE_JUMP if should_leave(returning, waited_s, wait_s) else MOVE_WAIT
	return MOVE_GATE if has_gate else MOVE_RUN


## Where a carrier running for a gate steers now, in the gate's frame (the mouth at the origin, ships leave along +Z from
## `departure_z` in front of it): out round the gate's side when it is beside or behind the mouth, onto the axis in front,
## then through the mouth's centre.
static func gate_run_target(local: Vector3, departure_z: float, radius_m: float) -> Vector3:
	var lateral := Vector2(local.x, local.y)
	var off_axis_m: float = lateral.length()
	if local.z < 0.0 and off_axis_m <= GATE_AXIS_RADII * radius_m:
		return Vector3(0.0, 0.0, radius_m)
	if local.z <= 0.5 * departure_z:
		return Vector3(0.0, 0.0, departure_z)
	var side: Vector2 = lateral / off_axis_m if off_axis_m > 1.0 else Vector2.RIGHT
	var clear_m: float = GATE_CLEAR_RADII * radius_m
	if off_axis_m < 0.9 * clear_m:
		return Vector3(side.x * clear_m, side.y * clear_m, local.z)
	return Vector3(side.x * clear_m, side.y * clear_m, departure_z)


## Whether it throws every docked fighter out at once (M8-T08, the maintainer 2026-11-20): under attack, with a drive that
## cannot take it away. While that lasts it calls nobody home either.
static func cornered(under_attack: bool, drive_ready: bool) -> bool:
	return under_attack and not drive_ready


## The slow weave it flies on top of whatever else it does, so it never sits still: a velocity of `speed_mps` whose
## direction turns once in about `period_s`, on a plane and from a phase its own `seed_value` gives. Sim time in.
static func weave(seed_value: int, t_s: float, speed_mps: float, period_s: float) -> Vector3:
	var u: float = _unit(seed_value, 1)
	var v: float = _unit(seed_value, 2)
	var z: float = 2.0 * u - 1.0
	var r: float = sqrt(maxf(1.0 - z * z, 0.0))
	var a := Vector3(r * cos(TAU * v), z, r * sin(TAU * v))
	var b: Vector3 = a.cross(Vector3.UP if absf(a.y) < 0.9 else Vector3.RIGHT).normalized()
	var turn: float = TAU * (t_s / period_s + _unit(seed_value, 3))
	turn += WEAVE_WOBBLE * sin(TAU * (t_s / (WEAVE_WOBBLE_SHARE * period_s) + _unit(seed_value, 4)))
	return (a * cos(turn) + b * sin(turn)) * speed_mps


## Which way, and how hard (0 to 1), it is pushed out of the places it keeps away from: spheres of `radii` round
## `centres` (a hostile station's guns and their margin, groups of hostile fighters). Zero outside them all.
static func keep_out(at: Vector3, centres: PackedVector3Array, radii: PackedFloat32Array) -> Vector3:
	var push := Vector3.ZERO
	for i: int in centres.size():
		var off: Vector3 = at - centres[i]
		var d: float = off.length()
		if d >= radii[i]:
			continue
		var depth: float = clampf((radii[i] - d) / maxf(EASE_SHARE * radii[i], 1.0), 0.0, 1.0)
		push += (off / d if d > 1e-3 else Vector3.UP) * lerpf(KEEP_OUT_MIN, 1.0, depth)
	return push.limit_length(1.0)


## Seconds a straight flight from `from` to `to` at `speed_mps` spends inside the keep-outs.
static func time_inside(from: Vector3, to: Vector3, centres: PackedVector3Array, radii: PackedFloat32Array,
		speed_mps: float) -> float:
	var line: Vector3 = to - from
	var length: float = line.length()
	if length < 1e-3 or speed_mps <= 0.0:
		return 0.0
	var inside_m: float = 0.0
	for i: int in centres.size():
		# The stretch of the line inside this sphere: between the two roots of |from + t line - centre| = radius.
		var off: Vector3 = from - centres[i]
		var b: float = off.dot(line) / (length * length)
		var c: float = (off.length_squared() - radii[i] * radii[i]) / (length * length)
		var disc: float = b * b - c
		if disc <= 0.0:
			continue
		var root: float = sqrt(disc)
		inside_m += maxf(clampf(-b + root, 0.0, 1.0) - clampf(-b - root, 0.0, 1.0), 0.0) * length
	return inside_m / speed_mps


## Where a carrier on a run from `from` to `goal` steers now (M8-T08): the goal itself, or a point beside one of the
## keep-outs when going round it costs less. A route costs its flying time plus `danger_weight` times its time inside the
## keep-outs, so with every way dangerous it still takes the least bad one.
static func route_via(from: Vector3, goal: Vector3, centres: PackedVector3Array, radii: PackedFloat32Array, speed_mps: float,
		danger_weight: float) -> Vector3:
	var best: Vector3 = goal
	var best_cost: float = _leg_cost(from, goal, centres, radii, speed_mps, danger_weight)
	var along: Vector3 = (goal - from).normalized() if from.distance_to(goal) > 1e-3 else Vector3.FORWARD
	var side: Vector3 = along.cross(Vector3.UP if absf(along.y) < 0.9 else Vector3.RIGHT).normalized()
	var up: Vector3 = side.cross(along).normalized()
	for i: int in centres.size():
		for k: int in ROUND_WAYS:
			var angle: float = TAU * float(k) / float(ROUND_WAYS)
			var via: Vector3 = centres[i] + (side * cos(angle) + up * sin(angle)) * radii[i] * ROUND_SHARE
			var cost: float = _leg_cost(from, via, centres, radii, speed_mps, danger_weight) \
					+ _leg_cost(via, goal, centres, radii, speed_mps, danger_weight)
			if cost < best_cost - ROUTE_GAIN_S:
				best_cost = cost
				best = via
	return best


static func _leg_cost(from: Vector3, to: Vector3, centres: PackedVector3Array, radii: PackedFloat32Array, speed_mps: float,
		danger_weight: float) -> float:
	return from.distance_to(to) / maxf(speed_mps, 1e-3) + danger_weight * time_inside(from, to, centres, radii, speed_mps)


# A number in [0, 1) from a seed and a salt: the same for the same carrier every time, no shared generator.
static func _unit(seed_value: int, salt: int) -> float:
	return float(hash([seed_value, salt]) & 0xFFFFFF) / float(0x1000000)


## The turn rate the helm asks for, rad/s about each World axis: toward `wanted` from `forward`, eased near it, at most
## `rate_max` (0 with no wanted heading).
static func turn_rate(forward: Vector3, wanted: Vector3, rate_max: float, gain: float = 0.5) -> Vector3:
	if wanted.length() < 1e-3 or forward.length() < 1e-3:
		return Vector3.ZERO
	var f: Vector3 = forward.normalized()
	var w: Vector3 = wanted.normalized()
	var axis: Vector3 = f.cross(w)
	var angle: float = f.angle_to(w)
	if axis.length() < 1e-4:
		if angle < 1.0:
			return Vector3.ZERO
		axis = f.cross(Vector3.UP if absf(f.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT)  # dead astern: any way round
	return axis.normalized() * minf(angle * gain, rate_max)
