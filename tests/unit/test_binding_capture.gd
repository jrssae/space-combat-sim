extends GutTest
## BindingCapture (architecture §18, D57; M5-T04): waits for one press to bind. Pure: handcrafted events, no InputMap and no
## scene. A held B or Esc, or the timeout, ends the wait without a binding.

var capture: BindingCapture


func before_each() -> void:
	capture = BindingCapture.new()


func _button(index: int, pressed: bool = true) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = index as JoyButton
	event.pressed = pressed
	return event


func _axis(axis: int, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis as JoyAxis
	event.axis_value = value
	return event


func _key(code: Key, pressed: bool = true, echo: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	return event


func _mouse(button: MouseButton, pressed: bool = true) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	return event


# --- Waiting -----------------------------------------------------------------------------------------------------


func test_a_capture_that_was_not_started_takes_nothing() -> void:
	assert_false(capture.is_waiting())
	assert_false(capture.feed(_button(2)), "the event is left to the menu")
	assert_eq(capture.state, BindingCapture.State.IDLE)


func test_a_button_press_is_captured_and_swallowed() -> void:
	capture.start()
	assert_true(capture.is_waiting())
	assert_true(capture.feed(_button(2)))
	assert_eq(capture.state, BindingCapture.State.CAPTURED)
	assert_eq(capture.descriptor, "pad:button:2")
	assert_false(capture.is_waiting())


func test_events_after_the_capture_are_left_to_the_menu() -> void:
	capture.start()
	capture.feed(_button(2))
	assert_false(capture.feed(_button(2, false)), "the release of the captured button")
	assert_false(capture.feed(_button(3)))
	assert_eq(capture.descriptor, "pad:button:2", "the first press stays the result")


func test_the_pads_navigation_and_accept_buttons_are_captured_like_any_other() -> void:
	for index: int in [0, 11, 12, 13, 14]:  # A, D-pad up, down, left, right
		capture.start()
		assert_true(capture.feed(_button(index)), "button %d" % index)
		assert_eq(capture.descriptor, "pad:button:%d" % index)


func test_a_button_the_game_does_not_use_is_ignored_with_a_hint() -> void:
	capture.start()
	assert_true(capture.feed(_button(5)), "Guide is swallowed, not acted on")
	assert_true(capture.is_waiting(), "and the wait goes on")
	assert_false(capture.hint.is_empty())
	assert_true(capture.feed(_button(15)))
	assert_true(capture.is_waiting())


func test_start_forgets_the_last_result() -> void:
	capture.start()
	capture.feed(_button(2))
	capture.start()
	assert_true(capture.is_waiting())
	assert_eq(capture.descriptor, "")
	assert_eq(capture.hint, "")


# --- Keys and the mouse ------------------------------------------------------------------------------------------


func test_a_key_press_is_captured_by_its_physical_key() -> void:
	capture.start()
	assert_true(capture.feed(_key(KEY_E)))
	assert_eq(capture.descriptor, "key:E")


func test_key_repeats_and_releases_are_swallowed_and_ignored() -> void:
	capture.start()
	assert_true(capture.feed(_key(KEY_E, true, true)), "an auto-repeat")
	assert_true(capture.feed(_key(KEY_E, false)), "a release with no press seen")
	assert_true(capture.is_waiting())


func test_a_modifier_on_its_own_or_in_a_chord_is_ignored_with_a_hint() -> void:
	capture.start()
	var shift := _key(KEY_SHIFT)
	shift.shift_pressed = true
	assert_true(capture.feed(shift))
	assert_true(capture.is_waiting())
	assert_string_contains(capture.hint.to_lower(), "modifier")
	var chord := _key(KEY_E)
	chord.ctrl_pressed = true
	assert_true(capture.feed(chord))
	assert_true(capture.is_waiting(), "Ctrl+E is not one plain key")


func test_the_console_key_is_captured_so_that_bind_can_refuse_it_with_its_reason() -> void:
	capture.start()
	assert_true(capture.feed(_key(KEY_QUOTELEFT)))
	assert_eq(capture.state, BindingCapture.State.CAPTURED)
	assert_eq(capture.descriptor, "key:QuoteLeft")


func test_mouse_buttons_are_captured_and_the_wheel_is_not() -> void:
	capture.start()
	assert_true(capture.feed(_mouse(MOUSE_BUTTON_WHEEL_UP)), "swallowed")
	assert_true(capture.is_waiting(), "but a wheel notch cannot be held")
	assert_true(capture.feed(_mouse(MOUSE_BUTTON_RIGHT)))
	assert_eq(capture.descriptor, "mouse:2")


func test_mouse_motion_is_left_alone() -> void:
	capture.start()
	assert_false(capture.feed(InputEventMouseMotion.new()), "so hovering still works")
	assert_true(capture.is_waiting())


func test_injected_menu_actions_are_swallowed_and_ignored() -> void:
	capture.start()
	var action := InputEventAction.new()
	action.action = &"ui_down"
	action.pressed = true
	assert_true(capture.feed(action))
	assert_true(capture.is_waiting())


# --- Sticks and triggers -----------------------------------------------------------------------------------------


func test_a_stick_pushed_from_rest_is_captured_with_its_direction() -> void:
	capture.start()
	assert_true(capture.feed(_axis(3, 0.0)))
	assert_true(capture.feed(_axis(3, -0.4)))
	assert_true(capture.is_waiting(), "not far enough yet")
	assert_true(capture.feed(_axis(3, -1.0)))
	assert_eq(capture.descriptor, "pad:axis:3-")


func test_a_stick_held_when_the_wait_began_is_not_a_press() -> void:
	capture.start()
	assert_true(capture.feed(_axis(1, 1.0)), "the stick was already over")
	assert_true(capture.feed(_axis(1, 0.97)))
	assert_true(capture.is_waiting())
	capture.feed(_axis(1, 0.0))
	capture.feed(_axis(1, 1.0))
	assert_eq(capture.descriptor, "pad:axis:1+", "it counts once it has been let go and pushed again")


func test_a_trigger_pulled_is_captured_and_cannot_be_bound_the_other_way() -> void:
	capture.start()
	capture.feed(_axis(5, 0.0))
	assert_true(capture.feed(_axis(5, -1.0)))
	assert_true(capture.is_waiting(), "triggers only read in the + direction")
	capture.feed(_axis(5, 0.9))
	assert_eq(capture.descriptor, "pad:axis:5+")


func test_an_axis_outside_the_standard_pad_is_ignored() -> void:
	capture.start()
	capture.feed(_axis(7, 0.0))
	assert_true(capture.feed(_axis(7, 1.0)))
	assert_true(capture.is_waiting())


# --- Ending the wait without a binding ---------------------------------------------------------------------------


func test_a_tap_of_b_or_escape_binds_it() -> void:
	capture.start()
	assert_true(capture.feed(_button(1)))
	assert_true(capture.is_waiting(), "B may be the start of a hold")
	assert_true(capture.feed(_button(1, false)))
	assert_eq(capture.descriptor, "pad:button:1", "released in time: it is the press")
	capture.start()
	capture.feed(_key(KEY_ESCAPE))
	capture.feed(_key(KEY_ESCAPE, false))
	assert_eq(capture.descriptor, "key:Escape")


func test_holding_b_cancels() -> void:
	capture.start()
	capture.feed(_button(1))
	capture.advance(BindingCapture.CANCEL_HOLD_S - 0.1)
	assert_true(capture.is_waiting())
	capture.advance(0.2)
	assert_eq(capture.state, BindingCapture.State.CANCELLED)
	assert_eq(capture.descriptor, "")
	assert_false(capture.feed(_button(1, false)), "the release afterwards is the menu's")


func test_holding_escape_cancels() -> void:
	capture.start()
	capture.feed(_key(KEY_ESCAPE))
	capture.feed(_key(KEY_ESCAPE, true, true))  # the repeats of a held key do not restart the hold
	capture.advance(BindingCapture.CANCEL_HOLD_S)
	assert_eq(capture.state, BindingCapture.State.CANCELLED)


func test_another_press_while_b_is_held_is_what_gets_bound() -> void:
	capture.start()
	capture.feed(_button(1))
	capture.feed(_button(3))
	assert_eq(capture.descriptor, "pad:button:3")
	capture.advance(5.0)
	assert_eq(capture.state, BindingCapture.State.CAPTURED, "the hold is forgotten")


func test_time_without_a_press_ends_the_wait() -> void:
	capture.start()
	capture.advance(BindingCapture.TIMEOUT_S - 0.5)
	assert_true(capture.is_waiting())
	capture.advance(0.6)
	assert_eq(capture.state, BindingCapture.State.TIMED_OUT)
	assert_false(capture.feed(_button(2)), "the late press belongs to the menu")


func test_a_given_timeout_is_used() -> void:
	capture.start(1.0)
	capture.advance(1.1)
	assert_eq(capture.state, BindingCapture.State.TIMED_OUT)


func test_cancel_ends_the_wait() -> void:
	capture.start()
	capture.cancel()
	assert_eq(capture.state, BindingCapture.State.CANCELLED)
	assert_false(capture.is_waiting())


func test_advance_does_nothing_when_not_waiting() -> void:
	capture.advance(100.0)
	assert_eq(capture.state, BindingCapture.State.IDLE)
