extends GutTest
## The pause menu in flight (architecture §18, D57, Q15; AC2): Start opens it over the paused world with Resume, Restart,
## Settings, Controls and Quit to menu; the frame beside it shows the objectives (or free flight) and the pad's legend; the
## pad drives it with `ui_*` events. A recording stand-in for `Game` takes Restart and Quit.

var main: Main
var source: FakeInputSource
var game: RecordingGame


func before_each() -> void:
	get_tree().paused = false
	game = RecordingGame.new()
	autofree(game)
	source = FakeInputSource.new()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.waves_auto_start = false
	main.raider_pool_size = 1  # one hostile for the auto-track check
	add_child_autofree(main)
	main.pause_menu.game = game
	await _ticks(2)


func after_each() -> void:
	get_tree().paused = false
	ControlProfiles.use(ControlProfile.DEFAULT_NAME)  # a test that rebinds leaves the project's map as it found it


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _tap(action: StringName) -> void:
	source.hold(action)
	await _ticks(2)
	source.release(action)
	await _ticks(2)


## One pad press of a `ui_*` action, delivered to the paused tree.
func _pad(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		event.strength = 1.0 if pressed else 0.0
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await get_tree().process_frame


func _menu() -> PauseMenu:
	return main.pause_menu


func _focused_text() -> String:
	var focused: Control = _menu().frame().current_page().focused_option()
	return (focused as Button).text if focused is Button else ""


func _open() -> void:
	await _tap(InputAdapter.PAUSE)


# --- Opening and closing ------------------------------------------------------------------------------------------


func test_start_opens_the_menu_and_pauses_the_world() -> void:
	assert_false(_menu().is_open())
	assert_false(_menu().visible)
	await _open()
	assert_true(_menu().is_open())
	assert_true(_menu().visible)
	assert_true(get_tree().paused)
	assert_eq(_menu().process_mode, Node.PROCESS_MODE_ALWAYS, "the menu runs while the world is paused")
	var t: float = SimClock.now()
	await _ticks(10)
	assert_eq(SimClock.now(), t, "sim time stops behind the menu")
	assert_eq(_focused_text(), "Resume", "the pad's A resumes without pointing first")


func test_the_pause_list_has_the_five_entries() -> void:
	await _open()
	var page: ChoiceListScreen = _menu().frame().current_page() as ChoiceListScreen
	assert_eq(page.option_ids(), [&"resume", &"restart", &"settings", &"controls", &"quit"] as Array[StringName])
	assert_eq(page.button_of(&"quit").text, "Quit to menu")


func test_start_again_resumes() -> void:
	await _open()
	await _tap(InputAdapter.PAUSE)
	assert_false(_menu().is_open())
	assert_false(_menu().visible)
	assert_false(get_tree().paused)


func test_resume_closes_the_menu() -> void:
	await _open()
	await _pad(&"ui_accept")
	assert_false(_menu().is_open())
	assert_false(get_tree().paused)


func test_b_at_the_root_resumes() -> void:
	await _open()
	var backs: int = main.audio.times_played(&"ui_back")
	await _pad(&"ui_cancel")
	assert_false(_menu().is_open())
	assert_false(get_tree().paused)
	assert_eq(main.audio.times_played(&"ui_back"), backs + 1, "leaving the menu has the back sound")


func test_the_pads_buttons_act_on_nothing_behind_the_menu() -> void:
	assert_true(DebugConsole.registry.execute("spawn raider idle 300")[0].ok)
	var respawns: Array[int] = []
	main.player_respawned.connect(func() -> void: respawns.append(1))
	main.ship.linear_velocity = Vector3(0.0, 0.0, -40.0)
	await _ticks(10)
	await _open()
	var position: Vector3 = main.ship.global_position
	var velocity: Vector3 = main.ship.linear_velocity
	var camera: CameraRig.Mode = main.camera_rig.mode
	var lights: bool = main.ship.running_lights
	var navigation: Array[StringName] = [InputAdapter.RESET_SHIP, InputAdapter.TOGGLE_CAMERA,
			InputAdapter.TOGGLE_RUNNING_LIGHTS, InputAdapter.AUTOTRACK]  # Back, Y, D-pad left, X
	for pass_number: int in 2:  # let go inside the menu, then close it while the buttons are still down
		for action: StringName in navigation:
			source.hold(action)
		await _ticks(4)
		if pass_number == 0:
			for action: StringName in navigation:
				source.release(action)
			await _ticks(4)
		else:
			await _pad(&"ui_accept")  # Resume, A being the pad's accept
			assert_false(_menu().is_open())
			await _ticks(4)
			for action: StringName in navigation:
				source.release(action)
			await _ticks(4)
		assert_eq(respawns.size(), 0, "Back did not respawn the ship (pass %d)" % pass_number)
		assert_eq(main.camera_rig.mode, camera, "Y did not change the camera (pass %d)" % pass_number)
		assert_eq(main.ship.running_lights, lights, "D-pad left did not toggle the lights (pass %d)" % pass_number)
		assert_false(main.adapter.autotrack_on, "X did not switch auto-track on (pass %d)" % pass_number)
		assert_false(main.ship.targeting.system.has_selection(), "nor take the nearest hostile (pass %d)" % pass_number)
		if pass_number == 0:
			assert_eq(main.ship.global_position, position, "the paused ship did not move")
			assert_eq(main.ship.linear_velocity, velocity, "and was not reset")


func test_after_resume_a_and_b_in_flight_press_no_hidden_button() -> void:
	await _open()
	await _pad(&"ui_down")  # the focus is on Restart
	await _tap(InputAdapter.PAUSE)  # Start resumes
	assert_false(_menu().is_open())
	var accepts: int = main.audio.times_played(&"ui_accept")
	var backs: int = main.audio.times_played(&"ui_back")
	await _pad(&"ui_accept")  # A in flight
	await _pad(&"ui_cancel")  # B in flight
	assert_eq(game.restarts, 0, "no stale Restart was pressed")
	assert_false(_menu().is_open(), "B in flight does not open or close anything")
	assert_eq(main.audio.times_played(&"ui_accept"), accepts, "no accept sound in flight")
	assert_eq(main.audio.times_played(&"ui_back"), backs, "nor a back sound")
	assert_eq(_menu().frame().depth(), 0, "the closed menu holds no pages")


func test_the_button_that_closes_the_menu_does_not_also_act_in_flight() -> void:
	await _open()
	source.hold(InputAdapter.TARGET_CYCLE)  # B on the pad is also the target button
	await _ticks(3)
	await _pad(&"ui_cancel")
	assert_false(_menu().is_open())
	source.release(InputAdapter.TARGET_CYCLE)
	await _ticks(4)
	assert_eq(main.ship.targeting.selected_name(), "", "releasing B after resuming selects nothing")


func test_the_console_pause_command_still_pauses_without_the_menu() -> void:
	DebugConsole.registry.execute("pause on")
	assert_true(get_tree().paused)
	assert_false(_menu().is_open(), "a debug pause is not the pause menu")
	DebugConsole.registry.execute("pause off")
	assert_false(get_tree().paused)


# --- Entries -----------------------------------------------------------------------------------------------------


func test_restart_asks_game_to_play_the_run_again() -> void:
	await _open()
	await _pad(&"ui_down")
	await _pad(&"ui_accept")
	assert_eq(game.restarts, 1)


func test_a_refused_restart_is_shown() -> void:
	game.refusal = "a scenario is already loading"
	await _open()
	await _pad(&"ui_down")
	await _pad(&"ui_accept")
	assert_eq(_menu().frame().message(), "a scenario is already loading")


func test_quit_to_menu_returns_to_the_front_end() -> void:
	await _open()
	for i: int in 4:
		await _pad(&"ui_down")
	assert_eq(_focused_text(), "Quit to menu")
	await _pad(&"ui_accept")
	assert_eq(game.menus_shown, 1)


func test_settings_and_controls_open_in_the_frame_and_start_steps_back() -> void:
	await _open()
	await _pad(&"ui_down")
	await _pad(&"ui_down")
	await _pad(&"ui_accept")
	assert_eq(_menu().frame().current_page().title, "Settings")
	assert_eq(_menu().frame().depth(), 2)
	assert_not_null(_menu().frame().pad_diagram(), "the same frame, the diagram still in view")
	await _tap(InputAdapter.PAUSE)
	assert_true(_menu().is_open(), "Start steps back one page, it does not resume")
	assert_eq(_menu().frame().depth(), 1)
	await _pad(&"ui_down")
	await _pad(&"ui_accept")
	assert_eq(_menu().frame().current_page().title, "Controls")
	await _pad(&"ui_cancel")
	assert_eq(_menu().frame().depth(), 1, "B steps back too")
	assert_true(get_tree().paused)


func test_the_escape_key_is_the_pause_action_and_does_not_count_twice() -> void:
	await _open()
	await _pad(&"ui_down")
	await _pad(&"ui_down")
	await _pad(&"ui_accept")
	assert_eq(_menu().frame().depth(), 2)
	for pressed: bool in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_ESCAPE
		key.physical_keycode = KEY_ESCAPE
		key.pressed = pressed
		Input.parse_input_event(key)
		Input.flush_buffered_events()
		await get_tree().process_frame
	assert_eq(_menu().frame().depth(), 2, "the page leaves the key to the pause action Main reads")


# --- The frame in flight -----------------------------------------------------------------------------------------


func test_the_right_panel_says_free_flight_and_whether_encounters_are_on() -> void:
	game.flow.request = GameFlow.make_request(&"free_flight", &"free_flight", true)
	await _open()
	assert_eq(_menu().frame().objectives_panel().shown_lines(), PackedStringArray(["Free flight", "Encounters: on"]))
	await _tap(InputAdapter.PAUSE)
	game.flow.request = GameFlow.make_request(&"free_flight", &"free_flight", false)
	await _open()
	assert_eq(_menu().frame().objectives_panel().shown_lines(), PackedStringArray(["Free flight", "Encounters: off"]))


func test_a_missions_objectives_fill_the_right_panel() -> void:
	_menu().objectives_source = func() -> Array[Dictionary]:
		return [
			{"id": &"defend", "text": "Defend the buoy", "primary": true, "state": &"active"},
			{"id": &"clear", "text": "Clear the raiders", "primary": true, "state": &"done"},
			{"id": &"spare", "text": "Save the wing", "primary": false, "state": &"failed"},
			{"id": &"twist", "text": "Not yet", "primary": true, "state": &"hidden"},
		]
	game.flow.request = GameFlow.make_request(&"mission", &"buoy_defence")
	await _open()
	assert_eq(_menu().frame().objectives_panel().shown_lines(), PackedStringArray([
		"[ ] Defend the buoy", "[x] Clear the raiders", "[!] Save the wing (optional)"]), "hidden ones are not shown")


func test_the_running_missions_objectives_are_wired_in_from_main() -> void:
	var mission_main: Main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	mission_main.input_source = source
	mission_main.scenario_path = "res://tests/fixtures/missions/test_mission.json"
	add_child_autofree(mission_main)
	mission_main.pause_menu.game = game
	await _ticks(30)
	var showing: Array[Dictionary] = ObjectivesModel.lines(mission_main.objectives())
	assert_gt(showing.size(), 0, "the test mission has declared objectives by now")
	mission_main.pause_menu.open()
	var shown: PackedStringArray = mission_main.pause_menu.frame().objectives_panel().shown_lines()
	assert_eq(shown.size(), showing.size())
	assert_string_contains(shown[0], String(showing[0]["text"]))
	mission_main.pause_menu.close()


func test_the_diagram_shows_the_flight_layout() -> void:
	await _open()
	var rows: PackedStringArray = _menu().frame().pad_diagram().rows_text()
	assert_has(rows, "A  Fire")
	assert_has(rows, "Start  Pause")
	assert_has(rows, "LB  Left retro")


func test_the_legend_follows_a_rebind_made_while_paused() -> void:
	await _open()
	assert_eq(_menu().frame().pad_diagram().legend.label_for(&"x"), "Auto-track")
	assert_true(ControlProfiles.bind(&"fire", "pad:button:2")["ok"])
	assert_string_contains(_menu().frame().pad_diagram().legend.label_for(&"x"), "Fire")


# --- Sound and housekeeping --------------------------------------------------------------------------------------


func test_the_menu_sounds_play_while_the_world_is_paused() -> void:
	await _open()
	var before: int = main.audio.times_played(&"ui_move")
	await _pad(&"ui_down")
	assert_eq(main.audio.times_played(&"ui_move"), before + 1)
	var voice: AudioStreamPlayer = main.audio.play_ui(&"ui_accept")
	assert_not_null(voice)
	assert_true(voice.playing)
	assert_eq(voice.process_mode, Node.PROCESS_MODE_ALWAYS, "not held back by the paused World")


func test_the_console_provider_reports_the_menu() -> void:
	assert_eq(DebugConsole.registry.read("pause_menu.open")["value"], false)
	await _open()
	assert_eq(DebugConsole.registry.read("pause_menu.open")["value"], true)
	assert_eq(DebugConsole.registry.read("pause_menu.page")["value"], "PAUSED")
	assert_eq(DebugConsole.registry.read("pause_menu.depth")["value"], 1)


func test_freeing_main_with_the_menu_open_unpauses_the_tree() -> void:
	await _open()
	assert_true(get_tree().paused)
	remove_child(main)
	main.free()
	assert_false(get_tree().paused)
	assert_false(DebugConsole.registry.has_provider(&"pause_menu"))
