extends GutTest
## The Controls page (architecture §18, D57, Q15; AC4): pick a profile, list every action, rebind by a press, unbind, save as,
## see why a change was refused, leave the `ui_*` actions alone, and let the diagram follow. Driven the way a pad drives it:
## injected `ui_*` events for the menu and real joypad, key and mouse events for the press to bind. The profiles are the real
## `ControlProfiles` autoload with its user folder pointed at a scratch folder.

const FrameScene: PackedScene = preload("res://src/frontend/menu_frame.tscn")
const FrontEndScene: PackedScene = preload("res://src/frontend/front_end.tscn")
const USER_DIR := "user://test_controls_screen"
const SETTINGS_PATH := "user://test_controls_screen_settings.cfg"

var frame: MenuFrame
var screen: ControlsScreen
var game: RecordingGame
var saved_user_dir: String
var saved_settings_path: String


func before_each() -> void:
	get_tree().paused = false
	saved_user_dir = ControlProfiles.store.user_dir
	saved_settings_path = Settings.config_path
	ControlProfiles.store.user_dir = USER_DIR
	_clean()
	ControlProfiles.use(ControlProfile.DEFAULT_NAME)
	game = RecordingGame.new()
	autofree(game)


func after_each() -> void:
	get_tree().paused = false
	ControlProfiles.use(ControlProfile.DEFAULT_NAME)  # a test that rebinds leaves the project's map as it found it
	ControlProfiles.store.user_dir = saved_user_dir
	Settings.config_path = saved_settings_path
	_clean()


func _clean() -> void:
	for path: String in [SETTINGS_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if DirAccess.dir_exists_absolute(USER_DIR):
		for file_name: String in DirAccess.get_files_at(USER_DIR):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(USER_DIR.path_join(file_name)))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(USER_DIR))


# --- Helpers -----------------------------------------------------------------------------------------------------


## A frame whose root is a one-entry page, with the Controls page pushed on it: B can leave Controls and `depth()` is 2.
func _open_controls() -> void:
	frame = FrameScene.instantiate() as MenuFrame
	add_child_autofree(frame)
	var home := ChoiceListScreen.new()
	home.setup("HOME", [{"id": &"controls", "text": "Controls"}] as Array[Dictionary])
	frame.set_root(home)
	screen = MenuScreens.controls() as ControlsScreen
	screen.persist = false
	frame.push_screen(screen)
	await wait_process_frames(2)


func _dispatch(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await get_tree().process_frame


## One pad press of a `ui_*` action, delivered to the tree.
func _pad(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		event.strength = 1.0 if pressed else 0.0
		await _dispatch(event)


func _button_event(index: int, pressed: bool) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = index as JoyButton
	event.pressed = pressed
	return event


## A real pad button, down and up.
func _press_button(index: int) -> void:
	await _dispatch(_button_event(index, true))
	await _dispatch(_button_event(index, false))


func _press_key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		await _dispatch(event)


func _axis_event(axis: int, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis as JoyAxis
	event.axis_value = value
	return event


func _focused_text() -> String:
	var page: MenuScreen = frame.current_page()
	var focused: Control = page.focused_option()
	return (focused as Button).text if focused is Button else ""


## Walks the D-pad down until the focused row starts with `prefix`.
func _walk_to(prefix: String) -> void:
	for i: int in 80:
		if _focused_text().begins_with(prefix):
			return
		await _pad(&"ui_down")
	fail_test("no row starting with '%s' (stopped on '%s')" % [prefix, _focused_text()])


## Opens the view of one action with the pad and starts a capture on its first row.
func _start_capture_on(title: String) -> void:
	await _walk_to(title + ":")
	await _pad(&"ui_accept")
	assert_eq(screen.current_view(), ControlsScreen.View.ACTION, "A opens %s" % title)
	await _pad(&"ui_accept")
	assert_true(screen.is_capturing(), "A on Add a binding waits for a press")


func _bindings(action: StringName) -> PackedStringArray:
	return ControlProfile.from_input_map("live").descriptors_for(action)


func _ui_snapshot() -> Dictionary:
	var out: Dictionary = {}
	for action: StringName in InputMap.get_actions():
		if String(action).begins_with("ui_"):
			var events: Array[String] = []
			for event: InputEvent in InputMap.action_get_events(action):
				events.append(event.as_text())
			out[action] = [events, InputMap.action_get_deadzone(action)]
	return out


# --- The list ----------------------------------------------------------------------------------------------------


func test_every_game_action_is_listed_with_its_bindings() -> void:
	await _open_controls()
	var texts: PackedStringArray = []
	for child: Node in screen.get_children():
		if child is Button:
			texts.append((child as Button).text)
	assert_eq(texts.size(), InputAdapter.ACTIONS.size() + 3, "the profile, every action, save as and back")
	var live: ControlProfile = ControlProfile.from_input_map("live")
	for action: StringName in InputAdapter.ACTIONS:
		assert_has(texts, ControlsModel.row_text(live, action))
	assert_string_contains(texts[0], "Profile: default")
	assert_eq(screen.title, "Controls")
	assert_eq(frame.current_page(), screen)


func test_the_pad_walks_the_list_and_b_leaves_the_page() -> void:
	await _open_controls()
	assert_string_contains(_focused_text(), "Profile: default", "A works without pointing first")
	await _pad(&"ui_down")
	assert_string_contains(_focused_text(), ControlsModel.action_title(InputAdapter.ACTIONS[0]))
	await _pad(&"ui_cancel")
	assert_eq(frame.depth(), 1, "B at the list goes back to the page below")


func test_the_right_panel_gives_the_exact_bindings_of_the_action_in_focus() -> void:
	await _open_controls()
	await _walk_to("Fire:")
	var content: Dictionary = frame.objectives_panel().content
	assert_eq(content["title"], "FIRE")
	assert_string_contains(String(content["lines"][0]["text"]), "fire: pad:button:0")


func test_the_diagram_lights_the_buttons_of_the_action_in_focus() -> void:
	await _open_controls()
	await _walk_to("Fire:")
	assert_eq(frame.pad_diagram().highlighted(), [&"a"] as Array[StringName])
	await _pad(&"ui_cancel")
	assert_eq(frame.pad_diagram().highlighted().size(), 0, "nothing stays lit once the page is left")


# --- Profiles ----------------------------------------------------------------------------------------------------


func test_picking_a_profile_applies_it_and_the_diagram_follows() -> void:
	await _open_controls()
	assert_eq(frame.pad_diagram().legend.label_for(&"dpad_right"), "", "the default leaves D-pad right free")
	await _pad(&"ui_accept")
	assert_eq(screen.current_view(), ControlsScreen.View.PROFILES)
	assert_string_contains(_focused_text(), "* default", "the profile in use has the focus")
	await _pad(&"ui_down")
	assert_string_contains(_focused_text(), "m1_classic")
	await _pad(&"ui_accept")
	assert_eq(ControlProfiles.active_name, "m1_classic")
	assert_eq(screen.current_view(), ControlsScreen.View.LIST, "back on the list")
	assert_string_contains(screen.status(), "Using m1_classic")
	assert_string_contains(_focused_text(), "Profile: m1_classic")
	assert_string_contains(frame.pad_diagram().legend.label_for(&"dpad_right"), "Roll", "m1_classic rolls on the D-pad")
	var row: String = ""
	for child: Node in screen.get_children():
		if child is Button and (child as Button).text.begins_with("Roll right:"):
			row = (child as Button).text
	assert_string_contains(row, "D-pad right", "the list shows the profile now in use")


func test_picking_a_profile_drops_unsaved_changes_and_says_so() -> void:
	assert_true(ControlProfiles.bind(&"brake", "pad:button:2")["ok"])
	await _open_controls()
	assert_string_contains(_focused_text(), "unsaved changes")
	await _pad(&"ui_accept")
	await _pad(&"ui_accept")  # the profile in use, again
	assert_string_contains(screen.status(), "unsaved changes were dropped")
	assert_false(ControlProfiles.is_unsaved())
	assert_does_not_have(_bindings(InputAdapter.BRAKE), "pad:button:2")


func test_b_in_the_picker_goes_back_to_the_list_not_out_of_the_page() -> void:
	await _open_controls()
	await _pad(&"ui_accept")
	await _pad(&"ui_cancel")
	assert_eq(screen.current_view(), ControlsScreen.View.LIST)
	assert_eq(frame.depth(), 2)
	assert_string_contains(_focused_text(), "Profile:", "to the row it left")


func test_the_choice_is_kept_for_the_next_start() -> void:
	Settings.config_path = SETTINGS_PATH
	await _open_controls()
	screen.persist = true
	await _pad(&"ui_accept")
	await _pad(&"ui_down")
	await _pad(&"ui_accept")
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(SETTINGS_PATH), OK, "the settings file was written")
	assert_eq(cfg.get_value("settings", "control_profile", ""), "m1_classic")


# --- Rebinding by a press ----------------------------------------------------------------------------------------


func test_a_pad_press_is_bound_and_does_not_navigate_or_act() -> void:
	await _open_controls()
	await _start_capture_on("Fire")
	assert_string_contains(screen.status(), "Press a button or key for Fire")
	var focus: String = _focused_text()
	await _press_button(JOY_BUTTON_X)
	assert_has(_bindings(InputAdapter.FIRE), "pad:button:2")
	assert_false(screen.is_capturing())
	assert_eq(screen.current_view(), ControlsScreen.View.ACTION, "the press did not leave the view")
	assert_eq(frame.depth(), 2)
	assert_eq(_focused_text(), focus, "nor move the focus")
	assert_string_contains(screen.status(), "X bound to Fire")
	assert_string_contains(screen.status(), "Not saved yet")
	assert_true(ControlProfiles.is_unsaved())


func test_the_accept_button_pressed_to_bind_it_does_not_also_press_the_row() -> void:
	await _open_controls()
	await _start_capture_on("Brake")
	await _press_button(JOY_BUTTON_A)  # A is ui_accept: it would press Add a binding again
	assert_has(_bindings(InputAdapter.BRAKE), "pad:button:0")
	assert_false(screen.is_capturing(), "no second wait was started by the same press")
	assert_eq(screen.current_view(), ControlsScreen.View.ACTION)


func test_the_dpad_pressed_to_bind_it_does_not_move_the_focus() -> void:
	await _open_controls()
	await _start_capture_on("Brake")
	var focus: String = _focused_text()
	await _press_button(JOY_BUTTON_DPAD_DOWN)
	assert_has(_bindings(InputAdapter.BRAKE), "pad:button:12")
	assert_eq(_focused_text(), focus, "ui_down did not walk the rows")
	assert_string_contains(screen.status(), "also bound to", "D-pad down already does something else")


func test_the_press_does_not_reach_the_page_below_either() -> void:
	await _open_controls()
	await _start_capture_on("Brake")
	await _press_button(JOY_BUTTON_B)  # a tap of B binds it; it is not ui_cancel
	assert_has(_bindings(InputAdapter.BRAKE), "pad:button:1")
	assert_eq(frame.depth(), 2, "B did not go back")
	assert_eq(screen.current_view(), ControlsScreen.View.ACTION)


func test_holding_b_cancels_the_wait_and_changes_nothing() -> void:
	await _open_controls()
	await _start_capture_on("Brake")
	var before: PackedStringArray = _bindings(InputAdapter.BRAKE)
	await _dispatch(_button_event(JOY_BUTTON_B, true))
	assert_true(screen.is_capturing(), "B may still turn out to be a tap")
	screen.advance(BindingCapture.CANCEL_HOLD_S + 0.1)
	assert_false(screen.is_capturing())
	assert_string_contains(screen.status(), "Cancelled")
	await _dispatch(_button_event(JOY_BUTTON_B, false))
	assert_eq(_bindings(InputAdapter.BRAKE), before)
	assert_eq(frame.depth(), 2, "letting go of B is not a Back")
	assert_eq(screen.current_view(), ControlsScreen.View.ACTION)


func test_a_wait_nobody_answers_gives_up() -> void:
	await _open_controls()
	await _start_capture_on("Brake")
	var before: PackedStringArray = _bindings(InputAdapter.BRAKE)
	screen.advance(BindingCapture.TIMEOUT_S + 0.1)
	assert_false(screen.is_capturing())
	assert_string_contains(screen.status(), "No press")
	assert_eq(_bindings(InputAdapter.BRAKE), before)


func test_a_key_is_bound_by_its_physical_key() -> void:
	await _open_controls()
	await _start_capture_on("Brake")
	await _press_key(KEY_J)
	assert_has(_bindings(InputAdapter.BRAKE), "key:J")


func test_a_stick_pushed_is_bound_with_its_direction() -> void:
	await _open_controls()
	await _start_capture_on("Brake")
	await _dispatch(_axis_event(JOY_AXIS_LEFT_X, 0.0))
	await _dispatch(_axis_event(JOY_AXIS_LEFT_X, 1.0))
	await _dispatch(_axis_event(JOY_AXIS_LEFT_X, 0.0))
	assert_has(_bindings(InputAdapter.BRAKE), "pad:axis:0+")
	assert_eq(screen.current_view(), ControlsScreen.View.ACTION, "the stick did not walk the menu")


func test_a_mouse_button_is_bound() -> void:
	await _open_controls()
	await _start_capture_on("Brake")
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_MIDDLE
		event.pressed = pressed
		await _dispatch(event)
	assert_has(_bindings(InputAdapter.BRAKE), "mouse:3")


func test_replace_swaps_a_binding_for_the_pressed_one() -> void:
	await _open_controls()
	await _walk_to("Fire:")
	await _pad(&"ui_accept")
	await _walk_to("Replace A")
	await _pad(&"ui_accept")
	assert_true(screen.is_capturing())
	await _press_button(JOY_BUTTON_X)
	var bound: PackedStringArray = _bindings(InputAdapter.FIRE)
	assert_has(bound, "pad:button:2")
	assert_does_not_have(bound, "pad:button:0")
	assert_string_contains(screen.status(), "X replaces A on Fire")


func test_the_legend_follows_a_rebind_and_comes_back() -> void:
	await _open_controls()
	assert_eq(frame.pad_diagram().legend.label_for(&"x"), "Auto-track")
	await _start_capture_on("Fire")
	await _press_button(JOY_BUTTON_X)
	assert_string_contains(frame.pad_diagram().legend.label_for(&"x"), "Fire")
	assert_string_contains(frame.pad_diagram().legend.label_for(&"x"), "Auto-track")
	assert_true(ControlProfiles.use(ControlProfile.DEFAULT_NAME)["ok"])
	assert_eq(frame.pad_diagram().legend.label_for(&"x"), "Auto-track", "and back")


func test_a_change_made_elsewhere_shows_in_the_list_at_once() -> void:
	await _open_controls()
	assert_true(ControlProfiles.bind(&"brake", "pad:button:2")["ok"])  # the console's bind
	var row: String = ""
	for child: Node in screen.get_children():
		if child is Button and (child as Button).text.begins_with("Brake:"):
			row = (child as Button).text
	assert_string_contains(row, "X")
	assert_string_contains(_focused_text(), "Profile: default (unsaved changes)".left(16), "the focus is kept")


# --- Unbinding ---------------------------------------------------------------------------------------------------


func test_unbind_removes_one_binding() -> void:
	await _open_controls()
	await _walk_to("Fire:")
	await _pad(&"ui_accept")
	await _walk_to("Unbind Key Space")
	await _pad(&"ui_accept")
	var left: PackedStringArray = _bindings(InputAdapter.FIRE)
	assert_does_not_have(left, "key:Space")
	assert_has(left, "pad:button:0")
	assert_string_contains(screen.status(), "Unbound Key Space from Fire")
	assert_eq(screen.current_view(), ControlsScreen.View.ACTION)


# --- The rules ---------------------------------------------------------------------------------------------------


func test_the_last_pad_binding_cannot_be_unbound_and_the_reason_is_shown() -> void:
	await _open_controls()
	await _walk_to("Fire:")
	await _pad(&"ui_accept")
	await _walk_to("Unbind A")
	await _pad(&"ui_accept")
	assert_has(_bindings(InputAdapter.FIRE), "pad:button:0", "still bound")
	assert_string_contains(screen.status(), "Not changed")
	assert_string_contains(screen.status(), "needs a pad binding")
	assert_false(ControlProfiles.is_unsaved(), "nothing was applied")


func test_a_refused_bind_shows_its_reason() -> void:
	await _open_controls()
	await _start_capture_on("Brake")
	var before: PackedStringArray = _bindings(InputAdapter.BRAKE)
	await _press_key(KEY_QUOTELEFT)  # the console key
	assert_string_contains(screen.status(), "console key")
	assert_string_contains(screen.status(), "Not changed")
	assert_eq(_bindings(InputAdapter.BRAKE), before)
	assert_false(DebugConsole.is_open(), "the capture took the key first")
	assert_false(screen.is_capturing())


func test_a_modifier_alone_is_refused_with_a_hint_and_the_wait_goes_on() -> void:
	await _open_controls()
	await _start_capture_on("Brake")
	var shift := InputEventKey.new()
	shift.keycode = KEY_SHIFT
	shift.physical_keycode = KEY_SHIFT
	shift.shift_pressed = true
	shift.pressed = true
	await _dispatch(shift)
	assert_true(screen.is_capturing())
	assert_string_contains(screen.status().to_lower(), "modifier")
	shift.pressed = false
	await _dispatch(shift)


func test_a_binding_shared_with_another_action_is_allowed_and_named() -> void:
	await _open_controls()
	await _start_capture_on("Brake")
	await _press_button(JOY_BUTTON_Y)  # the camera button
	assert_has(_bindings(InputAdapter.BRAKE), "pad:button:3")
	assert_string_contains(screen.status(), "also bound to Camera")


func test_ui_actions_survive_every_change_the_page_makes() -> void:
	var before: Dictionary = _ui_snapshot()
	assert_gt(before.size(), 4, "the menus have their actions")
	await _open_controls()
	await _pad(&"ui_accept")
	await _pad(&"ui_down")
	await _pad(&"ui_accept")  # m1_classic
	assert_eq(_ui_snapshot(), before, "after a profile was applied")
	await _start_capture_on("Brake")
	await _press_button(JOY_BUTTON_A)
	assert_eq(_ui_snapshot(), before, "after A was bound to an action")
	await _pad(&"ui_down")  # off Add a binding
	screen.advance(ControlsScreen.GRACE_S + 0.1)
	await _walk_to("Unbind A")
	await _pad(&"ui_accept")
	assert_eq(_ui_snapshot(), before, "after it was unbound")
	await _pad(&"ui_cancel")
	await _walk_to("Save as a new profile")
	await _pad(&"ui_accept")
	await _pad(&"ui_accept")
	assert_eq(_ui_snapshot(), before, "after a save")
	assert_true(ControlProfiles.use(ControlProfile.DEFAULT_NAME)["ok"])
	assert_eq(_ui_snapshot(), before, "after going back to the default")


# --- Save as -----------------------------------------------------------------------------------------------------


func test_save_as_writes_the_layout_and_uses_it() -> void:
	await _open_controls()
	await _start_capture_on("Brake")
	await _press_button(JOY_BUTTON_X)
	screen.advance(ControlsScreen.GRACE_S + 0.1)
	await _pad(&"ui_cancel")
	await _walk_to("Save as a new profile")
	await _pad(&"ui_accept")
	assert_eq(screen.current_view(), ControlsScreen.View.SAVE_AS)
	assert_eq(_focused_text(), "Save", "A saves under the suggested name")
	assert_eq(screen.name_edit().text, "my_controls")
	screen.name_edit().text = "Pilot One"
	await _pad(&"ui_accept")
	assert_eq(screen.current_view(), ControlsScreen.View.LIST)
	assert_has(ControlProfiles.store.user_names(), "pilot_one")
	assert_eq(ControlProfiles.active_name, "pilot_one")
	assert_string_contains(screen.status(), "Saved pilot_one")
	assert_false(ControlProfiles.is_unsaved())
	var loaded: Dictionary = ControlProfiles.store.load_profile("pilot_one")
	assert_true(loaded["ok"])
	assert_has((loaded["profile"] as ControlProfile).descriptors_for(InputAdapter.BRAKE), "pad:button:2")
	assert_string_contains(_focused_text(), "Save as", "the focus is back on the row it came from")
	assert_eq(ControlProfiles.use(ControlProfile.DEFAULT_NAME)["ok"], true)
	assert_does_not_have(_bindings(InputAdapter.BRAKE), "pad:button:2")
	assert_true(ControlProfiles.use("pilot_one")["ok"])
	assert_has(_bindings(InputAdapter.BRAKE), "pad:button:2")


func test_save_as_refuses_a_built_in_name_and_says_why() -> void:
	await _open_controls()
	await _walk_to("Save as a new profile")
	await _pad(&"ui_accept")
	screen.name_edit().text = "default"
	await _pad(&"ui_accept")
	assert_eq(screen.current_view(), ControlsScreen.View.SAVE_AS, "the page stays for another name")
	assert_string_contains(screen.status(), "built-in")
	assert_eq(ControlProfiles.store.user_names().size(), 0)


func test_save_as_refuses_a_name_that_cannot_be_a_file() -> void:
	await _open_controls()
	await _walk_to("Save as a new profile")
	await _pad(&"ui_accept")
	screen.name_edit().text = "bad/name!"
	await _pad(&"ui_accept")
	assert_string_contains(screen.status(), "not a profile name")
	assert_eq(ControlProfiles.store.user_names().size(), 0)


func test_saving_over_the_profile_in_use_is_suggested_and_noted() -> void:
	await _open_controls()
	await _walk_to("Save as a new profile")
	await _pad(&"ui_accept")
	await _pad(&"ui_accept")
	assert_eq(ControlProfiles.active_name, "my_controls")
	await _walk_to("Save as a new profile")
	await _pad(&"ui_accept")
	assert_eq(screen.name_edit().text, "my_controls", "a user profile in use is offered for saving over")
	await _pad(&"ui_accept")
	assert_string_contains(screen.status(), "replaced the old one")


func test_b_leaves_save_as_for_the_list() -> void:
	await _open_controls()
	await _walk_to("Save as a new profile")
	await _pad(&"ui_accept")
	await _pad(&"ui_cancel")
	assert_eq(screen.current_view(), ControlsScreen.View.LIST)
	assert_eq(frame.depth(), 2)


# --- The frame keeps its place while a press is awaited ------------------------------------------------------------


func test_the_frame_does_not_leave_the_page_while_a_press_is_awaited() -> void:
	await _open_controls()
	await _start_capture_on("Brake")
	assert_true(frame.go_back(), "the pause action in flight asks the frame to go back")
	assert_true(screen.is_capturing())
	assert_eq(frame.depth(), 2)
	assert_eq(screen.current_view(), ControlsScreen.View.ACTION)


func test_the_frame_holds_still_for_a_moment_after_the_press_then_steps_back_normally() -> void:
	await _open_controls()
	await _start_capture_on("Brake")
	await _press_button(JOY_BUTTON_X)
	assert_true(frame.go_back())
	assert_eq(screen.current_view(), ControlsScreen.View.ACTION, "the same press, as the pause action, is not a Back")
	screen.advance(ControlsScreen.GRACE_S + 0.1)
	assert_true(frame.go_back())
	assert_eq(screen.current_view(), ControlsScreen.View.LIST, "afterwards Back steps out of the view")
	assert_eq(frame.depth(), 2)
	assert_true(frame.go_back())
	assert_eq(frame.depth(), 1, "then out of the page")


# --- Reachable from both menus -----------------------------------------------------------------------------------


func test_the_front_end_opens_the_page_with_the_pad_alone() -> void:
	var front: FrontEnd = FrontEndScene.instantiate() as FrontEnd
	front.game = game
	add_child_autofree(front)
	await wait_process_frames(2)
	frame = front.frame()
	for i: int in 4:
		await _pad(&"ui_down")
	assert_eq(_focused_text(), "Controls")
	await _pad(&"ui_accept")
	screen = frame.current_page() as ControlsScreen
	assert_not_null(screen, "the placeholder is gone")
	screen.persist = false
	await _start_capture_on("Brake")
	await _press_button(JOY_BUTTON_X)
	assert_has(_bindings(InputAdapter.BRAKE), "pad:button:2")
	assert_string_contains(frame.pad_diagram().legend.label_for(&"x"), "Brake", "the diagram of the front end follows")
	screen.advance(1.0)
	await _pad(&"ui_cancel")
	await _pad(&"ui_cancel")
	assert_eq(frame.depth(), 1, "B leaves the view, then the page")


func test_the_pause_menu_opens_the_page_and_start_during_a_wait_does_not_leave_it() -> void:
	var source := FakeInputSource.new()
	var main: Main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.waves_auto_start = false
	main.raider_pool_size = 1
	add_child_autofree(main)
	main.pause_menu.game = game
	await wait_physics_frames(2)
	source.hold(InputAdapter.PAUSE)
	await wait_physics_frames(2)
	source.release(InputAdapter.PAUSE)
	await wait_physics_frames(2)
	assert_true(main.pause_menu.is_open())
	frame = main.pause_menu.frame()
	await _walk_to("Controls")
	await _pad(&"ui_accept")
	screen = frame.current_page() as ControlsScreen
	assert_not_null(screen, "Controls from the pause menu is the real page")
	screen.persist = false
	await _start_capture_on("Brake")
	source.hold(InputAdapter.PAUSE)  # Start, as Main reads it
	await wait_physics_frames(3)
	source.release(InputAdapter.PAUSE)
	await wait_physics_frames(3)
	assert_true(main.pause_menu.is_open())
	assert_eq(frame.depth(), 2, "Start did not step back while a press was awaited")
	assert_true(screen.is_capturing())
	await _press_button(JOY_BUTTON_START)  # the press is bound, and is also the pause action
	source.hold(InputAdapter.PAUSE)
	await wait_physics_frames(3)
	source.release(InputAdapter.PAUSE)
	await wait_physics_frames(3)
	assert_has(_bindings(InputAdapter.BRAKE), "pad:button:6")
	assert_eq(frame.depth(), 2, "nor did the same press arriving as the pause action just after")
	assert_eq(screen.current_view(), ControlsScreen.View.ACTION)
	assert_true(main.pause_menu.is_open())
	main.pause_menu.close()
