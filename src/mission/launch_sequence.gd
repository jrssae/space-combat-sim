class_name LaunchSequence
extends RefCounted
## One wing's launch from its Cobra arm (M7-T08, D76, AC7; Q3 as corrected): up to twelve Starfuries, six on the racks over the arm's
## six doors (wave 1) and six in the second row (wave 2). Each fighter's door opens, it drops down its rail from the rack and is let
## go at the release point with the drum's surface velocity plus the rail's speed along the drop direction. The second row moves
## onto the racks once they are free and drops `wave_gap_s` after the first wave's last release. Pure: it lives in the drum's frame
## and is told the drum's angle each tick, so a rebase or the drum's turn moves nothing in it.
##
## Hold under the spine (maintainer): the stationary frame passes over each arm once a turn. A drop starts only when the arm stays
## out of every blocked sector (`StationHardpoints.launch_blocked`) from the drop's start to its release; until then the fighter holds
## on its rack and the wave's later drops wait behind it.
##
## Steps and timings come from a `LaunchProfile`, so M8's squadron launch runs this for several wings in turn.

enum Phase { STAGED, MOVING, RACKED, HELD, DROPPING, RELEASED }
enum DoorState { CLOSED, OPENING, OPEN, CLOSING }

const PHASE_NAMES: PackedStringArray = ["staged", "moving", "racked", "held", "dropping", "released"]
const DOOR_NAMES: PackedStringArray = ["closed", "opening", "open", "closing"]
## How finely a drop's sweep of arm angles is checked against the blocked sectors, degrees.
const CLEAR_STEP_DEG: float = 0.5
const EPS_S: float = 1e-6

var valid: bool = false
var error: String = ""
var wing: String = ""
var profile: LaunchProfile = null
## The wing's launch doors (`StationHardpoints.cobra_bays` entries), door 1 first.
var bays: Array[Dictionary] = []
## The arm's outward normal at drum angle 0, degrees (its `cobra_arm` angle).
var arm_angle_deg: float = 0.0
## Seconds since the launch began.
var time_s: float = 0.0
## The drum's turn and spin as last given to `advance`.
var drum_angle: float = 0.0
var spin_rate_rad_s: float = 0.0
## Each fighter: `id`, `bay` (index into `bays`), `wave` (1 or 2), `k` (its place in the wave's order), `phase`, `step_since`,
## `drop_start`, `released_at` (-1 until then), `held_s` (seconds spent holding), `skip`.
var fighters: Array[Dictionary] = []
## Each door (by bay index): `state`, `open` (0 shut to 1 open), `last_release` (-1 until one left).
var doors: Array[Dictionary] = []
## When the first wave's last fighter was let go (-1 until then).
var first_wave_done_s: float = -1.0

var _hardpoints: StationHardpoints = null


## A launch of `ids` from `wing_name`'s arm: the first six take the racks, starting at door `first_door` and going on round the
## arm, and drop in that order; the next six wait in the second row behind the same doors. Check `valid`.
static func create(hardpoints: StationHardpoints, wing_name: String, ids: PackedStringArray, p_profile: LaunchProfile,
		first_door: int = 1, p_drum_angle: float = 0.0, p_spin: float = 0.0) -> LaunchSequence:
	var made := LaunchSequence.new()
	made.error = made._setup(hardpoints, wing_name, ids, p_profile, first_door)
	made.valid = made.error.is_empty()
	made.drum_angle = p_drum_angle
	made.spin_rate_rad_s = p_spin
	return made


## Moves the launch on by `delta` seconds with the drum at `p_drum_angle` (radians about +Z) turning at `p_spin` rad/s. Returns what
## happened, in order: each `{kind, id, bay}` with kind `door_opening`, `door_open`, `door_closing`, `door_closed`, `move`,
## `racked`, `hold`, `drop`, `release`.
func advance(delta: float, p_drum_angle: float, p_spin: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not valid:
		return events
	time_s += delta
	drum_angle = p_drum_angle
	spin_rate_rad_s = p_spin
	_step_doors(delta, events)
	for f: Dictionary in fighters:
		_step_fighter(f, delta, events)
	if first_wave_done_s < 0.0 and _wave_released(1):
		first_wave_done_s = time_s
	return events


## Cuts the fighter `id`'s launch short (the player's skip): it is let go from its release point at once, with the hand-off
## state a played launch ends in, unless its arm is under the spine now; then it waits on its rack, door open, and goes the
## moment the arm is clear (never inside a blocked sector).
func skip(id: String) -> void:
	var f: Dictionary = fighter(id)
	if f.is_empty() or f["phase"] == Phase.RELEASED:
		return
	f["skip"] = true
	var door: Dictionary = doors[f["bay"]]
	door["state"] = DoorState.OPEN
	door["open"] = 1.0
	if blocked_now():
		_enter(f, Phase.HELD)
	else:
		_release(f, [] as Array[Dictionary])


## The fighter called `id`, or empty.
func fighter(id: String) -> Dictionary:
	for f: Dictionary in fighters:
		if f["id"] == id:
			return f
	return {}


## Every fighter let go and every door shut again.
func finished() -> bool:
	for f: Dictionary in fighters:
		if f["phase"] != Phase.RELEASED:
			return false
	for d: Dictionary in doors:
		if d["state"] != DoorState.CLOSED:
			return false
	return true


## Whether the arm is in a blocked sector now.
func blocked_now() -> bool:
	return _hardpoints.launch_blocked(arm_angle_now())


## The arm's outward normal now, degrees about +Z from +X.
func arm_angle_now() -> float:
	return fposmod(arm_angle_deg + rad_to_deg(drum_angle), 360.0)


## The fighter's step for the launch camera: `door` (on its rack, its door opening or open), `hold`, `drop`, `release`, or
## `&""` while it waits in the second row.
func step_of(id: String) -> StringName:
	var f: Dictionary = fighter(id)
	if f.is_empty():
		return &""
	match int(f["phase"]):
		Phase.RACKED:
			return &"door"
		Phase.HELD:
			return &"hold"
		Phase.DROPPING:
			return &"drop"
		Phase.RELEASED:
			return &"release"
	return &""


## Seconds the fighter has been in its step.
func step_time(id: String) -> float:
	var f: Dictionary = fighter(id)
	return time_s - float(f["step_since"]) if not f.is_empty() else 0.0


## A door's leaves' swing now, degrees (eased).
func door_angle_deg(bay_index: int) -> float:
	return smoothstep(0.0, 1.0, float(doors[bay_index]["open"])) * profile.door_open_deg


## The fighter's pose in the drum's frame: on its rack, on its way there, or on its rail.
func local_pose(id: String) -> Transform3D:
	var f: Dictionary = fighter(id)
	var bay: Dictionary = bays[f["bay"]]
	return Transform3D(rack_basis(bay), _local_point(f, bay))


## The fighter's state in the station's frame with the drum's axis through `drum_pivot`: `transform`, `velocity` (against the
## station: the rail's speed plus the drum's turn) and `angular` (the drum's spin). A released fighter reads its hand-off state.
func state_of(id: String, drum_pivot: Vector3) -> Dictionary:
	var f: Dictionary = fighter(id)
	if f.is_empty():
		return {}
	var bay: Dictionary = bays[f["bay"]]
	return _state(_local_point(f, bay), _local_velocity(f, bay), rack_basis(bay), drum_pivot)


## The hand-off state of the fighter `id` with the drum as it is now: at its release point with the drum's surface velocity there
## plus the rail's speed along the drop direction, turning with the drum (see `state_of`).
func handoff_of(id: String, drum_pivot: Vector3) -> Dictionary:
	var f: Dictionary = fighter(id)
	if f.is_empty():
		return {}
	var bay: Dictionary = bays[f["bay"]]
	return _state(bay["release"], (bay["release_direction"] as Vector3).normalized() * release_speed(bay), rack_basis(bay),
			drum_pivot)


## The rail's speed at the release point, m/s (from rest at a steady acceleration over `drop_s`).
func release_speed(bay: Dictionary) -> float:
	return 2.0 * _length(_rail(bay)) / profile.drop_s


## A racked fighter's attitude in the drum's frame: its nose along the bay's `forward`, its top along `up` (toward the axis).
static func rack_basis(bay: Dictionary) -> Basis:
	var back: Vector3 = -(bay["forward"] as Vector3).normalized()
	var up: Vector3 = (bay["up"] as Vector3).normalized()
	return Basis(up.cross(back).normalized(), up, back).orthonormalized()


## A door's frame in the drum's frame: at its middle, x across the arm, y out of the drum (its normal), z aft. The launch camera's
## `bay` actor.
static func door_frame(bay: Dictionary) -> Transform3D:
	var x: Vector3 = (bay["across"] as Vector3).normalized()
	var y: Vector3 = (bay["normal"] as Vector3).normalized()
	return Transform3D(Basis(x, y, x.cross(y)).orthonormalized(), bay["door"])


## One line a fighter, for the console.
func describe() -> String:
	var parts := PackedStringArray()
	for f: Dictionary in fighters:
		parts.append("%s %s wave %d %s%s" % [f["id"], (bays[f["bay"]] as Dictionary)["name"], f["wave"], PHASE_NAMES[f["phase"]],
				" (held %.1f s)" % f["held_s"] if float(f["held_s"]) > 0.0 else ""])
	return "; ".join(parts)


# --- steps -----------------------------------------------------------------------------------------------------------


func _step_doors(delta: float, events: Array[Dictionary]) -> void:
	for i: int in doors.size():
		var d: Dictionary = doors[i]
		var name: String = (bays[i] as Dictionary)["name"]
		if _door_wanted(i) and (d["state"] == DoorState.CLOSED or d["state"] == DoorState.CLOSING):
			d["state"] = DoorState.OPENING
			events.append({"kind": "door_opening", "id": "", "bay": name})
		elif d["state"] == DoorState.OPEN and _door_done(i):
			d["state"] = DoorState.CLOSING
			events.append({"kind": "door_closing", "id": "", "bay": name})
		if d["state"] == DoorState.OPENING:
			d["open"] = minf(1.0, float(d["open"]) + (delta / profile.door_open_s if profile.door_open_s > 0.0 else 1.0))
			if float(d["open"]) >= 1.0 - EPS_S:
				d["open"] = 1.0
				d["state"] = DoorState.OPEN
				events.append({"kind": "door_open", "id": "", "bay": name})
		elif d["state"] == DoorState.CLOSING:
			d["open"] = maxf(0.0, float(d["open"]) - (delta / profile.door_close_s if profile.door_close_s > 0.0 else 1.0))
			if float(d["open"]) <= EPS_S:
				d["open"] = 0.0
				d["state"] = DoorState.CLOSED
				events.append({"kind": "door_closed", "id": "", "bay": name})


func _step_fighter(f: Dictionary, delta: float, events: Array[Dictionary]) -> void:
	var bay_name: String = (bays[f["bay"]] as Dictionary)["name"]
	match int(f["phase"]):
		Phase.STAGED:
			if _rack_free(f):
				_enter(f, Phase.MOVING)
				events.append({"kind": "move", "id": f["id"], "bay": bay_name})
		Phase.MOVING:
			if time_s - float(f["step_since"]) >= profile.row_move_s - EPS_S:
				_enter(f, Phase.RACKED)
				events.append({"kind": "racked", "id": f["id"], "bay": bay_name})
		Phase.DROPPING:
			if time_s - float(f["drop_start"]) >= profile.drop_s - EPS_S:
				_release(f, events)
		Phase.RACKED, Phase.HELD:
			if f["phase"] == Phase.HELD:
				f["held_s"] = float(f["held_s"]) + delta
			if bool(f["skip"]):
				if not blocked_now():
					_release(f, events)
				return
			if not _due(f) or (doors[f["bay"]] as Dictionary)["state"] != DoorState.OPEN:
				return
			if _clear_for_drop():
				f["drop_start"] = time_s
				_enter(f, Phase.DROPPING)
				events.append({"kind": "drop", "id": f["id"], "bay": bay_name})
			elif f["phase"] != Phase.HELD:
				_enter(f, Phase.HELD)
				events.append({"kind": "hold", "id": f["id"], "bay": bay_name})


func _enter(f: Dictionary, phase: Phase) -> void:
	f["phase"] = phase
	f["step_since"] = time_s


func _release(f: Dictionary, events: Array[Dictionary]) -> void:
	if float(f["drop_start"]) < 0.0:
		f["drop_start"] = time_s  # a skip: it counts as started for the wave's order
	f["released_at"] = time_s
	_enter(f, Phase.RELEASED)
	(doors[f["bay"]] as Dictionary)["last_release"] = time_s
	events.append({"kind": "release", "id": f["id"], "bay": (bays[f["bay"]] as Dictionary)["name"]})


# The drop is due: its time has come and the fighter before it in the wave dropped at least a stagger ago (a hold slips the rest).
func _due(f: Dictionary) -> bool:
	var k: int = f["k"]
	var due: float
	if int(f["wave"]) == 1:
		due = k * profile.stagger_s + profile.door_open_s
	else:
		if first_wave_done_s < 0.0:
			return false
		due = first_wave_done_s + profile.wave_gap_s + k * profile.stagger_s
	if time_s < due - EPS_S:
		return false
	if k == 0:
		return true
	var before: Dictionary = _in_wave(int(f["wave"]), k - 1)
	if before.is_empty():
		return true
	var started: float = float(before["drop_start"])
	return started >= 0.0 and time_s >= started + profile.stagger_s - EPS_S


# The arm stays clear of every blocked sector from now to the end of a drop started now.
func _clear_for_drop() -> bool:
	var start: float = arm_angle_now()
	var sweep: float = rad_to_deg(spin_rate_rad_s * profile.drop_s)
	var steps: int = ceili(absf(sweep) / CLEAR_STEP_DEG)
	for s: int in steps + 1:
		var a: float = start + (sweep * float(s) / float(steps) if steps > 0 else 0.0)
		if _hardpoints.launch_blocked(a):
			return false
	return true


# A door opens for its first-wave fighter's turn, and stays open while any fighter of its own is still to go.
func _door_wanted(bay_index: int) -> bool:
	for f: Dictionary in fighters:
		if int(f["bay"]) != bay_index or f["phase"] == Phase.RELEASED:
			continue
		if int(f["wave"]) == 1 and time_s > int(f["k"]) * profile.stagger_s + EPS_S:
			return true
		if int(f["wave"]) == 2 and first_wave_done_s >= 0.0:
			return true
	return false


func _door_done(bay_index: int) -> bool:
	var d: Dictionary = doors[bay_index]
	for f: Dictionary in fighters:
		if int(f["bay"]) == bay_index and f["phase"] != Phase.RELEASED:
			return false
	return float(d["last_release"]) >= 0.0 and time_s - float(d["last_release"]) > profile.door_close_after_s + EPS_S


# The second row's fighter may move up once the rack in front of it is empty.
func _rack_free(f: Dictionary) -> bool:
	for other: Dictionary in fighters:
		if other != f and int(other["bay"]) == int(f["bay"]) and int(other["wave"]) == 1 and other["phase"] != Phase.RELEASED:
			return false
	return true


func _wave_released(wave: int) -> bool:
	var any: bool = false
	for f: Dictionary in fighters:
		if int(f["wave"]) == wave:
			any = true
			if f["phase"] != Phase.RELEASED:
				return false
	return any


func _in_wave(wave: int, k: int) -> Dictionary:
	for f: Dictionary in fighters:
		if int(f["wave"]) == wave and int(f["k"]) == k:
			return f
	return {}


# --- poses -------------------------------------------------------------------------------------------------------------


func _local_point(f: Dictionary, bay: Dictionary) -> Vector3:
	match int(f["phase"]):
		Phase.STAGED:
			return bay["staging"]
		Phase.MOVING:
			var u: float = clampf((time_s - float(f["step_since"])) / profile.row_move_s, 0.0, 1.0)
			var path: Array[Vector3] = bay["staging_path"]
			return _along(path, smoothstep(0.0, 1.0, u) * _length(path))
		Phase.DROPPING:
			var u: float = clampf((time_s - float(f["drop_start"])) / profile.drop_s, 0.0, 1.0)
			var rail: Array[Vector3] = _rail(bay)
			return _along(rail, u * u * _length(rail))
		Phase.RELEASED:
			return bay["release"]
	return bay["rail_start"]


# Against the drum: along the second row's path or down the rail.
func _local_velocity(f: Dictionary, bay: Dictionary) -> Vector3:
	match int(f["phase"]):
		Phase.MOVING:
			var u: float = clampf((time_s - float(f["step_since"])) / profile.row_move_s, 0.0, 1.0)
			var path: Array[Vector3] = bay["staging_path"]
			var length: float = _length(path)
			return _tangent(path, smoothstep(0.0, 1.0, u) * length) * (length * 6.0 * u * (1.0 - u) / profile.row_move_s)
		Phase.DROPPING:
			var u: float = clampf((time_s - float(f["drop_start"])) / profile.drop_s, 0.0, 1.0)
			var rail: Array[Vector3] = _rail(bay)
			var length: float = _length(rail)
			return _tangent(rail, u * u * length) * (2.0 * length * u / profile.drop_s)
		Phase.RELEASED:
			return (bay["release_direction"] as Vector3).normalized() * release_speed(bay)
	return Vector3.ZERO


func _state(point: Vector3, rail_velocity: Vector3, basis: Basis, drum_pivot: Vector3) -> Dictionary:
	var turn := Basis(Vector3.BACK, drum_angle)
	var omega := Vector3(0.0, 0.0, spin_rate_rad_s)
	var arm: Vector3 = turn * point
	return {"transform": Transform3D(turn * basis, drum_pivot + arm), "velocity": turn * rail_velocity + omega.cross(arm),
			"angular": omega}


static func _rail(bay: Dictionary) -> Array[Vector3]:
	return [bay["rail_start"], bay["rail_end"], bay["release"]] as Array[Vector3]


static func _length(path: Array[Vector3]) -> float:
	var total: float = 0.0
	for i: int in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


static func _along(path: Array[Vector3], s: float) -> Vector3:
	var left: float = s
	for i: int in range(1, path.size()):
		var seg: float = path[i - 1].distance_to(path[i])
		if left <= seg or i == path.size() - 1:
			return path[i - 1].lerp(path[i], clampf(left / seg, 0.0, 1.0) if seg > 0.0 else 1.0)
		left -= seg
	return path[-1]


static func _tangent(path: Array[Vector3], s: float) -> Vector3:
	var left: float = s
	for i: int in range(1, path.size()):
		var seg: float = path[i - 1].distance_to(path[i])
		if seg > 0.0 and (left < seg or i == path.size() - 1):
			return (path[i] - path[i - 1]) / seg
		left -= seg
	return Vector3.ZERO


# --- setup -------------------------------------------------------------------------------------------------------------


func _setup(hardpoints: StationHardpoints, wing_name: String, ids: PackedStringArray, p_profile: LaunchProfile,
		first_door: int) -> String:
	if hardpoints == null or not hardpoints.valid:
		return "the station's hardpoints are not loaded"
	if p_profile == null:
		return "no launch profile"
	_hardpoints = hardpoints
	profile = p_profile
	wing = wing_name.to_lower()
	bays = hardpoints.bays_of(wing)
	bays.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["door_number"]) < int(b["door_number"]))
	if bays.is_empty():
		return "no Cobra arm flies wing '%s'" % wing_name
	for bay: Dictionary in bays:
		for key: String in ["rail_start", "rail_end", "release", "release_direction", "forward", "up", "staging", "door",
				"across", "normal"]:
			if not bay.get(key) is Vector3:
				return "%s has no %s" % [bay["name"], key]
		if not bay.get("staging_path") is Array or (bay["staging_path"] as Array).size() < 2:
			return "%s has no staging_path" % bay["name"]
	var arm: Dictionary = {}
	for a: Variant in hardpoints.cobra_arm.get("arms", []):
		if a is Dictionary and str((a as Dictionary).get("wing", "")) == wing:
			arm = a
	if arm.is_empty():
		return "the cobra_arm layout has no arm for wing '%s'" % wing_name
	arm_angle_deg = float(arm.get("angle_deg", 0.0))
	var per_wave: int = bays.size()
	if first_door < 1 or first_door > per_wave:
		return "wing %s has doors 1 to %d, not %d" % [wing_name, per_wave, first_door]
	if ids.is_empty() or ids.size() > 2 * per_wave:
		return "a wing launches 1 to %d fighters, not %d" % [2 * per_wave, ids.size()]
	for i: int in per_wave:
		doors.append({"state": DoorState.CLOSED, "open": 0.0, "last_release": -1.0})
	for i: int in ids.size():
		var wave: int = 1 if i < per_wave else 2
		var k: int = i % per_wave
		fighters.append({"id": ids[i], "bay": (first_door - 1 + k) % per_wave, "wave": wave, "k": k,
				"phase": Phase.RACKED if wave == 1 else Phase.STAGED, "step_since": 0.0, "drop_start": -1.0, "released_at": -1.0,
				"held_s": 0.0, "skip": false})
	return ""
