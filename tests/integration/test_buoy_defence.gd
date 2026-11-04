extends GutTest
## Buoy defence (architecture §18, M5-T10, AC10): the front end lists it and starts it; `play` loads it through the loading
## screen into its cinematic intro; the intro's two shots play and the controls hand over with the objectives up; console
## commands drive it to success and to both failures (the buoy destroyed, the player destroyed), each with its last line and
## then the debrief; it is set on the ring of 16 buoys, whose two nearest neighbours sit on the radar's rim from NAV ALPHA; and a
## skipped run spawns every ship from the scenario's pools.

const SCENARIO_ID: StringName = &"buoy_defence"
const MISSION_PATH: String = "res://data/scenarios/buoy_defence.json"
const FrontEndScene: PackedScene = preload("res://src/frontend/front_end.tscn")
## The beat before the debrief, shortened so the tests do not wait three seconds each (a closing line still holds it).
const BEAT_S: float = 0.25
const WAVE_ONE: Array[String] = ["RAIDER 1", "RAIDER 2", "RAIDER 3"]
const WAVE_TWO: Array[String] = ["RAIDER 4", "RAIDER 5", "RAIDER 6", "RAIDER 7"]

var main: Main
var holder: Node
var source: FakeInputSource
var _saved: Dictionary = {}


func before_each() -> void:
	get_tree().paused = false
	source = FakeInputSource.new()
	_saved = {"flow": Game.flow, "parent": Game.scene_parent, "main_path": Game.main_scene_path}
	Game.flow = GameFlow.new()
	holder = Node.new()
	add_child_autofree(holder)
	Game.scene_parent = holder


func after_each() -> void:
	get_tree().paused = false
	DebugConsole.flags.invulnerable = false
	Game.flow = _saved["flow"]
	Game.scene_parent = _saved["parent"]
	Game.main_scene_path = _saved["main_path"]


# --- helpers -----------------------------------------------------------------------------------------------------------


func _ticks(n: int) -> void:
	for _i: int in n:
		await get_tree().physics_frame


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


# Waits for a state of the run (lines and shots hold on sim time), failing clearly if it never comes.
func _wait_for(what: String, reached: Callable, max_ticks: int = 1500) -> void:
	var waited: int = 0
	while not bool(reached.call()) and waited < max_ticks:
		await _ticks(1)
		waited += 1
	assert_true(bool(reached.call()), "waited %d ticks for: %s" % [waited, what])


# Buoy defence in the real Main, started as the flow starts a mission (a request, then space).
func _fly() -> void:
	Game.flow.enter_directly(GameFlow.make_request(&"mission", SCENARIO_ID, false, 3))
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	main.scenario_path = MISSION_PATH
	main.scenario_seed = 3
	holder.add_child(main)
	await _ticks(2)
	main.mission.debrief_delay_s = BEAT_S


func _api() -> MissionApi:
	return main.mission.api


func _shot_id() -> StringName:
	var shot: CinematicShot = main.camera_rig.playing_shot()
	return shot.id if shot != null else &""


func _alive(names: Array[String]) -> int:
	var n: int = 0
	for ship_name: String in names:
		n += 1 if _api().alive(ship_name) else 0
	return n


func _debrief() -> DebriefScreen:
	return holder.get_child(0) as DebriefScreen if holder.get_child_count() == 1 else null


func _objective_states() -> Dictionary:
	var out: Dictionary = {}
	for entry: Dictionary in Game.flow.last_result.get("objectives", []):
		out[String(entry["id"])] = String(entry["state"])
	return out


func _buoy(buoy_name: String) -> NavBuoy:
	for buoy: NavBuoy in main.buoys:
		if buoy.display_name == buoy_name:
			return buoy
	return null


# --- from the menu ---------------------------------------------------------------------------------------------------------


func test_the_front_end_lists_buoy_defence_with_its_briefing_and_starts_it() -> void:
	var game := RecordingGame.new()
	autofree(game)
	var front: FrontEnd = FrontEndScene.instantiate() as FrontEnd
	front.game = game
	add_child_autofree(front)
	await wait_process_frames(2)
	(front.frame().current_page() as ChoiceListScreen).button_of(&"missions").pressed.emit()
	await wait_process_frames(2)
	var page: MissionSelect = front.frame().current_page() as MissionSelect
	assert_not_null(page)
	assert_has(page.option_ids(), SCENARIO_ID)
	page.button_of(SCENARIO_ID).grab_focus()
	await wait_process_frames(2)
	var shown: PackedStringArray = front.frame().objectives_panel().shown_lines()
	assert_eq(shown[0], "Buoy defence")
	assert_string_contains("\n".join(shown), "NAV ALPHA", "the briefing shows beside the list")
	page.button_of(SCENARIO_ID).pressed.emit()
	assert_eq(game.played, [GameFlow.make_request(&"mission", SCENARIO_ID)] as Array[Dictionary])


func test_play_loads_it_through_the_loading_screen_into_the_cinematic_intro() -> void:
	Game.main_scene_path = Game.MAIN_SCENE
	assert_true(_run("play buoy_defence").ok)
	await _wait_for("Main after the loading screen", func() -> bool: return holder.get_child_count() == 1 and holder.get_child(0) is Main, 1200)
	main = holder.get_child(0) as Main
	await _ticks(2)
	assert_eq(Game.flow.state, GameFlow.State.IN_SPACE)
	assert_eq(main.mission.state_name(), "running")
	assert_eq(_api().step_name(), &"intro")
	assert_eq(main.camera_rig.mode, CameraRig.Mode.CINEMATIC)
	assert_eq(_shot_id(), &"relay", "it opens on the relay buoy")
	assert_false(main.hud.visible, "the HUD hides for the intro")
	assert_true(main.controls_locked())


# --- the intro and the hand-over -----------------------------------------------------------------------------------------


func test_the_intro_frames_the_buoy_then_the_wing_then_hands_over() -> void:
	await _fly()
	assert_eq(_shot_id(), &"relay")
	assert_true(_api().controls_locked, "locked from the first frame")
	await _wait_for("the wing's fly-past", func() -> bool: return _shot_id() == &"wing", 600)
	assert_true(main.mission.comms.is_showing(), "Control hails the wing over the fly-past")
	assert_eq(main.mission.comms.callsign(), "CONTROL")
	var lead: Vector3 = main.ship.linear_velocity
	assert_almost_eq(lead, Vector3(0.0, 0.0, -40.0), Vector3.ONE * 0.5, "the wing flies in on its start velocity")
	await _wait_for("the brief", func() -> bool: return _api().step_name() == &"brief", 600)
	assert_eq(main.camera_rig.mode, CameraRig.Mode.CHASE, "the camera is back")
	assert_true(_api().controls_locked, "still held while Control briefs")
	await _wait_for("the hand-over", func() -> bool: return not _api().controls_locked, 1500)
	assert_eq(_api().objective_state(&"protect"), ObjectiveBook.ACTIVE)
	assert_eq(_api().objective_state(&"raiders"), ObjectiveBook.ACTIVE)
	assert_eq(_api().objective_state(&"home"), ObjectiveBook.ACTIVE)
	assert_eq(_api().waypoint_name, "NAV ALPHA")
	assert_true(main.hud.visible)


func test_every_actor_a_shot_names_is_in_play_from_the_start() -> void:
	await _fly()
	for shot_id: StringName in _api().cinematics:
		var shot: CinematicShot = _api().cinematics[shot_id]
		for key: CinematicShot.Frame in shot.keys:
			for point: CinematicShot.Point in [key.position, key.look_at]:
				if not point.actor.is_empty():
					assert_not_null(main.mission.stage.actor_pose(point.actor), "%s names %s" % [shot_id, point.actor])


# --- success and failure, driven by console commands ---------------------------------------------------------------------


func test_console_commands_drive_it_to_success_and_the_debrief() -> void:
	DebugConsole.flags.invulnerable = true
	await _fly()
	assert_true(_run("mission goto wave_one").ok)
	await _ticks(2)
	assert_eq(_alive(WAVE_ONE), 3, "wave one jumped in")
	var first: Combatant = main.ships.alive(ShipPool.DEFAULT_TYPE)[0]
	assert_gt(main.world.to_universe(first.ship.global_position).distance_to(UniversePos.new()), 6000.0,
			"beyond the AI's sensors from the buoy")
	assert_eq(((first.driver.brain as AiPilot).context as AiContext).objective_name, "NAV ALPHA", "sent at the buoy")
	assert_true(_run("kill all").ok)
	await _wait_for("wave two", func() -> bool: return _alive(WAVE_TWO) == 4)
	assert_true(_journal_has("say control_second_group"), "a warning before the second group")
	assert_true(_run("kill all").ok)
	await _wait_for("the end", func() -> bool: return _api().has_ended())
	assert_true(bool(_api().result["success"]), str(_api().result))
	assert_true(_journal_has("say control_success"))
	await _wait_for("the debrief", func() -> bool: return _debrief() != null, 600)
	assert_eq(Game.flow.state, GameFlow.State.DEBRIEF)
	assert_eq_deep(_objective_states(), {"protect": "done", "raiders": "done", "home": "done"})


func test_losing_the_buoy_fails_it_with_controls_last_line() -> void:
	await _fly()
	assert_true(_run("mission goto wave_one").ok)
	await _ticks(2)
	assert_true(_run("set targeting.selected \"NAV ALPHA\"").ok)
	assert_true(_run("damage 100 target").ok)
	await _wait_for("the end", func() -> bool: return _api().has_ended(), 30)
	assert_false(bool(_api().result["success"]))
	assert_eq(_api().result["reason"], "objective failed: protect")
	assert_true(_buoy("NAV ALPHA").is_destroyed())
	assert_eq(_api().dialog.current.id, &"control_relay_lost")
	assert_eq(main.mission.comms.callsign(), "CONTROL")
	await _ticks(ceili(BEAT_S * Engine.physics_ticks_per_second) + 4)
	assert_null(_debrief(), "the debrief waits for the last line")
	await _wait_for("the debrief", func() -> bool: return _debrief() != null, 600)
	assert_eq(Game.flow.last_result["reason"], "objective failed: protect")
	assert_eq(_objective_states()["protect"], "failed")


func test_losing_the_player_fails_it_with_alpha_twos_last_line() -> void:
	await _fly()
	assert_true(_run("mission goto wave_one").ok)
	await _ticks(2)
	assert_true(_run("kill player").ok)
	await _wait_for("the end", func() -> bool: return _api().has_ended(), 30)
	assert_eq(_api().result["reason"], "player destroyed")
	assert_eq(_api().dialog.current.id, &"alpha_2_leader_down")
	assert_eq(main.mission.comms.callsign(), "ALPHA 2")
	await _wait_for("the debrief", func() -> bool: return _debrief() != null, 600)
	assert_false(bool(Game.flow.last_result["success"]))


# --- the ring ------------------------------------------------------------------------------------------------------------


func test_it_is_set_on_a_ring_of_sixteen_and_the_radar_rims_nav_alphas_neighbours() -> void:
	await _fly()
	assert_eq(main.buoys.size(), 16)
	for buoy: NavBuoy in main.buoys:
		assert_eq(buoy.targetable.broadcast_range_m, 1.0e7, "every buoy broadcasts to 10 000 km")
	await _ticks(2)
	var names: PackedStringArray = PackedStringArray()
	for info: TargetInfo in main.ship.targeting.candidates():
		names.append(info.display_name)
	for heard: String in ["NAV ALPHA", "NAV BRAVO", "NAV PAPA"]:
		assert_has(names, heard)
	for far: String in ["NAV CHARLIE", "NAV OSCAR", "NAV INDIA"]:
		assert_does_not_have(names, far, "beyond 10 000 km")
	var dots: Array[RadarModel.Dot] = RadarModel.dots(main.ship.targeting.candidates(), 0, main.ship.global_position,
			main.ship.global_basis, Factions.EARTH_ALLIANCE)
	var rims: Dictionary = {}
	for dot: RadarModel.Dot in dots:
		rims[dot.id] = dot.rim
	assert_true(rims.get(_buoy("NAV BRAVO").targetable.get_instance_id(), false), "NAV BRAVO on the rim")
	assert_true(rims.get(_buoy("NAV PAPA").targetable.get_instance_id(), false), "NAV PAPA on the rim")
	assert_false(rims.get(_buoy("NAV ALPHA").targetable.get_instance_id(), true), "NAV ALPHA close by, inside the sphere")


# --- pools ---------------------------------------------------------------------------------------------------------------


func test_a_skipped_run_spawns_every_ship_from_the_pools() -> void:
	DebugConsole.flags.invulnerable = true
	await _fly()
	assert_true(_run("mission goto wrap").ok)
	for ship_name: String in WAVE_ONE + WAVE_TWO:
		assert_true(_journal_has("spawn %s raider_fighter" % ship_name), ship_name)
	assert_eq(main.ships.pool_size(ShipPool.DEFAULT_TYPE), 7, "seven raiders, all the script spawns")
	assert_eq(main.ships.pool_size(ShipPool.ALLY_TYPE), 3, "Alpha 2, 3 and 4")
	assert_eq(_api().objective_state(&"raiders"), ObjectiveBook.DONE)
	assert_true(_run("mission skip").ok)
	assert_true(_api().has_ended())
	assert_true(bool(_api().result["success"]))


func _journal_has(entry: String) -> bool:
	return Array(_api().journal).has(entry)
