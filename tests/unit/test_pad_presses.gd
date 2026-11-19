extends GutTest
## PadPresses (M8-T22): which parts of the pad the menus' diagram lights, from the joypad events fed to it.

var presses: PadPresses


func before_each() -> void:
	presses = PadPresses.new()


func _button(index: int, pressed: bool, device: int = 0) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = index as JoyButton
	event.pressed = pressed
	return event


func _axis(axis: int, value: float, device: int = 0) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = axis as JoyAxis
	event.axis_value = value
	return event


func test_nothing_is_lit_at_first() -> void:
	assert_eq(presses.widgets(), [] as Array[StringName])


func test_a_button_is_lit_while_it_is_held() -> void:
	assert_true(presses.feed(_button(JOY_BUTTON_X, true)), "the press changes what is lit")
	assert_eq(presses.widgets(), [&"x"] as Array[StringName])
	assert_false(presses.feed(_button(JOY_BUTTON_X, true)), "a repeat changes nothing")
	assert_true(presses.feed(_button(JOY_BUTTON_X, false)))
	assert_eq(presses.widgets(), [] as Array[StringName])


func test_every_drawn_button_has_its_part() -> void:
	var expected: Dictionary = {
		JOY_BUTTON_A: &"a", JOY_BUTTON_B: &"b", JOY_BUTTON_X: &"x", JOY_BUTTON_Y: &"y", JOY_BUTTON_BACK: &"back",
		JOY_BUTTON_START: &"start", JOY_BUTTON_LEFT_STICK: &"l3", JOY_BUTTON_RIGHT_STICK: &"r3",
		JOY_BUTTON_LEFT_SHOULDER: &"lb", JOY_BUTTON_RIGHT_SHOULDER: &"rb", JOY_BUTTON_DPAD_UP: &"dpad_up",
		JOY_BUTTON_DPAD_DOWN: &"dpad_down", JOY_BUTTON_DPAD_LEFT: &"dpad_left", JOY_BUTTON_DPAD_RIGHT: &"dpad_right",
	}
	for index: int in expected:
		presses.clear()
		presses.feed(_button(index, true))
		assert_eq(presses.widgets(), [expected[index]] as Array[StringName], "button %d" % index)


func test_buttons_the_diagram_does_not_draw_change_nothing() -> void:
	assert_false(presses.feed(_button(JOY_BUTTON_GUIDE, true)))
	assert_false(presses.feed(_button(JOY_BUTTON_PADDLE1, true)))
	assert_eq(presses.widgets(), [] as Array[StringName])


func test_several_parts_come_in_the_diagram_order() -> void:
	presses.feed(_button(JOY_BUTTON_START, true))
	presses.feed(_button(JOY_BUTTON_A, true))
	presses.feed(_axis(JOY_AXIS_TRIGGER_LEFT, 1.0))
	assert_eq(presses.widgets(), [&"lt", &"a", &"start"] as Array[StringName])


func test_a_trigger_is_lit_once_pulled_past_its_threshold() -> void:
	assert_false(presses.feed(_axis(JOY_AXIS_TRIGGER_RIGHT, 0.1)), "a resting trigger's jitter lights nothing")
	assert_true(presses.feed(_axis(JOY_AXIS_TRIGGER_RIGHT, 0.6)))
	assert_eq(presses.widgets(), [&"rt"] as Array[StringName])
	assert_true(presses.feed(_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)))
	assert_eq(presses.widgets(), [] as Array[StringName])


func test_a_trigger_resting_at_minus_one_is_not_lit() -> void:
	presses.feed(_axis(JOY_AXIS_TRIGGER_LEFT, -1.0))
	assert_eq(presses.widgets(), [] as Array[StringName])


func test_a_stick_is_lit_while_it_is_off_centre_in_any_direction() -> void:
	presses.feed(_axis(JOY_AXIS_RIGHT_Y, -0.8))
	assert_eq(presses.widgets(), [&"rs"] as Array[StringName])
	presses.feed(_axis(JOY_AXIS_RIGHT_Y, 0.0))
	assert_eq(presses.widgets(), [] as Array[StringName])
	presses.feed(_axis(JOY_AXIS_LEFT_X, 0.3))
	assert_eq(presses.widgets(), [] as Array[StringName], "inside the threshold on one axis")
	presses.feed(_axis(JOY_AXIS_LEFT_Y, 0.3))
	assert_eq(presses.widgets(), [&"ls"] as Array[StringName], "a diagonal counts by its length")


func test_the_stick_and_its_click_are_separate_parts() -> void:
	presses.feed(_axis(JOY_AXIS_LEFT_X, 1.0))
	presses.feed(_button(JOY_BUTTON_LEFT_STICK, true))
	assert_eq(presses.widgets(), [&"ls", &"l3"] as Array[StringName])


func test_a_button_held_on_two_pads_stays_lit_until_both_let_go() -> void:
	presses.feed(_button(JOY_BUTTON_Y, true, 0))
	presses.feed(_button(JOY_BUTTON_Y, true, 1))
	assert_false(presses.feed(_button(JOY_BUTTON_Y, false, 0)))
	assert_eq(presses.widgets(), [&"y"] as Array[StringName])
	assert_true(presses.feed(_button(JOY_BUTTON_Y, false, 1)))


func test_keys_and_the_mouse_change_nothing() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	assert_false(presses.feed(key))
	assert_false(presses.feed(InputEventMouseButton.new()))


func test_clear_forgets_what_was_held() -> void:
	presses.feed(_button(JOY_BUTTON_B, true))
	presses.feed(_axis(JOY_AXIS_LEFT_X, 1.0))
	presses.clear()
	assert_eq(presses.widgets(), [] as Array[StringName])
