extends GutTest
## The front end (architecture §18, D57; AC2): the main menu, its pages and what each starts, all driven the way a pad drives
## them, with injected `ui_*` events. A recording stand-in for `Game` takes the requests, so nothing is loaded.

const FrontEndScene: PackedScene = preload("res://src/frontend/front_end.tscn")
const FIXTURES := "res://tests/fixtures/scenarios/"

var game: RecordingGame
var quits: int = 0


var _encounters_backup: Variant = true


func before_each() -> void:
	get_tree().paused = false
	_encounters_backup = Settings.get_value(&"encounters")
	Settings.set_value(&"encounters", true)
	game = RecordingGame.new()
	autofree(game)
	quits = 0


func after_each() -> void:
	Settings.set_value(&"encounters", _encounters_backup)


func _missions() -> Array[Dictionary]:
	return [
		{"id": &"mission_demo", "title": "Demo Run", "briefing": "Escort the freighter.\nHold the line."},
		{"id": &"mission_second", "title": "Second", "briefing": "Another one."},
	]


func _front_end(missions: Array[Dictionary] = []) -> FrontEnd:
	var front: FrontEnd = FrontEndScene.instantiate() as FrontEnd
	front.game = game
	front.mission_entries = func() -> Array[Dictionary]: return missions
	front.quit_game = func() -> void: quits += 1
	add_child_autofree(front)
	await wait_process_frames(2)
	return front


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


func _focused_text(front: FrontEnd) -> String:
	var focused: Control = front.frame().current_page().focused_option()
	return (focused as Button).text if focused is Button else ""


func _page_title(front: FrontEnd) -> String:
	return front.frame().current_page().title


# --- The start screen ----------------------------------------------------------------------------------------


func test_the_start_screen_lists_the_entries_and_focuses_the_first() -> void:
	var front: FrontEnd = await _front_end()
	var menu: ChoiceListScreen = front.frame().current_page() as ChoiceListScreen
	assert_eq(menu.option_ids(), [&"new_game", &"load_game", &"free_flight", &"settings", &"quit"] as Array[StringName])
	assert_eq(_focused_text(front), "New game", "the pad's A works without pointing first")
	assert_eq(front.frame().depth(), 1)


func test_the_start_screen_has_no_pad_diagram_or_right_panel() -> void:
	var front: FrontEnd = await _front_end()
	assert_not_null(front.frame().pad_diagram(), "the nodes stay in the kit")
	assert_false(front.frame().pad_diagram().is_visible_in_tree(), "no controller diagram on the start screen")
	assert_false(front.frame().objectives_panel().is_visible_in_tree(), "no right panel either")
	assert_false((front.frame().current_page() as MenuScreen).show_pad)
	await _pad(&"ui_down")
	await _pad(&"ui_accept")
	assert_eq(_page_title(front), "Free flight")
	assert_true(front.frame().objectives_panel().is_visible_in_tree(), "its text sits in a box of its own beside the list (M7-T31)")
	assert_false(front.frame().pad_diagram().is_visible_in_tree())
	await _pad(&"ui_cancel")
	await _pad(&"ui_down")
	await _pad(&"ui_accept")
	assert_eq(_page_title(front), "Settings")
	assert_true(front.frame().objectives_panel().is_visible_in_tree(), "the settings pages keep the help panel")


func test_load_game_is_greyed_out_and_the_focus_skips_it_both_ways() -> void:
	var front: FrontEnd = await _front_end()
	var menu: ChoiceListScreen = front.frame().current_page() as ChoiceListScreen
	assert_true(menu.button_of(&"load_game").disabled)
	assert_eq(menu.button_of(&"load_game").focus_mode, Control.FOCUS_NONE)
	await _pad(&"ui_down")
	assert_eq(_focused_text(front), "Free flight", "down skips Load game")
	await _pad(&"ui_up")
	assert_eq(_focused_text(front), "New game", "up skips it too")
	menu.button_of(&"load_game").pressed.emit()
	assert_eq(front.frame().depth(), 1, "A on it does nothing")
	assert_eq(game.played.size(), 0)


func test_the_pad_alone_walks_the_menu_and_back() -> void:
	var front: FrontEnd = await _front_end()
	await _pad(&"ui_down")
	assert_eq(_focused_text(front), "Free flight")
	await _pad(&"ui_down")
	assert_eq(_focused_text(front), "Settings")
	await _pad(&"ui_up")
	assert_eq(_focused_text(front), "Free flight")
	await _pad(&"ui_accept")
	assert_eq(_page_title(front), "Free flight", "A opens the page")
	assert_eq(front.frame().depth(), 2)
	await _pad(&"ui_cancel")
	assert_eq(front.frame().depth(), 1, "B goes back")
	assert_eq(_focused_text(front), "Free flight", "to the entry it left")


func test_b_on_the_start_screen_does_nothing_harmful() -> void:
	var front: FrontEnd = await _front_end()
	await _pad(&"ui_cancel")
	assert_eq((front.get_node(^"%Audio") as AudioDirector).times_played(&"ui_back"), 0, "no beep for a back that goes nowhere")
	assert_eq(front.frame().depth(), 1)
	assert_eq(game.played.size(), 0)
	assert_eq(quits, 0)


func test_the_pad_never_strands_when_the_focus_is_lost() -> void:
	var front: FrontEnd = await _front_end()
	await _pad(&"ui_down")
	front.get_viewport().gui_release_focus()
	assert_null(front.frame().current_page().focused_option())
	await _pad(&"ui_down")
	assert_eq(_focused_text(front), "New game", "the D-pad lands on the first option")
	await _pad(&"ui_down")
	assert_eq(_focused_text(front), "Free flight", "and walks on from there")


func test_quit_quits() -> void:
	var front: FrontEnd = await _front_end()
	(front.frame().current_page() as ChoiceListScreen).button_of(&"quit").pressed.emit()
	assert_eq(quits, 1)


# --- Free flight -------------------------------------------------------------------------------------------------


func _open_free_flight(front: FrontEnd) -> void:
	await _pad(&"ui_down")
	await _pad(&"ui_accept")


func test_free_flight_starts_with_encounters_on_by_default() -> void:
	var front: FrontEnd = await _front_end()
	await _open_free_flight(front)
	assert_eq(_focused_text(front), "Encounters: on")
	assert_string_contains(front.frame().detail_text(), "nav buoys", "the text sits under the list")
	await _pad(&"ui_down")
	assert_eq(_focused_text(front), "Start")
	await _pad(&"ui_accept")
	_assert_free_flight(true)


func test_free_flight_starts_with_encounters_off_when_toggled() -> void:
	var front: FrontEnd = await _front_end()
	await _open_free_flight(front)
	await _pad(&"ui_accept")  # the toggle
	assert_eq(_focused_text(front), "Encounters: off")
	await _pad(&"ui_down")
	await _pad(&"ui_accept")
	_assert_free_flight(false)
	assert_false(bool(Settings.get_value(&"encounters")), "the page keeps the choice in Settings.encounters (M5-T17)")
	var again: FrontEnd = await _front_end()
	await _open_free_flight(again)
	assert_eq(_focused_text(again), "Encounters: off", "and opens with it next time")


# One free-flight request with `encounters`, on a fresh session seed (M5-T17).
func _assert_free_flight(encounters: bool) -> void:
	assert_eq(game.played.size(), 1)
	if game.played.size() != 1:
		return
	var request: Dictionary = game.played[0]
	assert_eq(request, GameFlow.make_request(&"free_flight", &"free_flight", encounters, int(request["seed"])))
	assert_gt(int(request["seed"]), 0, "a fresh session seed")


func test_a_refused_start_is_shown_not_swallowed() -> void:
	game.refusal = "no scenario 'free_flight'"
	var front: FrontEnd = await _front_end()
	await _open_free_flight(front)
	await _pad(&"ui_down")
	await _pad(&"ui_accept")
	assert_eq(front.frame().message(), "no scenario 'free_flight'")


# --- New game ----------------------------------------------------------------------------------------------------


func test_new_game_lists_the_missions_then_the_five_scenes() -> void:
	var front: FrontEnd = await _front_end(_missions())
	await _pad(&"ui_accept")
	assert_eq(_page_title(front), "New game")
	var page: NewGameSelect = front.frame().current_page() as NewGameSelect
	assert_eq(page.option_ids(), [&"mission_demo", &"mission_second", &"combat_sandbox", &"dogfight", &"instructor_route",
			&"civilian_showcase", &"station_showcase"] as Array[StringName])
	assert_eq(_focused_text(front), "Demo Run")
	assert_true(page.show_right, "the text sits in its own box beside the list (M7-T31)")


func test_the_text_under_the_list_follows_the_highlight() -> void:
	var front: FrontEnd = await _front_end(_missions())
	await _pad(&"ui_accept")
	assert_eq(front.frame().detail_text(), "Demo Run\nEscort the freighter.\nHold the line.")
	await _pad(&"ui_down")
	assert_eq(front.frame().detail_text(), "Second\nAnother one.", "the briefing of the next mission")
	await _pad(&"ui_down")
	assert_eq(_focused_text(front), "Combat sandbox")
	assert_string_contains(front.frame().detail_text(), "Combat sandbox\n", "a scene shows its title and its description")
	assert_gt(front.frame().detail_text().length(), "Combat sandbox\n".length() + 20)


func test_every_scene_has_a_description_in_its_scenario_file() -> void:
	for scene: Dictionary in NewGameSelect.SCENES:
		assert_false(NewGameSelect.scene_description(scene["id"]).is_empty(), "%s has a description" % scene["id"])
		assert_true(ScenarioLoader.load(GameFlow.scenario_path(scene["id"]))["ok"], "%s still loads with it" % scene["id"])


func test_choosing_a_mission_starts_it() -> void:
	var front: FrontEnd = await _front_end(_missions())
	await _pad(&"ui_accept")
	await _pad(&"ui_down")
	await _pad(&"ui_accept")
	assert_eq(game.played.size(), 1)
	assert_eq(game.played[0]["scenario_id"], &"mission_second")
	assert_eq(game.played[0]["kind"], &"mission")
	assert_gt(int(game.played[0]["seed"]), 0, "a fresh seed per start (M5-T30: the civilian varies)")


func test_new_game_starts_each_sandbox_scene() -> void:
	var front: FrontEnd = await _front_end()
	await _pad(&"ui_accept")
	var page: NewGameSelect = front.frame().current_page() as NewGameSelect
	assert_eq(page.option_ids(), [&"combat_sandbox", &"dogfight", &"instructor_route", &"civilian_showcase", &"station_showcase"] as Array[StringName],
			"with no missions the scenes alone")
	for id: StringName in page.option_ids():
		page.button_of(id).pressed.emit()
	assert_eq(game.played, [
		GameFlow.make_request(&"sandbox", &"combat_sandbox"),
		GameFlow.make_request(&"sandbox", &"dogfight"),
		GameFlow.make_request(&"sandbox", &"instructor_route"),
		GameFlow.make_request(&"sandbox", &"civilian_showcase"),  # M5-T16
		GameFlow.make_request(&"sandbox", &"station_showcase"),  # M7-T12
	] as Array[Dictionary])
	for request: Dictionary in game.played:
		assert_true(FileAccess.file_exists(GameFlow.scenario_path(request["scenario_id"])), "%s exists" % request["scenario_id"])


func test_missions_come_from_the_scenario_files_by_default() -> void:
	var front: FrontEnd = FrontEndScene.instantiate() as FrontEnd
	front.game = game
	add_child_autofree(front)
	await wait_process_frames(2)
	await _pad(&"ui_accept")
	var page: NewGameSelect = front.frame().current_page() as NewGameSelect
	assert_not_null(page, "New game opens with the catalogue of data/scenarios")
	assert_eq(page.option_ids().size(), MissionCatalog.entries().size() + NewGameSelect.SCENES.size())
	assert_true(page.is_mission(&"civilian_escort"))


func test_b_leaves_new_game() -> void:
	var front: FrontEnd = await _front_end()
	await _pad(&"ui_accept")
	await _pad(&"ui_cancel")
	assert_eq(front.frame().depth(), 1)
	assert_eq(_focused_text(front), "New game")


# --- Settings and Controls ---------------------------------------------------------------------------------------


func test_settings_lists_five_groups_and_each_opens_its_page() -> void:
	var front: FrontEnd = await _front_end()
	await _pad(&"ui_down")
	await _pad(&"ui_down")
	await _pad(&"ui_accept")
	assert_true(front.frame().current_page() is SettingsGroupsScreen)
	var list: ChoiceListScreen = front.frame().current_page() as ChoiceListScreen
	assert_eq(list.option_ids(), [&"gameplay", &"controls", &"camera_hud", &"video", &"audio"] as Array[StringName])
	var titles: Array[String] = []
	for id: StringName in list.option_ids():
		titles.append(list.button_of(id).text)
	assert_eq(titles, ["Gameplay", "Controls", "Camera & HUD", "Video", "Audio"] as Array[String])
	for i: int in 5:
		var page_title: String = _focused_text(front)
		await _pad(&"ui_accept")
		assert_eq(_page_title(front), page_title, "A opens the %s page" % page_title)
		assert_eq(front.frame().depth(), 3)
		await _pad(&"ui_cancel")
		assert_eq(_page_title(front), "Settings")
		assert_eq(_focused_text(front), page_title, "B returns to the group it left")
		await _pad(&"ui_down")


func test_controls_inside_settings_keeps_the_pad_diagram() -> void:
	var front: FrontEnd = await _front_end()
	for i: int in 2:
		await _pad(&"ui_down")
	await _pad(&"ui_accept")
	await _pad(&"ui_down")
	await _pad(&"ui_accept")
	assert_true(front.frame().current_page() is ControlsScreen)
	assert_true(front.frame().pad_diagram().is_visible_in_tree(), "it highlights the button of the action in focus")
	await _pad(&"ui_cancel")
	await _pad(&"ui_cancel")
	await _pad(&"ui_cancel")
	assert_eq(_page_title(front), "SPACE COMBAT SIM")
	assert_eq(_focused_text(front), "Settings")


func test_the_controls_settings_open_from_the_controls_page() -> void:
	var front: FrontEnd = await _front_end()
	for i: int in 2:
		await _pad(&"ui_down")
	await _pad(&"ui_accept")
	await _pad(&"ui_down")
	await _pad(&"ui_accept")
	var controls: ControlsScreen = front.frame().current_page() as ControlsScreen
	var row: Button = null
	for child: Node in controls.get_children():
		if child is Button and (child as Button).text.begins_with("Sensitivity"):
			row = child
	assert_not_null(row, "a row for the controls settings")
	row.grab_focus()
	await _pad(&"ui_accept")
	var page: SettingsScreen = front.frame().current_page() as SettingsScreen
	assert_not_null(page)
	assert_eq(page.listed_keys(), SettingsMenuModel.new(null, [&"controls"] as Array[StringName]).visible_keys())
	assert_true(page.listed_keys().has(&"invert_y"))


# --- Sound and sky -----------------------------------------------------------------------------------------------


func test_moving_and_accepting_make_the_menu_sounds() -> void:
	var front: FrontEnd = await _front_end()
	var audio: AudioDirector = front.get_node(^"%Audio") as AudioDirector
	assert_true(audio.has_sound(&"ui_move"), "run scripts/gen_assets.sh, then import")
	assert_true(audio.has_sound(&"ui_accept"))
	assert_true(audio.has_sound(&"ui_back"))
	assert_eq(audio.times_played(&"ui_move"), 0, "showing the first page is silent")
	await _pad(&"ui_down")
	assert_eq(audio.times_played(&"ui_move"), 1)
	await _pad(&"ui_accept")
	assert_eq(audio.times_played(&"ui_accept"), 1)
	await _pad(&"ui_cancel")
	assert_eq(audio.times_played(&"ui_back"), 1)


func test_the_sky_drifts_slowly_and_stays_near_the_nebula() -> void:
	assert_true(FrontEnd.drift_basis(0.0).is_equal_approx(Basis.IDENTITY), "it starts on the forward view")
	var worst_deg: float = 0.0
	var fastest_deg_s: float = 0.0
	var last: Basis = FrontEnd.drift_basis(0.0)
	for step: int in range(1, 3601):
		var now: Basis = FrontEnd.drift_basis(float(step))
		fastest_deg_s = maxf(fastest_deg_s, rad_to_deg(last.get_rotation_quaternion().angle_to(now.get_rotation_quaternion())))
		worst_deg = maxf(worst_deg, rad_to_deg(Basis.IDENTITY.get_rotation_quaternion().angle_to(now.get_rotation_quaternion())))
		last = now
	assert_lt(fastest_deg_s, 1.5, "slow: about a degree a second at most")
	assert_lt(worst_deg, 40.0, "never far from the view that has the nebula in it")
	assert_gt(worst_deg, 20.0, "but it does move")


func test_the_camera_follows_the_drift() -> void:
	var front: FrontEnd = await _front_end()
	var camera: Camera3D = front.get_node(^"%Camera") as Camera3D
	assert_true(camera.current)
	await wait_seconds(0.5)
	assert_false(camera.basis.is_equal_approx(Basis.IDENTITY), "the camera has turned a little")


# --- ui_* actions ------------------------------------------------------------------------------------------------


func test_the_pads_dpad_a_and_b_are_in_the_default_ui_maps() -> void:
	var expected: Dictionary = {
		&"ui_up": JOY_BUTTON_DPAD_UP, &"ui_down": JOY_BUTTON_DPAD_DOWN, &"ui_left": JOY_BUTTON_DPAD_LEFT,
		&"ui_right": JOY_BUTTON_DPAD_RIGHT, &"ui_accept": JOY_BUTTON_A, &"ui_cancel": JOY_BUTTON_B,
	}
	for action: StringName in expected:
		var found: bool = false
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == expected[action]:
				found = true
		assert_true(found, "%s has pad button %d" % [action, expected[action]])
	var stick: bool = false
	for event: InputEvent in InputMap.action_get_events(&"ui_down"):
		stick = stick or (event is InputEventJoypadMotion and (event as InputEventJoypadMotion).axis == JOY_AXIS_LEFT_Y)
	assert_true(stick, "the left stick walks the menu too")


func test_applying_a_control_profile_leaves_the_ui_actions_alone() -> void:
	var before: Dictionary = {}
	for action: StringName in InputMap.get_actions():
		if String(action).begins_with("ui_"):
			before[action] = InputMap.action_get_events(action).size()
	assert_gt(before.size(), 10)
	assert_true(ControlProfile.from_input_map("probe").apply_to_input_map().is_empty())
	for action: StringName in before:
		assert_eq(InputMap.action_get_events(action).size(), before[action], "%s is as it was" % action)
	for action: StringName in InputAdapter.ACTIONS:
		assert_false(String(action).begins_with("ui_"), "%s: no game action is a ui_ action" % action)
