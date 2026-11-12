extends GutTest
## Civilian escort (architecture §18 D62, M5-T30, AC10): the front end lists it and starts it; `play` loads it into its
## cinematic intro; console commands drive it to success and to both failures (the civilian destroyed, the player destroyed),
## each with its last line and then the debrief; the civilian flees when attacked and resumes its route; a skipped wave leaves
## no raider behind and the civilian at its point; the pools hold every ship the script spawns; buoys broadcast to 1 000 km.
## A whole run without skips (the civilian crosses the belt without hitting a rock) is under `GUT_SLOW`.

const SCENARIO_ID: StringName = &"civilian_escort"
const MISSION_PATH: String = "res://data/scenarios/civilian_escort.json"
const FrontEndScene: PackedScene = preload("res://src/frontend/front_end.tscn")
const MissionScriptClass: GDScript = preload("res://data/missions/civilian_escort.gd")
## The beat before the debrief, shortened so the tests do not wait three seconds each (a closing line still holds it).
const BEAT_S: float = 0.25
const WAVE_ONE: Array[String] = ["RAIDER 1", "RAIDER 2", "RAIDER 3"]
const WAVE_TWO: Array[String] = ["RAIDER 4", "RAIDER 5", "RAIDER 6", "RAIDER 7"]
const WAVE_THREE: Array[String] = ["RAIDER 8", "RAIDER 9", "RAIDER 10", "RAIDER 11", "RAIDER 12", "RAIDER 13"]

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


# Civilian escort in the real Main, started as the flow starts a mission (a request, then space).
func _fly(seed_value: int = 3) -> void:
	Game.flow.enter_directly(GameFlow.make_request(&"mission", SCENARIO_ID, false, seed_value))
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	main.scenario_path = MISSION_PATH
	main.scenario_seed = seed_value
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


func _civilian() -> Combatant:
	for c: Combatant in main.scenario_ships:
		if ShipCatalog.is_civilian(main.ships.type_of(c)):
			return c
	return null


func _civilian_name() -> String:
	return _api().filled(ScenarioLoader.CIVILIAN_PLACEHOLDER)


func _behaviour(c: Combatant) -> String:
	return str(c.driver.brain.describe().get("behaviour", "none"))


func _at(c: Combatant) -> UniversePos:
	return main.world.to_universe(c.ship.global_position)


# --- from the menu ---------------------------------------------------------------------------------------------------------


func test_the_front_end_lists_the_escort_with_its_briefing_and_starts_it_on_a_fresh_seed() -> void:
	var game := RecordingGame.new()
	autofree(game)
	var front: FrontEnd = FrontEndScene.instantiate() as FrontEnd
	front.game = game
	add_child_autofree(front)
	await wait_process_frames(2)
	(front.frame().current_page() as ChoiceListScreen).button_of(&"new_game").pressed.emit()
	await wait_process_frames(2)
	var page: NewGameSelect = front.frame().current_page() as NewGameSelect
	assert_not_null(page)
	assert_has(page.option_ids(), SCENARIO_ID)
	assert_does_not_have(page.option_ids(), &"buoy_defence", "Buoy defence is gone (Q36)")
	page.button_of(SCENARIO_ID).grab_focus()
	await wait_process_frames(2)
	var shown: String = front.frame().detail_text()
	assert_true(shown.begins_with("Civilian escort"))
	assert_string_contains(shown, "NAV BETA", "the briefing shows under the list")
	page.button_of(SCENARIO_ID).pressed.emit()
	assert_eq(game.played.size(), 1)
	assert_eq(game.played[0]["scenario_id"], SCENARIO_ID)
	assert_gt(int(game.played[0]["seed"]), 0, "a seed of its own, so the civilian varies")


func test_play_loads_it_into_the_cinematic_intro_with_the_drawn_civilian() -> void:
	Game.main_scene_path = Game.MAIN_SCENE
	assert_true(_run("play civilian_escort 11").ok)
	await _wait_for("Main after the loading screen", func() -> bool: return holder.get_child_count() == 1 and holder.get_child(0) is Main, 1200)
	main = holder.get_child(0) as Main
	await _ticks(2)
	assert_eq(main.mission.state_name(), "running")
	assert_eq(_api().step_name(), &"intro")
	assert_eq(main.camera_rig.mode, CameraRig.Mode.CINEMATIC)
	assert_eq(_shot_id(), &"departure", "it opens on the civilian at NAV ALPHA")
	assert_true(main.controls_locked())
	var civilian: Combatant = _civilian()
	assert_not_null(civilian)
	assert_eq(civilian.display_name, _civilian_name())
	assert_eq(main.ships.pool_size(main.ships.type_of(civilian)), 1, "only the drawn hull is pooled")
	for type: StringName in ShipCatalog.CIVILIAN_TYPES:
		if type != main.ships.type_of(civilian):
			assert_eq(main.ships.pool_size(type), 0, "no %s pooled" % type)


# --- the intro and the hand-over -----------------------------------------------------------------------------------------


func test_the_intro_hands_over_with_the_objectives_and_the_civilian_marked() -> void:
	await _fly()
	await _wait_for("the wing's fly-past", func() -> bool: return _shot_id() == &"wing", 900)
	assert_true(main.mission.comms.is_showing(), "the civilian hails over the fly-past")
	assert_string_contains(_api().dialog.current.text, _civilian_name(), "the line names the drawn ship")
	await _wait_for("the hand-over", func() -> bool: return not _api().controls_locked, 2400)
	assert_eq(_api().objective_state(&"escort"), ObjectiveBook.ACTIVE)
	assert_eq(_api().objective_state(&"home"), ObjectiveBook.ACTIVE)
	assert_eq(_api().waypoint_name, _civilian_name())
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
	_civilian().damageable.invulnerable = true
	assert_true(_run("mission goto wave_one").ok)
	await _ticks(2)
	assert_eq(_alive(WAVE_ONE), 3, "wave one jumped in")
	var first: Combatant = main.ships.alive(ShipPool.DEFAULT_TYPE)[0]
	var range_m: float = _at(first).distance_to(_at(_civilian()))
	assert_between(range_m, 6000.0, 12000.0, "6 to 12 km from the civilian")
	assert_eq(((first.driver.brain as AiPilot).context as AiContext).objective_name, _civilian_name(), "sent at the civilian")
	assert_true(_run("kill all").ok)
	assert_true(_run("mission goto wave_two").ok)
	await _ticks(2)
	assert_eq(_alive(WAVE_TWO), 4, "wave two")
	assert_true(_run("kill all").ok)
	assert_true(_run("mission goto wave_three").ok)
	await _ticks(2)
	assert_eq(_alive(WAVE_THREE), 6, "wave three")
	assert_true(_run("kill all").ok)
	assert_true(_run("mission skip").ok)
	await _wait_for("the end", func() -> bool: return _api().has_ended(), 2400)
	assert_true(bool(_api().result["success"]), str(_api().result))
	assert_true(_journal_has("say control_success"))
	assert_lt(_at(_civilian()).distance_to(_buoy_at("NAV BETA")), MissionScriptClass.ARRIVAL_M, "at NAV BETA")
	await _wait_for("the debrief", func() -> bool: return _debrief() != null, 600)
	assert_eq(Game.flow.state, GameFlow.State.DEBRIEF)
	assert_eq_deep(_objective_states(), {"escort": "done", "home": "done"})


func test_losing_the_civilian_fails_it_with_controls_last_line() -> void:
	await _fly()
	assert_true(_run("mission goto wave_one").ok)
	await _ticks(2)
	assert_true(_civilian().damageable.kill())
	await _wait_for("the end", func() -> bool: return _api().has_ended(), 30)
	assert_false(bool(_api().result["success"]))
	assert_eq(_api().result["reason"], "objective failed: escort")
	assert_eq(_api().dialog.current.id, &"control_civilian_lost")
	assert_string_contains(_api().dialog.current.text, _civilian_name())
	await _wait_for("the debrief", func() -> bool: return _debrief() != null, 600)
	assert_eq(_objective_states()["escort"], "failed")


func test_losing_the_player_fails_it_with_alpha_twos_last_line() -> void:
	await _fly()
	assert_true(_run("mission goto wave_one").ok)
	await _ticks(2)
	assert_true(_run("kill player").ok)
	await _wait_for("the end", func() -> bool: return _api().has_ended(), 30)
	assert_eq(_api().result["reason"], "player destroyed")
	assert_eq(_api().dialog.current.id, &"alpha_2_leader_down")
	await _wait_for("the debrief", func() -> bool: return _debrief() != null, 600)
	assert_false(bool(Game.flow.last_result["success"]))


# --- flee and resume (Q39) -----------------------------------------------------------------------------------------------


func test_the_civilian_flees_when_attacked_and_resumes_its_route() -> void:
	DebugConsole.flags.invulnerable = true
	await _fly()
	var civilian: Combatant = _civilian()
	civilian.damageable.invulnerable = true
	assert_true(_run("mission goto wave_one").ok)
	await _ticks(2)
	assert_eq(_behaviour(civilian), "follow_path", "on its route before the raiders close")
	await _wait_for("the civilian fleeing", func() -> bool: return _behaviour(civilian) == "retreat", 60 * 90)
	assert_true(_run("kill all").ok)
	await _wait_for("the civilian back on its route", func() -> bool: return _behaviour(civilian) == "follow_path", 60 * 30)
	var before: float = _at(civilian).distance_to(_buoy_at("NAV BETA"))
	await _ticks(60 * 10)
	assert_lt(_at(civilian).distance_to(_buoy_at("NAV BETA")), before - 200.0, "closing on NAV BETA again")


# --- skipping and pools --------------------------------------------------------------------------------------------------


func test_a_skipped_wave_leaves_no_raider_and_the_civilian_at_its_point() -> void:
	DebugConsole.flags.invulnerable = true
	await _fly()
	assert_true(_run("mission goto wave_two").ok)
	await _ticks(2)
	for ship_name: String in WAVE_ONE:
		assert_true(_journal_has("spawn %s raider_fighter" % ship_name), ship_name)
		assert_false(_api().alive(ship_name), "%s released by the skip" % ship_name)
	assert_eq(_alive(WAVE_TWO), 4, "the step played now has its wave")
	var point: Vector3 = MissionScriptClass.POINT_50
	assert_lt(_at(_civilian()).distance_to(UniversePos.new(point.x, point.y, point.z)), 1.0, "at the 50 % point")


func test_a_skipped_run_spawns_every_ship_from_the_pools() -> void:
	DebugConsole.flags.invulnerable = true
	await _fly()
	assert_true(_run("mission goto arrive").ok)
	for ship_name: String in WAVE_ONE + WAVE_TWO + WAVE_THREE:
		assert_true(_journal_has("spawn %s raider_fighter" % ship_name), ship_name)
	assert_eq(main.ships.pool_size(ShipPool.DEFAULT_TYPE), 13, "thirteen raiders, all the script spawns")
	assert_eq(main.ships.pool_size(ShipPool.ALLY_TYPE), 1, "ALPHA 2")
	assert_true(_run("mission skip").ok)
	assert_true(_api().has_ended())
	assert_true(bool(_api().result["success"]))


func test_buoys_broadcast_to_1000_km_and_no_ring_is_laid() -> void:
	await _fly()
	assert_eq(main.buoys.size(), 2, "NAV ALPHA and NAV BETA, no ring (Q41)")
	for buoy: NavBuoy in main.buoys:
		assert_eq(buoy.targetable.broadcast_range_m, 1.0e6)


# --- the whole crossing (slow) -------------------------------------------------------------------------------------------


func test_a_saturn_8_crosses_the_belt_without_hitting_a_rock() -> void:
	if OS.get_environment("GUT_SLOW") != "1":
		pending("GUT_SLOW=1 runs the whole crossing")
		return
	DebugConsole.flags.invulnerable = true
	var seed_value: int = _seed_for(&"saturn_8_transport")
	await _fly(seed_value)
	var civilian: Combatant = _civilian()
	assert_eq(main.ships.type_of(civilian), &"saturn_8_transport")
	civilian.damageable.invulnerable = true
	var hull: float = civilian.damageable.hull.hp
	assert_true(_run("mission goto depart").ok)
	# No raiders: the waves are skipped as they come, so only the rocks stand in the way.
	await _wait_for("the crossing", func() -> bool:
		if _api().step_name() in [&"wave_one", &"wave_two", &"wave_three"]:
			_run("kill all")
		return _at(civilian).distance_to(_buoy_at("NAV BETA")) < MissionScriptClass.ARRIVAL_M, 60 * 600)
	assert_eq(civilian.damageable.hull.hp, hull, "no rock hit on the way")


func _seed_for(type: StringName) -> int:
	for seed_value: int in 500:
		var result: Dictionary = ScenarioLoader.load(MISSION_PATH)
		ScenarioLoader.resolve_random_civilian(result, seed_value)
		if result["spawns"][0]["type"] == type:
			return seed_value
	return 0


func _buoy_at(buoy_name: String) -> UniversePos:
	for buoy: NavBuoy in main.buoys:
		if buoy.display_name == buoy_name:
			return main.world.to_universe(buoy.global_position)
	return null


func _journal_has(entry: String) -> bool:
	return Array(_api().journal).has(entry)
