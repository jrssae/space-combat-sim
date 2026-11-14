class_name LaunchSequence
extends RefCounted
## One wing's launch from its Cobra arm (M7-T08, D76, AC7; Q3 as corrected): up to twelve Starfuries, six on the racks over the arm's
## six doors (wave 1) and six in the second row (wave 2). Starfuries launch front first (maintainer): stored on the rack at 90 degrees
## to the launch, each one's door opens and the clamp turns it nose-out (`rotate_s`), then it drops nose first down its rail and is let
## go past the release point with the drum's surface velocity plus the rail's speed along the drop direction. The ejection is quick
## (`drop_s`, under a second), and a wave's doors fire in turn along the arm a seeded 0.25 to 0.5 s apart (maintainer, after the
## show's launch). The second row moves
## onto the racks once they are free and drops `wave_gap_s` after the first wave's last release. Pure: it lives in the drum's frame
## and is told the drum's angle each tick, so a rebase or the drum's turn moves nothing in it.
##
## Hold under the spine (maintainer): the stationary frame passes over each arm once a turn. A drop starts only when the arm stays
## out of every blocked sector (`StationHardpoints.launch_blocked`) from the drop's start to its release; until then the fighter holds
## on its rack while the rest of the wave goes on in order; held fighters that come clear together go at least `stagger_min_s` apart.
##
## Steps and timings come from a `LaunchProfile`, so M8's squadron launch runs this for several wings in turn.

enum Phase { STAGED, MOVING, RACKED, ROTATING, HELD, DROPPING, RELEASED }
enum DoorState { CLOSED, OPENING, OPEN, CLOSING }

const PHASE_NAMES: PackedStringArray = ["staged", "moving", "racked", "rotating", "held", "dropping", "released"]
const DOOR_NAMES: PackedStringArray = ["closed", "opening", "open", "closing"]
## How finely a drop's sweep of arm angles is checked against the blocked sectors, degrees.
const CLEAR_STEP_DEG: float = 0.5
const EPS_S: float = 1e-6
## A door leaf's thickness, m (the generator's leaves are 0.5 m deep).
const LEAF_THICKNESS_M: float = 0.5

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
## `drop_start`, `released_at` (-1 until then), `held_s` (seconds spent holding), `skip`, `turn` (0 stored to 1 turned nose-out).
var fighters: Array[Dictionary] = []
## Each door (by bay index): `state`, `open` (0 shut to 1 open), `last_release` (-1 until one left).
var doors: Array[Dictionary] = []
## When the first wave's last fighter was let go (-1 until then).
var first_wave_done_s: float = -1.0
## Each wave's firing times from its start, by place in the wave (seeded gaps between `stagger_min_s` and `stagger_max_s`).
var slots: Array[PackedFloat64Array] = []
## The launch's seed: the gaps between the doors come from it.
var seed_value: int = 0

var _hardpoints: StationHardpoints = null


## A launch of `ids` from `wing_name`'s arm: the first six take the racks, starting at door `first_door`, then the doors aft of it
## along the arm, then those forward of it, and fire in that order; the next six wait in the second row behind the same doors. The
## gaps between the doors come from `p_seed`. Check `valid`.
static func create(hardpoints: StationHardpoints, wing_name: String, ids: PackedStringArray, p_profile: LaunchProfile,
		first_door: int = 1, p_drum_angle: float = 0.0, p_spin: float = 0.0, p_seed: int = 0) -> LaunchSequence:
	var made := LaunchSequence.new()
	made.seed_value = p_seed
	made.error = made._setup(hardpoints, wing_name, ids, p_profile, first_door)
	made.valid = made.error.is_empty()
	made.drum_angle = p_drum_angle
	made.spin_rate_rad_s = p_spin
	return made


## Moves the launch on by `delta` seconds with the drum at `p_drum_angle` (radians about +Z) turning at `p_spin` rad/s. Returns what
## happened, in order: each `{kind, id, bay}` with kind `door_opening`, `door_open`, `door_closing`, `door_closed`, `move`,
## `racked`, `rotate`, `turned`, `hold`, `drop`, `release`.
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
	f["turn"] = 1.0
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


## The fighter's step for the launch camera: `door` (stored on its rack, its door opening), `rotate` (the clamp turning it, then
## waiting nose-out for its drop), `hold`, `drop`, `release`, or `&""` while it waits in the second row.
func step_of(id: String) -> StringName:
	var f: Dictionary = fighter(id)
	if f.is_empty():
		return &""
	match int(f["phase"]):
		Phase.RACKED:
			return &"door" if float(f["turn"]) < 1.0 else &"rotate"
		Phase.ROTATING:
			return &"rotate"
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


## The fighter's pose in the drum's frame: stored on its rack, turning in the clamp, on its way up, or nose first on its rail.
func local_pose(id: String) -> Transform3D:
	var f: Dictionary = fighter(id)
	var bay: Dictionary = bays[f["bay"]]
	return Transform3D(_local_basis(f, bay), _local_point(f, bay))


## The fighter's state in the station's frame with the drum's axis through `drum_pivot`: `transform`, `velocity` (against the
## station: the rail's speed plus the drum's turn) and `angular` (the drum's spin, plus the clamp's turn while it turns). A released
## fighter reads its hand-off state.
func state_of(id: String, drum_pivot: Vector3) -> Dictionary:
	var f: Dictionary = fighter(id)
	if f.is_empty():
		return {}
	var bay: Dictionary = bays[f["bay"]]
	return _state(_local_point(f, bay), _local_velocity(f, bay), _local_basis(f, bay), drum_pivot, _local_turn_rate(f, bay))


## The hand-off state of the fighter `id` with the drum as it is now: nose out at its release point, with the drum's surface
## velocity there plus the rail's speed along the drop direction, turning with the drum (see `state_of`).
func handoff_of(id: String, drum_pivot: Vector3) -> Dictionary:
	var f: Dictionary = fighter(id)
	if f.is_empty():
		return {}
	var bay: Dictionary = bays[f["bay"]]
	return _state(release_point(bay), (bay["release_direction"] as Vector3).normalized() * release_speed(bay), launch_basis(bay),
			drum_pivot)


## The rail's speed at the release point, m/s (from rest at a steady acceleration over `drop_s`).
func release_speed(bay: Dictionary) -> float:
	return 2.0 * _length(_rail(bay)) / profile.drop_s


## Where a nose-first fighter is let go: the station's release point, `release_extra_m` further out along the drop.
func release_point(bay: Dictionary) -> Vector3:
	return (bay["release"] as Vector3) + (bay["release_direction"] as Vector3).normalized() * profile.release_extra_m


## The stored attitude in the drum's frame (the profile's, in the bay's door frame).
func stored_basis(bay: Dictionary) -> Basis:
	return door_frame(bay).basis * profile.stored_basis()


## The launch attitude in the drum's frame: nose out through the door.
func launch_basis(bay: Dictionary) -> Basis:
	return door_frame(bay).basis * profile.launch_basis()


## How far the station's rack pose (its hardpoint `forward` and `up`) is from the profile's stored pose, degrees: 0 when they agree.
func stored_pose_offset_deg(bay: Dictionary) -> float:
	return rad_to_deg(rack_basis(bay).get_rotation_quaternion().angle_to(stored_basis(bay).get_rotation_quaternion()))


## How a fighter of bounds `fighter_aabb` (its own frame) fits the arm `cobra_arm` lays out, in metres to spare (negative: it does not
## fit): through the door nose first (`door_across_m`, `door_along_m`), turning in the clamp at the rack (`turn_ceiling_m` to the hall's
## ceiling, `turn_floor_m` to the doors' plane, `turn_neighbour_m` to the next rack's stored fighter along the arm) and let go
## (`release_tail_m`, its tail past the arm's top).
static func clearances(fighter_aabb: AABB, arm: Dictionary, p_profile: LaunchProfile) -> Dictionary:
	var floor_r: float = float(arm["door_floor_r"])
	var hang_y: float = float(arm["hang_r"]) - floor_r
	var ceiling_y: float = float((arm["hall"] as Dictionary)["ceiling_r"]) - floor_r
	var top_y: float = float(arm.get("door_depth_m", 0.0))
	var half: Array = arm["door_half_m"]
	var corners: Array[Vector3] = []
	for i: int in 8:
		corners.append(fighter_aabb.get_endpoint(i))
	var launch: Basis = p_profile.launch_basis()
	var stored: Basis = p_profile.stored_basis()
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for c: Vector3 in corners:
		var p: Vector3 = launch * c
		lo = lo.min(p)
		hi = hi.max(p)
	var turn_lo: float = INF
	var turn_hi: float = -INF
	var turn_z: float = 0.0
	var qs: Quaternion = stored.get_rotation_quaternion()
	var ql: Quaternion = launch.get_rotation_quaternion()
	for step: int in 61:
		var b := Basis(qs.slerp(ql, float(step) / 60.0))
		for c: Vector3 in corners:
			var p: Vector3 = b * c
			turn_lo = minf(turn_lo, hang_y + p.y)
			turn_hi = maxf(turn_hi, hang_y + p.y)
			turn_z = maxf(turn_z, absf(p.z))
	var stored_z: float = 0.0
	for c: Vector3 in corners:
		stored_z = maxf(stored_z, absf((stored * c).z))
	var release_y: float = float(arm["release_r"]) - floor_r + p_profile.release_extra_m
	return {"door_across_m": float(half[0]) - maxf(absf(lo.x), absf(hi.x)), "door_along_m": float(half[1]) - maxf(absf(lo.z), absf(hi.z)),
			"turn_ceiling_m": turn_lo - ceiling_y, "turn_floor_m": -turn_hi,
			"turn_neighbour_m": float(arm.get("pitch_m", 0.0)) - turn_z - stored_z, "release_tail_m": release_y + lo.y - top_y}


## Room across between a nose-first fighter of bounds `fighter_aabb` and the leaves of `bay`'s door swung `open_deg` outward, m
## (negative: they meet). Each leaf runs from its hinge toward the door's middle and is `LEAF_THICKNESS_M` thick; a leaf opened past
## 90 degrees stands outside the opening, short of it leans over it.
static func leaf_clearance(fighter_aabb: AABB, bay: Dictionary, open_deg: float, p_profile: LaunchProfile) -> float:
	var frame: Transform3D = door_frame(bay)
	var half_span: float = 0.0
	for i: int in 8:
		half_span = maxf(half_span, absf((p_profile.launch_basis() * fighter_aabb.get_endpoint(i)).x))
	var room: float = INF
	for leaf: Dictionary in bay.get("leaves", []) as Array:
		var hinge: float = absf((frame.affine_inverse() * (leaf["point"] as Vector3)).x)
		var lean: float = hinge * cos(deg_to_rad(open_deg))  # how far its free edge reaches back over the opening
		room = minf(room, hinge - LEAF_THICKNESS_M - maxf(lean, 0.0) - half_span)
	return room


## A racked fighter's attitude in the drum's frame as the station's hardpoints give it: its nose along `forward`, its top along `up`.
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
		Phase.ROTATING:
			var turning: float = time_s - float(f["step_since"])
			f["turn"] = clampf(turning / profile.rotate_s, 0.0, 1.0) if profile.rotate_s > 0.0 else 1.0
			if float(f["turn"]) >= 1.0 - EPS_S:
				f["turn"] = 1.0
				f["phase"] = Phase.RACKED  # nose out, waiting for its drop: still the `rotate` step
				events.append({"kind": "turned", "id": f["id"], "bay": bay_name})
				_step_fighter(f, 0.0, events)
		Phase.RACKED, Phase.HELD:
			if f["phase"] == Phase.HELD:
				f["held_s"] = float(f["held_s"]) + delta
			if bool(f["skip"]):
				if not blocked_now():
					_release(f, events)
				return
			if float(f["turn"]) < 1.0:
				if time_s >= _nominal_due(f) - profile.rotate_s - EPS_S:
					_enter(f, Phase.ROTATING)
					events.append({"kind": "rotate", "id": f["id"], "bay": bay_name})
					_step_fighter(f, delta, events)
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


# When a fighter's drop is due by the clock alone: its door open and its turn done for the first wave, `wave_gap_s` after the
# first wave's last release for the second (INF until then).
func _nominal_due(f: Dictionary) -> float:
	var k: int = f["k"]
	if int(f["wave"]) == 1:
		return slots[0][k] + profile.lead_s()
	if first_wave_done_s < 0.0:
		return INF
	return first_wave_done_s + profile.wave_gap_s + slots[1][k]


# The drop is due: its time has come, and no other fighter of its wave started its drop less than `stagger_min_s` ago (so held fighters
# that come clear together still ripple out in order).
func _due(f: Dictionary) -> bool:
	if time_s < _nominal_due(f) - EPS_S:
		return false
	for other: Dictionary in fighters:
		if other != f and int(other["wave"]) == int(f["wave"]) and float(other["drop_start"]) >= 0.0 \
				and time_s < float(other["drop_start"]) + profile.stagger_min_s - EPS_S:
			return false
	return true


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
		if int(f["wave"]) == 1 and time_s > slots[0][int(f["k"])] + EPS_S:
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
			return release_point(bay)
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


# Stored, turning in the clamp (eased), or nose out.
func _local_basis(f: Dictionary, bay: Dictionary) -> Basis:
	var turned: float = smoothstep(0.0, 1.0, float(f["turn"]))
	var q: Quaternion = profile.stored_basis().get_rotation_quaternion().slerp(profile.launch_basis().get_rotation_quaternion(), turned)
	return door_frame(bay).basis * Basis(q)


# The clamp's turn rate against the drum while it turns (rad/s, drum frame).
func _local_turn_rate(f: Dictionary, bay: Dictionary) -> Vector3:
	if f["phase"] != Phase.ROTATING or profile.rotate_s <= 0.0:
		return Vector3.ZERO
	var u: float = clampf((time_s - float(f["step_since"])) / profile.rotate_s, 0.0, 1.0)
	var qs: Quaternion = profile.stored_basis().get_rotation_quaternion()
	var delta_q: Quaternion = qs.inverse() * profile.launch_basis().get_rotation_quaternion()
	if delta_q.w < 0.0:
		delta_q = -delta_q  # the short way round, as the slerp turns it
	var axis: Vector3 = qs * delta_q.get_axis().normalized()
	return door_frame(bay).basis * axis * (delta_q.get_angle() * 6.0 * u * (1.0 - u) / profile.rotate_s)


func _state(point: Vector3, rail_velocity: Vector3, basis: Basis, drum_pivot: Vector3, turn_rate: Vector3 = Vector3.ZERO) -> Dictionary:
	var turn := Basis(Vector3.BACK, drum_angle)
	var omega := Vector3(0.0, 0.0, spin_rate_rad_s)
	var arm: Vector3 = turn * point
	return {"transform": Transform3D(turn * basis, drum_pivot + arm), "velocity": turn * rail_velocity + omega.cross(arm),
			"angular": omega + turn * turn_rate}


func _rail(bay: Dictionary) -> Array[Vector3]:
	return [bay["rail_start"], bay["rail_end"], release_point(bay)] as Array[Vector3]


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
	# The named door first, then the doors aft of it along the arm, then those forward of it, nearest first: a ripple along the row.
	var order: Array[int] = []
	for d: int in range(first_door - 1, per_wave):
		order.append(d)
	for d: int in range(first_door - 2, -1, -1):
		order.append(d)
	for wave: int in 2:
		var times := PackedFloat64Array([0.0])
		for k: int in range(1, per_wave):
			var gap: float = lerpf(profile.stagger_min_s, profile.stagger_max_s, LaunchCut.unit(seed_value, "stagger %d" % wave, k))
			times.append(times[k - 1] + gap)
		slots.append(times)
	for i: int in ids.size():
		var wave: int = 1 if i < per_wave else 2
		var k: int = i % per_wave
		fighters.append({"id": ids[i], "bay": order[k], "wave": wave, "k": k,
				"phase": Phase.RACKED if wave == 1 else Phase.STAGED, "step_since": 0.0, "drop_start": -1.0, "released_at": -1.0,
				"held_s": 0.0, "skip": false, "turn": 0.0})
	return ""
