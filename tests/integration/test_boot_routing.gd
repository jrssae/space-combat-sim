extends GutTest
## Boot and Game on scratch instances (architecture §18, D50; AC1 and AC2's loading screen): a windowed launch shows the
## front end, every scripted run goes straight to Main, Free flight reaches the real Main through the loading screen, and
## the console's `menu`, `play` and `game` provider drive the same moves. The real autoload is only checked for its wiring.

const GameScript := preload("res://src/autoload/game.gd")
const SettingsScript := preload("res://src/autoload/settings.gd")
const BootScene: PackedScene = preload("res://src/frontend/boot.tscn")

## An empty scene standing in for Main, so the routing tests do not pay for building the real one.
const STAND_IN_MAIN := "res://tests/fixtures/console_host.tscn"
const CONFIG_PATH := "user://test_boot_routing_settings.cfg"

var settings: SettingsScript
var registry: ConsoleRegistry
var game: GameScript
var host: Node


func before_each() -> void:
	get_tree().paused = false
	settings = SettingsScript.new()
	settings.config_path = CONFIG_PATH  # never written: defaults only
	settings.joy_mappings_path = "user://test_no_such_gamecontrollerdb.txt"
	add_child_autofree(settings)
	registry = ConsoleRegistry.new()
	host = Node.new()
	add_child_autofree(host)
	game = _make_game()


func after_each() -> void:
	get_tree().paused = false


func _make_game() -> GameScript:
	var made: GameScript = GameScript.new()
	made.settings = settings
	made.registry = registry
	made.scene_parent = host
	made.main_scene_path = STAND_IN_MAIN
	add_child_autofree(made)
	return made


func _boot(user_args: Array, headless: bool = false) -> void:
	var boot: Boot = BootScene.instantiate() as Boot
	boot.engine_args = PackedStringArray(["--path", "."])
	boot.user_args = PackedStringArray(user_args)
	boot.headless = headless
	boot.game = game
	host.add_child(boot)
	await wait_process_frames(2)  # the scene change is deferred


func _shown() -> Node:
	return host.get_child(0) if host.get_child_count() == 1 else null


func _shown_path() -> String:
	var shown: Node = _shown()
	return shown.scene_file_path if shown != null else "<%d scenes>" % host.get_child_count()


func _run(line: String) -> ConsoleResult:
	var results: Array[ConsoleResult] = registry.execute(line)
	return results[0]


func _in_space_with(path: String) -> bool:
	return game.flow.state == GameFlow.State.IN_SPACE and _shown_path() == path


# --- Boot routing (AC1) ----------------------------------------------------------------------------------------


func test_a_windowed_launch_shows_the_front_end() -> void:
	await _boot([])
	assert_eq(_shown_path(), GameScript.FRONT_END_SCENE, "the boot scene is replaced by the front end")
	assert_eq(game.flow.state, GameFlow.State.FRONT_END)
	assert_eq(game.flow.request, {})
	var menu: ChoiceListScreen = (_shown() as FrontEnd).frame().current_page() as ChoiceListScreen
	assert_not_null(menu, "the main menu is on show")
	assert_has(menu.option_ids(), &"free_flight")
	assert_has(menu.option_ids(), &"quit")


func test_every_scripted_run_goes_straight_to_main_with_the_scenario_setting() -> void:
	var cases: Array[Array] = [
		[[], true, false, "headless"],
		[["--console-exec=wait 30; quit"], false, false, "console-exec"],
		[["--console-file=smoke.cfg"], false, false, "console-file"],
		[[], false, true, "skip_front_end"],
	]
	for case: Array in cases:
		for child: Node in host.get_children():
			host.remove_child(child)
			child.free()
		game.flow = GameFlow.new()
		settings.set_value(&"skip_front_end", case[2])
		await _boot(case[0], case[1])
		assert_eq(_shown_path(), STAND_IN_MAIN, case[3])
		assert_eq(game.flow.state, GameFlow.State.IN_SPACE, case[3])
		assert_eq(game.flow.request, GameFlow.make_request(&"sandbox", &"combat_sandbox"),
				"%s: Settings.scenario, encounters off, seed 0" % case[3])


func test_the_scenario_argument_picks_the_scenario_for_this_session() -> void:
	await _boot(["--scenario=free_flight"])
	assert_eq(_shown_path(), STAND_IN_MAIN)
	assert_eq(settings.get_value(&"scenario"), &"free_flight")
	assert_true(settings.is_unsaved(&"scenario"), "session only, like the scenario command")
	assert_eq(game.flow.request, GameFlow.make_request(&"free_flight", &"free_flight"))


func test_an_unknown_scenario_argument_is_an_error_and_keeps_the_setting() -> void:
	await _boot(["--scenario=nowhere"])
	assert_push_error("nowhere")
	assert_eq(_shown_path(), STAND_IN_MAIN, "a scripted run still goes straight to Main")
	assert_eq(settings.get_value(&"scenario"), &"combat_sandbox")


# --- Loading (AC2) ---------------------------------------------------------------------------------------------


func test_free_flight_reaches_the_real_main_through_the_loading_screen() -> void:
	game.main_scene_path = GameScript.MAIN_SCENE
	await _boot([])
	var seen: Array[String] = []  # an Array, so the lambda appends to this one (a packed array would be copied)
	host.child_entered_tree.connect(func(node: Node) -> void: seen.append(node.scene_file_path))
	var front: FrontEnd = _shown() as FrontEnd
	(front.frame().current_page() as ChoiceListScreen).button_of(&"free_flight").pressed.emit()
	var page: FreeFlightSelect = front.frame().current_page() as FreeFlightSelect
	assert_not_null(page, "Free flight opens its page")
	page.start_requested.emit(page.encounters)
	assert_eq(game.flow.state, GameFlow.State.LOADING)
	await wait_until(func() -> bool: return _in_space_with(GameScript.MAIN_SCENE), 60.0)
	assert_true(_in_space_with(GameScript.MAIN_SCENE), "Main replaced the loading screen")
	assert_eq(", ".join(PackedStringArray(seen)), GameScript.LOADING_SCENE + ", " + GameScript.MAIN_SCENE,
			"the loading screen showed while Main loaded")
	var main: Main = _shown() as Main
	assert_not_null(main)
	if main == null:
		return
	await wait_physics_frames(2)
	assert_eq(main.resolved_scenario_path(), ScenarioLoader.FREE_FLIGHT_PATH, "the request's scenario")
	assert_eq(main.scenario_seed, int(game.flow.request["seed"]), "and its seed")
	assert_true(main.encounters, "with encounters on (M5-T17)")
	assert_eq(main.buoys.size(), 5, "free flight's nav buoys")
	assert_eq(game.flow.request, GameFlow.make_request(&"free_flight", &"free_flight", true, main.scenario_seed),
			"encounters start on")


func test_leaving_a_paused_scene_unpauses_the_tree() -> void:
	get_tree().paused = true
	game.show_front_end()
	await get_tree().process_frame  # the deferred change runs while paused
	await get_tree().process_frame
	assert_false(get_tree().paused)
	assert_eq(_shown_path(), GameScript.FRONT_END_SCENE)


# --- Restart (the pause menu's Restart, M5-T02) -----------------------------------------------------------------


func test_restart_plays_the_request_that_started_the_run_again() -> void:
	var request: Dictionary = GameFlow.make_request(&"sandbox", &"dogfight", false, 5)
	assert_true(game.flow.enter_directly(request))
	assert_eq(game.restart(), "", "accepted")
	assert_eq(game.flow.state, GameFlow.State.LOADING)
	assert_eq(game.flow.request, request, "the same scenario and seed")
	await wait_until(func() -> bool: return _in_space_with(STAND_IN_MAIN), 10.0)
	assert_true(_in_space_with(STAND_IN_MAIN), "the run was loaded again")


func test_restart_with_no_request_plays_the_scenario_setting() -> void:
	assert_eq(game.flow.request, {})
	settings.set_value(&"scenario", &"instructor_route")
	assert_eq(game.restart(), "")
	assert_eq(game.flow.request, GameFlow.make_request(&"sandbox", &"instructor_route"))
	await wait_until(func() -> bool: return _in_space_with(STAND_IN_MAIN), 10.0)


func test_restart_while_loading_says_why() -> void:
	assert_eq(game.restart(), "")
	assert_string_contains(game.restart(), "already loading")
	await wait_until(func() -> bool: return _in_space_with(STAND_IN_MAIN), 10.0)


# --- Console (AC1) ---------------------------------------------------------------------------------------------


func test_the_game_provider_reads_the_flow() -> void:
	assert_eq(registry.read("game.state")["value"], "front_end")
	assert_eq(registry.read("game.request")["value"], "none")
	assert_eq(registry.read("game.last_result")["value"], "none")
	game.flow.enter_directly(GameFlow.make_request(&"sandbox", &"dogfight", false, 3))
	game.flow.end_run({"success": false, "reason": "player destroyed"})
	assert_eq(registry.read("game.state")["value"], "debrief")
	assert_eq(registry.read("game.request")["value"], "dogfight (sandbox), encounters off, seed 3")
	assert_eq(registry.read("game.last_result")["value"], "failure: player destroyed")


func test_play_goes_through_loading_and_menu_returns_to_the_front_end() -> void:
	var refused: ConsoleResult = _run("play nowhere")
	assert_false(refused.ok)
	assert_string_contains(refused.error, "nowhere")
	assert_eq(game.flow.state, GameFlow.State.FRONT_END, "a refusal changes nothing")

	var result: ConsoleResult = _run("play free_flight 7")
	assert_true(result.ok, result.text())
	assert_eq(registry.read("game.state")["value"], "loading")
	await wait_until(func() -> bool: return _in_space_with(STAND_IN_MAIN), 10.0)
	assert_true(_in_space_with(STAND_IN_MAIN))
	assert_eq(registry.read("game.request")["value"], "free_flight (free_flight), encounters off, seed 7")

	assert_true(_run("play dogfight").ok, "play from space (a restart)")
	var twice: ConsoleResult = _run("play dogfight")
	assert_false(twice.ok, "not while loading")
	assert_string_contains(twice.error, "already loading")
	await wait_until(func() -> bool: return _in_space_with(STAND_IN_MAIN), 10.0)
	assert_eq(registry.read("game.request")["value"], "dogfight (sandbox), encounters off, seed 0")

	assert_true(_run("menu").ok)
	assert_eq(registry.read("game.state")["value"], "front_end")
	await wait_process_frames(2)
	assert_eq(_shown_path(), GameScript.FRONT_END_SCENE)


func test_play_offers_every_scenario_file() -> void:
	var ids: PackedStringArray = game.scenario_ids()
	for id: String in ["combat_sandbox", "dogfight", "free_flight", "instructor_route"]:
		assert_has(ids, id)
	assert_string_contains(registry.help(&"play")[0], "free_flight")


func test_removing_game_removes_its_console_entries() -> void:
	assert_true(registry.has_command(&"menu"))
	assert_true(registry.has_command(&"play"))
	assert_true(registry.has_provider(&"game"))
	remove_child(game)
	game.free()
	assert_false(registry.has_command(&"menu"))
	assert_false(registry.has_command(&"play"))
	assert_false(registry.has_provider(&"game"))


# --- Wiring ----------------------------------------------------------------------------------------------------


func test_the_project_boots_through_the_real_autoload() -> void:
	assert_eq(ProjectSettings.get_setting("application/run/main_scene"), "res://src/frontend/boot.tscn")
	var root: Window = get_tree().root
	var real: Node = root.get_node_or_null(^"Game")
	assert_not_null(real, "Game is an autoload")
	assert_gt(real.get_index(), root.get_node(^"ControlProfiles").get_index(), "registered after ControlProfiles")
	assert_true(DebugConsole.registry.has_command(&"menu"))
	assert_true(DebugConsole.registry.has_command(&"play"))
	assert_true(DebugConsole.registry.has_provider(&"game"))
	assert_eq(SettingsSchema.new().get_default(&"skip_front_end"), false)
