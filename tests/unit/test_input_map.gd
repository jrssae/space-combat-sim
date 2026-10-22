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
	&"fire": ["button", JOY_BUTTON_A, 0],
	&"toggle_flight_assist": ["button", JOY_BUTTON_B, 0],
	&"brake": ["button", JOY_BUTTON_RIGHT_STICK, 0],
	&"autotrack": ["button", JOY_BUTTON_X, 0],
	&"camera_look": ["button", JOY_BUTTON_LEFT_STICK, 0],
	&"toggle_camera": ["button", JOY_BUTTON_Y, 0],
	&"reset_ship": ["button", JOY_BUTTON_BACK, 0],
	&"pause": ["button", JOY_BUTTON_START, 0],
}

const KEYBOARD_ONLY: Array[StringName] = [
	&"debug_toggle_fallback_mesh", &"debug_toggle_overlay", &"target_ahead", &"target_prev", &"screenshot",
]

# Keyboard layout B (architecture §6.1, M3-T01): every flight key under the left hand, because the right hand flies the
# mouse. action -> physical keys in event order (an action not listed has none). The mouse flies pitch and yaw, so those
# have no keys; target_prev is the wheel and target_ahead the hold of B / Mouse 2, so neither has a key. Ctrl, Alt, the
# number row and ` are unbound (Alt frees the mouse, ` is the console).
const KEYS_B: Dictionary = {
	&"main_left": [KEY_Q, KEY_W],
	&"main_right": [KEY_E, KEY_W],
	&"retro_left": [KEY_A, KEY_S],
	&"retro_right": [KEY_D, KEY_S],
	&"strafe_up": [KEY_R],
	&"strafe_down": [KEY_F],
	&"strafe_left": [KEY_Z],
	&"strafe_right": [KEY_C],
	&"roll_left": [KEY_CAPSLOCK],
	&"roll_right": [KEY_G],
	&"brake": [KEY_X],
	&"autotrack": [KEY_SHIFT],
	&"fire": [KEY_SPACE],
	&"weapon_next": [KEY_V],
	&"target_next": [KEY_B],
	&"toggle_flight_assist": [KEY_T],
	&"toggle_camera": [KEY_TAB],
	&"pause": [KEY_ESCAPE],
	&"reset_ship": [KEY_BACKSPACE],
	&"screenshot": [KEY_N, KEY_PRINT],
	&"debug_toggle_overlay": [KEY_F3],
	&"debug_toggle_fallback_mesh": [KEY_F4],
}

# action -> mouse buttons in event order (an action not listed has none).
const MOUSE_B: Dictionary = {
	&"fire": [MOUSE_BUTTON_LEFT],
	&"target_next": [MOUSE_BUTTON_RIGHT],
	&"camera_look": [MOUSE_BUTTON_MIDDLE],
	&"autotrack": [MOUSE_BUTTON_XBUTTON1],
	&"weapon_next": [MOUSE_BUTTON_XBUTTON2],
}

# The left block of a US keyboard: the Q-T, A-G and Z-B columns, Shift, Caps Lock, Tab and Space.
const LEFT_BLOCK: Array[Key] = [
	KEY_Q, KEY_W, KEY_E, KEY_R, KEY_T, KEY_A, KEY_S, KEY_D, KEY_F, KEY_G, KEY_Z, KEY_X, KEY_C, KEY_V, KEY_B,
	KEY_SHIFT, KEY_CAPSLOCK, KEY_TAB, KEY_SPACE,
]

# The only keys outside the left block, each for one housekeeping action.
const OUTSIDE_THE_BLOCK: Dictionary = {
	KEY_ESCAPE: [&"pause"],
	KEY_BACKSPACE: [&"reset_ship"],
	KEY_N: [&"screenshot"],
	KEY_PRINT: [&"screenshot"],
	KEY_F3: [&"debug_toggle_overlay"],
	KEY_F4: [&"debug_toggle_fallback_mesh"],
}


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


func test_every_action_is_reachable_from_somewhere() -> void:
	# Layout B leaves the mouse wheel (target_prev) and a held B / Mouse 2 (target_ahead) to cover two actions that have no
	# event of their own; pitch and yaw keep their pad bindings and the mouse's motion.
	var eventless: Array[StringName] = [&"target_ahead", &"target_prev"]
	for action: StringName in InputAdapter.ACTIONS:
		var count: int = InputMap.action_get_events(action).size()
		if eventless.has(action):
			assert_eq(count, 0, "%s: no key, no pad button (the wheel and the B hold reach it)" % action)
		else:
			assert_gt(count, 0, "%s has a binding" % action)


func test_keyboard_layout_b_is_exactly_the_table() -> void:
	for action: StringName in InputAdapter.ACTIONS:
		var keys: Array = []
		var buttons: Array = []
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventKey:
				var key := event as InputEventKey
				assert_eq(key.keycode, KEY_NONE, "%s: a physical key, not a logical one" % action)
				assert_false(key.shift_pressed or key.ctrl_pressed or key.alt_pressed or key.meta_pressed,
						"%s: no modifier flags" % action)
				keys.append(key.physical_keycode)
			elif event is InputEventMouseButton:
				buttons.append((event as InputEventMouseButton).button_index)
		assert_eq(keys, KEYS_B.get(action, []), "%s: keys" % action)
		assert_eq(buttons, MOUSE_B.get(action, []), "%s: mouse buttons" % action)


func test_no_flight_key_is_right_of_the_g_b_column() -> void:
	for action: StringName in InputAdapter.ACTIONS:
		for event: InputEvent in InputMap.action_get_events(action):
			if not event is InputEventKey:
				continue
			var key: Key = (event as InputEventKey).physical_keycode
			if LEFT_BLOCK.has(key):
				continue
			var owners: Array = OUTSIDE_THE_BLOCK.get(key, [])
			assert_true(owners.has(action), "%s: %s is outside the left block" % [action, OS.get_keycode_string(key)])


func test_pitch_and_yaw_have_no_keys_because_the_mouse_flies() -> void:
	for action: StringName in [&"pitch_down", &"pitch_up", &"yaw_left", &"yaw_right"]:
		for event: InputEvent in InputMap.action_get_events(action):
			assert_false(event is InputEventKey or event is InputEventMouseButton, "%s: pad only" % action)


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
	# Pods by position: the left key of a row drives the left pod, the right key the right pod, the middle key both.
	assert_true(_has_key(&"main_right", KEY_W) and _has_key(&"main_left", KEY_W), "W = both mains")
	assert_true(_has_key(&"retro_right", KEY_S) and _has_key(&"retro_left", KEY_S), "S = both retros")
	assert_true(_has_key(&"main_left", KEY_Q) and _has_key(&"main_right", KEY_E), "Q / E = left / right main")
	assert_true(_has_key(&"retro_left", KEY_A) and _has_key(&"retro_right", KEY_D), "A / D = left / right retro")
	assert_false(_has_key(&"main_right", KEY_Q) or _has_key(&"main_left", KEY_E), "Q and E each drive one pod")
	assert_false(_has_key(&"retro_right", KEY_A) or _has_key(&"retro_left", KEY_D), "A and D each drive one pod")


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
	assert_true(_has_key(&"roll_left", KEY_CAPSLOCK) and _has_key(&"roll_right", KEY_G), "Caps Lock / G roll (left hand)")


func test_target_ahead_has_r3_and_dpad_up_carries_the_hold() -> void:
	# Pads without stick clicks reach target_ahead by holding D-pad Up (InputAdapter); R3 still works where it exists.
	var dpad_up: Array[StringName] = []
	for action: StringName in InputAdapter.ACTIONS:
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == JOY_BUTTON_DPAD_UP:
				dpad_up.append(action)
	assert_eq(dpad_up, [&"target_next"] as Array[StringName], "D-pad Up is the tap-or-hold target button alone")
	assert_false(InputAdapter.EDGE_ACTIONS.has(&"target_next"), "it is not a press edge: tap fires on release")
	assert_true(InputAdapter.EDGE_ACTIONS.has(&"target_ahead"), "an event bound to target_ahead stays a press edge")
	assert_true(_has_key(&"target_next", KEY_B), "B carries the same tap-or-hold as D-pad Up")
	assert_true(_has_mouse(&"target_next", MOUSE_BUTTON_RIGHT), "and so does Mouse 2")


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


func _has_mouse(action: StringName, button: MouseButton) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == button:
			return true
	return false
