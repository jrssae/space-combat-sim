extends GutTest
## Cobra-bay launches on the real main scene (M7-T08, D76, AC7): the `station_launch` scenario starts the player on Alpha 3's rack
## with the controls held and the wingmen on the arm's other racks; the fighters ride the turning drum; the launch camera plays its
## shots; the player is handed over at the release point with the drum's surface velocity; a skip (Start) lands in the same state;
## the wingmen follow from the next doors in the wave order; a rebase mid-launch moves nothing on screen; a launch due under the
## spine holds; `launch wing` launches twelve AI Starfuries. Every place comes from the station's hardpoints.

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


func _expected_release(bay_name: String) -> Dictionary:
	var bay: Dictionary = station.hardpoints.bay(bay_name)
	var rail: float = (bay["rail_end"] as Vector3).distance_to(bay["rail_start"]) + (bay["release"] as Vector3).distance_to(bay["rail_end"])
	var speed: float = 2.0 * rail / main.launches.profile.drop_s
	return {"point": bay["release"], "velocity": (bay["release_direction"] as Vector3).normalized() * speed}


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
	# Carried with the drum: a second later still on its rack, which has moved some 36 m with the turn.
	var before: Vector3 = main.ship.global_position
	await _ticks(60)
	var rack_now: Vector3 = _on_drum(station.hardpoints.bay("cobra_bay_alpha_3")["rail_start"])
	assert_almost_eq(main.ship.global_position, rack_now, Vector3.ONE * 0.05, "still on the rack")
	assert_gt(main.ship.global_position.distance_to(before), 25.0, "which turned with the drum")
	assert_almost_eq(main.ship.linear_velocity.length(), station.spin.rate_rad_s * 227.5, 0.5, "at the drum's speed there")
	assert_eq(shots_seen[0], "launch_hall", "the launch camera opens in the hall")
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
	assert_false(main.launches.locks_controls(), "the controls come back at the hand-off")
	assert_ne(main.ship.collision_layer, 0, "it collides again")
	assert_false(main.ship.custom_integrator, "and thrust moves it again")
	# Jolt flies it on from the hand-off state: one step later it has moved a tick's worth at that velocity.
	var at: Vector3 = (handoff["transform"] as Transform3D).origin
	assert_almost_eq(main.ship.global_position, at + (handoff["velocity"] as Vector3) * DT, Vector3.ONE * 0.05,
			"flies on from the release point")
	await _ticks(240)
	for shot: String in ["launch_hall", "launch_drop", "launch_chase"]:
		assert_true(shots_seen.has(shot), "the launch camera played %s (%s)" % [shot, shots_seen])
	assert_false(main.camera_rig.is_playing_shot(), "and gave the view back")
	assert_null(main.launches.fill, "the fill went out with its shot")
	assert_false(rig.has_emitter(drop_fill), "and left the light rig")
	var door: Vector3 = _on_drum(station.hardpoints.bay("cobra_bay_alpha_3")["door"])
	assert_gt(main.ship.global_position.distance_to(door), 30.0, "it has left the bay")


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
		assert_gte(times[k] - times[k - 1], main.launches.profile.stagger_s - 1e-6, "a stagger apart")
	var wingman: Ship = _ship("ALPHA 4").ship
	assert_ne(wingman.collision_layer, 0, "the last wingman flies free")
	assert_gt(wingman.global_position.distance_to(_on_drum(station.hardpoints.bay("cobra_bay_alpha_6")["rail_start"])), 15.0,
			"and has left its rack")


func test_a_rebase_mid_launch_moves_nothing_on_screen() -> void:
	await _start()
	await _ticks(200)  # on the rail
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
	# The wing whose arm will be under the spine when its drop is due (one always is: the sector and a drop's sweep span 92 deg).
	var rate_deg: float = rad_to_deg(station.spin.rate_rad_s)
	var due_s: float = main.launches.profile.door_open_s + 2.0 * DT
	var pick: String = ""
	for arm: Variant in station.hardpoints.cobra_arm["arms"]:
		var at_due: float = float(arm["angle_deg"]) + rad_to_deg(station.drum_angle) + rate_deg * due_s
		var blocked: bool = false
		for s: int in 52:
			blocked = blocked or station.hardpoints.launch_blocked(at_due + rate_deg * main.launches.profile.drop_s * s / 51.0)
		if blocked and String(arm["wing"]) != "alpha":
			pick = String(arm["wing"])
	if pick.is_empty():
		pass_test("alpha's arm is the blocked one now; the pure tests cover the hold")
		return
	gut.p("held launch from wing %s" % pick)
	var result: ConsoleResult = DebugConsole.registry.execute("launch %s 2" % pick)[0]
	assert_true(result.ok, "\n".join(result.lines))
	var seq: LaunchSequence = main.launches.player_launch()["seq"]
	assert_true(await _until(func() -> bool: return seq.fighter(main.combatant.display_name)["phase"] == LaunchSequence.Phase.HELD, 300),
			"held on the rack")
	assert_true(shots_seen.has("launch_hold"), "the camera watches the arm wait")
	assert_ne(DebugConsole.registry.execute("get launch.held")[0].lines[0], "launch.held = none")
	main.launches.last_handoff = {}
	assert_true(await _until(func() -> bool: return not main.launches.last_handoff.is_empty(), 1500), "let go once clear")
	assert_false(station.hardpoints.launch_blocked(seq.arm_angle_now()), "not inside the blocked sector")
	assert_gt(float(seq.fighter(main.combatant.display_name)["held_s"]), 0.0)


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
