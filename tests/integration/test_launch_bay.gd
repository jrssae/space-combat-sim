extends GutTest
## Cobra-bay launches on the real main scene (M7-T08, D76, AC7): the `station_launch` scenario starts the player on Alpha 3's rack
## with the controls held and the wingmen on the arm's other racks; the fighters ride the turning drum; the launch camera plays its
## shots; the player is handed over at the release point with the drum's surface velocity; a skip (Start) lands in the same state;
## the wingmen follow from the next doors in the wave order; the doors' toothed leaves slide apart and shut again (M8-T02); a rebase mid-launch moves nothing on screen; a launch due under the
## spine holds; `launch wing` launches twelve AI Starfuries, `launch wing all` every wing, and a launched Alpha wing flies as the
## player's wingmen, takes the wing orders (M7-T58) and forms up with its arms even (M7-T74).
## Every place comes from the station's hardpoints.

const DT: float = 1.0 / 60.0
const SCENARIO: String = "res://data/scenarios/station_launch.json"

var main: Main
var station: Station
var source: FakeInputSource
var shots_seen: PackedStringArray = PackedStringArray()


func before_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()
	shots_seen = PackedStringArray()


func after_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()


func _start() -> void:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	source = FakeInputSource.new()
	main.input_source = source
	main.scenario_path = SCENARIO
	main.raider_pool_size = 0
	main.waves_auto_start = false
	add_child_autofree(main)
	await _ticks(2)
	station = main.far_props.station


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame
		var shot: CinematicShot = main.camera_rig.playing_shot() if main != null else null
		if shot != null and (shots_seen.is_empty() or shots_seen[-1] != String(shot.id)):
			shots_seen.append(String(shot.id))


func _until(done: Callable, limit: int) -> bool:
	for i: int in limit:
		if done.call():
			return true
		await _ticks(1)
	return bool(done.call())


func _ship(ship_name: String) -> Combatant:
	for c: Combatant in main.ships.alive():
		if c.display_name == ship_name:
			return c
	return null


# Where the drum carries a point given in its frame, now (the drum's body after this tick's step).
func _on_drum(point: Vector3) -> Vector3:
	return station.to_world(point, StationHardpoints.DRUM)


# A World state put back in the drum's frame at `drum_angle`: the point and the velocity against the turning drum.
func _in_drum(xform: Transform3D, velocity: Vector3, drum_angle: float) -> Dictionary:
	var station_xform: Transform3D = station.global_transform
	var turn := Basis(Vector3.BACK, drum_angle)
	var arm: Vector3 = station_xform.affine_inverse() * xform.origin - station.drum_origin
	var v: Vector3 = station_xform.basis.inverse() * (velocity - main.world.rest_velocity())
	var relative: Vector3 = v - Vector3(0.0, 0.0, station.spin.rate_rad_s).cross(arm)
	return {"point": turn.inverse() * arm, "velocity": turn.inverse() * relative}


# Nose first, let go `release_extra_m` past the station's release point at the rail's speed there.
func _expected_release(bay_name: String) -> Dictionary:
	var bay: Dictionary = station.hardpoints.bay(bay_name)
	var profile: LaunchProfile = main.launches.profile
	var out: Vector3 = (bay["release_direction"] as Vector3).normalized()
	var point: Vector3 = (bay["release"] as Vector3) + out * profile.release_extra_m
	var rail: float = (bay["rail_end"] as Vector3).distance_to(bay["rail_start"]) + point.distance_to(bay["rail_end"])
	return {"point": point, "velocity": out * (2.0 * rail / profile.drop_s), "nose": out}


func test_the_scenario_starts_the_player_on_its_rack_with_the_wingmen_beside() -> void:
	await _start()
	assert_not_null(station, "the scenario anchors on Babylon 5")
	assert_eq(main.launches.start_bay, "cobra_bay_alpha_3")
	assert_true(main.controls_locked(), "the controls are held on the rack")
	var bays: Dictionary = {"PLAYER": "cobra_bay_alpha_3", "ALPHA 2": "cobra_bay_alpha_4", "ALPHA 3": "cobra_bay_alpha_5",
			"ALPHA 4": "cobra_bay_alpha_6"}
	for ship_name: String in bays:
		var ship: Ship = main.ship if ship_name == "PLAYER" else _ship(ship_name).ship
		var rack: Vector3 = _on_drum(station.hardpoints.bay(bays[ship_name])["rail_start"])
		assert_almost_eq(ship.global_position, rack, Vector3.ONE * 0.05, "%s hangs on %s's rack" % [ship_name, bays[ship_name]])
		assert_eq(ship.collision_layer, 0, "%s touches nothing while it rides the drum" % ship_name)
	# Stored at 90 degrees to the launch: nose along the arm, as the station's rack pose has it.
	var bay: Dictionary = station.hardpoints.bay("cobra_bay_alpha_3")
	var drum_basis: Basis = station.global_basis * Basis(Vector3.BACK, station.drum_angle)
	assert_almost_eq(main.ship.global_basis * Vector3.FORWARD, drum_basis * (bay["forward"] as Vector3), Vector3.ONE * 0.01,
			"stored nose along the arm")
	assert_almost_eq(main.ship.global_basis * Vector3.UP, drum_basis * (bay["up"] as Vector3), Vector3.ONE * 0.01,
			"its top toward the drum's axis")
	# Carried with the drum: a second later still on its rack, which has moved some 36 m with the turn.
	var before: Vector3 = main.ship.global_position
	await _ticks(60)
	var rack_now: Vector3 = _on_drum(station.hardpoints.bay("cobra_bay_alpha_3")["rail_start"])
	assert_almost_eq(main.ship.global_position, rack_now, Vector3.ONE * 0.05, "still on the rack")
	assert_gt(main.ship.global_position.distance_to(before), 25.0, "which turned with the drum")
	assert_almost_eq(main.ship.linear_velocity.length(), station.spin.rate_rad_s * 227.5, 0.5, "at the drum's speed there")
	var cut: Array = main.launches.launches[0]["cut"]
	assert_eq(cut[0]["phase"], "rack", "the cut opens on the rack")
	assert_eq(shots_seen[0], String(cut[0]["variant"]), "the launch camera opens with the cut's rack shot")

	assert_eq(DebugConsole.registry.execute("get launch.player")[0].lines[0], "launch.player = true")


func test_the_player_is_handed_over_with_the_bays_velocity() -> void:
	await _start()
	var rig: LightRig = LightRig.of(main)
	assert_true(await _until(func() -> bool: return main.launches.fill != null, 400), "the drop is lit by its fill")
	assert_true(rig.has_emitter(main.launches.fill), "through the scene's light rig (the LightPicker's budget)")
	var drop_fill: LightEmitter = main.launches.fill
	assert_true(await _until(func() -> bool: return not main.launches.last_handoff.is_empty(), 900), "the player is let go")
	var handoff: Dictionary = main.launches.last_handoff
	assert_eq(handoff["bay"], "cobra_bay_alpha_3")
	assert_false(bool(handoff["skipped"]))
	var drum: Dictionary = _in_drum(handoff["transform"], handoff["velocity"], float(handoff["drum_angle"]))
	var expected: Dictionary = _expected_release("cobra_bay_alpha_3")
	assert_almost_eq(drum["point"], expected["point"], Vector3.ONE * 0.01, "at the release point")
	assert_almost_eq(drum["velocity"], expected["velocity"], Vector3.ONE * 0.01, "moving with the drum plus the rail's speed")
	var turn := Basis(Vector3.BACK, float(handoff["drum_angle"]))
	assert_almost_eq((handoff["transform"] as Transform3D).basis * Vector3.FORWARD,
			station.global_basis * turn * (expected["nose"] as Vector3), Vector3.ONE * 0.01, "nose first, out of the drum")
	assert_false(main.launches.locks_controls(), "the controls come back at the hand-off")
	assert_ne(main.ship.collision_layer, 0, "it collides again")
	assert_false(main.ship.custom_integrator, "and thrust moves it again")
	# Jolt flies it on from the hand-off state: one step later it has moved a tick's worth at that velocity.
	var at: Vector3 = (handoff["transform"] as Transform3D).origin
	assert_almost_eq(main.ship.global_position, at + (handoff["velocity"] as Vector3) * DT, Vector3.ONE * 0.05,
			"flies on from the release point")
	# Its engines light as it clears: a second later it is moving faster along its nose than it was let go.
	var nose: Vector3 = (handoff["transform"] as Transform3D).basis * Vector3.FORWARD
	await _ticks(60)
	assert_gt((main.ship.linear_velocity - (handoff["velocity"] as Vector3)).dot(nose), 5.0, "under thrust, nose first")
	await _ticks(320)
	var played := PackedStringArray()
	var log: Array[Dictionary] = main.launches.sequencer.log
	for k: int in log.size():
		played.append(String(main.launches._launch_shot["cut"][log[k]["index"]]["variant"]))
		if k > 0:
			assert_gte(float(log[k]["start"]) - float(log[k - 1]["start"]), main.launches.profile.min_shot_s - 1e-6,
					"each shot held at least a second")
	assert_eq(shots_seen, played, "the launch camera played its cut as the sequencer called it")
	assert_true(played.size() >= 4, "rack, turn, drop and chase at least (%s)" % played)
	assert_false(main.camera_rig.is_playing_shot(), "and gave the view back")
	assert_null(main.launches.fill, "the fill went out with its shot")
	assert_false(rig.has_emitter(drop_fill), "and left the light rig")
	var door: Vector3 = _on_drum(station.hardpoints.bay("cobra_bay_alpha_3")["door"])
	assert_gt(main.ship.global_position.distance_to(door), 30.0, "it has left the bay")


func test_a_starfury_fits_the_real_arm_nose_first() -> void:
	await _start()
	var manifest: Dictionary = MeshAssets.read_manifest("starfury_aurora")
	var lo: Array = manifest["aabb_min"]
	var hi: Array = manifest["aabb_max"]
	var box := AABB(Vector3(lo[0], lo[1], lo[2]), Vector3(hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]))
	var fit: Dictionary = LaunchSequence.clearances(box, station.hardpoints.cobra_arm, main.launches.profile)
	gut.p("clearances: %s" % fit)
	for key: String in fit:
		assert_gt(float(fit[key]), 1.0, "%s: %.2f m to spare" % [key, fit[key]])
	var seq: LaunchSequence = main.launches.launches[0]["seq"]
	for bay: Dictionary in seq.bays:
		assert_almost_eq(seq.stored_pose_offset_deg(bay), 0.0, 0.5, "%s: the station's rack pose is the stored pose" % bay["name"])
		var leaf: float = LaunchSequence.leaf_clearance(box, bay, 1.0, main.launches.profile)
		assert_gt(leaf, 2.0, "%s: its leaves slid back leave %.2f m beside the wings" % [bay["name"], leaf])


func test_skipping_lands_in_the_same_state() -> void:
	await _start()
	await _ticks(30)
	source.hold(InputAdapter.PAUSE)
	await _ticks(1)
	source.release(InputAdapter.PAUSE)
	await _ticks(2)
	assert_false(main.launches.last_handoff.is_empty(), "Start skips to the hand-off")
	var handoff: Dictionary = main.launches.last_handoff
	assert_true(bool(handoff["skipped"]))
	assert_false(main.pause_menu.is_open(), "Start skipped; it did not pause")
	var drum: Dictionary = _in_drum(handoff["transform"], handoff["velocity"], float(handoff["drum_angle"]))
	var expected: Dictionary = _expected_release("cobra_bay_alpha_3")
	assert_almost_eq(drum["point"], expected["point"], Vector3.ONE * 0.01, "the same release point")
	assert_almost_eq(drum["velocity"], expected["velocity"], Vector3.ONE * 0.01, "the same velocity against the drum")
	assert_false(main.camera_rig.is_playing_shot(), "the shot is cut")
	assert_false(main.controls_locked(), "the controls are back")
	await _ticks(30)
	assert_eq(main.launches.launches.size(), 1, "the wingmen go on with their launch")


func test_the_wingmen_launch_from_the_next_doors_in_the_wave_order() -> void:
	await _start()
	var released: Array[String] = []
	var times: Array[float] = []
	var seq: LaunchSequence = main.launches.launches[0]["seq"]
	for i: int in 1200:
		await _ticks(1)
		for f: Dictionary in seq.fighters:
			if f["phase"] == LaunchSequence.Phase.RELEASED and not released.has(String(f["id"])):
				released.append(String(f["id"]))
				times.append(float(f["released_at"]))
		if released.size() == 4:
			break
	assert_eq(released, [main.combatant.display_name, "ALPHA 2", "ALPHA 3", "ALPHA 4"] as Array[String],
			"the player first, then the wing in order")
	for k: int in range(1, 4):
		assert_between(times[k] - times[k - 1], main.launches.profile.stagger_min_s - DT, main.launches.profile.stagger_max_s + DT,
				"the doors ripple a quarter to half a second apart")
	var wingman: Ship = _ship("ALPHA 4").ship
	assert_ne(wingman.collision_layer, 0, "the last wingman flies free")
	assert_gt(wingman.global_position.distance_to(_on_drum(station.hardpoints.bay("cobra_bay_alpha_6")["rail_start"])), 15.0,
			"and has left its rack")


func test_the_doors_toothed_leaves_slide_apart_for_the_launch_and_shut_after() -> void:
	# M8-T02: the player's door (Alpha 3) through its launch: shut, sliding, open for the ejection, sliding, shut; and the ripple.
	await _start()
	var seq: LaunchSequence = main.launches.launches[0]["seq"]
	var bay_name: String = "cobra_bay_alpha_3"
	var bay: Dictionary = station.hardpoints.bay(bay_name)
	var index: int = -1
	for k: int in seq.bays.size():
		if seq.bays[k]["name"] == bay_name:
			index = k
	assert_gt(index, -1)
	var leaves: StationDoorLeaves = main.launches.door_leaves()
	assert_not_null(leaves, "the director found the drum's leaves")
	assert_eq(leaves.count(), 24, "two leaves on each of the 24 doors")
	assert_eq(leaves.leaf_count(bay_name), 2)
	var normal: Vector3 = (bay["normal"] as Vector3).normalized()
	var across: Vector3 = (bay["across"] as Vector3).normalized()
	var travel: float = float((bay["leaves"] as Array)[0]["travel_m"])
	var shut: Array[Transform3D] = []
	for which: int in 2:
		var now: Transform3D = leaves.leaf_transform(bay_name, which)
		shut.append(Transform3D(now.basis, now.origin - leaves.slide_direction(bay_name, which) * leaves.slide_m(bay_name, which)))
	assert_almost_eq(shut[0].origin, shut[1].origin, Vector3.ONE * 1e-4, "shut, the two leaves lie on one door (their teeth mesh)")
	var states: Array[int] = [int(seq.doors[index]["state"])]
	var first_tick: Dictionary = {}  # state -> the tick it was first seen
	var last_share: float = leaves.open_share(bay_name)
	var opened_at: Dictionary = {}  # bay index -> tick its door began to open
	var dropped_ajar: bool = false
	for tick: int in 900:
		var state: int = int(seq.doors[index]["state"])
		if state != states[-1]:
			states.append(state)
			first_tick[state] = tick
		for k: int in seq.doors.size():
			if int(seq.doors[k]["state"]) != LaunchSequence.DoorState.CLOSED and not opened_at.has(k):
				opened_at[k] = tick
		var share: float = leaves.open_share(bay_name)
		assert_almost_eq(share, seq.door_share(index), 1e-6, "the drawn leaves follow the sequence")
		if state == LaunchSequence.DoorState.OPENING:
			assert_gte(share, last_share, "sliding back")
		elif state == LaunchSequence.DoorState.CLOSING:
			assert_lte(share, last_share, "sliding shut")
		last_share = share
		for which: int in 2:
			var moved: Vector3 = leaves.leaf_transform(bay_name, which).origin - shut[which].origin
			var side: float = 1.0 if which == 0 else -1.0
			assert_almost_eq(moved, across * side * share * travel, Vector3.ONE * 1e-3, "each leaf slides across the arm, away from the other")
			assert_almost_eq(moved.dot(normal), 0.0, 1e-3, "in the doors' plane: it never swings out")
			assert_true(leaves.leaf_transform(bay_name, which).basis.is_equal_approx(shut[which].basis), "and never turns")
		var player: Dictionary = seq.fighter(main.combatant.display_name)
		if player["phase"] == LaunchSequence.Phase.DROPPING and share < 1.0:
			dropped_ajar = true
		if states.size() > 1 and state == LaunchSequence.DoorState.CLOSED:
			break
		await _ticks(1)
	var names: Array[String] = []
	for state: int in states:
		names.append(LaunchSequence.DOOR_NAMES[state])
	if names[0] == "closed":
		names.remove_at(0)
	assert_eq(names, ["opening", "open", "closing", "closed"] as Array[String], "shut, sliding, open, sliding, shut")
	assert_false(dropped_ajar, "the fighter is ejected only through a fully open door")
	assert_eq(leaves.open_share(bay_name), 0.0, "shut again")
	for which: int in 2:
		assert_almost_eq(leaves.leaf_transform(bay_name, which).origin, shut[which].origin, Vector3.ONE * 1e-5, "back on its door")
	var profile: LaunchProfile = main.launches.profile
	assert_almost_eq(float(int(first_tick[LaunchSequence.DoorState.CLOSED]) - int(first_tick[LaunchSequence.DoorState.CLOSING])) * DT, profile.door_close_s,
			2.0 * DT, "the closing time kept")
	assert_gt(travel - float((bay["leaves"] as Array)[0]["reach_m"]), (bay["door_half_m"] as Vector2).x, "open, the teeth are out of the well")
	# The ripple kept: the wave's four doors (the player's, then the wingmen's aft of it) start a quarter to half a second apart.
	var starts: Array[int] = []
	for k: int in opened_at:
		starts.append(int(opened_at[k]))
	starts.sort()
	assert_eq(starts.size(), 4, "a door for the player and each of the three wingmen")
	for k: int in range(1, starts.size()):
		assert_between(float(starts[k] - starts[k - 1]) * DT, profile.stagger_min_s - DT, profile.stagger_max_s + DT, "the doors ripple open")


func test_a_rebase_mid_launch_moves_nothing_on_screen() -> void:
	await _start()
	await _ticks(150)  # nose first on the rail (the ejection runs 2.3 s to 3.05 s)
	var seq: LaunchSequence = main.launches.launches[0]["seq"]
	assert_eq(seq.fighter(main.combatant.display_name)["phase"], LaunchSequence.Phase.DROPPING, "dropping down the rail")
	var offset := Vector3(4000.0, -1500.0, 2500.0)
	var in_station: Vector3 = station.global_transform.affine_inverse() * main.ship.global_position
	var screen: Vector3 = main.ship.global_position - main.camera_rig.get_viewport().get_camera_3d().global_position
	main.world.rebase(offset)
	assert_almost_eq(station.global_transform.affine_inverse() * main.ship.global_position, in_station, Vector3.ONE * 1e-3,
			"the fighter stays where it was on the station")
	assert_almost_eq(main.ship.global_position - main.camera_rig.get_viewport().get_camera_3d().global_position, screen,
			Vector3.ONE * 1e-3, "and where it was on screen")
	await _ticks(1)
	var expected: Vector3 = station.global_transform * seq.state_of(main.combatant.display_name, station.drum_origin)["transform"].origin
	assert_lt(main.ship.global_position.distance_to(expected), 1.0, "the next tick carries it on down the rail")
	assert_true(await _until(func() -> bool: return not main.launches.last_handoff.is_empty(), 400))
	var handoff: Dictionary = main.launches.last_handoff
	var drum: Dictionary = _in_drum(handoff["transform"], handoff["velocity"], float(handoff["drum_angle"]))
	assert_almost_eq(drum["point"], _expected_release("cobra_bay_alpha_3")["point"], Vector3.ONE * 0.01,
			"handed over at the release point all the same")


func test_a_launch_due_under_the_spine_holds_until_clear() -> void:
	await _start()
	DebugConsole.registry.execute("launch skip")
	await _ticks(2)
	# Wait for a wing (not Alpha's, still launching its wingmen) whose arm will be under the spine when its drop is due.
	assert_true(await _until(func() -> bool: return not _blocked_wing().is_empty(), 900), "an arm comes under the spine within a turn")
	var pick: String = _blocked_wing()
	gut.p("held launch from wing %s" % pick)
	var result: ConsoleResult = DebugConsole.registry.execute("launch %s 2" % pick)[0]
	assert_true(result.ok, "\n".join(result.lines))
	var seq: LaunchSequence = main.launches.player_launch()["seq"]
	assert_true(await _until(func() -> bool: return seq.fighter(main.combatant.display_name)["phase"] == LaunchSequence.Phase.HELD, 300),
			"held on the rack")
	var hold_ids := PackedStringArray()
	for variant: Dictionary in main.launches.profile.phase("hold")["variants"]:
		hold_ids.append(String(variant["id"]))
	assert_true(Array(shots_seen).any(func(id: String) -> bool: return hold_ids.has(id)), "the camera watches it wait (%s)" % shots_seen)
	await _ticks(30)
	_assert_cold(main.combatant, "held under the spine")
	assert_ne(DebugConsole.registry.execute("get launch.held")[0].lines[0], "launch.held = none")
	main.launches.last_handoff = {}
	assert_true(await _until(func() -> bool: return not main.launches.last_handoff.is_empty(), 1500), "let go once clear")
	assert_false(station.hardpoints.launch_blocked(seq.arm_angle_now()), "not inside the blocked sector")
	assert_gt(float(seq.fighter(main.combatant.display_name)["held_s"]), 0.0)


# The wing (not Alpha) whose arm will be well inside a blocked sector when a drop asked for now is due, or "".
func _blocked_wing() -> String:
	var rate_deg: float = rad_to_deg(station.spin.rate_rad_s)
	var due_s: float = main.launches.profile.lead_s() + 2.0 * DT
	for arm: Variant in station.hardpoints.cobra_arm["arms"]:
		var at_due: float = float(arm["angle_deg"]) + rad_to_deg(station.drum_angle) + rate_deg * due_s
		var blocked: bool = true
		for margin: float in [-2.0, 0.0, 2.0]:
			blocked = blocked and station.hardpoints.launch_blocked(at_due + margin)
		if blocked and String(arm["wing"]) != "alpha":
			return String(arm["wing"])
	return ""


func test_launch_wing_sends_twelve_starfuries_in_two_waves() -> void:
	await _start()
	var result: ConsoleResult = DebugConsole.registry.execute("launch wing zeta")[0]
	assert_true(result.ok, "\n".join(result.lines))
	var launch: Dictionary = main.launches.launches[-1]
	var seq: LaunchSequence = launch["seq"]
	assert_eq(seq.fighters.size(), 12, "twelve Starfuries")
	assert_eq((launch["ships"] as Dictionary).size(), 12)
	await _ticks(1)
	var first: Ship = _ship("ZETA 1").ship
	var seventh: Ship = _ship("ZETA 7").ship
	assert_almost_eq(first.global_position, _on_drum(station.hardpoints.bay("cobra_bay_zeta_1")["rail_start"]), Vector3.ONE * 0.05,
			"the first on door 1's rack")
	assert_almost_eq(seventh.global_position, _on_drum(station.hardpoints.bay("cobra_bay_zeta_1")["staging"]), Vector3.ONE * 0.05,
			"the seventh in the second row behind it")
	assert_true(await _until(func() -> bool: return seq.fighter("ZETA 1")["phase"] == LaunchSequence.Phase.RELEASED, 1500),
			"the first wave goes")
	assert_ne(first.collision_layer, 0, "and flies free")
	assert_true(await _until(func() -> bool: return seq.fighter("ZETA 7")["phase"] != LaunchSequence.Phase.STAGED, 60),
			"the second row moves up once its rack is empty")


func test_a_failed_wing_launch_leaves_no_hulls_in_the_wing() -> void:
	await _start()
	var wings_before: int = main.wings.wings.size()
	var free_before: int = main.ships.free_count(ShipPool.ALLY_TYPE)
	main.launches.profile = null  # `_start` refuses without a launch profile
	for attempt: int in 2:
		var why: String = main.launches.launch_wing("zeta")
		assert_false(why.is_empty(), "the launch fails (try %d)" % attempt)
		assert_null(main.wings.wing_named("ZETA"), "the wing this call made is gone again")
		assert_eq(main.wings.wings.size(), wings_before)
	assert_true(main.ships.free_count(ShipPool.ALLY_TYPE) >= free_before, "the hulls are back in the pool")
	# A wing that was there before keeps its place but not the hulls of the failed launch.
	var existing: Wing = main.wings.create_wing("ZETA", null)
	assert_false(main.launches.launch_wing("zeta").is_empty())
	assert_eq(main.wings.wing_named("ZETA"), existing, "a wing from before stays")
	assert_null(existing.leader)
	assert_eq(existing.members().size(), 0, "with nobody parked in it")


# The scenario started, the player skipped out and the Alpha arm's launch (the player's three wingmen) is over.
func _start_with_alpha_clear() -> void:
	await _start()
	DebugConsole.registry.execute("launch skip")
	assert_true(await _until(func() -> bool: return not main.launches.is_launching("alpha"), 3000), "the wingmen are out")


func _order_of(c: Combatant) -> AiContext.Order:
	return (c.driver.brain as AiPilot).context.order


func test_launch_wing_all_launches_every_wing() -> void:
	await _start_with_alpha_clear()
	var result: ConsoleResult = DebugConsole.registry.execute("launch wing all")[0]
	assert_true(result.ok, "\n".join(result.lines) + result.error)
	assert_eq(result.lines.size(), LaunchDirector.WINGS.size(), "a line a wing")
	for wing: String in LaunchDirector.WINGS:
		assert_true(main.launches.is_launching(wing), "wing %s launches" % wing)
	for launch: Dictionary in main.launches.launches:
		var expected: int = 8 if launch["wing"] == "alpha" else LaunchDirector.WING_SIZE
		assert_eq((launch["ships"] as Dictionary).size(), expected, "%s: Alpha fills the player's eight free slots" % launch["wing"])
	for wing_name: String in ["BETA", "DELTA", "ZETA"]:
		var wing: Wing = main.wings.wing_named(wing_name)
		assert_not_null(wing)
		assert_true(wing != null and wing.leader != null and not wing.leader.is_player, "%s keeps its own AI leader" % wing_name)
		assert_eq(wing.members().size(), LaunchDirector.WING_SIZE - 1 if wing != null else -1)
	var again: ConsoleResult = DebugConsole.registry.execute("launch wing all")[0]
	assert_false(again.ok, "nothing more to launch while every wing is on its way")


func test_a_launched_alpha_wing_flies_as_the_players_wingmen() -> void:
	await _start_with_alpha_clear()
	var own: Wing = main.wings.player_wing()
	assert_eq(own.name, "ALPHA")
	assert_eq(own.leader, main.combatant, "the player is Alpha 1")
	var wings_before: int = main.wings.wings.size()
	# A launch that falls through leaves the player's wing as it was.
	var kept: LaunchProfile = main.launches.profile
	main.launches.profile = null
	assert_false(main.launches.launch_wing("alpha").is_empty())
	assert_eq(own.size, Wing.DEFAULT_SIZE, "the slots it grew are gone again")
	assert_eq(own.members().size(), 3, "with only the three wingmen in it")
	main.launches.profile = kept
	var result: ConsoleResult = DebugConsole.registry.execute("launch wing alpha")[0]
	assert_true(result.ok, result.error)
	var ships: Array = (main.launches.launches[-1]["ships"] as Dictionary).values()
	assert_eq(ships.size(), 8, "the rest of Alpha: eleven slots less the three wingmen")
	assert_eq(own.size, LaunchDirector.WING_SIZE - 1)
	assert_eq(main.wings.wings.size(), wings_before, "no second Alpha wing")
	for c: Combatant in ships:
		var slot: int = own.slot_of(c)
		assert_between(slot, 4, 11, "%s flies a slot of the player's wing" % c.display_name)
		assert_eq(c.display_name, own.callsign(slot), "named for its slot")
	await _ticks(1)
	var leader_id: int = main.combatant.targetable.get_instance_id()
	# The comms menu, as the radial menu sends it.
	assert_true(DebugConsole.registry.execute("commsmenu open")[0].ok, "the menu opens")
	assert_true(DebugConsole.registry.execute("commsmenu pick 1")[0].ok, "FORM ON ME")
	await _ticks(1)
	assert_eq(own.order, AiContext.Order.FORM_ON_ME)
	assert_string_contains(main.wings.last_ack, "FORMING UP")
	for c: Combatant in ships:
		assert_eq(_order_of(c), AiContext.Order.FORM_ON_ME, "%s forms up" % c.display_name)
		assert_eq((c.driver.brain as AiPilot).context.leader_id, leader_id, "on the player")
	# The keyboard's order key (keys 1-4).
	source.hold(InputAdapter.WING_COVER, 1.0, true)
	await _ticks(2)
	source.release(InputAdapter.WING_COVER)
	await _ticks(1)
	for c: Combatant in ships:
		assert_eq(_order_of(c), AiContext.Order.COVER_ME, "%s covers the player" % c.display_name)
	# The console's `wing order`.
	assert_true(DebugConsole.registry.execute("wing order form")[0].ok)
	await _ticks(1)
	for c: Combatant in ships:
		assert_eq(_order_of(c), AiContext.Order.FORM_ON_ME)
	# Once out of its door, a launched wingman flies its slot on the player.
	var first: Combatant = own.member_at(4)
	var seq: LaunchSequence = main.launches.launches[-1]["seq"]
	assert_true(await _until(func() -> bool: return seq.fighter(first.display_name)["phase"] == LaunchSequence.Phase.RELEASED, 1500),
			"Alpha 5 is out")
	await _ticks(60)
	assert_eq(str((first.driver.brain as AiPilot).describe().get("behaviour", "")), "formation", "Alpha 5 forms on the player")


# The farthest any member of `wing` is from its slot on the player, m.
func _worst_slot_error(wing: Wing) -> float:
	var lead: Ship = main.ship
	var worst: float = 0.0
	for c: Combatant in wing.members():
		var slot: Vector3 = Formation.slot_point(lead.global_position, -lead.global_basis.z, lead.global_basis.y,
				wing.slot_offset(wing.slot_of(c)))
		worst = maxf(worst, c.ship.global_position.distance_to(slot))
	return worst


func test_a_launched_alpha_wing_forms_up_with_its_arms_even() -> void:
	# M7-T74: the grown wing formed up all on one side of the V; now five a side and ALPHA 12 on the centreline.
	if not SlowTests.enabled():
		pass_test("slow: some 70 s of flight (GUT_SLOW=1 runs it)")
		return
	await _start_with_alpha_clear()
	var own: Wing = main.wings.player_wing()
	assert_true(DebugConsole.registry.execute("launch wing alpha")[0].ok)
	assert_true(DebugConsole.registry.execute("wing order form")[0].ok)
	assert_true(await _until(func() -> bool: return not main.launches.is_launching("alpha"), 4000), "Alpha is out")
	assert_eq(own.members().size(), 11, "the player's three wingmen and the eight launched")
	# Within half a spacing of its slot, each wingman is surely on its slot's side.
	var near_m: float = 0.5 * Formation.DEFAULT_SPACING_M
	var settled: bool = await _until(func() -> bool: return _worst_slot_error(own) < near_m, 60 * 180)
	assert_true(settled, "formed up: every wingman within %.0f m of its slot (worst %.0f m)" % [near_m, _worst_slot_error(own)])
	var lead: Ship = main.ship
	var left: int = 0
	var right: int = 0
	var centre := PackedStringArray()
	for c: Combatant in own.members():
		var rel: Vector3 = lead.global_basis.orthonormalized().inverse() * (c.ship.global_position - lead.global_position)
		if absf(rel.x) < near_m:
			centre.append(c.display_name)
			assert_gt(rel.z, 0.0, "%s behind the player" % c.display_name)
		elif rel.x < 0.0:
			left += 1
		else:
			right += 1
	assert_eq([left, right], [5, 5], "five a side")
	assert_eq(centre, PackedStringArray(["ALPHA 12"]), "the odd one centred behind")


func test_mission_api_launch_from_starts_the_players_launch() -> void:
	await _start()
	DebugConsole.registry.execute("launch skip")
	await _ticks(2)
	var stage := MissionStage.new()
	stage.setup(main, null)
	var api := MissionApi.new(null, null, stage)
	api.launch_from("zeta", 2)  # a script awaits it; here it runs to its first wait
	assert_eq(api.journal[-1], "launch_from zeta 2", "journaled as a world change")
	assert_true(main.launches.locks_controls(), "the player is on Zeta 2's rack")
	await _ticks(1)
	assert_almost_eq(main.ship.global_position,
			_on_drum(station.hardpoints.bay("cobra_bay_zeta_2")["rail_start"]), Vector3.ONE * 0.05, "on its rack")
	stage.skip_launch()
	await _ticks(2)
	if stage.launching():
		var seq: LaunchSequence = main.launches.player_launch()["seq"]
		assert_true(station.hardpoints.launch_blocked(seq.arm_angle_now()), "still on the rack only while under the spine")
	else:
		assert_eq(main.launches.last_handoff["bay"], "cobra_bay_zeta_2", "a skip hands the player over")
	api.release()
	stage.teardown()


func test_each_launch_draws_a_cut_and_a_pinned_seed_repeats_it() -> void:
	await _start()
	assert_string_contains(main.launches._cut_text(), "rack ")
	DebugConsole.registry.execute("launch skip")
	await _ticks(3)
	var cuts := PackedStringArray()
	for wing: String in ["zeta", "beta", "delta"]:
		assert_eq(main.launches.launch_player(wing, 2, false), "", "launch from %s 2" % wing)
		cuts.append(main.launches._cut_text().split(": ")[1])
		DebugConsole.registry.execute("launch skip")
		assert_true(await _until(func() -> bool: return not main.launches.locks_controls(), 900))
	assert_eq(main.launches.launch_count, 4, "four player launches this run")
	assert_ne(cuts[0], cuts[1], "the next launch draws another cut")
	DebugConsole.registry.execute("launch seed 4242")
	var fresh := LaunchCut.new(main.launches.profile)
	var expected: String = ", ".join(fresh.pick(4242).map(func(e: Dictionary) -> String: return "%s %s" % [e["phase"], e["variant"]]))
	var seeded := LaunchCut.new(main.launches.profile)
	main.launches.cut = seeded  # fresh bags, as a new scenario run has
	assert_true(await _until(func() -> bool: return main.launches.launches.all(
			func(l: Dictionary) -> bool: return l["wing"] != "alpha"), 1800), "Alpha's launch is over")
	assert_eq(main.launches.launch_player("alpha", 4, false), "")
	assert_string_contains(main.launches._cut_text(), "seed 4242")
	assert_eq(main.launches._cut_text().split(": ")[1], expected, "a pinned seed with fresh bags gives the seed's cut")
	assert_eq(DebugConsole.registry.execute("get launch.launches")[0].lines[0], "launch.launches = 5")


# No plume, RCS puff or engine level: what the flight output (read by the plumes and the engine voices) and the plumes show.
func _assert_cold(c: Combatant, when: String) -> void:
	var out: FlightOutput = c.ship.get_flight_output()
	assert_true(c.ship.clamped, "%s: in the clamp (%s)" % [c.display_name, when])
	for level: float in out.main_levels:
		assert_eq(level, 0.0, "%s: no main pod %s" % [c.display_name, when])
	for level: float in out.retro_levels:
		assert_eq(level, 0.0, "%s: no retro %s" % [c.display_name, when])
	assert_eq(out.rcs_force_b, Vector3.ZERO, "%s: no RCS thrust %s" % [c.display_name, when])
	assert_eq(out.rcs_torque_b, Vector3.ZERO, "%s: no RCS turn %s" % [c.display_name, when])
	if c.thrusters != null:
		for i: int in c.thrusters.glow_count():
			assert_almost_eq(c.thrusters.glow_level(i), 0.0, 1e-3, "%s: plume %d dark %s" % [c.display_name, i, when])


func test_thrusters_stay_cold_in_the_clamp_and_fire_at_the_ejection() -> void:
	await _start()
	var seq: LaunchSequence = main.launches.launches[0]["seq"]
	var me: String = main.combatant.display_name
	await _ticks(60)
	_assert_cold(main.combatant, "stored on the rack")
	assert_true(await _until(func() -> bool: return seq.fighter(me)["phase"] == LaunchSequence.Phase.ROTATING, 200), "the clamp turns it")
	for i: int in 4:
		await _ticks(15)
		assert_eq(seq.fighter(me)["phase"], LaunchSequence.Phase.ROTATING)
		_assert_cold(main.combatant, "while the clamp turns it")
		_assert_cold(_ship("ALPHA 2"), "on the next rack")
	assert_true(await _until(func() -> bool: return not main.launches.last_handoff.is_empty(), 200), "ejected")
	await _ticks(5)
	assert_false(main.ship.clamped, "out of the clamp at the ejection")
	var out: FlightOutput = main.ship.get_flight_output()
	var lit: float = 0.0
	for level: float in out.main_levels:
		lit = maxf(lit, level)
	assert_gt(lit, 0.5, "its main pods fire as it clears the arm")
	await _ticks(10)
	var glowing: float = 0.0
	for i: int in main.combatant.thrusters.glow_count():
		glowing = maxf(glowing, main.combatant.thrusters.glow_level(i))
	assert_gt(glowing, 0.1, "and their plumes show")
	assert_true(await _until(func() -> bool: return seq.fighter("ALPHA 2")["phase"] == LaunchSequence.Phase.RELEASED, 120))
	await _ticks(2)
	assert_false(_ship("ALPHA 2").ship.clamped, "a wingman leaves the clamp at its ejection too")
