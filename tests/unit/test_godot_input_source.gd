extends GutTest
## GodotInputSource against Input state injected with parse_input_event on a fake pad 0.


class OnePadSource:
	extends GodotInputSource

	func _pad_ids() -> Array[int]:
		var pads: Array[int] = [0]
		return pads

	func _pad_guid(_pad: int) -> String:
		return "fakepad0"

	func _pad_name(_pad: int) -> String:
		return "Fake Pad"


var source: OnePadSource


func before_each() -> void:
	source = OnePadSource.new()
	source.trigger_deadzone = 0.05
	_release_everything()


func after_each() -> void:
	_release_everything()


func test_trigger_rest_zero() -> void:
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	source.poll(1.0 / 60.0)
	assert_eq(source.get_trigger(&"main_right"), 0.0)
	_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	assert_almost_eq(source.get_trigger(&"main_right"), 1.0, 1e-5)
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.525)
	assert_almost_eq(source.get_trigger(&"main_right"), 0.5, 1e-5)


func test_trigger_rest_minus_one_is_detected() -> void:
	watch_signals(source)
	_axis(JOY_AXIS_TRIGGER_LEFT, -1.0)
	_axis(JOY_AXIS_TRIGGER_RIGHT, -1.0)
	source.poll(1.0 / 60.0)
	assert_signal_emitted(source, "trigger_rest_changed")
	assert_eq(source.get_trigger(&"main_left"), 0.0, "idle -1 pad reads zero")
	_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	assert_almost_eq(source.get_trigger(&"main_left"), 1.0, 1e-5)


func test_keyboard_masked_pad_passes_through() -> void:
	_key(KEY_E, true)
	assert_eq(source.get_trigger(&"main_right"), 1.0, "E = right mains")
	assert_true(source.is_pressed(&"main_right"))
	_axis(JOY_AXIS_TRIGGER_LEFT, 0.525)
	source.keyboard_mouse_enabled = false
	assert_eq(source.get_trigger(&"main_right"), 0.0, "key masked while the console is open")
	assert_almost_eq(source.get_trigger(&"main_left"), 0.5, 1e-5, "pad unaffected")
	_button(JOY_BUTTON_A, true)
	assert_true(source.is_pressed(&"fire"), "pad buttons unaffected")


func test_stick_vector_and_buttons() -> void:
	_axis(JOY_AXIS_RIGHT_X, 1.0)  # right stick X is roll (§6.1)
	var v: Vector2 = source.get_vector(&"roll_left", &"roll_right", &"pitch_down", &"pitch_up", 0.15)
	assert_almost_eq(v.x, 1.0, 1e-5)
	assert_false(source.is_pressed(&"yaw_right"), "the stick no longer yaws")
	_axis(JOY_AXIS_RIGHT_X, 0.1)
	v = source.get_vector(&"roll_left", &"roll_right", &"pitch_down", &"pitch_up", 0.15)
	assert_eq(v, Vector2.ZERO, "drift inside the radial deadzone")
	_button(JOY_BUTTON_DPAD_RIGHT, true)
	assert_true(source.is_pressed(&"yaw_right"), "D-pad right is yaw")
	assert_false(source.is_pressed(&"roll_right"))
	_button(JOY_BUTTON_RIGHT_SHOULDER, true)
	assert_true(source.is_pressed(&"retro_right"))
	assert_false(source.is_pressed(&"retro_left"))


func test_pad_info() -> void:
	_axis(JOY_AXIS_LEFT_X, 0.25)
	var info: Array[Dictionary] = source.pad_info()
	assert_eq(info.size(), 1)
	assert_almost_eq(float((info[0]["axes"] as Array)[0]), 0.25, 1e-5)
	assert_true(info[0].has("trigger_rest"))


func _axis(axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _button(button: JoyButton, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = button
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _key(key: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = key
	e.keycode = key
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _release_everything() -> void:
	for axis: int in 6:
		_axis(axis as JoyAxis, 0.0)
	for button: int in 15:
		_button(button as JoyButton, false)
	for key: Key in [KEY_E, KEY_W, KEY_Q]:
		_key(key, false)
	Input.flush_buffered_events()
