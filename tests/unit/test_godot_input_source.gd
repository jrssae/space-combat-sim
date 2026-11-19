extends GutTest
## GodotInputSource against Input state injected with parse_input_event on a fake pad.


class OnePadSource:
	extends GodotInputSource

	## Past any id a real pad gets (Godot numbers them from 0), so a pad on the desk cannot feed the test.
	const DEVICE: int = 15

	func _pad_ids() -> Array[int]:
		var pads: Array[int] = [DEVICE]
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


func test_b_is_tap_for_the_nearest_enemy_and_hold_for_the_target_menu() -> void:
	var adapter := InputAdapter.new()
	var dt: float = 1.0 / 60.0
	_key(KEY_B, true)
	assert_false(adapter.sample(source, dt).combat.target_nearest, "a tap acts on release")
	_key(KEY_B, false)
	var tap: PilotCommand = adapter.sample(source, dt)
	assert_true(tap.combat.target_nearest, "tap: the nearest enemy")
	assert_false(tap.ui.target_menu_open)

	_key(KEY_B, true)
	var next_ticks: int = 0
	var ahead_ticks: int = 0
	for i: int in 40:  # 0.67 s, well past the 0.35 s hold threshold
		var held: PilotCommand = adapter.sample(source, dt)
		next_ticks += 1 if held.combat.target_nearest else 0
		ahead_ticks += 1 if held.ui.target_menu_open else 0
	_key(KEY_B, false)
	var released: PilotCommand = adapter.sample(source, dt)
	next_ticks += 1 if released.combat.target_nearest else 0
	ahead_ticks += 1 if released.ui.target_menu_open else 0
	assert_eq(ahead_ticks, 1, "hold: the target menu, once")
	assert_eq(next_ticks, 0, "and the release after a hold does not also tap")


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
	_axis(JOY_AXIS_RIGHT_X, 1.0)  # right stick X is yaw (§6.1, M3-T15; its diagonals roll in InputAdapter)
	var v: Vector2 = source.get_vector(&"yaw_left", &"yaw_right", &"pitch_down", &"pitch_up", 0.15)
	assert_almost_eq(v.x, 1.0, 1e-5)
	assert_false(source.is_pressed(&"roll_right"), "the roll actions are the keys")
	_axis(JOY_AXIS_RIGHT_X, 0.1)
	v = source.get_vector(&"yaw_left", &"yaw_right", &"pitch_down", &"pitch_up", 0.15)
	assert_eq(v, Vector2.ZERO, "drift inside the radial deadzone")
	_button(JOY_BUTTON_DPAD_RIGHT, true)
	assert_false(source.is_pressed(&"yaw_right"), "D-pad right is free")
	assert_false(source.is_pressed(&"roll_right"))
	_button(JOY_BUTTON_RIGHT_SHOULDER, true)
	assert_true(source.is_pressed(&"retro_right"))
	assert_false(source.is_pressed(&"retro_left"))


func test_the_left_stick_points_a_radial_menu_and_the_right_stick_does_not() -> void:
	# M7-T37: the radial actions are on the left stick's axes, through the real InputMap bindings.
	var adapter := InputAdapter.new()
	_axis(JOY_AXIS_RIGHT_X, 1.0)
	_axis(JOY_AXIS_RIGHT_Y, -1.0)
	assert_eq(adapter.sample_radial(source, 1.0 / 60.0).radial_point, Vector2.ZERO, "the right stick points at nothing")
	_axis(JOY_AXIS_RIGHT_X, 0.0)
	_axis(JOY_AXIS_RIGHT_Y, 0.0)
	_axis(JOY_AXIS_LEFT_X, 1.0)
	assert_almost_eq(adapter.sample_radial(source, 1.0 / 60.0).radial_point, Vector2(1.0, 0.0), Vector2(1e-5, 1e-5), "left stick right")
	_axis(JOY_AXIS_LEFT_X, 0.0)
	_axis(JOY_AXIS_LEFT_Y, -1.0)  # stick up is a negative Y
	assert_almost_eq(adapter.sample_radial(source, 1.0 / 60.0).radial_point, Vector2(0.0, 1.0), Vector2(1e-5, 1e-5), "left stick up")


func test_the_numbered_keys_pick_a_radial_menus_entries_and_the_dpad_does_nothing() -> void:
	# M8-T24 (D90, maintainer 2026-11-19), through the real InputMap: keys 1-8 are entries 1-8; the D-pad neither picks nor closes.
	var adapter := InputAdapter.new()
	adapter.begin_radial(source)
	for button: JoyButton in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT]:
		_button(button, true)
		var ui: UiCommand = adapter.sample_radial(source, 1.0 / 60.0)
		assert_eq(ui.radial_entry, -1, "D-pad %d picks nothing" % button)
		assert_false(ui.comms_open, "D-pad %d closes nothing (D-pad Right is the pad's comms button)" % button)
		assert_eq(ui.radial_point, Vector2.ZERO, "and points nowhere")
		_button(button, false)
	_key(KEY_CTRL, true)
	assert_true(adapter.sample_radial(source, 1.0 / 60.0).comms_open, "Ctrl still closes the comms menu")
	_key(KEY_CTRL, false)
	var keys: Array[Key] = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8]
	for i: int in keys.size():
		_key(keys[i], true)
		assert_eq(adapter.sample_radial(source, 1.0 / 60.0).radial_entry, i, "key %d" % (i + 1))
		_key(keys[i], false)
	adapter.sample_radial(source, 1.0 / 60.0)
	assert_eq(adapter.sample_radial(source, 1.0 / 60.0).radial_entry, -1, "nothing pressed")


func test_the_stick_vector_ignores_keys() -> void:
	_key(KEY_Z, true)  # strafe left, by key
	var by_key: Vector2 = source.get_vector(&"strafe_left", &"strafe_right", &"strafe_down", &"strafe_up", 0.15)
	assert_lt(by_key.x, -0.5, "get_vector reads the key")
	assert_eq(source.get_stick_vector(&"strafe_left", &"strafe_right", &"strafe_down", &"strafe_up", 0.15), Vector2.ZERO,
			"get_stick_vector does not")
	_axis(JOY_AXIS_LEFT_X, 1.0)
	assert_gt(source.get_stick_vector(&"strafe_left", &"strafe_right", &"strafe_down", &"strafe_up", 0.15).x, 0.5, "the stick is read")
	_key(KEY_Z, false)


func test_pad_info() -> void:
	_axis(JOY_AXIS_LEFT_X, 0.25)
	var info: Array[Dictionary] = source.pad_info()
	assert_eq(info.size(), 1)
	assert_almost_eq(float((info[0]["axes"] as Array)[0]), 0.25, 1e-5)
	assert_true(info[0].has("trigger_rest"))


func _axis(axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = OnePadSource.DEVICE
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _button(button: JoyButton, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = OnePadSource.DEVICE
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
	for key: Key in [KEY_E, KEY_W, KEY_Q, KEY_S, KEY_A, KEY_D, KEY_B, KEY_G, KEY_CAPSLOCK, KEY_Z, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5,
			KEY_6, KEY_7, KEY_8, KEY_CTRL]:
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
