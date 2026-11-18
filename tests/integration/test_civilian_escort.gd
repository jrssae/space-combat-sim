extends TestSteps
## Civilian escort (architecture §18 D62, M5-T30, AC10): the front end lists it and starts it; `play` loads it into its
## cinematic intro; console commands drive it to success and to both failures (the civilian destroyed, the player destroyed),
## each with its last line and then the debrief; the civilian flees when attacked and resumes its route; a skipped wave leaves
## no raider behind and the civilian at its point; the pools hold every ship the script spawns; buoys broadcast to 1 000 km.
## A whole run without skips (the civilian crosses the belt without hitting a rock) is under `GUT_SLOW`.
## M8-T08 (Q6, AC7): each wave rides in docked on a raider strike carrier and is launched; the carrier hangs back, takes its
## survivors home and flees; raiders gone home count as down; destroying a carrier is the optional objective.

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


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


# Waits for a state of the run (lines and shots hold on sim time), failing clearly if it never comes.
func _wait_for(what: String, reached: Callable, max_ticks: int = 1500) -> void:
	var waited: int = 0
	while not bool(reached.call()) and waited < max_ticks:
		await _ticks(1)
		waited += 1
	assert_true(bool(reached.call()), "waited %d ticks for: %s" % [waited, what])


# Civilian escort in the real Main, started as the flow starts a mission (a request, then space); `input` stands in for the pad.
func _fly(seed_value: int = 3, input: InputSource = null) -> void:
	Game.flow.enter_directly(GameFlow.make_request(&"mission", SCENARIO_ID, false, seed_value))
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = input if input != null else source
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
	assert_does_not_have(page.option_ids(), &"buoy_defense", "Buoy defense is gone (Q36)")
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


# --- skipping the opening and the civilian's hull bar (M7-T54) ----------------------------------------------------------


func test_holding_x_on_the_pad_skips_the_opening_and_a_tap_does_not() -> void:
	await _fly()
	await _wait_for("the first shot", func() -> bool: return _shot_id() == &"departure", 120)
	await _ticks(2)
	assert_true(main.mission.opening_skip_offered(), "offered while the intro plays")
	assert_eq(main.mission.skip_prompt.text, SkipPrompt.prompt_text(BindingNames.of_action(InputAdapter.AUTOTRACK)))
	assert_string_contains(main.mission.skip_prompt.text, "SKIP")
	assert_string_contains(DebugConsole.registry.execute("get mission.opening_skip")[0].lines[0], "true")
	source.hold(InputAdapter.AUTOTRACK)
	await _ticks(6)
	source.release(InputAdapter.AUTOTRACK)
	await _ticks(2)
	assert_eq(_api().step_name(), &"intro", "a tap skips nothing")
	source.hold(InputAdapter.AUTOTRACK)
	await _wait_for("the hold's bar", func() -> bool: return main.mission.skip_prompt.progress > 0.0, 60)
	assert_true(_api().controls_locked, "still the opening while the bar fills")
	await _wait_for("the hand-over", func() -> bool: return not _api().controls_locked, 150)
	source.release(InputAdapter.AUTOTRACK)
	assert_eq(_api().step_name(), &"depart", "the intro and the briefing are skipped")
	assert_true(_journal_has("skip opening to depart"))
	assert_eq(_api().objective_state(&"escort"), ObjectiveBook.ACTIVE)
	assert_eq(_api().waypoint_name, _civilian_name())
	await _ticks(2)
	assert_false(main.camera_rig.is_playing_shot(), "the shot is cut")
	assert_true(main.hud.visible, "the HUD is back")
	assert_eq(main.mission.skip_prompt.text, "", "the prompt goes")
	assert_false(main.mission.opening_skip_offered())
	assert_string_contains(DebugConsole.registry.execute("get mission.opening_skip")[0].lines[0], "false")


# Council round 1 (O5): the hold that skips the opening runs no interaction of a target that offers one.
func test_the_hold_that_skips_the_opening_runs_no_interaction() -> void:
	await _fly()
	await _wait_for("the first shot", func() -> bool: return _shot_id() == &"departure", 120)
	var civilian: Combatant = _civilian()
	var ran: Array[int] = [0]
	civilian.targetable.interaction = TargetInteraction.new(&"dock", "DOCK", func() -> String:
		ran[0] += 1
		return "")
	assert_true(main.ship.targeting.select_id(civilian.targetable.get_instance_id()), "(a target that offers an interaction)")
	source.hold(InputAdapter.AUTOTRACK)
	await _wait_for("the hand-over", func() -> bool: return not _api().controls_locked, 150)
	await _ticks(2)
	source.release(InputAdapter.AUTOTRACK)
	await _ticks(2)
	assert_eq(_api().step_name(), &"depart", "(the opening is skipped)")
	assert_eq(ran[0], 0, "the same hold runs nothing")
	assert_eq(main.interactions.runs, 0)


func test_holding_the_keyboards_auto_track_key_skips_the_opening_too() -> void:
	var keys := GodotInputSource.new()
	keys.keyboard_mouse_enabled = true
	await _fly(3, keys)
	await _wait_for("the first shot", func() -> bool: return _shot_id() == &"departure", 120)
	_shift(true)
	await _wait_for("the hand-over", func() -> bool: return not _api().controls_locked, 200)
	_shift(false)
	assert_eq(_api().step_name(), &"depart", "Shift held skips it as X does (keyboard parity)")


func test_the_hud_shows_the_civilians_name_and_hull_as_a_bar() -> void:
	await _fly()
	assert_true(_run("mission goto depart").ok)
	await _ticks(3)
	var civilian: Combatant = _civilian()
	civilian.damageable.hull.hp = civilian.damageable.hull.max_hp * 0.6
	await _wait_for("the hull bar", func() -> bool: return main.hud.frame.escort_rows.size() == 1, 30)
	await _ticks(2)
	var row: HudLayout.RosterRow = main.hud.frame.escort_rows[0]
	assert_eq(row.text, "%s  60%%" % _civilian_name().to_upper())
	assert_almost_eq(row.hull, 0.6, 0.01)
	assert_has(main.hud.painted_items(), HudSurface.ESCORT)
	assert_string_contains(DebugConsole.registry.execute("get mission.hull_bars")[0].lines[0], "60%")
	assert_true(civilian.damageable.kill())
	await _ticks(3)
	assert_string_ends_with(main.hud.frame.escort_rows[0].text, "LOST")


func _shift(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_SHIFT
	event.keycode = KEY_SHIFT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


# --- the waves' spacing (M7-T54) -----------------------------------------------------------------------------------------


func test_a_wave_waits_for_the_last_to_be_down_and_then_a_breather() -> void:
	DebugConsole.flags.invulnerable = true
	await _fly()
	_civilian().damageable.invulnerable = true
	assert_true(_run("mission goto wave_one").ok)
	await _ticks(2)
	var past := UniversePos.new(MissionScriptClass.POINT_75.x, 0.0, MissionScriptClass.POINT_75.z, _api().world.system_id)
	main.mission.stage.place(_civilian_name(), past)  # past the next wave's mark while wave one still flies
	var scale_backup: float = Engine.time_scale
	Engine.time_scale = 4.0
	await _ticks(60 * 5 / 4)
	assert_eq(_api().step_name(), &"wave_one", "wave two waits while wave one is up")
	assert_true(_run("kill all").ok)
	var down_s: float = _api().time_s()
	await _wait_for("wave two", func() -> bool: return _journal_has("spawn RAIDER 4 raider_fighter"),
			roundi(60.0 * (MissionScriptClass.BREATHER_S + 15.0) / 4.0))
	Engine.time_scale = scale_backup
	# The breather counts from when the step sees the wave down, after its lines.
	assert_between(_api().time_s() - down_s, MissionScriptClass.BREATHER_S, MissionScriptClass.BREATHER_S + 10.0,
			"a breather after wave one is down")
	assert_eq(_api().step_name(), &"wave_two")


func test_a_civilian_back_from_a_detour_still_brings_the_next_wave() -> void:
	DebugConsole.flags.invulnerable = true
	await _fly()
	assert_true(_run("mission goto wave_one").ok)
	await _ticks(2)
	assert_true(_run("kill all").ok)
	# Two kilometres off the line, level with the 50 % point: a point trigger of 1 km would never see it.
	var aside := UniversePos.new(2000.0, 0.0, MissionScriptClass.POINT_50.z - 200.0, _api().world.system_id)
	main.mission.stage.place(_civilian_name(), aside)
	var scale_backup: float = Engine.time_scale
	Engine.time_scale = 4.0
	await _wait_for("wave two", func() -> bool: return _api().step_name() == &"wave_two",
			roundi(60.0 * (MissionScriptClass.BREATHER_S + 15.0) / 4.0))
	Engine.time_scale = scale_backup


func test_every_actor_a_shot_names_is_in_play_from_the_start() -> void:
	await _fly()
	for shot_id: StringName in _api().cinematics:
		var shot: CinematicShot = _api().cinematics[shot_id]
		for key: CinematicShot.Frame in shot.keys:
			for point: CinematicShot.Point in [key.position, key.look_at]:
				if not point.actor.is_empty():
					assert_not_null(main.mission.stage.actor_pose(point.actor), "%s names %s" % [shot_id, point.actor])


# --- the waves' carriers (M8-T08) ----------------------------------------------------------------------------------------


func _carriers() -> CarrierJumps:
	return CarrierJumps.attach(main.world)


# Runs the mission on at `speed` until `reached` holds (or `seconds` of sim time have passed). The physics rate rises with the
# time scale, so each step is still 1/60 s of sim time (the docking paths are flown at the game's own step).
func _run_on(seconds: float, reached: Callable, speed: float = 4.0) -> void:
	var scale_backup: float = Engine.time_scale
	var rate_backup: int = Engine.physics_ticks_per_second
	Engine.time_scale = speed
	Engine.physics_ticks_per_second = roundi(rate_backup * speed)
	var until_s: float = SimClock.now() + seconds
	while SimClock.now() < until_s and not bool(reached.call()):
		await _ticks(1)
	Engine.time_scale = scale_backup
	Engine.physics_ticks_per_second = rate_backup


func test_a_wave_rides_in_docked_on_a_strike_carrier_and_is_launched() -> void:
	DebugConsole.flags.invulnerable = true
	await _fly()
	_civilian().damageable.invulnerable = true
	assert_true(_run("mission goto wave_one").ok)
	await _ticks(2)
	assert_eq(_carriers().runs().size(), 1, "one carrier brings the wave")
	var run: CarrierRun = _carriers().runs()[0]
	var cap: CapitalStandin = run.carrier
	assert_eq(cap.ship_class, CapitalStandin.STRIKE_CARRIER)
	assert_eq(cap.targetable.display_name, "RAIDER CARRIER 1", "named by the wave's data")
	assert_eq(cap.dock.docked_count(), 3, "its three raiders ride in on its cradles (Q6)")
	assert_eq(_alive(WAVE_ONE), 3, "and count as in play while they do")
	assert_true(_api().alive("RAIDER CARRIER 1"), "the carrier is an actor of the mission")
	assert_eq(_api().objective_state(&"carrier"), ObjectiveBook.ACTIVE, "destroying a carrier is offered")
	await _run_on(60.0, func() -> bool: return run.state == CarrierRun.State.STANDOFF)
	assert_eq(run.state, CarrierRun.State.STANDOFF, "clear of its point it launches them and hangs back")
	assert_eq(cap.dock.launches, 3)
	for c: Combatant in main.ships.alive(ShipPool.DEFAULT_TYPE):
		assert_true(c.ship.is_visible_in_tree(), "%s is launched" % c.display_name)
		assert_false(c.ship.has_meta(CarrierJumps.RIDING_META))
	assert_eq(_alive(WAVE_ONE), 3)
	assert_gt(_at(_civilian()).distance_to(main.world.to_universe(cap.global_position)), 5000.0, "the carrier stays well back")
	await _run_on(60.0, func() -> bool: return _journal_has("say control_carrier"))
	assert_true(_journal_has("say control_carrier"), "Control's line for the carrier")


func test_the_objectives_carriers_are_the_waves_carriers() -> void:
	var listed: Array = []
	for objective: Dictionary in (JSON.parse_string(FileAccess.get_file_as_string(MISSION_PATH)) as Dictionary)["mission"]["objectives"]:
		if String(objective["id"]) == String(MissionScriptClass.CARRIER_OBJECTIVE):
			listed = objective["success"]["names"]
			assert_false(bool(objective["primary"]), "optional")
			assert_false(bool(objective["success"]["all"]), "any one of them")
	var named: Array = []
	for wave: Dictionary in MissionScriptClass.WAVES:
		named.append(wave["carrier"]["name"])
		assert_eq(wave["carrier"]["arrival"], "docked", "every wave rides in docked (Q6)")
	assert_eq(listed, named)


func test_destroying_a_carrier_is_the_optional_objective() -> void:
	DebugConsole.flags.invulnerable = true
	await _fly()
	_civilian().damageable.invulnerable = true
	assert_true(_run("mission goto wave_one").ok)
	await _ticks(2)
	var run: CarrierRun = _carriers().runs()[0]
	await _run_on(60.0, func() -> bool: return run.state == CarrierRun.State.STANDOFF)
	assert_eq(_api().objective_state(&"carrier"), ObjectiveBook.ACTIVE)
	assert_true(_run("carrier kill").ok)
	await _ticks(4)
	assert_eq(_api().objective_state(&"carrier"), ObjectiveBook.DONE, "a carrier destroyed")
	assert_false(_api().has_ended(), "an optional objective ends nothing")
	assert_eq(_alive(WAVE_ONE), 3, "its launched raiders fight on")


func test_a_carrier_that_gets_away_is_not_a_kill_and_raiders_gone_home_are_down() -> void:
	DebugConsole.flags.invulnerable = true
	await _fly()
	_civilian().damageable.invulnerable = true
	assert_true(_run("mission goto wave_two").ok)
	await _ticks(2)
	var run: CarrierRun = _carriers().runs()[-1]
	var cap: CapitalStandin = run.carrier
	assert_eq(cap.targetable.display_name, "RAIDER CARRIER 2")
	assert_eq(_carriers().runs().size(), 1, "the skipped first wave's carrier is gone with it")
	await _run_on(60.0, func() -> bool: return run.state == CarrierRun.State.STANDOFF)
	for c: Combatant in main.ships.alive(ShipPool.DEFAULT_TYPE):
		if c.display_name == "RAIDER 4":
			c.damageable.kill()  # just launched, the others are still beside their carrier
	await _run_on(float(run.options["wait_s"]) + 5.0, func() -> bool: return run.state == CarrierRun.State.FLEEING)
	assert_eq(run.flee_reason, CarrierTactics.FLEE_ALL_DOCKED, "three left: they went home, and their carrier flees (D83)")
	assert_eq(cap.dock.docked_count(), 3)
	await _ticks(2)
	assert_eq(_alive(WAVE_TWO), 0, "raiders back on their cradles are out of the fight: the wave is down")
	assert_eq(run.move, CarrierTactics.MOVE_RUN, "no gate here and its drive recharging: it runs")
	assert_true(_run("carrier charge").ok)
	await _run_on(120.0, func() -> bool: return _carriers().runs().is_empty())
	assert_true(_carriers().runs().is_empty(), "recharged, it jumped out")
	await _ticks(2)
	assert_false(_api().alive("RAIDER CARRIER 2"))
	assert_eq(_api().objective_state(&"carrier"), ObjectiveBook.ACTIVE, "a carrier that got away is no kill")
	assert_eq(main.ships.alive(ShipPool.DEFAULT_TYPE).size(), 0, "its docked raiders left with it")


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
	assert_eq_deep(_objective_states(), {"escort": "done", "home": "done", "carrier": "active"})


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


# A fair escort's run (Q40, M7-T54): each wave is fought down `FIGHT_S_PER_RAIDER` a raider after it first closes on the
# civilian, the rest is the mission's own flight and triggers. It prints the timeline the pacing was set from.
const FIGHT_S_PER_RAIDER: float = 10.0
const CONTACT_M: float = 2000.0
const SPEED_UP: float = 2.0


func test_a_fought_run_takes_6_to_8_minutes_with_each_wave_cleared_before_the_next() -> void:
	if OS.get_environment("GUT_SLOW") != "1":
		pending("GUT_SLOW=1 flies a whole fought run")
		return
	DebugConsole.flags.invulnerable = true
	await _fly(3)
	_civilian().damageable.invulnerable = true
	var scale_backup: float = Engine.time_scale
	Engine.time_scale = SPEED_UP
	var waves: Array = [WAVE_ONE, WAVE_TWO, WAVE_THREE]
	var spawned: Array[float] = [-1.0, -1.0, -1.0]
	var contact: Array[float] = [-1.0, -1.0, -1.0]
	var cleared: Array[float] = [-1.0, -1.0, -1.0]
	var ticks: int = 0
	while not _api().has_ended() and ticks < roundi(60.0 * 900.0 / SPEED_UP):
		await _ticks(1)
		ticks += 1
		var now: float = _api().time_s()
		if ticks % roundi(60.0 * 15.0 / SPEED_UP) == 0:
			var civ: Combatant = _civilian()
			gut.p("  t %4.0f s  %-10s  civilian at %5.1f km, %3.0f m/s, %s" % [now, _api().step_name(),
					_at(civ).distance_to(_buoy_at("NAV ALPHA")) / 1000.0,
					civ.ship.linear_velocity.length(), _behaviour(civ)])
		for w: int in 3:
			var names: Array[String] = waves[w]
			if spawned[w] < 0.0 and _journal_has("spawn %s raider_fighter" % names[0]):
				spawned[w] = now
			if spawned[w] < 0.0 or cleared[w] >= 0.0:
				continue
			if contact[w] < 0.0 and _closest_raider_m(names) < CONTACT_M:
				contact[w] = now
			if contact[w] >= 0.0 and now - contact[w] >= FIGHT_S_PER_RAIDER * names.size():
				for c: Combatant in main.ships.alive(ShipPool.DEFAULT_TYPE):
					if names.has(c.display_name):
						c.damageable.kill()
				cleared[w] = now
	Engine.time_scale = scale_backup
	var end_s: float = _api().time_s()
	gut.p("fought run (seed 3, %s): waves at %s, contact %s, cleared %s, end %.0f s" % [_civilian_name(), spawned, contact,
			cleared, end_s])
	assert_true(_api().has_ended() and bool(_api().result.get("success", false)), str(_api().result))
	for w: int in [1, 2]:
		assert_gt(spawned[w] - cleared[w - 1], MissionScriptClass.BREATHER_S - 0.1,
				"wave %d comes a breather after wave %d is down" % [w + 1, w])
	assert_between(end_s, 360.0, 480.0, "6 to 8 minutes (Q40)")


func _closest_raider_m(names: Array[String]) -> float:
	var best: float = INF
	var at: Vector3 = _civilian().ship.global_position
	for c: Combatant in main.ships.alive(ShipPool.DEFAULT_TYPE):
		if names.has(c.display_name):
			best = minf(best, c.ship.global_position.distance_to(at))
	return best


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
