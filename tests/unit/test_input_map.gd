extends GutTest
## project.godot [input] must match architecture §6.1 exactly, using only the standard SDL layout.

# action -> [kind, index, sign] for its pad binding ("axis" sign is the axis_value direction).
const PAD_BINDINGS: Dictionary = {
	&"main_right": ["axis", JOY_AXIS_TRIGGER_RIGHT, 1],
	&"main_left": ["axis", JOY_AXIS_TRIGGER_LEFT, 1],
	&"retro_right": ["button", JOY_BUTTON_RIGHT_SHOULDER, 0],
	&"retro_left": ["button", JOY_BUTTON_LEFT_SHOULDER, 0],
	&"pitch_down": ["axis", JOY_AXIS_RIGHT_Y, -1],
	&"pitch_up": ["axis", JOY_AXIS_RIGHT_Y, 1],
	&"roll_left": ["axis", JOY_AXIS_RIGHT_X, -1],
	&"roll_right": ["axis", JOY_AXIS_RIGHT_X, 1],
	&"strafe_left": ["axis", JOY_AXIS_LEFT_X, -1],
	&"strafe_right": ["axis", JOY_AXIS_LEFT_X, 1],
	&"strafe_down": ["axis", JOY_AXIS_LEFT_Y, 1],
	&"strafe_up": ["axis", JOY_AXIS_LEFT_Y, -1],
	&"yaw_left": ["button", JOY_BUTTON_DPAD_LEFT, 0],
	&"yaw_right": ["button", JOY_BUTTON_DPAD_RIGHT, 0],
	&"target_next": ["button", JOY_BUTTON_DPAD_UP, 0],
	&"weapon_next": ["button", JOY_BUTTON_DPAD_DOWN, 0],
	&"target_ahead": ["button", JOY_BUTTON_RIGHT_STICK, 0],
	&"fire": ["button", JOY_BUTTON_A, 0],
	&"toggle_flight_assist": ["button", JOY_BUTTON_B, 0],
	&"brake": ["button", JOY_BUTTON_X, 0],
	&"toggle_camera": ["button", JOY_BUTTON_Y, 0],
	&"reset_ship": ["button", JOY_BUTTON_BACK, 0],
	&"pause": ["button", JOY_BUTTON_START, 0],
	&"debug_toggle_overlay": ["button", JOY_BUTTON_LEFT_STICK, 0],
}

const KEYBOARD_ONLY: Array[StringName] = [&"debug_toggle_fallback_mesh"]


func before_all() -> void:
	# These tests pin project.godot's map. A saved control profile (settings.control_profile) may have replaced it
	# at start-up, so put the default snapshot back first (ControlProfile tests cover the profiles themselves).
	ControlProfiles.store.default_profile().apply_to_input_map()


func test_every_action_exists() -> void:
	for action: StringName in InputAdapter.ACTIONS:
		assert_true(InputMap.has_action(action), "InputMap has %s" % action)


func test_pad_bindings_match_the_layout() -> void:
	assert_eq(PAD_BINDINGS.size() + KEYBOARD_ONLY.size(), InputAdapter.ACTIONS.size(), "table covers every action")
	for action: StringName in PAD_BINDINGS.keys():
		var expected: Array = PAD_BINDINGS[action]
		var found: bool = false
		for event: InputEvent in InputMap.action_get_events(action):
			if expected[0] == "axis" and event is InputEventJoypadMotion:
				var m := event as InputEventJoypadMotion
				found = found or (m.axis == expected[1] and signf(m.axis_value) == float(expected[2]))
			elif expected[0] == "button" and event is InputEventJoypadButton:
				found = found or (event as InputEventJoypadButton).button_index == expected[1]
		assert_true(found, "%s bound to %s %s" % [action, expected[0], expected[1]])


func test_only_standard_sdl_indices_and_any_device() -> void:
	for action: StringName in InputAdapter.ACTIONS:
		var pad_events: int = 0
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventJoypadMotion:
				pad_events += 1
				var axis: int = (event as InputEventJoypadMotion).axis
				assert_between(axis, 0, 5, "%s axis index" % action)
			elif event is InputEventJoypadButton:
				pad_events += 1
				var button: int = (event as InputEventJoypadButton).button_index
				assert_between(button, 0, 14, "%s button index" % action)
				assert_ne(button, JOY_BUTTON_GUIDE, "%s must not use Guide" % action)
			if event is InputEventJoypadMotion or event is InputEventJoypadButton:
				assert_eq(event.device, -1, "%s binds any pad" % action)
		if not KEYBOARD_ONLY.has(action):
			assert_gt(pad_events, 0, "%s has a pad binding" % action)


func test_every_action_is_reachable_from_the_keyboard() -> void:
	for action: StringName in InputAdapter.ACTIONS:
		var keys: int = 0
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventKey or event is InputEventMouseButton:
				keys += 1
		assert_gt(keys, 0, "%s has a keyboard fallback" % action)


func test_console_key_is_never_bound() -> void:
	# Godot's own ui_* actions are left alone (ui_swap_input_direction is a text-editing shortcut that only
	# reaches focused text fields, after the console has handled `); every game action is checked.
	for action: StringName in InputMap.get_actions():
		if String(action).begins_with("ui_"):
			continue
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventKey:
				var key := event as InputEventKey
				assert_ne(key.physical_keycode, KEY_QUOTELEFT, "` is the console key (%s)" % action)
				assert_ne(key.keycode, KEY_QUOTELEFT, "` is the console key (%s)" % action)


func test_both_sides_keys() -> void:
	assert_true(_has_key(&"main_right", KEY_W) and _has_key(&"main_left", KEY_W), "W = both mains")
	assert_true(_has_key(&"retro_right", KEY_S) and _has_key(&"retro_left", KEY_S), "S = both retros")


func test_trigger_deadzone() -> void:
	assert_almost_eq(InputMap.action_get_deadzone(&"main_right"), 0.05, 1e-6)
	assert_almost_eq(InputMap.action_get_deadzone(&"strafe_left"), 0.15, 1e-6)


func test_right_stick_rolls_and_dpad_yaws() -> void:
	# The maintainer's swap: right stick X is roll (analog, like pitch), D-pad Left/Right is yaw (digital).
	for action: StringName in [&"roll_left", &"roll_right", &"pitch_down", &"pitch_up"]:
		assert_almost_eq(InputMap.action_get_deadzone(action), 0.15, 1e-6, "%s: stick deadzone" % action)
		assert_false(_has_pad_button(action), "%s: no D-pad button" % action)
	for action: StringName in [&"yaw_left", &"yaw_right"]:
		assert_true(_has_pad_button(action), "%s: a D-pad button" % action)
		for event: InputEvent in InputMap.action_get_events(action):
			assert_false(event is InputEventJoypadMotion, "%s: no stick axis" % action)
	assert_true(_has_key(&"yaw_left", KEY_J) and _has_key(&"yaw_right", KEY_L), "J/L stay yaw")
	assert_true(_has_key(&"roll_left", KEY_U) and _has_key(&"roll_right", KEY_O), "U/O stay roll")


func test_target_ahead_has_r3_and_dpad_up_carries_the_hold() -> void:
	# Pads without stick clicks reach target_ahead by holding D-pad Up (InputAdapter); R3 still works where it exists.
	var dpad_up: Array[StringName] = []
	for action: StringName in InputAdapter.ACTIONS:
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == JOY_BUTTON_DPAD_UP:
				dpad_up.append(action)
	assert_eq(dpad_up, [&"target_next"] as Array[StringName], "D-pad Up is the tap-or-hold target button alone")
	assert_false(InputAdapter.EDGE_ACTIONS.has(&"target_next"), "it is not a press edge: tap fires on release")
	assert_true(InputAdapter.EDGE_ACTIONS.has(&"target_ahead"), "R3 / G stay a press edge")


func _has_pad_button(action: StringName) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadButton:
			return true
	return false


func _has_key(action: StringName, key: Key) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == key:
			return true
	return false
