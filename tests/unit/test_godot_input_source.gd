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


func before_all() -> void:
	# The default layout (a saved control profile may have replaced it at start-up).
	ControlProfiles.store.default_profile().apply_to_input_map()


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


func test_pods_by_position() -> void:
	# Layout B: Q / E are the left / right main, A / D the left / right retro, W and S the pair.
	var cases: Array[Array] = [
		[KEY_Q, 1.0, 0.0, false, false], [KEY_E, 0.0, 1.0, false, false], [KEY_W, 1.0, 1.0, false, false],
		[KEY_A, 0.0, 0.0, true, false], [KEY_D, 0.0, 0.0, false, true], [KEY_S, 0.0, 0.0, true, true],
	]
	for c: Array in cases:
		var key: Key = c[0]
		var label: String = OS.get_keycode_string(key)
		_key(key, true)
		assert_eq(source.get_trigger(&"main_left"), c[1], "%s: main_left" % label)
		assert_eq(source.get_trigger(&"main_right"), c[2], "%s: main_right" % label)
		assert_eq(source.is_pressed(&"retro_left"), c[3], "%s: retro_left" % label)
		assert_eq(source.is_pressed(&"retro_right"), c[4], "%s: retro_right" % label)
		_key(key, false)


func test_caps_lock_rolls_left_while_it_is_down() -> void:
	# Layout B rolls left on Caps Lock. The platform layer must deliver a press and a release for it (not a toggle);
	# this pins that the input source then reads it as held and released. The real keyboard on X11 and Wayland is the
	# maintainer's check (M3 AC14).
	var roll := func() -> Vector2:
		return source.get_vector(&"roll_left", &"roll_right", &"pitch_down", &"pitch_up", 0.15)
	_key(KEY_CAPSLOCK, true)
	assert_true(source.is_pressed(&"roll_left"), "down")
	assert_almost_eq((roll.call() as Vector2).x, -1.0, 1e-5, "rolls left")
	_key(KEY_CAPSLOCK, false)
	assert_false(source.is_pressed(&"roll_left"), "up")
	assert_eq(roll.call(), Vector2.ZERO, "and stops")
	_key(KEY_G, true)
	assert_almost_eq((roll.call() as Vector2).x, 1.0, 1e-5, "G rolls right")


func test_b_is_tap_for_next_target_and_hold_for_the_one_nearest_the_nose() -> void:
	var adapter := InputAdapter.new()
	var dt: float = 1.0 / 60.0
	_key(KEY_B, true)
	assert_false(adapter.sample(source, dt).combat.target_next, "a tap acts on release")
	_key(KEY_B, false)
	var tap: CombatCommand = adapter.sample(source, dt).combat
	assert_true(tap.target_next, "tap: next target")
	assert_false(tap.target_ahead)

	_key(KEY_B, true)
	var next_ticks: int = 0
	var ahead_ticks: int = 0
	for i: int in 40:  # 0.67 s, well past the 0.35 s hold threshold
		var combat: CombatCommand = adapter.sample(source, dt).combat
		next_ticks += 1 if combat.target_next else 0
		ahead_ticks += 1 if combat.target_ahead else 0
	_key(KEY_B, false)
	var released: CombatCommand = adapter.sample(source, dt).combat
	next_ticks += 1 if released.target_next else 0
	ahead_ticks += 1 if released.target_ahead else 0
	assert_eq(ahead_ticks, 1, "hold: nearest the nose, once")
	assert_eq(next_ticks, 0, "and the release after a hold does not also cycle")


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
	for key: Key in [KEY_E, KEY_W, KEY_Q, KEY_S, KEY_A, KEY_D, KEY_B, KEY_G, KEY_CAPSLOCK]:
		_key(key, false)
	Input.flush_buffered_events()


func test_a_free_mouse_reads_as_idle() -> void:
	var source := GodotInputSource.new()
	source.add_mouse_motion(Vector2(10.0, 5.0))
	source.add_wheel(2)
	assert_eq(source.take_mouse_delta(), Vector2(10.0, 5.0), "captured: motion arrives")
	assert_eq(source.take_wheel_steps(), 2)
	source.mouse_free = true
	source.add_mouse_motion(Vector2(10.0, 5.0))
	source.add_wheel(2)
	assert_eq(source.take_mouse_delta(), Vector2.ZERO, "the desktop has the mouse: no turn")
	assert_eq(source.take_wheel_steps(), 0, "and no target cycling")
