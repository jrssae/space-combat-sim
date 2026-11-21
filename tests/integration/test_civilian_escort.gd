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
## Six, eight and ten raiders (the maintainer, 2026-11-18).
const WAVE_ONE: Array[String] = ["RAIDER 1", "RAIDER 2", "RAIDER 3", "RAIDER 4", "RAIDER 5", "RAIDER 6"]
const WAVE_TWO: Array[String] = ["RAIDER 7", "RAIDER 8", "RAIDER 9", "RAIDER 10", "RAIDER 11", "RAIDER 12", "RAIDER 13",
		"RAIDER 14"]
const WAVE_THREE: Array[String] = ["RAIDER 15", "RAIDER 16", "RAIDER 17", "RAIDER 18", "RAIDER 19", "RAIDER 20", "RAIDER 21",
		"RAIDER 22", "RAIDER 23", "RAIDER 24"]

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
	for type: StringName in ShipCatalog.civilian_types():
		if type != main.ships.type_of(civilian):
			assert_eq(main.ships.pool_size(type), 0, "no %s pooled" % type)


## D89 (M8-T23): the escort flies in its own system, Gamma Leporis: its ships are spawned there, with no station, no nebula
## and no home dock for anyone, round the ice world rather than Epsilon III.
func test_it_runs_in_gamma_leporis_with_no_station_no_nebula_and_no_home_dock() -> void:
	await _fly()
	assert_eq(main.star_system.system.id, &"gamma_leporis")
	assert_true(main.star_system.system.is_valid(), "; ".join(main.star_system.system.errors))
	assert_false(main.star_system.system.has_id(&"babylon5"))
	assert_true(main.star_system.system.has_id(&"gamma_leporis_ii"))
	assert_eq(main.world.origin.system_id, &"gamma_leporis")
	assert_eq(main.world.to_universe(main.ship.global_position).system_id, &"gamma_leporis")
	assert_not_null(_civilian(), "the civilian is spawned in the new system")
	assert_eq(_at(_civilian()).system_id, &"gamma_leporis")
	assert_true(main.far_props.station == null or not is_instance_valid(main.far_props.station), "no Babylon 5 here")
	assert_false(main.space_environment._nebula_shown, "the sky has no nebula")
	var wing: Wing = main.wings.player_wing()
	assert_eq(wing.members().size(), 2, "ALPHA 2 and ALPHA 3 fly with the player")
	for c: Combatant in [main.combatant] + wing.members():
		assert_eq(c.home, &"", "%s has no home dock" % c.display_name)
		assert_null(main.docking.home_dock(c))


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
	await _wait_for("wave two", func() -> bool: return _journal_has("spawn %s raider_fighter" % WAVE_TWO[0]),
			roundi(60.0 * (MissionScriptClass.WAVE_TWO_BREATHER_S + 15.0) / 4.0))
	Engine.time_scale = scale_backup
	# The breather counts from when the step sees the wave down, after its lines.
	assert_between(_api().time_s() - down_s, MissionScriptClass.WAVE_TWO_BREATHER_S, MissionScriptClass.WAVE_TWO_BREATHER_S + 10.0,
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
			roundi(60.0 * (MissionScriptClass.WAVE_TWO_BREATHER_S + 15.0) / 4.0))
	Engine.time_scale = scale_backup


func test_the_waves_and_the_arrival_do_not_need_nav_beta_in_one_piece() -> void:
	# M8-T08: a stray bolt took the buoy in a long fight beside it, and the mission waited on the buoy for ever.
	DebugConsole.flags.invulnerable = true
	await _fly()
	_civilian().damageable.invulnerable = true
	for buoy: NavBuoy in main.buoys:
		if buoy.display_name == "NAV BETA":
			buoy.set_destroyed(true)
	assert_true(_run("mission goto wave_one").ok)
	await _ticks(2)
	assert_false(_api().alive("NAV BETA"), "the buoy is gone")
	assert_true(_run("kill all").ok)
	var beta: Vector3 = MissionScriptClass.BETA_AT
	main.mission.stage.place(_civilian_name(), UniversePos.new(beta.x + 600.0, beta.y, beta.z + 600.0, _api().world.system_id))
	var limit_s: float = MissionScriptClass.WAVE_TWO_BREATHER_S + 20.0
	await _run_on(limit_s, func() -> bool: return _api().step_name() == &"wave_two")
	assert_eq(_api().step_name(), &"wave_two", "the next wave comes by the civilian's place")
	await _ticks(2)
	assert_true(_run("kill all").ok)
	await _run_on(limit_s, func() -> bool: return _api().step_name() == &"wave_three")
	assert_eq(_api().step_name(), &"wave_three", "and the last")
	await _ticks(2)
	assert_true(_run("kill all").ok)
	await _run_on(60.0, func() -> bool: return _api().world.line_finished(&"civilian_nearly_there"))
	await _ticks(2)
	assert_true(_api().world.line_finished(&"civilian_nearly_there"), "past the wave's lines, it waits for the arrival")
	assert_false(_api().watched().has("nav beta"), "the arrival waits on the civilian's route, not on the buoy: %s" % str(_api().watched()))


# --- the maintainer's play-test of 2026-11-19 (M8-T08) ------------------------------------------------------------------


func test_nav_beta_is_listed_with_the_escort_objective() -> void:
	DebugConsole.flags.invulnerable = true
	await _fly()
	assert_true(_run("mission goto depart").ok)
	await _ticks(2)
	assert_eq(_api().objective_state(&"escort"), ObjectiveBook.ACTIVE)
	assert_eq((_api().book.subject(&"escort")["actors"] as PackedStringArray)[0], "NAV BETA", "the escort is about NAV BETA first")
	var listed: Dictionary = {}
	for entry: Dictionary in main.target_menu._objectives():
		listed[String(entry["label"])] = entry
	assert_true(listed.has("NAV BETA"), "the target menu's objectives list NAV BETA from the hand-over: %s" % str(listed.keys()))
	assert_ne(int((listed.get("NAV BETA", {}) as Dictionary).get("target_id", 0)), 0, "as the buoy itself, to pick for a waypoint")


func test_a_civilian_taken_from_its_routes_end_flies_back_and_stops_there() -> void:
	# It arrived, a raid chased it off, and it idled where the chase ended, kilometres short, for the rest of the run. Its
	# route ends just past the 75 % mark until the last wave comes (M8-T26), so that is where it holds here.
	DebugConsole.flags.invulnerable = true
	await _fly()
	var civilian: Combatant = _civilian()
	civilian.damageable.invulnerable = true
	assert_true(_run("mission goto wave_one").ok)
	await _ticks(2)
	assert_true(_journal_has("hold_route_end %s" % _civilian_name()), "the script asks it to hold its route's end")
	# The wave stays up, out of the way, so no later one comes while this watches the civilian: one raider is left, far off
	# and pilotless, and its carrier does not call it home.
	var run: CarrierRun = _carriers().runs()[0]
	await _run_on(60.0, func() -> bool: return run.state == CarrierRun.State.STANDOFF)
	_park_the_wave(run, WAVE_ONE[0])
	var path := (civilian.driver.brain as AiPilot).behaviour(&"follow_path") as BehaviourFollowPath
	assert_eq(path.index, 1, "past the 25 % point, bound for the end of its route")
	var system: StringName = _api().world.system_id
	var mark: Vector3 = MissionScriptClass.HOLD_AT
	var end := UniversePos.new(mark.x, mark.y, mark.z, system)
	main.mission.stage.place(_civilian_name(), UniversePos.new(mark.x, mark.y, mark.z + 300.0, system))
	await _run_on(120.0, func() -> bool: return _api().world.route_done(_civilian_name()))
	assert_true(_api().world.route_done(_civilian_name()), "it flies its route to the end")
	for away: Vector3 in [Vector3(300.0, 0.0, 4000.0), Vector3(-200.0, 100.0, -2500.0)]:
		main.mission.stage.place(_civilian_name(), UniversePos.new(mark.x + away.x, mark.y + away.y, mark.z + away.z, system))
		civilian.ship.linear_velocity = main.world.rest_velocity()
		var from_m: float = _at(civilian).distance_to(end)
		await _run_on(25.0, func() -> bool: return false)
		assert_lt(_at(civilian).distance_to(end), from_m - 150.0, "taken %.0f m away, it is on its way back" % from_m)
		assert_eq(_behaviour(civilian), "follow_path")
		await _run_on(400.0, func() -> bool: return _at(civilian).distance_to(end) < MissionStage.HOLD_END_M \
				and (civilian.ship.linear_velocity - main.world.rest_velocity()).length() < 2.0)
		assert_lt(_at(civilian).distance_to(end), MissionStage.HOLD_END_M, "and it stops at its route's end")
		await _run_on(30.0, func() -> bool: return false)
		assert_lt(_at(civilian).distance_to(end), MissionStage.HOLD_END_M, "where it stays")
	assert_eq(_api().step_name(), &"wave_one", "the wave was up all the while")


# Leaves one raider of the wave `run` brought, far off and pilotless, and its carrier not calling it home: the wave stays up
# and out of the way, so no later wave comes while a test watches the civilian. Returns that raider.
func _park_the_wave(run: CarrierRun, keep: String) -> Combatant:
	run.options["recall_left"] = 0
	var kept: Combatant = null
	for c: Combatant in main.ships.alive(ShipPool.DEFAULT_TYPE):
		if c.display_name != keep:
			c.damageable.kill()
			continue
		c.driver.brain = null
		c.damageable.invulnerable = true
		c.ship.global_position += Vector3(0.0, 90000.0, 0.0)
		kept = c
	return kept


func test_the_civilian_waits_in_the_third_field_until_the_last_wave_comes() -> void:
	# M8-T26 (the play-test of 2026-11-21): it was at NAV BETA before the second wave was beaten. Its route now ends at the
	# 75 % mark; the last leg is flown only once the third wave has jumped in, however slow the player or fast the civilian.
	DebugConsole.flags.invulnerable = true
	await _fly()
	var civilian: Combatant = _civilian()
	civilian.damageable.invulnerable = true
	assert_true(_run("mission goto wave_one").ok)
	var path := (civilian.driver.brain as AiPilot).behaviour(&"follow_path") as BehaviourFollowPath
	await _run_on(20.0, func() -> bool: return path.index >= 1)  # past its route's first point before the next skip moves it
	assert_true(_run("mission goto wave_two").ok)
	await _ticks(2)
	var run: CarrierRun = _carriers().runs()[-1]
	await _run_on(60.0, func() -> bool: return run.state == CarrierRun.State.STANDOFF)
	var last: Combatant = _park_the_wave(run, WAVE_TWO[0])
	var system: StringName = _api().world.system_id
	var mark: Vector3 = MissionScriptClass.HOLD_AT
	var hold := UniversePos.new(mark.x, mark.y, mark.z, system)
	main.mission.stage.place(_civilian_name(), UniversePos.new(mark.x, mark.y, mark.z + 400.0, system))
	await _run_on(60.0, func() -> bool: return _api().world.route_done(_civilian_name()))
	await _run_on(240.0, func() -> bool: return _at(civilian).distance_to(hold) < MissionStage.HOLD_END_M \
			and (civilian.ship.linear_velocity - main.world.rest_velocity()).length() < 2.0)
	await _run_on(30.0, func() -> bool: return false)
	assert_eq(_api().step_name(), &"wave_two", "the second wave is still up")
	assert_lt(_at(civilian).distance_to(hold), MissionStage.HOLD_END_M, "it waits just past the 75 % mark, in the third field")
	assert_gt(_at(civilian).distance_to(_buoy_at("NAV BETA")), 10000.0, "a long way short of NAV BETA")
	assert_false(_journal_has("fly_route %s %s" % [_civilian_name(), MissionScriptClass.LAST_LEG]))
	last.damageable.invulnerable = false
	last.damageable.kill()
	await _run_on(MissionScriptClass.BREATHER_S + 20.0, func() -> bool: return _api().step_name() == &"wave_three")
	assert_eq(_api().step_name(), &"wave_three", "the second wave down, the third jumps in")
	assert_true(_journal_has("fly_route %s %s" % [_civilian_name(), MissionScriptClass.LAST_LEG]), "and only now it is sent on")
	await _ticks(2)
	assert_true(_run("kill all").ok)
	var from_m: float = _at(civilian).distance_to(_buoy_at("NAV BETA"))
	await _run_on(60.0, func() -> bool: return false)
	assert_lt(_at(civilian).distance_to(_buoy_at("NAV BETA")), from_m - 1500.0, "it runs the last leg for NAV BETA")
	assert_false(_api().has_ended(), "not there yet")


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
	assert_eq(cap.dock.docked_count(), 6, "its six raiders ride in on its cradles (Q6)")
	assert_eq(_alive(WAVE_ONE), 6, "and count as in play while they do")
	assert_true(_api().alive("RAIDER CARRIER 1"), "the carrier is an actor of the mission")
	assert_eq(_api().objective_state(&"carrier"), ObjectiveBook.ACTIVE, "destroying a carrier is offered")
	await _run_on(60.0, func() -> bool: return run.state == CarrierRun.State.STANDOFF)
	assert_eq(run.state, CarrierRun.State.STANDOFF, "clear of its point it launches them and hangs back")
	assert_eq(cap.dock.launches, 6)
	for c: Combatant in main.ships.alive(ShipPool.DEFAULT_TYPE):
		assert_true(c.ship.is_visible_in_tree(), "%s is launched" % c.display_name)
		assert_false(c.ship.has_meta(CarrierJumps.RIDING_META))
	assert_eq(_alive(WAVE_ONE), 6)
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
	# Its death blast (M10-T09: a cruiser's reactor) takes the raiders near it; those out of its reach fight on.
	var reach: float = BlastTable.capital_death(&"", run.carrier.ship_class, run.carrier.faction, "reactor").radius_m
	var out_of_reach: Array[Combatant] = []
	for c: Combatant in main.ships.alive(ShipPool.DEFAULT_TYPE):
		if WAVE_ONE.has(c.display_name) and c.ship.global_position.distance_to(run.carrier.global_position) > reach + 50.0:
			out_of_reach.append(c)
	assert_true(_run("carrier kill").ok)
	await _ticks(4)
	assert_eq(_api().objective_state(&"carrier"), ObjectiveBook.DONE, "a carrier destroyed")
	assert_false(_api().has_ended(), "an optional objective ends nothing")
	for c: Combatant in out_of_reach:
		assert_true(_api().alive(c.display_name), "%s, out of its blast, fights on" % c.display_name)
	gut.p("raiders alive after the carrier's blast: %d of 6 (%d were out of its reach)" % [_alive(WAVE_ONE), out_of_reach.size()])


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
		if WAVE_TWO.find(c.display_name) in [0, 1, 2, 3, 4]:
			c.damageable.kill()  # five of the eight, just launched: the others are still beside their carrier
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
	assert_eq(_alive(WAVE_ONE), 6, "wave one jumped in")
	var first: Combatant = main.ships.alive(ShipPool.DEFAULT_TYPE)[0]
	var range_m: float = _at(first).distance_to(_at(_civilian()))
	assert_between(range_m, 6000.0, 12000.0, "6 to 12 km from the civilian")
	assert_eq(((first.driver.brain as AiPilot).context as AiContext).objective_name, _civilian_name(), "sent at the civilian")
	assert_true(_run("kill all").ok)
	assert_true(_run("mission goto wave_two").ok)
	await _ticks(2)
	assert_eq(_alive(WAVE_TWO), 8, "wave two")
	assert_true(_run("kill all").ok)
	assert_true(_run("mission goto wave_three").ok)
	await _ticks(2)
	assert_eq(_alive(WAVE_THREE), 10, "wave three")
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
	assert_eq(_alive(WAVE_TWO), 8, "the step played now has its wave")
	var point: Vector3 = MissionScriptClass.POINT_50
	var fifty := UniversePos.new(point.x, point.y, point.z, _api().world.system_id)
	assert_lt(_at(_civilian()).distance_to(fifty), 1.0, "at the 50 % point")


func test_a_skipped_run_spawns_every_ship_from_the_pools() -> void:
	DebugConsole.flags.invulnerable = true
	await _fly()
	assert_true(_run("mission goto arrive").ok)
	for ship_name: String in WAVE_ONE + WAVE_TWO + WAVE_THREE:
		assert_true(_journal_has("spawn %s raider_fighter" % ship_name), ship_name)
	assert_eq(main.ships.pool_size(ShipPool.DEFAULT_TYPE), 24, "twenty-four raiders, all the script spawns")
	assert_eq(main.ships.pool_size(ShipPool.ALLY_TYPE), 2, "ALPHA 2 and ALPHA 3")
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
	await _run_on(1800.0, func() -> bool:
		if _api().step_name() in [&"wave_one", &"wave_two", &"wave_three"] and not main.ships.alive(ShipPool.DEFAULT_TYPE).is_empty():
			_run("kill all")
		return _at(civilian).distance_to(_buoy_at("NAV BETA")) < MissionScriptClass.ARRIVAL_M)
	assert_lt(_at(civilian).distance_to(_buoy_at("NAV BETA")), MissionScriptClass.ARRIVAL_M, "it crosses all four fields to NAV BETA")
	assert_eq(civilian.damageable.hull.hp, hull, "no rock hit on the way")


# A fair escort's run (Q40, M7-T54; M8-T08's waves of six, eight and ten): each wave is fought down to the three its
# carrier calls home (D83), `FIGHT_S_PER_RAIDER` a raider after it first closes on the civilian; those three fly home and
# dock, which ends the wave. The rest is the mission's own flight and triggers. It prints the timeline.
const FIGHT_S_PER_RAIDER: float = 10.0
const CONTACT_M: float = 2000.0
## Ticks per real tick: the physics rate and the time scale rise together, so each step is still 1/60 s of sim time.
const SPEED_UP: float = 4.0
const GO_HOME_AT: int = 3


func test_a_fought_run_ends_each_wave_at_three_left_before_the_next_comes() -> void:
	if OS.get_environment("GUT_SLOW") != "1":
		pending("GUT_SLOW=1 flies a whole fought run")
		return
	DebugConsole.flags.invulnerable = true
	await _fly(3)
	_civilian().damageable.invulnerable = true
	_take_the_player_out_of_the_way()
	var scale_backup: float = Engine.time_scale
	var rate_backup: int = Engine.physics_ticks_per_second
	Engine.time_scale = SPEED_UP
	Engine.physics_ticks_per_second = roundi(rate_backup * SPEED_UP)
	var waves: Array = [WAVE_ONE, WAVE_TWO, WAVE_THREE]
	var spawned: Array[float] = [-1.0, -1.0, -1.0]
	var contact: Array[float] = [-1.0, -1.0, -1.0]
	var fought: Array[float] = [-1.0, -1.0, -1.0]
	var cleared: Array[float] = [-1.0, -1.0, -1.0]
	var arrived_s: float = -1.0  # when the civilian first comes within 3 km of NAV BETA
	var held_s: float = 0.0  # how long it sat still short of NAV BETA, waiting for the last wave
	var ticks: int = 0
	while not _api().has_ended() and _api().time_s() < 2400.0:
		await _ticks(1)
		ticks += 1
		_ride_over(_civilian())
		var now: float = _api().time_s()
		if arrived_s < 0.0 and _at(_civilian()).distance_to(_buoy_at("NAV BETA")) < 2.0 * MissionScriptClass.ARRIVAL_M:
			arrived_s = now
		if arrived_s < 0.0 and spawned[2] < 0.0 and _behaviour(_civilian()) == "idle":
			held_s += 1.0 / 60.0
		if ticks % (60 * 15) == 0:
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
			var kills: int = names.size() - GO_HOME_AT
			if fought[w] < 0.0 and contact[w] >= 0.0 and now - contact[w] >= FIGHT_S_PER_RAIDER * kills:
				for c: Combatant in main.ships.alive(ShipPool.DEFAULT_TYPE):
					if names.find(c.display_name) >= 0 and names.find(c.display_name) < kills:
						c.damageable.kill()
				fought[w] = now
			if fought[w] >= 0.0 and _alive(names) == 0:
				cleared[w] = now
	Engine.time_scale = scale_backup
	Engine.physics_ticks_per_second = rate_backup
	var end_s: float = _api().time_s()
	gut.p("fought run (seed 3, %s): waves at %s, contact %s, down to three at %s, home or dead at %s, the civilian at NAV BETA at %.0f s (held %.0f s on the way), end %.0f s, its hull %.0f %%" % [
			_civilian_name(), spawned, contact, fought, cleared, arrived_s, held_s, end_s, 100.0 * _civilian().damageable.hull.fraction()])
	assert_true(_api().has_ended() and bool(_api().result.get("success", false)), str(_api().result))
	for w: int in [1, 2]:
		assert_gt(spawned[w] - cleared[w - 1], [MissionScriptClass.WAVE_TWO_BREATHER_S, MissionScriptClass.BREATHER_S][w - 1] - 0.1,
				"wave %d comes a breather after wave %d is down" % [w + 1, w])
	# The timeline the maintainer asked for (2026-11-21): the civilian is not at NAV BETA until the third wave has come and
	# been fought, and gets there about when that wave is beaten.
	for w: int in 3:
		assert_gt(arrived_s, spawned[w], "it reaches NAV BETA after wave %d has jumped in" % (w + 1))
		assert_gt(arrived_s, contact[w], "and after wave %d has closed on it" % (w + 1))
	assert_between(arrived_s - cleared[2], -60.0, 240.0, "about when the third wave is beaten (%.0f s after)" % (arrived_s - cleared[2]))
	assert_lt(held_s, 120.0, "without a long wait on the way in a run fought at this pace (%.0f s)" % held_s)
	assert_between(end_s, 780.0, 1260.0, "13 to 21 minutes on the 60 km route with waves of six, eight and ten")


# --- the wing flies it with an AI in the player's place (M8-T08): a balance judgement --------------------------------------

## Sim seconds a tick at this speed (the physics rate rises with the time scale), and when a run is given up.
const AI_SPEED_UP: float = 4.0
const AI_LIMIT_S: float = 1200.0
## The pilotless player's ship is held this far over the civilian, so the wing fights where a player would.
const AI_STAY_M: float = 500.0


func test_the_wing_and_an_ai_leader_see_the_civilian_through_on_cover_seed_1() -> void:
	await _ai_fought_run(1, AiContext.Order.COVER_ME)


func test_the_wing_and_an_ai_leader_see_the_civilian_through_on_cover_seed_2() -> void:
	await _ai_fought_run(2, AiContext.Order.COVER_ME)


func test_the_wing_and_an_ai_leader_see_the_civilian_through_on_cover_seed_3() -> void:
	await _ai_fought_run(3, AiContext.Order.COVER_ME)


func test_the_wing_and_an_ai_leader_see_the_civilian_through_engaging_seed_1() -> void:
	await _ai_fought_run(1, AiContext.Order.ENGAGE_AT_WILL)


func test_the_wing_and_an_ai_leader_see_the_civilian_through_engaging_seed_2() -> void:
	await _ai_fought_run(2, AiContext.Order.ENGAGE_AT_WILL)


func test_the_wing_and_an_ai_leader_see_the_civilian_through_engaging_seed_3() -> void:
	await _ai_fought_run(3, AiContext.Order.ENGAGE_AT_WILL)


# The whole escort with waves of six, eight and ten, fought by ALPHA 2, ALPHA 3 and a third AI Starfury for the player's
# guns, on `order`; the civilian and every wingman can be lost. The player's own ship flies no guns: it is held over the
# civilian, where the wing covers it. It prints the raiders destroyed and gone home, the losses and the run's time.
func _ai_fought_run(seed_value: int, order: AiContext.Order) -> void:
	if BalanceTests.skip(self):
		return
	await _fly(seed_value)
	DebugConsole.flags.invulnerable = true  # the player's own ship flies no guns here: it is only where the wing stays
	main.ensure_free(ShipPool.ALLY_TYPE, 1)
	var stand_in: Combatant = _api().spawn({"type": "starfury_ally",
			"name": "ALPHA %d" % (main.ships.alive(ShipPool.ALLY_TYPE).size() + 2), "anchor": "player", "offset": [0, 0, 80],
			"velocity": [0, 0, -60], "behaviour": {"type": "ai", "profile": "ally_starfury"}, "wing": "ALPHA"})
	assert_not_null(stand_in, "the AI in the player's place")
	main.wings.give_order(order)
	_take_the_player_out_of_the_way()
	var tally: Dictionary = {"destroyed": 0, "with_carrier": 0, "carriers": 0, "fleeing": 0}
	for c: Combatant in main.ships.all_ships():
		c.damageable.destroyed.connect(func(info: HitInfo) -> void:
			var fleeing: bool = false
			for run: CarrierRun in _carriers().runs():
				fleeing = fleeing or (run.carrier.dock != null and run.carrier.dock.is_handling(c.ship))
			gut.p("  t %4.0f s  %s destroyed by %s (%s)%s" % [_api().time_s(), c.display_name, _name_of(info.shooter_id), info.cause,
					" on its way home" if fleeing else ""])
			if c.display_name.begins_with("RAIDER"):
				tally["with_carrier" if info.cause == HitInfo.CAUSE_CARRIER_LOST else "destroyed"] += 1
				tally["fleeing"] += 1 if fleeing else 0)
	var wingmen: Array[Combatant] = []
	for c: Combatant in main.ships.alive(ShipPool.ALLY_TYPE):
		wingmen.append(c)
	var civilian: Combatant = _civilian()
	var scale_backup: float = Engine.time_scale
	var rate_backup: int = Engine.physics_ticks_per_second
	Engine.time_scale = AI_SPEED_UP
	Engine.physics_ticks_per_second = roundi(rate_backup * AI_SPEED_UP)
	var ticks: int = 0
	var seen_carriers: Dictionary = {}
	while not _api().has_ended() and _api().time_s() < AI_LIMIT_S:
		await _ticks(1)
		ticks += 1
		for run: CarrierRun in _carriers().runs():
			if not seen_carriers.has(run):
				seen_carriers[run] = true
				run.carrier.damageable.destroyed.connect(func(_info: HitInfo) -> void: tally["carriers"] += 1, CONNECT_ONE_SHOT)
		_ride_over(civilian)
		if ticks % roundi(60.0 * 60.0) == 0:
			gut.p("  t %4.0f s  %-10s  civilian hull %3.0f %%, %4.1f km to go, %s; raiders destroyed %d, in play %d" % [_api().time_s(),
					_api().step_name(), 100.0 * civilian.damageable.hull.fraction(),
					_at(civilian).distance_to(_buoy_at("NAV BETA")) / 1000.0, _behaviour(civilian), tally["destroyed"],
					main.ships.alive(ShipPool.DEFAULT_TYPE).size()])
	Engine.time_scale = scale_backup
	Engine.physics_ticks_per_second = rate_backup
	var lost: PackedStringArray = PackedStringArray()
	for c: Combatant in wingmen:
		if c.damageable.hull.destroyed:
			lost.append(c.display_name)
	var came: int = 0
	var out: int = 0
	var raiders: int = 0
	for wave: Dictionary in MissionScriptClass.WAVES:
		raiders += int(wave["size"])
	for i: int in raiders:
		var ship_name: String = "RAIDER %d" % (i + 1)
		came += 1 if _journal_has("spawn %s raider_fighter" % ship_name) else 0
		out += 1 if _api().alive(ship_name) else 0
	var home: int = came - int(tally["destroyed"]) - int(tally["with_carrier"]) - out
	gut.p("AI fought run, seed %d, %s (%s, %.0f hull): %s after %.0f s; raiders come %d, destroyed %d, gone home %d, lost with a carrier %d, still out %d; carriers destroyed %d; wingmen lost %s; civilian hull %.0f %%" % [
			seed_value, AiContext.ORDER_WORDS[order], _civilian_name(), civilian.damageable.hull.max_hp,
			GameFlow.describe_result(_api().result) if _api().has_ended() else "not over", _api().time_s(), came, tally["destroyed"],
			home, tally["with_carrier"], out, tally["carriers"], ", ".join(lost) if not lost.is_empty() else "none",
			100.0 * civilian.damageable.hull.fraction()])
	gut.p("  of the raiders destroyed, %d were on their way home" % tally["fleeing"])
	if not _api().has_ended():
		gut.p("  not over: step %s, waiting on %s; NAV BETA %s" % [_api().step_name(), str(_api().watched()),
				"in play" if _api().alive("NAV BETA") else "gone"])
	assert_gte(came, WAVE_ONE.size(), "the run got as far as its first wave (a measurement, not a gate: read the lines above)")


# Nothing rams the pilotless player's ship: in these runs it only marks where the leader is.
func _take_the_player_out_of_the_way() -> void:
	main.ship.collision_layer = 0
	main.ship.collision_mask = 0


# Holds the pilotless player's ship over `civilian`, so the raiders it draws and the wing that covers it stay where a
# player would fight (left alone it coasts away for good and takes the fight with it).
func _ride_over(civilian: Combatant) -> void:
	if _api().controls_locked or civilian.damageable.hull.destroyed:
		return
	var to_place: Vector3 = civilian.ship.global_position + Vector3(0.0, AI_STAY_M, 0.0) - main.ship.global_position
	main.ship.linear_velocity = civilian.ship.linear_velocity + (0.5 * to_place).limit_length(400.0)


# Who an instance id is: a ship's name, else the node's.
func _name_of(id: int) -> String:
	var node := instance_from_id(id) as Node if id != 0 else null
	if node == null:
		return "nobody"
	if node == main.ship or main.ship.is_ancestor_of(node):
		return "the player"
	for c: Combatant in main.ships.all_ships():
		if c.ship == node or c.ship.is_ancestor_of(node):
			return c.display_name
	return String(node.name)


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
