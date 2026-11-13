extends GutTest
## `LaunchSequence` and `LaunchProfile` (M7-T08, D76, AC7): the hand-off state, a skip landing in the same state, the hold under the
## spine (none released inside a blocked sector), the 10 s gap between the waves, the second row onto the racks, the doors, and a
## rebase moving nothing. The arm here is laid out as the generator lays out the top (Alpha) arm.

const DT: float = 1.0 / 60.0
const SPIN: float = 0.148
const PIVOT := Vector3(0.0, 0.0, -1000.0)
## The generator's blocked sector over the arms (T05) and the top arm's angle.
const BLOCKED := [57.0, 123.5]
const ARM_DEG: float = 90.0


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
			"cobra_arm": {"arms": [{"name": "top", "wing": "alpha", "angle_deg": ARM_DEG, "bays": names}]},
			"launch_clearance": {"blocked_sectors_deg": [BLOCKED], "clear_distance_m": 260.0, "margin_deg": 10.0},
			"main_docking_bay": {"name": "main_docking_bay", "body": "drum"}, "cargo_bay": {"name": "cargo_bay", "body": "frame"},
			"grid_mounts": [], "lights": [], "tour_points": [], "damage_sections": []}})
	assert_true(hp.valid, hp.error)
	return hp


func _profile() -> LaunchProfile:
	var made: Dictionary = LaunchProfile.from_dict({"door_open_s": 3.0, "door_close_s": 3.0, "door_close_after_s": 2.0,
			"drop_s": 3.0, "stagger_s": 1.5, "wave_gap_s": 10.0, "row_move_s": 6.0})
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
	for step: StringName in [&"door", &"hold", &"drop"]:
		assert_false(profile.shots_in(step).is_empty(), "a shot for the %s step" % step)
	var bad: Dictionary = LaunchProfile.from_dict({"shots": [{"step": "landing", "keys": [{"t": 0.0,
			"position": {"actor": "bay"}, "look_at": {"actor": "bay"}}]}]})
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
	assert_eq(doors, PackedInt32Array([3, 4, 5, 6, 1, 2, 3, 4]), "the named door first, the second row behind the same doors")
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
	for i: int in 400:
		for e: Dictionary in seq.advance(DT, seq.drum_angle + SPIN * DT, SPIN):
			e["t"] = seq.time_s
			log.append(e)
			if e["kind"] == "release":
				at_release = seq.state_of("F1", PIVOT)
				handoff = seq.handoff_of("F1", PIVOT)
				release_angle = seq.drum_angle
	assert_almost_eq(float(_first(log, "door_open", "")["t"]), 3.0, 1e-6, "the door opens over door_open_s")
	assert_almost_eq(float(_first(log, "drop", "F1")["t"]), 3.0, 1e-6, "and the drop follows")
	assert_almost_eq(float(_first(log, "release", "F1")["t"]), 6.0, 1e-6, "the rail takes drop_s")
	var bay: Dictionary = seq.bays[seq.fighter("F1")["bay"]]
	var turn := Basis(Vector3.BACK, release_angle)
	var arm: Vector3 = turn * (bay["release"] as Vector3)
	var speed: float = 2.0 * 17.0 / 3.0  # 17 m of rail from rest in 3 s
	var expected_v: Vector3 = turn * Vector3(0.0, speed, 0.0) + Vector3(0.0, 0.0, SPIN).cross(arm)
	assert_almost_eq((handoff["transform"] as Transform3D).origin, PIVOT + arm, Vector3.ONE * 1e-4, "at the release point")
	assert_almost_eq(handoff["velocity"], expected_v, Vector3.ONE * 1e-4, "with the drum's surface velocity and the rail's speed")
	assert_almost_eq((expected_v - turn * Vector3(0.0, speed, 0.0)).length(), SPIN * 244.5, 1e-3, "about 36 m/s at r 244.5")
	assert_almost_eq(handoff["angular"], Vector3(0.0, 0.0, SPIN), Vector3.ONE * 1e-9, "turning with the drum")
	assert_almost_eq((at_release["transform"] as Transform3D).origin, (handoff["transform"] as Transform3D).origin,
			Vector3.ONE * 1e-4, "the played drop ends in the hand-off state")
	assert_almost_eq(at_release["velocity"], handoff["velocity"], Vector3.ONE * 1e-3)


func test_the_rail_is_continuous_into_the_hand_off() -> void:
	var seq := LaunchSequence.create(_hardpoints(), "alpha", _ids(1), _profile(), 1, _drum_for(200.0), SPIN)
	var last: Dictionary = {}
	for i: int in 400:
		var before: Dictionary = seq.state_of("F1", PIVOT)
		var events: Array[Dictionary] = seq.advance(DT, seq.drum_angle + SPIN * DT, SPIN)
		if not events.filter(func(e: Dictionary) -> bool: return e["kind"] == "release").is_empty():
			last = before
			break
	assert_false(last.is_empty())
	var handoff: Dictionary = seq.handoff_of("F1", PIVOT)
	assert_lt(((handoff["transform"] as Transform3D).origin - (last["transform"] as Transform3D).origin).length(), 1.0,
			"one tick before the release it is within a tick's travel of the release point")


func test_skipping_lands_in_the_same_hand_off_state() -> void:
	var played := LaunchSequence.create(_hardpoints(), "alpha", _ids(2), _profile(), 4, _drum_for(200.0), SPIN)
	_run(played, 7.0)
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
	assert_almost_eq(a["point"], Vector3(0.0, 244.5, -1875.5), Vector3.ONE * 1e-4, "door 4's release point")


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
	assert_almost_eq(float(hold["t"]), 3.0, 1e-6, "held when its drop was due")
	assert_almost_eq(float(drop["arm"]), BLOCKED[1], 0.2, "drops as the arm leaves the sector")
	assert_gt(float(seq.fighter("F1")["held_s"]), 0.0, "the hold is counted")
	assert_false(_hardpoints().launch_blocked(float(release["arm"])))


func test_a_drop_that_would_end_inside_the_sector_waits() -> void:
	# The arm is clear when the drop is due, but would turn into the sector before the release.
	var due_arm: float = 57.0 - 10.0  # 25 degrees of turn in a 3 s drop
	var seq := LaunchSequence.create(_hardpoints(), "alpha", _ids(1), _profile(), 1,
			_drum_for(due_arm - rad_to_deg(SPIN * 3.0)), SPIN)
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
	assert_almost_eq(float(_first(log, "drop", "F8")["t"]) - float(_first(log, "drop", "F7")["t"]), 1.5, 1e-6, "staggered")


func test_a_hold_slips_the_rest_of_the_wave() -> void:
	var seq := LaunchSequence.create(_hardpoints(), "alpha", _ids(3), _profile(), 1, _drum_for(70.0), SPIN)
	var log: Array[Dictionary] = _run(seq, 30.0)
	var d1: float = float(_first(log, "drop", "F1")["t"])
	assert_gt(d1, 3.0 + 1.0, "the first was held")
	assert_almost_eq(float(_first(log, "drop", "F2")["t"]) - d1, 1.5, 1e-6, "the next drops a stagger after it")
	assert_almost_eq(float(_first(log, "drop", "F3")["t"]) - d1, 3.0, 1e-6)


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
	assert_almost_eq(float(closing["t"]), 6.0 + 2.0 + DT, 1e-6, "closing door_close_after_s after the release (its first tick)")
	assert_almost_eq(float(_first(log, "door_closed", "")["t"]), 6.0 + 2.0 + 3.0, 1e-6)
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
