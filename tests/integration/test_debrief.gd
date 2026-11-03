extends GutTest
## The debrief (architecture §18, D56, AC9; M5-T09). Part one drives the screen alone with a recording stand-in for `Game`, the
## way a pad drives it (injected `ui_*` events). Part two plays the test mission in the real main scene under the real `Game`
## autoload (its scene parent pointed at a node of the test): it ends by `mission skip` and by the player's death, the debrief
## replaces Main after a short beat and shows the right content, and Retry and Front end leave it with nothing left behind.

const DebriefScene: PackedScene = preload("res://src/frontend/debrief_screen.tscn")
const MISSION_PATH: String = "res://tests/fixtures/missions/test_mission.json"
const RECORDING_MAIN: String = "res://tests/fixtures/recording_main.tscn"
## The beat before the debrief, shortened so the tests do not wait three seconds each.
const BEAT_S: float = 0.25

var game: RecordingGame
var holder: Node
var main: Main
var source: FakeInputSource
var _saved: Dictionary = {}


func before_each() -> void:
	get_tree().paused = false
	game = RecordingGame.new()
	autofree(game)
	source = FakeInputSource.new()
	_saved = {"flow": Game.flow, "parent": Game.scene_parent, "main_path": Game.main_scene_path}
	Game.flow = GameFlow.new()
	holder = Node.new()
	add_child_autofree(holder)
	Game.scene_parent = holder
	Game.main_scene_path = RECORDING_MAIN


func after_each() -> void:
	get_tree().paused = false
	Game.flow = _saved["flow"]
	Game.scene_parent = _saved["parent"]
	Game.main_scene_path = _saved["main_path"]


# --- Helpers ---------------------------------------------------------------------------------------------------------


func _result(overrides: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {
		"success": true, "reason": "every primary objective done", "scenario_id": &"test_mission", "title": "Test Mission",
		"objectives": [
			{"id": &"reach", "text": "Fly to NAV ALPHA", "primary": true, "state": &"done"},
			{"id": &"protect", "text": "Keep NAV ALPHA in one piece", "primary": false, "state": &"failed"},
		] as Array[Dictionary],
		"time_s": 95.0, "kills": 2, "assists": 1, "wing_losses": 1, "shots_fired": 40, "shots_hit": 10,
	}
	result.merge(overrides, true)
	return result


# A screen on its own, with `game` the recording stand-in. The input guard is off unless a test wants it.
func _screen(result: Dictionary, guard_s: float = 0.0) -> DebriefScreen:
	var screen: DebriefScreen = DebriefScene.instantiate() as DebriefScreen
	screen.game = game
	screen.result = result
	screen.input_guard_s = guard_s
	add_child_autofree(screen)
	await wait_process_frames(2)
	return screen


## One pad press: a `ui_*` action event down, delivered, then up.
func _pad(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		event.strength = 1.0 if pressed else 0.0
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await get_tree().process_frame


func _focused_text(screen: DebriefScreen) -> String:
	var focused: Control = screen.frame().current_page().focused_option()
	return (focused as Button).text if focused is Button else ""


func _ticks(n: int) -> void:
	for _i: int in n:
		await get_tree().physics_frame


func _beat_ticks() -> int:
	return ceili(BEAT_S * Engine.physics_ticks_per_second) + 8


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


# The test mission in the real Main, started the way the flow starts a run (a mission request, then space).
func _fly_mission(seed_value: int = 7, pools: bool = false) -> void:
	Game.flow.enter_directly(GameFlow.make_request(&"mission", &"test_mission", false, seed_value))
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	main.scenario_path = MISSION_PATH
	main.scenario_seed = seed_value
	if pools:
		main.ally_pool_size = 3
	holder.add_child(main)
	await _ticks(2)
	main.mission.debrief_delay_s = BEAT_S


# Skips to the last step and through it: the mission ends in success.
func _win() -> void:
	if main.mission.api.step_name() != &"report":
		assert_true(_run("mission goto report").ok)
	assert_true(_run("mission skip").ok)


func _screen_in_holder() -> DebriefScreen:
	return holder.get_child(0) as DebriefScreen if holder.get_child_count() == 1 else null


func _shown_lines(screen: DebriefScreen) -> PackedStringArray:
	return screen.frame().objectives_panel().shown_lines()


# --- The screen (pad-first) --------------------------------------------------------------------------------------------


func test_the_screen_names_the_result_and_offers_retry_and_front_end() -> void:
	var screen: DebriefScreen = await _screen(_result())
	var page: ChoiceListScreen = screen.frame().current_page() as ChoiceListScreen
	assert_eq(page.title, "MISSION COMPLETE")
	assert_eq(page.option_ids(), [&"retry", &"front_end"] as Array[StringName])
	assert_eq(_focused_text(screen), "Retry", "the pad's A works without pointing first")
	assert_not_null(screen.frame().pad_diagram(), "the controller diagram stays bottom left")


func test_a_failure_says_so_in_the_title() -> void:
	var screen: DebriefScreen = await _screen(_result({"success": false, "reason": "player destroyed"}))
	assert_eq(screen.frame().current_page().title, "MISSION FAILED")
	assert_has(_shown_lines(screen), "Failure - Player destroyed")


func test_the_right_panel_has_every_part_of_the_debrief() -> void:
	var screen: DebriefScreen = await _screen(_result())
	var lines: PackedStringArray = _shown_lines(screen)
	assert_eq(screen.frame().objectives_panel().content["title"], "DEBRIEF")
	for expected: String in ["Test Mission", "Success - Every primary objective done", "[x] Fly to NAV ALPHA",
			"[!] Keep NAV ALPHA in one piece (optional)", "Time: 1:35", "Kills: 2   Assists: 1", "Wing losses: 1",
			"Shots: 40 fired, 10 hit (25%)"]:
		assert_has(lines, expected)


func test_the_debrief_lines_are_set_small_enough_for_a_long_list() -> void:
	var screen: DebriefScreen = await _screen(_result())
	var labels: Array[Node] = screen.frame().objectives_panel().find_children("*", "Label", true, false)
	var last: Label = labels.back() as Label
	assert_eq(last.text, "Shots: 40 fired, 10 hit (25%)")
	assert_lt(last.get_theme_font_size(&"font_size"), screen.frame().get_theme_font_size(&"font_size", &"Label"),
			"smaller than the menu's own text, so more of a debrief shows at once")


func test_the_panel_stays_up_on_both_options() -> void:
	var screen: DebriefScreen = await _screen(_result())
	var before: PackedStringArray = _shown_lines(screen)
	await _pad(&"ui_down")
	assert_eq(_focused_text(screen), "Front end")
	assert_eq(_shown_lines(screen), before, "the debrief does not change with the focus")


func test_a_on_retry_retries() -> void:
	var screen: DebriefScreen = await _screen(_result())
	await _pad(&"ui_accept")
	assert_eq(game.retries, 1)
	assert_eq(game.menus_shown, 0)


func test_down_and_a_goes_to_the_front_end() -> void:
	var screen: DebriefScreen = await _screen(_result())
	await _pad(&"ui_down")
	await _pad(&"ui_accept")
	assert_eq(game.menus_shown, 1)
	assert_eq(game.retries, 0)
	assert_not_null(screen)


func test_b_does_nothing_so_the_debrief_is_not_skipped_by_accident() -> void:
	var screen: DebriefScreen = await _screen(_result())
	await _pad(&"ui_cancel")
	assert_eq([game.retries, game.menus_shown], [0, 0])
	assert_eq(screen.frame().depth(), 1)


func test_a_refused_retry_says_why_and_stays() -> void:
	game.refusal = "a scenario is already loading"
	var screen: DebriefScreen = await _screen(_result())
	await _pad(&"ui_accept")
	assert_eq(screen.frame().message(), "a scenario is already loading")


func test_a_press_that_was_meant_for_the_fight_does_nothing() -> void:
	var screen: DebriefScreen = await _screen(_result(), 0.5)
	await _pad(&"ui_accept")  # A is fire in flight: a tap as the screen opens must not pick Retry
	assert_eq(game.retries, 0, "ignored while the guard runs")
	await wait_seconds(0.6)
	await _pad(&"ui_accept")
	assert_eq(game.retries, 1, "and taken once it is over")


func test_a_screen_with_nothing_to_show_goes_back_to_the_front_end() -> void:
	var screen: DebriefScreen = DebriefScene.instantiate() as DebriefScreen
	screen.game = game  # no result given, and the recording game's flow has none either
	add_child_autofree(screen)
	await wait_process_frames(2)
	assert_push_error("no mission result")
	assert_eq(game.menus_shown, 1, "a debrief with no mission does not happen")


func test_the_screen_reads_the_flows_last_result_when_given_none() -> void:
	game.flow.last_result = _result({"title": "From The Flow"})
	var screen: DebriefScreen = DebriefScene.instantiate() as DebriefScreen
	screen.game = game
	screen.input_guard_s = 0.0
	add_child_autofree(screen)
	await wait_process_frames(2)
	assert_has(_shown_lines(screen), "From The Flow")


# --- The flow in the real game ----------------------------------------------------------------------------------------------


func test_a_won_mission_opens_the_debrief_after_a_beat() -> void:
	await _fly_mission()
	_win()
	assert_eq(Game.flow.state, GameFlow.State.DEBRIEF, "the mission is over")
	assert_true(is_instance_valid(main) and main.get_parent() == holder, "Main stays in space for the beat")
	await _ticks(10)
	await get_tree().process_frame
	assert_eq(main.hud.frame.status_line, "MISSION COMPLETE", "with the result on the HUD")
	assert_null(_screen_in_holder(), "not yet")
	await _ticks(_beat_ticks())
	await wait_process_frames(2)
	var screen: DebriefScreen = _screen_in_holder()
	assert_not_null(screen, "the debrief replaced Main")
	assert_false(is_instance_valid(main), "Main is gone")
	assert_eq(screen.frame().current_page().title, "MISSION COMPLETE")
	var lines: PackedStringArray = _shown_lines(screen)
	assert_has(lines, "Test Mission")
	assert_has(lines, "Success - Every primary objective done")
	assert_has(lines, "[x] Fly to NAV ALPHA")
	assert_has(lines, "[x] Destroy the raiders")
	assert_has(lines, "[x] Report to Control")
	assert_has(lines, "Wing losses: 0")
	assert_has(lines, "Shots: none fired")
	assert_eq(Game.flow.state, GameFlow.State.DEBRIEF)


func test_a_lost_mission_opens_a_failure_debrief() -> void:
	await _fly_mission()
	main.combatant.damageable.kill()
	await _ticks(2)
	assert_eq(Game.flow.state, GameFlow.State.DEBRIEF)
	await _ticks(_beat_ticks())
	await wait_process_frames(2)
	var screen: DebriefScreen = _screen_in_holder()
	assert_not_null(screen)
	assert_eq(screen.frame().current_page().title, "MISSION FAILED")
	var lines: PackedStringArray = _shown_lines(screen)
	assert_has(lines, "Failure - Player destroyed")
	assert_has(lines, "[ ] Fly to NAV ALPHA - not finished", "an objective still open reads as open")
	assert_has(lines, "[-] Destroy the raiders - not reached", "and one never shown as not reached")
	assert_false(lines.has("[x] Fly to NAV ALPHA"))


func test_the_time_is_the_missions_sim_time() -> void:
	await _fly_mission()
	await _ticks(150)
	_win()
	var ended_at_s: float = main.mission.api.result["time_s"]
	assert_gt(ended_at_s, 2.0, "two and a half seconds of ticks went by")
	assert_lt(ended_at_s, 10.0, "sim time, not the time the test took")
	await _ticks(_beat_ticks())
	await wait_process_frames(2)
	assert_has(_shown_lines(_screen_in_holder()), "Time: %s" % DebriefModel.format_time(ended_at_s))


func test_the_counters_reach_the_debrief() -> void:
	await _fly_mission(7, true)
	main.wings.replenish()  # three allied Starfuries in the player's wing
	await _ticks(2)
	var wing: Wing = main.wings.player_wing()
	assert_eq(wing.members().size(), 3, "a wing to lose ships from")
	# Shots: the player holds the trigger for a while.
	source.hold(InputAdapter.FIRE)
	await _ticks(90)
	source.release(InputAdapter.FIRE)
	var fired: int = main.mission.recorder.tally.shots_fired
	assert_gt(fired, 0, "bolts left the player's cannon")
	# One hit of the player's, one of an ally's.
	var hit_resolver := main.get_node(^"Combat/HitResolver") as HitResolver
	var player_id: int = main.ship.get_instance_id()
	hit_resolver.hit_resolved.emit(HitInfo.new(1, player_id, &"earth_alliance", 5.0))
	hit_resolver.hit_resolved.emit(HitInfo.new(1, wing.members()[0].ship.get_instance_id(), &"earth_alliance", 5.0))
	# A kill for the player, an assist, and a wingman lost.
	assert_true(_run("mission goto raid").ok)
	var raiders: Array[Combatant] = main.ships.alive(ShipPool.DEFAULT_TYPE)
	assert_eq(raiders.size(), 2)
	raiders[0].damageable.apply_hit(HitInfo.new(raiders[0].ship.get_instance_id(), player_id, &"earth_alliance", 99999.0))
	main.waves.credit.note_shot(raiders[1].targetable.get_instance_id())
	raiders[1].damageable.kill()  # the console's kill: someone else's
	wing.members()[0].damageable.kill()
	await _ticks(3)
	_win()
	await _ticks(_beat_ticks())
	await wait_process_frames(2)
	var screen: DebriefScreen = _screen_in_holder()
	assert_not_null(screen)
	var lines: PackedStringArray = _shown_lines(screen)
	assert_has(lines, "Kills: 1   Assists: 1")
	assert_has(lines, "Wing losses: 1")
	assert_has(lines, "Shots: %d fired, 1 hit (%s)" % [fired, DebriefModel.from_result({"shots_fired": fired, "shots_hit": 1}).accuracy_text()])


func test_pausing_during_the_beat_holds_the_debrief_back() -> void:
	await _fly_mission()
	_win()
	main.set_paused(true)
	await _ticks(_beat_ticks() + 10)
	await wait_process_frames(2)
	assert_null(_screen_in_holder(), "the beat is sim time: a paused game does not run it out")
	main.set_paused(false)
	await _ticks(_beat_ticks())
	await wait_process_frames(2)
	assert_not_null(_screen_in_holder())


func test_quitting_during_the_beat_leaves_no_debrief_behind() -> void:
	await _fly_mission()
	_win()
	Game.show_front_end()  # the pause menu's Quit to menu
	await wait_process_frames(3)
	await _ticks(_beat_ticks())
	assert_eq(holder.get_child_count(), 1)
	assert_true(holder.get_child(0) is FrontEnd, "the front end, not a late debrief over it")
	assert_eq(Game.flow.state, GameFlow.State.FRONT_END)


# --- Retry and Front end -------------------------------------------------------------------------------------------------


func test_retry_plays_the_same_scenario_and_seed_through_loading() -> void:
	await _fly_mission(42)
	_win()
	await _ticks(_beat_ticks())
	await wait_process_frames(2)
	var screen: DebriefScreen = _screen_in_holder()
	screen.input_guard_s = 0.0
	await _pad(&"ui_accept")  # Retry
	assert_eq(Game.flow.state, GameFlow.State.LOADING)
	await wait_until(func() -> bool: return Game.flow.state == GameFlow.State.IN_SPACE, 10.0)
	assert_eq(Game.flow.state, GameFlow.State.IN_SPACE)
	assert_eq(Game.flow.request, GameFlow.make_request(&"mission", &"test_mission", false, 42), "the same request")
	var rebuilt: Node = holder.get_child(0) if holder.get_child_count() == 1 else null
	assert_not_null(rebuilt, "one scene: the new run")
	assert_eq(rebuilt.scenario_path, GameFlow.scenario_path(&"test_mission"))
	assert_eq(rebuilt.scenario_seed, 42, "the same seed")
	assert_false(is_instance_valid(screen), "the debrief is gone")


func test_front_end_returns_to_the_front_end_and_leaves_nothing_behind() -> void:
	var orphans_before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	await _fly_mission()
	_win()
	await _ticks(_beat_ticks())
	await wait_process_frames(2)
	var screen: DebriefScreen = _screen_in_holder()
	screen.input_guard_s = 0.0
	await _pad(&"ui_down")
	await _pad(&"ui_accept")  # Front end
	await wait_process_frames(3)
	assert_eq(Game.flow.state, GameFlow.State.FRONT_END)
	assert_eq(holder.get_child_count(), 1)
	assert_true(holder.get_child(0) is FrontEnd)
	assert_false(is_instance_valid(screen), "the debrief is gone")
	assert_false(is_instance_valid(main), "and Main with it")
	assert_lte(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)), orphans_before, "no node left without a parent")


func test_retry_cycles_leave_the_tree_as_they_found_it() -> void:
	var orphans_before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for cycle: int in 2:
		Game.flow = GameFlow.new()
		Game.flow.enter_directly(GameFlow.make_request(&"mission", &"free_flight", false, cycle))
		assert_true(Game.end_mission(_result({"scenario_id": &"free_flight"})))
		assert_eq(Game.show_debrief(), "")
		await wait_process_frames(2)
		var screen: DebriefScreen = _screen_in_holder()
		assert_not_null(screen, "cycle %d: the debrief is up" % cycle)
		assert_eq(Game.retry(), "")
		await wait_until(func() -> bool: return Game.flow.state == GameFlow.State.IN_SPACE, 10.0)
		assert_eq(holder.get_child_count(), 1)
		assert_false(is_instance_valid(screen))
	assert_lte(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)), orphans_before)


# --- Guards -------------------------------------------------------------------------------------------------------------------


func test_no_debrief_at_the_front_end() -> void:
	assert_string_contains(Game.show_debrief(), "not over")
	await wait_process_frames(2)
	assert_eq(holder.get_child_count(), 0, "nothing was shown")


func test_no_debrief_for_a_run_that_is_not_a_mission() -> void:
	Game.flow.enter_directly(GameFlow.make_request(&"free_flight", &"free_flight"))
	assert_false(Game.end_mission(_result()), "no debrief is due")
	assert_eq(Game.flow.state, GameFlow.State.IN_SPACE, "the flow stays in space")
	assert_eq(Game.flow.last_result["scenario_id"], &"test_mission", "the result is kept for the console")
	assert_string_contains(Game.show_debrief(), "not over")
	await wait_process_frames(2)
	assert_eq(holder.get_child_count(), 0)


func test_no_debrief_for_a_mission_with_no_result() -> void:
	Game.flow.enter_directly(GameFlow.make_request(&"mission", &"test_mission"))
	Game.flow.end_run({})
	assert_string_contains(Game.show_debrief(), "no result")
	await wait_process_frames(2)
	assert_eq(holder.get_child_count(), 0)


func test_retry_is_only_offered_in_the_debrief() -> void:
	assert_string_contains(Game.retry(), "only offered in the debrief")
	Game.flow.enter_directly(GameFlow.make_request(&"mission", &"test_mission"))
	assert_string_contains(Game.retry(), "only offered in the debrief")
	assert_eq(Game.flow.state, GameFlow.State.IN_SPACE, "a refusal changes nothing")


# --- Console -----------------------------------------------------------------------------------------------------------------


func test_the_retry_command_and_debrief_provider() -> void:
	var refused: ConsoleResult = _run("retry")
	assert_false(refused.ok)
	assert_string_contains(refused.error, "only offered in the debrief")
	assert_eq(DebugConsole.registry.read("debrief.result")["value"], "none", "nothing has ended")
	Game.flow.enter_directly(GameFlow.make_request(&"mission", &"test_mission", false, 5))
	assert_true(Game.end_mission(_result({"success": false, "reason": "player destroyed"})))
	assert_eq(DebugConsole.registry.read("debrief.result")["value"], "failure")
	assert_eq(DebugConsole.registry.read("debrief.reason")["value"], "player destroyed")
	assert_eq(DebugConsole.registry.read("debrief.kills")["value"], "2")
	assert_eq(DebugConsole.registry.read("debrief.accuracy")["value"], "25%")
	var retried: ConsoleResult = _run("retry")
	assert_true(retried.ok, retried.text())
	assert_eq(Game.flow.state, GameFlow.State.LOADING)
	await wait_until(func() -> bool: return Game.flow.state == GameFlow.State.IN_SPACE, 10.0)
