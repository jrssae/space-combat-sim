extends GutTest
## ControlProfile: descriptors, InputMap <-> profile <-> config text round trips, validation, bind/unbind edits
## (architecture §15.12, AC13). Tests that touch the InputMap restore the project.godot map afterwards.

var _default: ControlProfile


func before_all() -> void:
	# The map as project.godot declares it (a saved profile may have been applied at start-up).
	_default = ControlProfiles.store.default_profile()
	_default.apply_to_input_map()


func after_each() -> void:
	_default.apply_to_input_map()


# --- Descriptors ----------------------------------------------------------------------------------------------


func test_descriptors_parse_to_the_right_events() -> void:
	var button: InputEventJoypadButton = ControlProfile.event_from("pad:button:11") as InputEventJoypadButton
	assert_not_null(button)
	assert_eq(button.button_index, JOY_BUTTON_DPAD_UP)
	assert_eq(button.device, -1, "any pad")

	var axis: InputEventJoypadMotion = ControlProfile.event_from("pad:axis:3-") as InputEventJoypadMotion
	assert_not_null(axis)
	assert_eq(axis.axis, JOY_AXIS_RIGHT_Y)
	assert_eq(axis.axis_value, -1.0)
	assert_eq((ControlProfile.event_from("pad:axis:5+") as InputEventJoypadMotion).axis, JOY_AXIS_TRIGGER_RIGHT)

	var key: InputEventKey = ControlProfile.event_from("key:Space") as InputEventKey
	assert_not_null(key)
	assert_eq(key.physical_keycode, KEY_SPACE, "a physical key")
	assert_eq(key.keycode, KEY_NONE)

	var mouse: InputEventMouseButton = ControlProfile.event_from("mouse:1") as InputEventMouseButton
	assert_not_null(mouse)
	assert_eq(mouse.button_index, MOUSE_BUTTON_LEFT)


func test_descriptor_spelling_is_canonical() -> void:
	assert_eq(ControlProfile.parse_descriptor("  PAD:Button:3 ")["descriptor"], "pad:button:3")
	assert_eq(ControlProfile.parse_descriptor("key:k")["descriptor"], "key:K")
	assert_eq(ControlProfile.parse_descriptor("key:space")["descriptor"], "key:Space")
	assert_eq(ControlProfile.parse_descriptor("key:f3")["descriptor"], "key:F3")
	assert_eq(ControlProfile.parse_descriptor("key:Kp_0")["descriptor"], "key:Kp 0", "underscore for a space")
	assert_eq(ControlProfile.parse_descriptor("pad:axis:2+")["descriptor"], "pad:axis:2+")


func test_every_key_the_default_map_binds_round_trips_through_its_name() -> void:
	for action: StringName in InputAdapter.ACTIONS:
		for event: InputEvent in InputMap.action_get_events(action):
			var descriptor: String = ControlProfile.descriptor_of(event)
			assert_ne(descriptor, "", "%s: %s is expressible" % [action, event.as_text()])
			var parsed: Dictionary = ControlProfile.parse_descriptor(descriptor)
			assert_true(parsed["ok"], "%s: %s parses (%s)" % [action, descriptor, parsed["error"]])
			assert_eq(parsed["descriptor"], descriptor, "%s is already canonical" % descriptor)


func test_bad_descriptors_say_why() -> void:
	var cases: Dictionary = {
		"pad:button:15": "outside the standard layout (0-14)",
		"pad:button:-1": "outside the standard layout",
		"pad:button:5": "Guide",
		"pad:button:x": "must be a number",
		"pad:axis:6+": "outside the standard layout (0-5)",
		"pad:axis:2": "<0-5>+ or <0-5>-",
		"pad:axis:5-": "trigger",
		"pad:hat:0": "unknown pad input",
		"pad:button": "expected pad:button",
		"key:": "unknown key name",
		"key:NoSuchKey": "unknown key name 'NoSuchKey'",
		"key:Shift+E": "modifier",
		"mouse:4": "mouse button must be",
		"mouse:left": "mouse button must be",
		"stick:1": "unknown binding 'stick:1'",
		"": "unknown binding",
	}
	for text: String in cases.keys():
		var parsed: Dictionary = ControlProfile.parse_descriptor(text)
		assert_false(parsed["ok"], "'%s' is rejected" % text)
		assert_string_contains(parsed["error"], cases[text], "'%s'" % text)
		assert_null(ControlProfile.event_from(text), "'%s' has no event" % text)


func test_the_console_key_cannot_be_named() -> void:
	for text: String in ["key:QuoteLeft", "key:quoteleft", "key:QUOTELEFT"]:
		var parsed: Dictionary = ControlProfile.parse_descriptor(text)
		assert_false(parsed["ok"], text)
		assert_string_contains(parsed["error"], "console key")
	# A key event the grammar cannot express is still named for the console key when that is what it is.
	var logical := InputEventKey.new()
	logical.keycode = KEY_QUOTELEFT
	assert_eq(ControlProfile.descriptor_of(logical), "key:QuoteLeft")


func test_events_the_grammar_cannot_express_have_no_descriptor() -> void:
	var shifted := InputEventKey.new()
	shifted.physical_keycode = KEY_E
	shifted.shift_pressed = true
	assert_eq(ControlProfile.descriptor_of(shifted), "", "modifier flags")
	var logical := InputEventKey.new()
	logical.keycode = KEY_E
	assert_eq(ControlProfile.descriptor_of(logical), "", "a logical key")
	var one_pad := InputEventJoypadButton.new()
	one_pad.device = 1
	one_pad.button_index = JOY_BUTTON_A
	assert_eq(ControlProfile.descriptor_of(one_pad), "", "a specific pad")
	var half_axis := InputEventJoypadMotion.new()
	half_axis.device = -1
	half_axis.axis = JOY_AXIS_LEFT_X
	half_axis.axis_value = 0.5
	assert_eq(ControlProfile.descriptor_of(half_axis), "", "a partial axis value")
	assert_eq(ControlProfile.descriptor_of(InputEventScreenTouch.new()), "", "other event kinds")


func test_profile_names() -> void:
	for good: String in ["default", "m1_classic", "a", "x".repeat(32), "pad_2"]:
		assert_true(ControlProfile.is_valid_name(good), good)
	for bad: String in ["", "Mine", "has space", "dash-ed", "x".repeat(33), "../evil", "a.b", "é"]:
		assert_false(ControlProfile.is_valid_name(bad), "'%s'" % bad)


# --- Round trips (AC13) ---------------------------------------------------------------------------------------


func test_the_project_map_is_a_valid_profile() -> void:
	var profile: ControlProfile = ControlProfile.from_input_map("default")
	assert_eq(profile.validate(), PackedStringArray(), "project.godot follows the profile rules")
	assert_eq(profile.bindings.size(), InputAdapter.ACTIONS.size())
	assert_eq(profile.descriptors_for(&"fire"), PackedStringArray(["pad:button:0", "key:Space", "mouse:1"]))
	assert_eq(profile.descriptors_for(&"main_right"), PackedStringArray(["pad:axis:5+", "key:R", "key:E"]))
	assert_almost_eq(float(profile.deadzones[&"main_right"]), 0.05, 1e-6)
	assert_almost_eq(float(profile.deadzones[&"yaw_left"]), 0.5, 1e-6)


func test_input_map_to_profile_to_text_to_profile_to_input_map_is_exact() -> void:
	var original: Dictionary = _capture_input_map()
	var profile: ControlProfile = ControlProfile.from_input_map("default")
	var text: String = profile.to_config_text()
	var loaded: Dictionary = ControlProfile.from_config_text(text, "default")
	assert_true(loaded["ok"], str(loaded["errors"]))
	var reread: ControlProfile = loaded["profile"]
	assert_true(profile.same_bindings(reread), "the text keeps every descriptor and deadzone")
	assert_eq(reread.to_config_text(), text, "and writes back identically")

	# Scramble the map, then restore it from the text: events, order and deadzones come back exactly.
	var scrambled: Dictionary = ControlProfiles.store.load_profile("m1_classic")
	assert_true(scrambled["ok"], str(scrambled["errors"]))
	assert_eq((scrambled["profile"] as ControlProfile).apply_to_input_map(), PackedStringArray())
	assert_false(ControlProfile.from_input_map().same_bindings(reread), "the map really changed")
	assert_eq(reread.apply_to_input_map(), PackedStringArray())
	var restored: Dictionary = _capture_input_map()
	assert_eq(restored.keys(), original.keys())
	for action: StringName in original.keys():
		var before: Dictionary = original[action]
		var after: Dictionary = restored[action]
		assert_almost_eq(float(after["deadzone"]), float(before["deadzone"]), 0.0, "%s deadzone" % action)
		var before_events: Array = before["events"]
		var after_events: Array = after["events"]
		assert_eq(after_events, before_events, "%s events, in order, field for field" % action)


func test_text_round_trip_keeps_a_description_and_user_edits() -> void:
	var profile: ControlProfile = _default.duplicate_profile()
	profile.name = "mine"
	profile.description = "my \"quoted\" layout"
	var edited: Dictionary = profile.with_bound(&"fire", "key:K")
	assert_true(edited["ok"])
	var loaded: Dictionary = ControlProfile.from_config_text((edited["profile"] as ControlProfile).to_config_text(), "mine")
	assert_true(loaded["ok"], str(loaded["errors"]))
	var reread: ControlProfile = loaded["profile"]
	assert_eq(reread.description, "my \"quoted\" layout")
	assert_eq(reread.descriptors_for(&"fire"), PackedStringArray(["pad:button:0", "key:Space", "mouse:1", "key:K"]))


func test_text_is_one_list_per_action_and_one_number_per_action() -> void:
	var text: String = _default.to_config_text()
	assert_string_contains(text, "[profile]")
	assert_string_contains(text, "format=1")
	assert_string_contains(text, "[bindings]")
	assert_string_contains(text, "fire=[\"pad:button:0\", \"key:Space\", \"mouse:1\"]")
	assert_string_contains(text, "debug_toggle_fallback_mesh=[\"key:F4\"]")
	assert_string_contains(text, "[deadzones]")
	assert_string_contains(text, "main_right=0.05")


# --- Validation (AC13) ----------------------------------------------------------------------------------------


func test_a_missing_action_is_reported_and_nothing_is_applied() -> void:
	var profile: ControlProfile = _default.duplicate_profile()
	profile.bindings.erase(&"fire")
	var errors: PackedStringArray = profile.validate()
	assert_eq(errors, PackedStringArray(["bindings.fire: missing"]))
	_assert_apply_refused_and_map_unchanged(profile)


func test_a_missing_deadzone_is_reported() -> void:
	var profile: ControlProfile = _default.duplicate_profile()
	profile.deadzones.erase(&"brake")
	assert_eq(profile.validate(), PackedStringArray(["deadzones.brake: missing"]))


func test_non_standard_pad_indices_are_rejected_and_nothing_is_applied() -> void:
	for bad: String in ["pad:button:15", "pad:button:5", "pad:axis:6+", "pad:button:99"]:
		var profile: ControlProfile = _default.duplicate_profile()
		profile.bindings[&"fire"] = [bad, "key:Space"]
		var errors: PackedStringArray = profile.validate()
		assert_gt(errors.size(), 0, bad)
		assert_string_contains(errors[0], "bindings.fire[0]", "names the action and the position (%s)" % bad)
		_assert_apply_refused_and_map_unchanged(profile)


func test_the_console_key_is_rejected_and_nothing_is_applied() -> void:
	var profile: ControlProfile = _default.duplicate_profile()
	profile.bindings[&"fire"] = ["pad:button:0", "key:QuoteLeft"]
	var errors: PackedStringArray = profile.validate()
	assert_eq(errors.size(), 1)
	assert_string_contains(errors[0], "bindings.fire[1]")
	assert_string_contains(errors[0], "console key")
	_assert_apply_refused_and_map_unchanged(profile)


func test_every_action_but_the_keyboard_only_one_needs_a_pad_binding() -> void:
	var profile: ControlProfile = _default.duplicate_profile()
	profile.bindings[&"fire"] = ["key:Space", "mouse:1"]
	var errors: PackedStringArray = profile.validate()
	assert_eq(errors.size(), 1)
	assert_string_contains(errors[0], "bindings.fire: needs a pad binding")
	profile = _default.duplicate_profile()
	profile.bindings[InputAdapter.TOGGLE_FALLBACK] = []
	assert_eq(profile.validate(), PackedStringArray(), "the keyboard-only debug action may be empty")
	profile.bindings[InputAdapter.TOGGLE_FALLBACK] = ["pad:button:7"]
	assert_eq(profile.validate(), PackedStringArray(), "or have a pad button")


func test_unknown_actions_and_duplicates_and_bad_deadzones() -> void:
	var profile: ControlProfile = _default.duplicate_profile()
	profile.bindings[&"fier"] = ["key:Y"]
	profile.deadzones[&"fier"] = 0.5
	profile.bindings[&"yaw_left"] = ["pad:button:13", "key:J", "key:j"]
	profile.deadzones[&"pause"] = 1.5
	profile.deadzones[&"reset_ship"] = "wide"
	var errors: PackedStringArray = profile.validate()
	var text: String = "\n".join(errors)
	assert_string_contains(text, "bindings.fier: unknown action (did you mean fire?)")
	assert_string_contains(text, "deadzones.fier: unknown action")
	assert_string_contains(text, "bindings.yaw_left[2]: key:J is listed twice")
	assert_string_contains(text, "deadzones.pause: must be in 0.0..0.9, got 1.5")
	assert_string_contains(text, "deadzones.reset_ship: expected a number")
	assert_eq(errors.size(), 5, text)


func test_an_input_map_event_the_grammar_cannot_save_makes_the_profile_invalid() -> void:
	var shifted := InputEventKey.new()
	shifted.physical_keycode = KEY_R
	shifted.shift_pressed = true
	InputMap.action_add_event(&"brake", shifted)
	var errors: PackedStringArray = ControlProfile.from_input_map().validate()
	assert_eq(errors.size(), 1)
	assert_string_contains(errors[0], "bindings.brake[2]")
	assert_string_contains(errors[0], "unknown binding")


func test_deadzones_are_part_of_the_profile() -> void:
	var profile: ControlProfile = _default.duplicate_profile()
	profile.deadzones[&"strafe_left"] = 0.25
	assert_false(profile.same_bindings(_default))
	assert_eq(profile.apply_to_input_map(), PackedStringArray())
	assert_almost_eq(InputMap.action_get_deadzone(&"strafe_left"), 0.25, 1e-6)
	assert_almost_eq(ControlProfile.from_input_map().deadzones[&"strafe_left"], 0.25, 1e-6)


# --- Text errors ----------------------------------------------------------------------------------------------


func test_syntax_errors_are_reported() -> void:
	var loaded: Dictionary = ControlProfile.from_config_text("[bindings\nfire=[", "broken")
	assert_engine_error("parse error")  # ConfigFile prints its own error as well
	assert_false(loaded["ok"])
	assert_null(loaded["profile"])
	assert_string_contains(loaded["errors"][0], "not valid config text")


func test_structure_errors_are_reported() -> void:
	var text: String = "\n".join([
		"[profile]", "format=2", "color=\"red\"",
		"[extras]", "x=1",
		"[bindings]", "fire=7", "pause=[\"pad:button:6\", 3]",
		"[deadzones]", "fire=0.5",
	])
	var loaded: Dictionary = ControlProfile.from_config_text(text, "broken")
	assert_false(loaded["ok"])
	var joined: String = "\n".join(loaded["errors"])
	assert_string_contains(joined, "[extras]: unknown section")
	assert_string_contains(joined, "profile.format: this build reads format 1, got 2")
	assert_string_contains(joined, "profile.color: unknown key")
	assert_string_contains(joined, "bindings.fire: expected a list")
	assert_string_contains(joined, "bindings.pause[1]: expected text, got int")
	assert_string_contains(joined, "bindings.main_right: missing", "and the validation rules still run")
	assert_not_null(loaded["profile"], "what did parse is available for inspection")


func test_a_single_descriptor_string_is_accepted_as_a_list() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "format", 1)
	for action: StringName in InputAdapter.ACTIONS:
		cfg.set_value("bindings", String(action), "pad:button:0")
		cfg.set_value("deadzones", String(action), 0.5)
	var loaded: Dictionary = ControlProfile.from_config(cfg, "one")
	assert_true(loaded["ok"], str(loaded["errors"]))
	assert_eq((loaded["profile"] as ControlProfile).descriptors_for(&"fire"), PackedStringArray(["pad:button:0"]))


# --- Editing --------------------------------------------------------------------------------------------------


func test_bind_adds_a_binding_to_a_copy() -> void:
	var result: Dictionary = _default.with_bound(&"fire", "key:k")
	assert_true(result["ok"], str(result["errors"]))
	assert_true(result["changed"])
	assert_eq(result["descriptor"], "key:K")
	var edited: ControlProfile = result["profile"]
	assert_eq(edited.descriptors_for(&"fire"), PackedStringArray(["pad:button:0", "key:Space", "mouse:1", "key:K"]))
	assert_eq(_default.descriptors_for(&"fire"), PackedStringArray(["pad:button:0", "key:Space", "mouse:1"]),
			"the original is untouched")


func test_bind_of_an_existing_binding_changes_nothing() -> void:
	var result: Dictionary = _default.with_bound(&"fire", "KEY:space")
	assert_true(result["ok"])
	assert_false(result["changed"])
	assert_true((result["profile"] as ControlProfile).same_bindings(_default))


func test_bind_rejects_bad_input_with_a_reason() -> void:
	var unknown: Dictionary = _default.with_bound(&"fier", "key:K")
	assert_false(unknown["ok"])
	assert_string_contains(unknown["errors"][0], "unknown action 'fier' (did you mean fire?)")
	var bad: Dictionary = _default.with_bound(&"fire", "pad:button:15")
	assert_false(bad["ok"])
	assert_string_contains(bad["errors"][0], "outside the standard layout")
	var console_key: Dictionary = _default.with_bound(&"fire", "key:QuoteLeft")
	assert_false(console_key["ok"])
	assert_string_contains(console_key["errors"][0], "console key")


func test_unbind_removes_one_binding() -> void:
	var result: Dictionary = _default.with_unbound(&"fire", "mouse:1")
	assert_true(result["ok"], str(result["errors"]))
	assert_eq((result["profile"] as ControlProfile).descriptors_for(&"fire"), PackedStringArray(["pad:button:0", "key:Space"]))


func test_unbind_of_something_not_bound_lists_what_is() -> void:
	var result: Dictionary = _default.with_unbound(&"fire", "key:K")
	assert_false(result["ok"])
	assert_string_contains(result["errors"][0], "fire has no key:K binding (it has: pad:button:0 key:Space mouse:1)")


func test_unbind_cannot_remove_the_last_pad_binding() -> void:
	var result: Dictionary = _default.with_unbound(&"fire", "pad:button:0")
	assert_false(result["ok"])
	assert_string_contains(result["errors"][0], "bindings.fire: needs a pad binding")
	# Add the replacement first, then the old one can go.
	var added: Dictionary = _default.with_bound(&"fire", "pad:button:7")
	var swapped: Dictionary = (added["profile"] as ControlProfile).with_unbound(&"fire", "pad:button:0")
	assert_true(swapped["ok"], str(swapped["errors"]))
	assert_eq((swapped["profile"] as ControlProfile).descriptors_for(&"fire"),
			PackedStringArray(["key:Space", "mouse:1", "pad:button:7"]))


func test_describe_action() -> void:
	assert_eq(_default.describe_action(&"fire"), "fire: pad:button:0 key:Space mouse:1 (deadzone 0.50)")
	assert_eq(_default.describe_action(&"main_left"), "main_left: pad:axis:4+ key:Q key:E (deadzone 0.05)")


func test_same_bindings_ignores_names() -> void:
	var other: ControlProfile = _default.duplicate_profile()
	other.name = "other"
	other.description = "something else"
	assert_true(_default.same_bindings(other))
	other.bindings[&"fire"] = ["pad:button:0"]
	assert_false(_default.same_bindings(other))


# --- The built-in classic layout ------------------------------------------------------------------------------


func test_m1_classic_is_the_default_with_yaw_and_roll_swapped_between_stick_and_dpad() -> void:
	var loaded: Dictionary = ControlProfiles.store.load_profile("m1_classic")
	assert_true(loaded["ok"], str(loaded["errors"]))
	var classic: ControlProfile = loaded["profile"]
	assert_string_contains(classic.description, "right stick X yaws")
	var swapped: Array[StringName] = [&"yaw_left", &"yaw_right", &"roll_left", &"roll_right"]
	for action: StringName in InputAdapter.ACTIONS:
		if swapped.has(action):
			continue
		assert_eq(classic.descriptors_for(action), _default.descriptors_for(action), "%s is unchanged" % action)
		assert_almost_eq(float(classic.deadzones[action]), float(_default.deadzones[action]), 1e-6, "%s deadzone" % action)
	assert_eq(classic.descriptors_for(&"yaw_left"), PackedStringArray(["pad:axis:2-", "key:J"]), "right stick X yaws")
	assert_eq(classic.descriptors_for(&"yaw_right"), PackedStringArray(["pad:axis:2+", "key:L"]))
	assert_eq(classic.descriptors_for(&"roll_left"), PackedStringArray(["pad:button:13", "key:Z"]), "D-pad rolls")
	assert_eq(classic.descriptors_for(&"roll_right"), PackedStringArray(["pad:button:14", "key:X"]))
	# The deadzones travel with the bindings: a stick-bound action wants the stick's, a button-bound one 0.5.
	assert_almost_eq(float(classic.deadzones[&"yaw_left"]), 0.15, 1e-6)
	assert_almost_eq(float(classic.deadzones[&"roll_left"]), 0.5, 1e-6)


# --- Helpers --------------------------------------------------------------------------------------------------


# action -> {"deadzone", "events": [[class, fields...], ...]}: every field the profile can express, exactly.
func _capture_input_map() -> Dictionary:
	var out: Dictionary = {}
	for action: StringName in InputAdapter.ACTIONS:
		var events: Array = []
		for event: InputEvent in InputMap.action_get_events(action):
			events.append(_fields(event))
		out[action] = {"deadzone": InputMap.action_get_deadzone(action), "events": events}
	return out


func _fields(event: InputEvent) -> Array:
	if event is InputEventJoypadButton:
		return ["button", event.device, (event as InputEventJoypadButton).button_index]
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return ["axis", motion.device, motion.axis, motion.axis_value]
	if event is InputEventKey:
		var key := event as InputEventKey
		return ["key", key.device, key.physical_keycode, key.keycode, key.shift_pressed, key.ctrl_pressed,
				key.alt_pressed, key.meta_pressed]
	if event is InputEventMouseButton:
		return ["mouse", event.device, (event as InputEventMouseButton).button_index]
	return ["other", event.as_text()]


func _assert_apply_refused_and_map_unchanged(profile: ControlProfile) -> void:
	var before: Dictionary = _capture_input_map()
	var errors: PackedStringArray = profile.apply_to_input_map()
	assert_gt(errors.size(), 0, "apply refuses an invalid profile")
	assert_eq(_capture_input_map(), before, "and leaves the InputMap exactly as it was")
