extends GutTest
## `LaunchSequence` and `LaunchProfile` (M7-T08, D76, AC7): the stored pose and the clamp's timed turn nose-out, the nose-first
## hand-off state, a skip landing in the same state, the hold under the spine (none released inside a blocked sector), the 10 s gap
## between the waves, the second row onto the racks, the doors, the clearances, and a rebase moving nothing. The arm here is laid out
## as the generator lays out the top (Alpha) arm.

const DT: float = 1.0 / 60.0
const SPIN: float = 0.148
const PIVOT := Vector3(0.0, 0.0, -1000.0)
## The generator's blocked sector over the arms (T05) and the top arm's angle.
const BLOCKED := [57.0, 123.5]
const ARM_DEG: float = 90.0
## The Starfury's bounds (`starfury_aurora`'s manifest): span 15.39 m, height 7.47 m, length 9.83 m, nose at -z.
const STARFURY := AABB(Vector3(-7.695, -3.6394, -4.4085), Vector3(15.39, 7.47, 9.83))
## First-wave timings with the profile below: the turn from 2 s to 4 s, the ejection from 4 s, the release at 4.75 s; 23 m of rail.
const TURN_S: float = 2.0
const DROP_AT_S: float = 4.0
const DROP_S: float = 0.75
const RELEASE_AT_S: float = 4.75
const RAIL_M: float = 23.0


func _hardpoints() -> StationHardpoints:
	var bays: Array = []
	var names: Array = []
	for n: int in range(1, 7):
		var z: float = -1944.5 + 23.0 * (n - 1)
		var bay_name: String = "cobra_bay_alpha_%d" % n
		names.append(bay_name)
		bays.append({"name": bay_name, "wing": "alpha", "arm": "top", "door_number": n, "body": "drum", "door": [0.0, 236.5, z],
				"door_half_m": [10.0, 7.0], "normal": [0.0, 1.0, 0.0], "across": [1.0, 0.0, 0.0], "rail_start": [0.0, 227.5, z],
				"rail_end": [0.0, 236.5, z], "release": [0.0, 244.5, z], "release_direction": [0.0, 1.0, 0.0],
				"surface_velocity": [-36.186, 0.0, 0.0], "forward": [0.0, 0.0, -1.0], "up": [0.0, -1.0, 0.0],
				"leaves": [{"leaf": "r", "point": [9.6, 236.5, z], "axis": [0.0, 0.0, 1.0]},
						{"leaf": "l", "point": [-9.6, 236.5, z], "axis": [0.0, 0.0, 1.0]}],
				"staging": [-28.0, 214.0, z], "staging_path": [[-28.0, 214.0, z], [0.0, 214.0, z], [0.0, 227.5, z]]})
	var hp := StationHardpoints.from_manifest({"hardpoints": {"spin_rad_s": SPIN, "cobra_bays": bays,
			"cobra_arm": {"arms": [{"name": "top", "wing": "alpha", "angle_deg": ARM_DEG, "bays": names}], "door_floor_r": 236.5,
					"hang_r": 227.5, "release_r": 244.5, "door_depth_m": 4.0, "door_half_m": [10.0, 7.0], "pitch_m": 23.0,
					"hall": {"ceiling_r": 219.0, "floor_r": 236.5}},
			"launch_clearance": {"blocked_sectors_deg": [BLOCKED], "clear_distance_m": 260.0, "margin_deg": 10.0},
			"main_docking_bay": {"name": "main_docking_bay", "body": "drum"}, "cargo_bay": {"name": "cargo_bay", "body": "frame"},
			"grid_mounts": [], "lights": [], "tour_points": [], "damage_sections": []}})
	assert_true(hp.valid, hp.error)
	return hp


func _profile() -> LaunchProfile:
	var made: Dictionary = LaunchProfile.from_dict({"door_open_s": 3.0, "door_close_s": 3.0, "door_close_after_s": 2.0,
			"drop_s": 0.75, "stagger_min_s": 0.25, "stagger_max_s": 0.5, "wave_gap_s": 10.0, "row_move_s": 6.0, "rotate_after_s": 2.0, "rotate_s": 2.0,
			"release_extra_m": 6.0, "stored_pose": {"forward": [0, 0, -1], "up": [0, -1, 0]},
			"launch_pose": {"forward": [0, 1, 0], "up": [0, 0, -1]}})
	assert_true(bool(made["ok"]), str(made.get("error", "")))
	return made["profile"]


func _ids(count: int) -> PackedStringArray:
	var out := PackedStringArray()
	for i: int in count:
		out.append("F%d" % (i + 1))
	return out


# The drum angle (radians) that puts the top arm at `arm_deg`.
func _drum_for(arm_deg: float) -> float:
	return deg_to_rad(arm_deg - ARM_DEG)


# Runs `seq` for `seconds` with the drum turning from where it stands; every event with its time.
func _run(seq: LaunchSequence, seconds: float, spin: float = SPIN, until_done: bool = false) -> Array[Dictionary]:
	var log: Array[Dictionary] = []
	var ticks: int = roundi(seconds / DT)
	for i: int in ticks:
		var angle: float = seq.drum_angle + spin * DT
		for e: Dictionary in seq.advance(DT, angle, spin):
			e["t"] = seq.time_s
			e["arm"] = seq.arm_angle_now()
			log.append(e)
		for f: Dictionary in seq.fighters:
			if f["phase"] == LaunchSequence.Phase.DROPPING:
				assert_false(seq.blocked_now(), "%s drops inside a blocked sector at %.2f deg" % [f["id"], seq.arm_angle_now()])
		if until_done and seq.finished():
			break
	return log


func _first(log: Array[Dictionary], kind: String, id: String) -> Dictionary:
	for e: Dictionary in log:
		if e["kind"] == kind and e["id"] == id:
			return e
	return {}


# A state put back in the drum's frame: the point against the drum's axis and the velocity against the turning drum.
func _in_drum(state: Dictionary, drum_angle: float, spin: float) -> Dictionary:
	var turn := Basis(Vector3.BACK, drum_angle)
	var arm: Vector3 = (state["transform"] as Transform3D).origin - PIVOT
	var relative: Vector3 = (state["velocity"] as Vector3) - Vector3(0.0, 0.0, spin).cross(arm)
	return {"point": turn.inverse() * arm, "velocity": turn.inverse() * relative,
			"basis": turn.inverse() * (state["transform"] as Transform3D).basis}


func test_the_profile_file_reads() -> void:
	var made: Dictionary = LaunchProfile.load_file()
	assert_true(bool(made["ok"]), str(made.get("error", "")))
	var profile: LaunchProfile = made["profile"]
	assert_almost_eq(profile.wave_gap_s, 10.0, 1e-9, "the maintainer's 10 s between the waves")
	for phase: Dictionary in profile.phases:
		for variant: Dictionary in phase["variants"]:
			for key: CinematicShot.Frame in (variant["shot"] as CinematicShot).keys:
				assert_false(key.up_actor.is_empty(), "%s keeps its picture upright against the arm" % variant["id"])
	var bad_fill: Dictionary = LaunchProfile.from_dict({"phases": [{"phase": "drop", "step": "drop", "variants": [{"id": "x",
			"fill": {"actor": "bay", "energy": 0}, "keys": [{"t": 0.0, "position": {"actor": "bay"}, "look_at": {"actor": "bay"}}]}]}]})
	assert_false(bool(bad_fill["ok"]), "a fill needs light")
	var bad_phase: Dictionary = LaunchProfile.from_dict({"phases": [{"phase": "drop", "step": "drop", "variants": []}]})
	assert_false(bool(bad_phase["ok"]), "a phase needs variants")
	var bad: Dictionary = LaunchProfile.from_dict({"phases": [{"step": "landing", "variants": [{"id": "x", "keys": [{"t": 0.0,
			"position": {"actor": "bay"}, "look_at": {"actor": "bay"}}]}]}]})
	assert_false(bool(bad["ok"]), "an unknown step is refused")
	assert_false(bool(LaunchProfile.from_dict({"drop_s": 0.0})["ok"]), "a drop takes time")


func test_bad_launches_are_refused() -> void:
	var hp := _hardpoints()
	assert_false(LaunchSequence.create(hp, "omega", _ids(1), _profile()).valid, "no such wing")
	assert_false(LaunchSequence.create(hp, "alpha", _ids(13), _profile()).valid, "twelve at most")
	assert_false(LaunchSequence.create(hp, "alpha", _ids(1), _profile(), 7).valid, "doors 1 to 6")
	assert_false(LaunchSequence.create(hp, "alpha", PackedStringArray(), _profile()).valid, "someone launches")
	assert_true(LaunchSequence.create(hp, "ALPHA", _ids(12), _profile(), 3).valid)


func test_the_first_wave_takes_the_racks_from_the_named_door_round_the_arm() -> void:
	var seq := LaunchSequence.create(_hardpoints(), "alpha", _ids(8), _profile(), 3)
	var doors := PackedInt32Array()
	for f: Dictionary in seq.fighters:
		doors.append(int((seq.bays[f["bay"]] as Dictionary)["door_number"]))
	assert_eq(doors, PackedInt32Array([3, 4, 5, 6, 2, 1, 3, 4]),
			"the named door first, then aft along the arm, then forward of it; the second row behind the same doors")
	assert_eq(seq.fighter("F1")["phase"], LaunchSequence.Phase.RACKED)
	assert_eq(seq.fighter("F7")["phase"], LaunchSequence.Phase.STAGED)
	assert_eq(seq.local_pose("F1").origin, Vector3(0.0, 227.5, -1898.5), "door 3's rack")
	assert_eq(seq.local_pose("F7").origin, Vector3(-28.0, 214.0, -1898.5), "door 3's staging point")
	assert_eq(seq.local_pose("F1").basis * Vector3.FORWARD, Vector3(0.0, 0.0, -1.0), "nose to the bow")
	assert_eq(seq.local_pose("F1").basis * Vector3.UP, Vector3(0.0, -1.0, 0.0), "top toward the axis")


func test_the_hand_off_is_the_release_point_with_the_drums_surface_velocity() -> void:
	var seq := LaunchSequence.create(_hardpoints(), "alpha", _ids(1), _profile(), 2, _drum_for(200.0), SPIN)
	var log: Array[Dictionary] = []
	var at_release: Dictionary = {}
	var handoff: Dictionary = {}
	var release_angle: float = 0.0
	for i: int in 500:
		for e: Dictionary in seq.advance(DT, seq.drum_angle + SPIN * DT, SPIN):
			e["t"] = seq.time_s
			log.append(e)
			if e["kind"] == "release":
				at_release = seq.state_of("F1", PIVOT)
				handoff = seq.handoff_of("F1", PIVOT)
				release_angle = seq.drum_angle
	assert_almost_eq(float(_first(log, "door_open", "")["t"]), 3.0, 1e-6, "the door opens over door_open_s")
	assert_almost_eq(float(_first(log, "drop", "F1")["t"]), DROP_AT_S, 1e-6, "the drop follows the clamp's turn")
	assert_almost_eq(float(_first(log, "release", "F1")["t"]), RELEASE_AT_S, 1e-6, "the rail takes drop_s")
	var bay: Dictionary = seq.bays[seq.fighter("F1")["bay"]]
	var turn := Basis(Vector3.BACK, release_angle)
	var arm: Vector3 = turn * ((bay["release"] as Vector3) + Vector3(0.0, 6.0, 0.0))
	var speed: float = 2.0 * RAIL_M / DROP_S  # 23 m of rail from rest in 0.75 s: 61.3 m/s
	var expected_v: Vector3 = turn * Vector3(0.0, speed, 0.0) + Vector3(0.0, 0.0, SPIN).cross(arm)
	assert_almost_eq((handoff["transform"] as Transform3D).origin, PIVOT + arm, Vector3.ONE * 1e-4,
			"at the release point, 6 m further out so its tail is clear")
	assert_almost_eq((handoff["transform"] as Transform3D).basis * Vector3.FORWARD, turn * Vector3.UP, Vector3.ONE * 1e-4,
			"nose first: its nose along the drop")
	assert_almost_eq(handoff["velocity"], expected_v, Vector3.ONE * 1e-4, "with the drum's surface velocity and the rail's speed")
	assert_almost_eq((expected_v - turn * Vector3(0.0, speed, 0.0)).length(), SPIN * 250.5, 1e-3, "about 37 m/s at r 250.5")
	assert_almost_eq(handoff["angular"], Vector3(0.0, 0.0, SPIN), Vector3.ONE * 1e-9, "turning with the drum")
	assert_almost_eq((at_release["transform"] as Transform3D).origin, (handoff["transform"] as Transform3D).origin,
			Vector3.ONE * 1e-4, "the played drop ends in the hand-off state")
	assert_almost_eq(at_release["velocity"], handoff["velocity"], Vector3.ONE * 1e-3)


func test_the_rail_is_continuous_into_the_hand_off() -> void:
	var seq := LaunchSequence.create(_hardpoints(), "alpha", _ids(1), _profile(), 1, _drum_for(200.0), SPIN)
	var last: Dictionary = {}
	for i: int in 500:
		var before: Dictionary = seq.state_of("F1", PIVOT)
		var events: Array[Dictionary] = seq.advance(DT, seq.drum_angle + SPIN * DT, SPIN)
		if not events.filter(func(e: Dictionary) -> bool: return e["kind"] == "release").is_empty():
			last = before
			break
	assert_false(last.is_empty())
	var handoff: Dictionary = seq.handoff_of("F1", PIVOT)
	assert_lt(((handoff["transform"] as Transform3D).origin - (last["transform"] as Transform3D).origin).length(), 1.3,
			"one tick before the release it is within a tick's travel of the release point")


func test_skipping_lands_in_the_same_hand_off_state() -> void:
	var played := LaunchSequence.create(_hardpoints(), "alpha", _ids(2), _profile(), 4, _drum_for(200.0), SPIN)
	_run(played, RELEASE_AT_S + 1.0)
	var skipped := LaunchSequence.create(_hardpoints(), "alpha", _ids(2), _profile(), 4, _drum_for(200.0), SPIN)
	_run(skipped, 1.0)
	skipped.skip("F1")
	assert_eq(skipped.fighter("F1")["phase"], LaunchSequence.Phase.RELEASED, "the skip lets it go at once")
	assert_eq(skipped.fighter("F2")["phase"], LaunchSequence.Phase.RACKED, "the wingman goes on with its own launch")
	var a: Dictionary = _in_drum(played.handoff_of("F1", PIVOT), played.drum_angle, SPIN)
	var b: Dictionary = _in_drum(skipped.state_of("F1", PIVOT), skipped.drum_angle, SPIN)
	assert_almost_eq(a["point"], b["point"], Vector3.ONE * 1e-4, "the same place on the drum")
	assert_almost_eq(a["velocity"], b["velocity"], Vector3.ONE * 1e-4, "the same velocity against the drum")
	assert_true((a["basis"] as Basis).is_equal_approx(b["basis"]), "the same attitude")
	assert_almost_eq(a["point"], Vector3(0.0, 250.5, -1875.5), Vector3.ONE * 1e-4, "door 4's release point")
	assert_almost_eq((b["basis"] as Basis) * Vector3.FORWARD, Vector3.UP, Vector3.ONE * 1e-4, "a skip goes nose first too")


func test_a_skip_under_the_spine_waits_for_clear_space() -> void:
	var seq := LaunchSequence.create(_hardpoints(), "alpha", _ids(1), _profile(), 1, _drum_for(100.0), SPIN)
	seq.skip("F1")
	assert_eq(seq.fighter("F1")["phase"], LaunchSequence.Phase.HELD, "under the spine a skip cannot let it go")
	var log: Array[Dictionary] = _run(seq, 10.0)
	var release: Dictionary = _first(log, "release", "F1")
	assert_false(release.is_empty(), "it goes once the arm is clear")
	assert_false(_hardpoints().launch_blocked(float(release["arm"])), "never inside the sector")
	assert_almost_eq(float(release["arm"]), BLOCKED[1], SPIN * DT * 180.0 / PI + 1e-6, "the tick the arm leaves it")


func test_a_launch_inside_the_blocked_sector_holds_and_drops_on_leaving_it() -> void:
	var seq := LaunchSequence.create(_hardpoints(), "alpha", _ids(1), _profile(), 1, _drum_for(70.0), SPIN)
	var log: Array[Dictionary] = _run(seq, 20.0)
	var hold: Dictionary = _first(log, "hold", "F1")
	var drop: Dictionary = _first(log, "drop", "F1")
	var release: Dictionary = _first(log, "release", "F1")
	assert_almost_eq(float(hold["t"]), DROP_AT_S, 1e-6, "held when its drop was due, nose out")
	assert_eq(float(seq.fighter("F1")["turn"]), 1.0, "turned before it holds")
	assert_almost_eq(float(drop["arm"]), BLOCKED[1], 0.2, "drops as the arm leaves the sector")
	assert_gt(float(seq.fighter("F1")["held_s"]), 0.0, "the hold is counted")
	assert_false(_hardpoints().launch_blocked(float(release["arm"])))


func test_a_drop_that_would_end_inside_the_sector_waits() -> void:
	# The arm is clear when the drop is due, but would turn into the sector before the release.
	var due_arm: float = 57.0 - 3.0  # 6.4 degrees of turn in a 0.75 s ejection
	var seq := LaunchSequence.create(_hardpoints(), "alpha", _ids(1), _profile(), 1,
			_drum_for(due_arm - rad_to_deg(SPIN * DROP_AT_S)), SPIN)
	var log: Array[Dictionary] = _run(seq, 30.0)
	assert_false(_first(log, "hold", "F1").is_empty(), "held rather than released under the spine")
	var release: Dictionary = _first(log, "release", "F1")
	assert_false(release.is_empty())
	assert_gt(float(release["arm"]), BLOCKED[1], "let go beyond the sector")


func test_no_release_inside_a_blocked_sector_over_a_whole_wing() -> void:
	for start: float in [0.0, 40.0, 90.0, 150.0, 250.0, 330.0]:
		var hp := _hardpoints()
		var seq := LaunchSequence.create(hp, "alpha", _ids(12), _profile(), 1, _drum_for(start), SPIN)
		var log: Array[Dictionary] = _run(seq, 200.0, SPIN, true)
		var released: int = 0
		for e: Dictionary in log:
			if e["kind"] == "release":
				released += 1
				assert_false(hp.launch_blocked(float(e["arm"])), "%s let go at %.1f deg (start %.0f)" % [e["id"], e["arm"], start])
		assert_eq(released, 12, "all twelve go (start %.0f)" % start)
		assert_true(seq.finished(), "and the doors shut (start %.0f)" % start)


# A fighter let go flies straight on while the drum turns under it (its surface velocity), so a release at a sector's edge can fly
# into the frame a few seconds later (M7-T12's clearance test found one 0.9 m from the spine): the hold checks that path too.
func test_no_fighter_is_let_go_onto_a_path_that_meets_the_frame() -> void:
	var reach: float = float(_hardpoints().launch_clearance["clear_distance_m"])
	var checked: int = 0
	for start: float in range(0, 360, 15):
		var hp := _hardpoints()
		var seq := LaunchSequence.create(hp, "alpha", _ids(6), _profile(), 3, _drum_for(start), SPIN)
		for tick: int in roundi(120.0 / DT):
			var angle: float = seq.drum_angle + SPIN * DT
			for e: Dictionary in seq.advance(DT, angle, SPIN):
				if e["kind"] != "release":
					continue
				var state: Dictionary = seq.handoff_of(String(e["id"]), PIVOT)
				var from: Vector3 = (state["transform"] as Transform3D).origin - PIVOT
				var velocity: Vector3 = state["velocity"]
				for step: int in 51:
					var at: Vector3 = from + velocity * (float(step) * 0.1)
					if Vector2(at.x, at.y).length() > Vector2(from.x, from.y).length() + reach:
						break
					assert_false(hp.launch_blocked(rad_to_deg(atan2(at.y, at.x))),
							"%s (start %.0f deg) is on a path into a blocked sector %.1f s out" % [e["id"], start, step * 0.1])
				checked += 1
	assert_gte(checked, 24 * 6 - 6, "the fighters of every start were let go")


# Arm at 45 degrees: out of the sector for the whole 0.75 s drop, yet the fighter's path curves into it a few seconds later.
func test_a_drop_whose_flight_would_meet_the_frame_waits() -> void:
	var seq := LaunchSequence.create(_hardpoints(), "alpha", _ids(1), _profile(), 1, _drum_for(45.0), SPIN)
	var log: Array[Dictionary] = _run(seq, 60.0, SPIN, true)
	assert_false(_first(log, "hold", "F1").is_empty(), "it holds although the arm is clear during the drop")
	assert_false(_first(log, "release", "F1").is_empty(), "and goes once the path is clear")


func test_the_second_wave_drops_ten_seconds_after_the_first_waves_last_release() -> void:
	var seq := LaunchSequence.create(_hardpoints(), "alpha", _ids(12), _profile(), 1, _drum_for(200.0), 0.0)
	var log: Array[Dictionary] = _run(seq, 60.0, 0.0)
	var last_first: float = 0.0
	for i: int in range(1, 7):
		last_first = maxf(last_first, float(_first(log, "release", "F%d" % i)["t"]))
	assert_almost_eq(seq.first_wave_done_s, last_first, 1e-9)
	assert_almost_eq(float(_first(log, "drop", "F7")["t"]), last_first + 10.0, 1e-6, "10 s after the first wave")
	for i: int in range(7, 13):
		var move: Dictionary = _first(log, "move", "F%d" % i)
		var racked: Dictionary = _first(log, "racked", "F%d" % i)
		var ahead: Dictionary = _first(log, "release", "F%d" % (i - 6))
		assert_almost_eq(float(move["t"]), float(ahead["t"]), 1e-6, "F%d moves up once its rack is empty" % i)
		assert_lt(float(racked["t"]), float(_first(log, "drop", "F%d" % i)["t"]), "and is on the rack before it drops")
	var gap: float = float(_first(log, "drop", "F8")["t"]) - float(_first(log, "drop", "F7")["t"])
	assert_between(gap, 0.25 - DT, 0.5 + DT, "the second wave ripples too")


func test_after_a_hold_the_wave_ripples_out_in_order() -> void:
	var seq := LaunchSequence.create(_hardpoints(), "alpha", _ids(3), _profile(), 1, _drum_for(70.0), SPIN)
	var log: Array[Dictionary] = _run(seq, 30.0)
	var d1: float = float(_first(log, "drop", "F1")["t"])
	var d2: float = float(_first(log, "drop", "F2")["t"])
	var d3: float = float(_first(log, "drop", "F3")["t"])
	assert_gt(d1, DROP_AT_S + 1.0, "the arm was under the spine")
	assert_true(d1 < d2 and d2 < d3, "still in order")
	assert_almost_eq(d2 - d1, 0.25, DT + 1e-6, "the least gap once they all come clear together")
	assert_almost_eq(d3 - d2, 0.25, DT + 1e-6)


func test_the_doors_fire_in_turn_along_the_arm_a_quarter_to_half_a_second_apart() -> void:
	var gaps_by_seed: Array[PackedFloat64Array] = []
	for seed_value: int in [7, 8, 7]:
		var seq := LaunchSequence.create(_hardpoints(), "alpha", _ids(6), _profile(), 1, _drum_for(200.0), 0.0, seed_value)
		var log: Array[Dictionary] = _run(seq, 12.0, 0.0)
		var last_door: int = 0
		var last_t: float = -1.0
		var gaps := PackedFloat64Array()
		for i: int in range(1, 7):
			var drop: Dictionary = _first(log, "drop", "F%d" % i)
			var door: int = int(seq.bays[seq.fighter("F%d" % i)["bay"]]["door_number"])
			assert_gt(door, last_door, "F%d fires from the next door along the arm" % i)
			if last_t >= 0.0:
				var gap: float = float(drop["t"]) - last_t
				assert_between(gap, 0.25 - DT, 0.5 + DT, "a gap of %.3f s (seed %d)" % [gap, seed_value])
				gaps.append(gap)
			last_door = door
			last_t = float(drop["t"])
		gaps_by_seed.append(gaps)
	assert_eq(gaps_by_seed[0], gaps_by_seed[2], "the same seed, the same ripple")
	assert_ne(gaps_by_seed[0], gaps_by_seed[1], "another seed, another ripple")


func test_the_ejection_is_quick() -> void:
	var seq := LaunchSequence.create(_hardpoints(), "alpha", _ids(1), _profile(), 1, _drum_for(200.0), 0.0)
	var clear_at: float = -1.0
	var drop_at: float = -1.0
	for i: int in roundi(6.0 / DT):
		seq.advance(DT, seq.drum_angle, 0.0)
		if seq.fighter("F1")["phase"] == LaunchSequence.Phase.DROPPING and drop_at < 0.0:
			drop_at = seq.time_s
		# Its tail (5.42 m behind its middle) past the top of the door's well (4 m out from the doors' plane, r 240.5).
		var middle_out: float = seq.local_pose("F1").origin.y - 236.5
		if drop_at >= 0.0 and clear_at < 0.0 and middle_out - 5.42 > 4.0:
			clear_at = seq.time_s
	assert_gt(clear_at, 0.0)
	assert_lt(clear_at - drop_at, 0.8, "clear of its door in %.2f s" % (clear_at - drop_at))
	var bay: Dictionary = seq.bays[0]
	assert_almost_eq(seq.release_speed(bay), 61.33, 0.01, "let go at 61 m/s along the drop")


func test_the_second_row_moves_along_its_path_onto_the_rack() -> void:
	var seq := LaunchSequence.create(_hardpoints(), "alpha", _ids(7), _profile(), 1, _drum_for(200.0), 0.0)
	var seen: Array[Vector3] = []
	for i: int in 1200:
		seq.advance(DT, seq.drum_angle, 0.0)
		if seq.fighter("F7")["phase"] == LaunchSequence.Phase.MOVING:
			seen.append(seq.local_pose("F7").origin)
	assert_gt(seen.size(), 300)
	assert_almost_eq(seen[0], Vector3(-28.0, 214.0, -1944.5), Vector3.ONE * 0.1, "from its staging point")
	assert_almost_eq(seen[-1], Vector3(0.0, 227.5, -1944.5), Vector3.ONE * 0.1, "to its rack")
	# Halfway in time is halfway along the 41.5 m path (eased at both ends): 20.75 m along its first leg.
	assert_almost_eq(seen[seen.size() / 2], Vector3(-7.25, 214.0, -1944.5), Vector3(0.5, 0.01, 0.01), "halfway along the path")


func test_a_door_swings_open_for_its_fighter_and_shuts_after() -> void:
	var seq := LaunchSequence.create(_hardpoints(), "alpha", _ids(1), _profile(), 1, _drum_for(200.0), 0.0)
	assert_eq(seq.door_angle_deg(0), 0.0, "shut")
	var log: Array[Dictionary] = _run(seq, 1.5, 0.0)
	assert_gt(seq.door_angle_deg(0), 0.0, "opening")
	assert_lt(seq.door_angle_deg(0), seq.profile.door_open_deg)
	assert_eq(seq.door_angle_deg(1), 0.0, "a door with no fighter stays shut")
	log.append_array(_run(seq, 20.0, 0.0, true))
	var closing: Dictionary = _first(log, "door_closing", "")
	assert_almost_eq(float(closing["t"]), RELEASE_AT_S + 2.0 + DT, 1e-6, "closing door_close_after_s after the release (its first tick)")
	assert_almost_eq(float(_first(log, "door_closed", "")["t"]), RELEASE_AT_S + 2.0 + 3.0, 1e-6)
	assert_true(seq.finished())


func test_a_rebase_moves_nothing_in_the_drums_frame() -> void:
	var seq := LaunchSequence.create(_hardpoints(), "alpha", _ids(1), _profile(), 1, _drum_for(200.0), SPIN)
	_run(seq, 4.0)
	var station := Transform3D(Basis.IDENTITY, Vector3(1200.0, -40.0, 300.0))
	var shift := Vector3(-4000.0, 0.0, 2500.0)
	var state: Dictionary = seq.state_of("F1", PIVOT)
	var before: Vector3 = station * (state["transform"] as Transform3D).origin
	var after: Vector3 = station.translated(shift) * (state["transform"] as Transform3D).origin
	assert_almost_eq(after - before, shift, Vector3.ONE * 1e-6, "the fighter moves exactly with the station")
	assert_eq(seq.state_of("F1", PIVOT)["velocity"], state["velocity"], "and its velocity is untouched")


func test_stored_at_ninety_degrees_the_clamp_turns_it_nose_out_on_time() -> void:
	var seq := LaunchSequence.create(_hardpoints(), "alpha", _ids(2), _profile(), 1, _drum_for(200.0), 0.0)
	var bay: Dictionary = seq.bays[0]
	assert_almost_eq(seq.stored_pose_offset_deg(bay), 0.0, 1e-3, "the station's rack pose is the profile's stored pose")
	assert_almost_eq(seq.local_pose("F1").basis * Vector3.FORWARD, Vector3(0, 0, -1), Vector3.ONE * 1e-5, "stored nose to the bow")
	assert_eq(seq.step_of("F1"), &"door")
	var log: Array[Dictionary] = []
	var halfway: Basis
	var rate_seen: Vector3
	var rate_measured: Vector3
	for i: int in roundi(RELEASE_AT_S / DT):
		var before: Basis = seq.local_pose("F1").basis
		for e: Dictionary in seq.advance(DT, seq.drum_angle, 0.0):
			e["t"] = seq.time_s
			log.append(e)
		if is_equal_approx(seq.time_s, TURN_S + 1.0):
			halfway = seq.local_pose("F1").basis
			rate_seen = Basis(Vector3.BACK, seq.drum_angle).inverse() * (seq.state_of("F1", PIVOT)["angular"] as Vector3)
			var turned: Basis = seq.local_pose("F1").basis * before.inverse()
			rate_measured = turned.get_rotation_quaternion().get_axis() * turned.get_rotation_quaternion().get_angle() / DT
	assert_almost_eq(float(_first(log, "rotate", "F1")["t"]), TURN_S, 1e-6, "the clamp turns rotate_after_s in")
	assert_almost_eq(float(_first(log, "turned", "F1")["t"]), TURN_S + 2.0, 1e-6, "for rotate_s")
	assert_almost_eq(float(_first(log, "rotate", "F2")["t"]), TURN_S + seq.slots[0][1], DT, "the next a stagger later")
	assert_almost_eq(rad_to_deg((halfway * Vector3.FORWARD).angle_to(Vector3(0, 0, -1))), 45.0, 0.5, "halfway round at halfway")
	assert_almost_eq(rate_seen, rate_measured, Vector3.ONE * 0.02, "its spin is the turn's own rate")
	assert_almost_eq(rate_seen.length(), PI / 2.0 * 1.5 / 2.0, 0.01, "an eased quarter turn in 2 s peaks at 1.18 rad/s")
	var drop_from: Dictionary = _first(log, "drop", "F1")
	assert_almost_eq(float(drop_from["t"]), DROP_AT_S, 1e-6, "drops as the turn ends")
	assert_almost_eq(seq.handoff_of("F1", PIVOT)["transform"].basis * Vector3.FORWARD, Basis(Vector3.BACK, seq.drum_angle) * Vector3.UP,
			Vector3.ONE * 1e-5, "nose out through the door")


func test_the_turn_waits_for_the_second_row_to_be_on_the_rack() -> void:
	var seq := LaunchSequence.create(_hardpoints(), "alpha", _ids(7), _profile(), 1, _drum_for(200.0), 0.0)
	var log: Array[Dictionary] = _run(seq, 40.0, 0.0)
	var racked: float = float(_first(log, "racked", "F7")["t"])
	var turn: float = float(_first(log, "rotate", "F7")["t"])
	assert_gt(turn, racked, "turned on the rack, not on its way up")
	assert_almost_eq(float(_first(log, "drop", "F7")["t"]) - turn, TURN_S, 1e-6, "and drops when the turn is done")


func test_a_starfury_fits_the_door_nose_first_and_turns_clear_in_the_hall() -> void:
	var fit: Dictionary = LaunchSequence.clearances(STARFURY, _hardpoints().cobra_arm, _profile())
	assert_almost_eq(float(fit["door_across_m"]), 2.305, 0.01, "its 15.4 m span through the 20 m door")
	assert_almost_eq(float(fit["door_along_m"]), 3.17, 0.01, "its 7.5 m height through the 14 m door")
	assert_gt(float(fit["turn_ceiling_m"]), 1.5, "turning clear of the hall's ceiling")
	assert_gt(float(fit["turn_floor_m"]), 2.0, "and of the doors' plane")
	assert_gt(float(fit["turn_neighbour_m"]), 10.0, "and of the next rack's fighter")
	assert_almost_eq(float(fit["release_tail_m"]), 4.58, 0.01, "let go with its tail 4.6 m past the arm's top")
	var stored_only: Dictionary = LaunchProfile.from_dict({"release_extra_m": 0.0})
	var at_station_release: Dictionary = LaunchSequence.clearances(STARFURY, _hardpoints().cobra_arm, stored_only["profile"])
	assert_lt(float(at_station_release["release_tail_m"]), 0.0, "at the station's own release point its tail would still be in the well")


# Whether `point` is in the picture of a 16:9 camera at `pose` (fov vertical, degrees), a margin in from the edges.
static func _in_view(pose: CinematicShot.Pose, point: Vector3) -> bool:
	var p: Vector3 = pose.transform.affine_inverse() * point
	if p.z > -1.0:
		return false
	var half_v: float = tan(deg_to_rad(pose.fov) * 0.5) * 0.95
	return absf(p.y / -p.z) < half_v and absf(p.x / -p.z) < half_v * 16.0 / 9.0


# A whole launch of `count` fighters from Alpha 3 (the player is F1) through the shipped profile, its cut drawn from `cut` and played
# through the shot sequencer, the drum still: each shot's window on screen, the player's pose each tick (drum frame; past the release
# at its hand-off velocity), the ejection times and the doors of the first wave in firing order.
func _timeline(cut: LaunchCut, seed_value: int, count: int, start_arm: float = 200.0, seconds: float = 14.0) -> Dictionary:
	var profile: LaunchProfile = cut.profile
	var seq := LaunchSequence.create(_hardpoints(), "alpha", _ids(count), profile, 3, _drum_for(start_arm), 0.0, seed_value)
	var shots: Array[Dictionary] = cut.pick(seed_value, mini(count, 6))
	var sequencer := LaunchShotSequencer.new(profile)
	var starts: Dictionary = {}
	var poses: Array[Transform3D] = []
	var releases := PackedFloat64Array()
	var windows: Array[Dictionary] = []
	var handoff: Dictionary = {}
	var released_at: float = -1.0
	for i: int in roundi(seconds / DT):
		for e: Dictionary in seq.advance(DT, seq.drum_angle, 0.0):
			if e["kind"] == "release":
				releases.append(seq.time_s)
		var step: StringName = seq.step_of("F1")
		if not step.is_empty() and not starts.has(step):
			starts[step] = seq.time_s - seq.step_time("F1")
		var due := PackedInt32Array()
		for k: int in shots.size():
			if starts.has(shots[k]["step"]) and seq.time_s - float(starts[shots[k]["step"]]) >= float(shots[k]["at_s"]) - 1e-6:
				due.append(k)
		var play: int = sequencer.next(seq.time_s, due, shots, LaunchDirector.released_count(seq), LaunchDirector.wave_left(seq))
		if play >= 0:
			if not windows.is_empty():
				windows[-1]["end"] = seq.time_s
			windows.append({"entry": shots[play], "start": seq.time_s,
					"end": seq.time_s + (shots[play]["shot"] as CinematicShot).duration_s})
		if step == &"release" and handoff.is_empty():
			var bay: Dictionary = seq.bays[seq.fighter("F1")["bay"]]
			handoff = {"transform": Transform3D(seq.launch_basis(bay), seq.release_point(bay)),
					"velocity": (bay["release_direction"] as Vector3).normalized() * seq.release_speed(bay)}
			released_at = seq.time_s
		if handoff.is_empty():
			poses.append(seq.local_pose("F1"))
		else:
			var at: Transform3D = handoff["transform"]
			poses.append(Transform3D(at.basis, at.origin + (handoff["velocity"] as Vector3) * (seq.time_s - released_at)))
	var doors: Array[Vector3] = []
	for k: int in mini(count, 3):
		doors.append(seq.bays[seq.fighter("F%d" % (k + 1))["bay"]]["door"])
	return {"windows": windows, "poses": poses, "releases": releases, "doors": doors,
			"door_frame": LaunchSequence.door_frame(seq.bays[seq.fighter("F1")["bay"]]), "seconds": seconds}


# Checks every shot window of a timeline: at least `min_shot_s` on screen (the last one its own length), a row shot over three
# ejections in a wave, and its subject in the picture all the time it is on screen. Returns the variants seen.
func _check_windows(run: Dictionary, profile: LaunchProfile, count: int, what: String) -> PackedStringArray:
	var seen := PackedStringArray()
	var poses: Array[Transform3D] = run["poses"]
	var door: Transform3D = run["door_frame"]
	var windows: Array[Dictionary] = run["windows"]
	for w: Dictionary in windows:
		var entry: Dictionary = w["entry"]
		var shot: CinematicShot = entry["shot"]
		var start: float = w["start"]
		var end: float = minf(float(w["end"]), float(run["seconds"]))
		seen.append(String(entry["variant"]))
		if float(w["end"]) <= float(run["seconds"]):
			assert_gte(float(w["end"]) - start, profile.min_shot_s - 1e-6, "%s held %.2f s (%s)" % [entry["variant"],
					float(w["end"]) - start, what])
		if bool(entry["row"]) and count >= profile.row_wave_min:
			var out: int = Array(run["releases"]).filter(func(t: float) -> bool: return t >= start - 1e-6 and t <= end + 1e-6).size()
			assert_gte(out, 3, "%s shows %d fighters come out (%s)" % [entry["variant"], out, what])
		for n: int in 9:
			var t: float = lerpf(start, end, float(n) / 8.0)
			var tick: int = clampi(roundi(t / DT) - 1, 0, poses.size() - 1)
			var fighter: Transform3D = poses[tick]
			var actor := func(name: String) -> Variant: return door if name == "bay" else (fighter if name == "fighter" else null)
			var pose: CinematicShot.Pose = shot.pose_at(t - start, actor, func(_o: PackedFloat64Array) -> Vector3: return Vector3.ZERO)
			if entry["subject"] == "row":
				for d: Vector3 in run["doors"] as Array[Vector3]:
					assert_true(_in_view(pose, d), "%s keeps door %s in frame %.2f s in (%s)" % [entry["variant"], d, t - start, what])
			else:
				assert_true(_in_view(pose, fighter.origin), "%s frames the fighter %.2f s in (%s)" % [entry["variant"], t - start, what])
	return seen


func test_every_shot_holds_a_second_and_frames_its_subject_in_seeded_runs() -> void:
	var profile: LaunchProfile = LaunchProfile.load_file()["profile"]
	var seen: Dictionary = {}
	for count: int in [1, 4]:
		var cut := LaunchCut.new(profile)
		for i: int in 10:
			var run: Dictionary = _timeline(cut, 9000 + i, count)
			for id: String in _check_windows(run, profile, count, "seed %d, %d fighters" % [9000 + i, count]):
				seen[id] = true
	var held := LaunchCut.new(profile)
	for i: int in 2:  # under the spine for good (the drum still): the hold pool
		for id: String in _check_windows(_timeline(held, 77 + i, 1, 70.0, 8.0), profile, 1, "held"):
			seen[id] = true
	for phase: Dictionary in profile.phases:
		for variant: Dictionary in phase["variants"]:
			assert_true(seen.has(String(variant["id"])), "%s played in some run" % variant["id"])


func test_a_wave_films_its_drop_with_a_row_shot_over_three_ejections() -> void:
	var profile: LaunchProfile = LaunchProfile.load_file()["profile"]
	var cut := LaunchCut.new(profile)
	for i: int in 6:
		var run: Dictionary = _timeline(cut, 500 + i, 4)
		var rows: Array = (run["windows"] as Array).filter(func(w: Dictionary) -> bool: return bool(w["entry"]["row"]))
		assert_eq(rows.size(), 1, "one row shot for the wave's drop (seed %d)" % (500 + i))
		var w: Dictionary = rows[0]
		var out: int = Array(run["releases"]).filter(func(t: float) -> bool: return t >= float(w["start"]) and t <= float(w["end"])).size()
		assert_gte(out, 3, "%s: %d come out in the shot" % [w["entry"]["variant"], out])
		assert_false((run["windows"] as Array).any(func(x: Dictionary) -> bool: return x["entry"]["phase"] == "exit"),
				"no cut per fighter: the exit is left out")
	assert_false(LaunchProfile.from_dict({"min_shot_s": 0.5})["ok"], "no shot under a second (maintainer)")


func test_the_launch_follows_the_doors_briskly_and_clear_of_the_leaves() -> void:
	var profile: LaunchProfile = LaunchProfile.load_file()["profile"]
	var hp := _hardpoints()
	var seq := LaunchSequence.create(hp, "alpha", _ids(6), profile, 1, _drum_for(200.0), 0.0, 31)
	var events: Dictionary = {}
	var worst_turn_y: float = -INF
	var nose_out_ajar: int = 0
	for i: int in roundi(10.0 / DT):
		for e: Dictionary in seq.advance(DT, seq.drum_angle, 0.0):
			var key: String = "%s %s" % [e["kind"], e["id"] if not String(e["id"]).is_empty() else e["bay"]]
			if not events.has(key):
				events[key] = seq.time_s
		for f: Dictionary in seq.fighters:
			var bay: Dictionary = seq.bays[f["bay"]]
			var to_door: Transform3D = LaunchSequence.door_frame(bay).affine_inverse() * seq.local_pose(String(f["id"]))
			var reach: float = -INF
			for c: int in 8:
				reach = maxf(reach, (to_door * STARFURY.get_endpoint(c)).y)
			if f["phase"] == LaunchSequence.Phase.ROTATING:
				worst_turn_y = maxf(worst_turn_y, reach)
			# Any part of it at the doors' plane (the leaves' swing) while the leaves are not fully open would meet them.
			if f["phase"] != LaunchSequence.Phase.RELEASED and reach > -0.5 \
					and seq.door_angle_deg(int(f["bay"])) < profile.door_open_deg - 1e-3:
				nose_out_ajar += 1
	for k: int in 6:
		var id: String = "F%d" % (k + 1)
		var bay_name: String = seq.bays[seq.fighter(id)["bay"]]["name"]
		var opened: float = events["door_open %s" % bay_name]
		var dropped: float = events["drop %s" % id]
		assert_between(dropped - opened, 0.25 - DT, 0.5 + DT, "%s ejected %.2f s after its door is open" % [id, dropped - opened])
		assert_lt(float(events["rotate %s" % id]), opened, "%s turns while its leaves swing" % id)
		assert_lte(float(events["turned %s" % id]), dropped + 1e-6, "and is nose-out before its ejection")
	assert_lt(worst_turn_y, -1.0, "the turn stays inside the doors' plane (%.2f m)" % worst_turn_y)
	assert_eq(nose_out_ajar, 0, "nothing reaches the doors' plane before the leaves are fully open")
	assert_gt(LaunchSequence.leaf_clearance(STARFURY, seq.bays[0], profile.door_open_deg, profile), 1.0,
			"the open leaves stand clear of its wings")
	assert_lt(LaunchSequence.leaf_clearance(STARFURY, seq.bays[0], 45.0, profile), 0.0, "a half-open leaf would be in its way")
	assert_almost_eq(profile.lead_s(), 2.3, 1e-6, "slot to ejection: door 2 s plus 0.3 s")
