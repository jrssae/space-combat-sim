extends TestSteps
## The pad diagram lights what is pressed on the real pad (M8-T22): in the pause menu and on the Controls page, from the
## joypad events the menus receive, and never once the menu is shut.

const FrameScene: PackedScene = preload("res://src/frontend/menu_frame.tscn")


func before_each() -> void:
	get_tree().paused = false


func after_each() -> void:
	get_tree().paused = false
	ControlProfiles.use(ControlProfile.DEFAULT_NAME)


func _dispatch(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await get_tree().process_frame


func _button(index: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = index
	event.pressed = pressed
	await _dispatch(event)


func _axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	await _dispatch(event)


func _widgets(names: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(names)
	return out


# X, the right stick and a trigger do nothing in a menu, so only the diagram answers them.
func _check_lights(frame: MenuFrame) -> void:
	var pad: PadDiagram = frame.pad_diagram()
	assert_true(pad.is_visible_in_tree(), "the page shows the diagram")
	assert_eq(pad.pressed(), _widgets([]))
	await _button(JOY_BUTTON_X, true)
	assert_eq(pad.pressed(), _widgets([&"x"]), "a button lights while it is held")
	await _button(JOY_BUTTON_LEFT_SHOULDER, true)
	assert_eq(pad.pressed(), _widgets([&"lb", &"x"]))
	await _button(JOY_BUTTON_X, false)
	await _button(JOY_BUTTON_LEFT_SHOULDER, false)
	assert_eq(pad.pressed(), _widgets([]), "and goes dark on release")
	await _axis(JOY_AXIS_TRIGGER_RIGHT, 0.9)
	assert_eq(pad.pressed(), _widgets([&"rt"]), "a trigger lights while it is pulled")
	await _axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	await _axis(JOY_AXIS_RIGHT_X, -0.9)
	assert_eq(pad.pressed(), _widgets([&"rs"]), "a stick lights while it is off centre")
	await _axis(JOY_AXIS_RIGHT_X, 0.0)
	assert_eq(pad.pressed(), _widgets([]))


func test_the_pause_menu_lights_what_is_pressed() -> void:
	var source := FakeInputSource.new()
	var game := RecordingGame.new()
	autofree(game)
	var main := (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.waves_auto_start = false
	add_child_autofree(main)
	main.pause_menu.game = game
	await _ticks(2)
	var pad: PadDiagram = main.pause_menu.frame().pad_diagram()
	await _button(JOY_BUTTON_X, true)
	assert_eq(pad.pressed(), _widgets([]), "in flight the hidden menu's diagram follows nothing")
	await _button(JOY_BUTTON_X, false)
	main.pause_menu.open()
	await get_tree().process_frame
	assert_true(get_tree().paused)
	await _check_lights(main.pause_menu.frame())
	await _button(JOY_BUTTON_Y, true)
	assert_eq(pad.pressed(), _widgets([&"y"]))
	main.pause_menu.close()
	assert_eq(pad.pressed(), _widgets([]), "closing with a button down leaves nothing lit for the next time")
	await _button(JOY_BUTTON_Y, false)


func test_the_controls_page_lights_what_is_pressed_beside_the_action_in_focus() -> void:
	var frame := FrameScene.instantiate() as MenuFrame
	add_child_autofree(frame)
	var home := ChoiceListScreen.new()
	home.setup("HOME", [{"id": &"controls", "text": "Controls"}] as Array[Dictionary])
	frame.set_root(home)
	var screen := MenuScreens.controls() as ControlsScreen
	screen.persist = false
	frame.push_screen(screen)
	await wait_process_frames(2)
	await _check_lights(frame)
	frame.highlight_actions([InputAdapter.FIRE] as Array[StringName])
	var focus_lit: Array[StringName] = frame.pad_diagram().highlighted()
	assert_false(focus_lit.is_empty(), "the action in focus is lit as before")
	await _button(JOY_BUTTON_X, true)
	assert_eq(frame.pad_diagram().pressed(), _widgets([&"x"]))
	assert_eq(frame.pad_diagram().highlighted(), focus_lit, "the press does not take the focus highlight away")
	await _button(JOY_BUTTON_X, false)


func test_a_pad_that_goes_away_takes_its_held_buttons_along() -> void:
	var frame := FrameScene.instantiate() as MenuFrame
	add_child_autofree(frame)
	var home := ChoiceListScreen.new()
	home.setup("HOME", [{"id": &"one", "text": "One"}] as Array[Dictionary])
	frame.set_root(home)
	await wait_process_frames(2)
	await _button(JOY_BUTTON_X, true)
	assert_eq(frame.pad_diagram().pressed(), _widgets([&"x"]))
	Joypads.changed.emit()  # the pad dropped; its release never comes
	assert_eq(frame.pad_diagram().pressed(), _widgets([]))
