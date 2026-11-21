extends GutTest
## The control hint's words (M8 D80): the pad's and the keyboard's live bindings of a check's actions, named as the
## interaction prompt names them, and following a rebind.

var _saved: ControlProfile = null


func before_all() -> void:
	ControlProfiles.store.default_profile().apply_to_input_map()


func before_each() -> void:
	_saved = ControlProfile.from_input_map("saved")


func after_each() -> void:
	_saved.apply_to_input_map()


func _check(entry: Dictionary) -> ControlCheck:
	var base: Dictionary = {"id": "x", "label": "DO IT", "kind": "state", "events": [],
			"when": [{"field": "assist", "op": "set"}]}
	base.merge(entry, true)
	var made: Dictionary = ControlCheck.from_dict(base)
	assert_true(bool(made["ok"]), str(made["error"]))
	return made["check"] as ControlCheck


# Gives each action exactly these bindings in the live input map, as the controls menu does when it applies a profile.
func _rebind(edits: Dictionary) -> void:
	var profile: ControlProfile = ControlProfile.from_input_map("edit")
	for action: StringName in edits:
		profile.bindings[action] = edits[action]
	assert_eq(profile.apply_to_input_map(), PackedStringArray(), "the edited layout applies")


func test_a_pair_names_both_pad_controls_and_the_key_that_drives_both() -> void:
	var check: ControlCheck = _check({"actions": ["main_left", "main_right"], "need": "all", "label": "FIRE BOTH MAIN PODS"})
	assert_eq(ControlHintText.bindings(check), "LT + RT / W", "W is bound to both pods; the mouse has no way to press them")
	assert_eq(ControlHintText.line(check), "LT + RT / W: FIRE BOTH MAIN PODS")


func test_a_stick_is_named_with_its_way_for_one_action_and_alone_for_a_pair() -> void:
	assert_eq(ControlHintText.bindings(_check({"actions": ["strafe_left"]})), "L STICK LEFT / Z")
	assert_eq(ControlHintText.bindings(_check({"actions": ["strafe_up"]})), "L STICK UP / R")
	assert_eq(ControlHintText.bindings(_check({"actions": ["pitch_up", "pitch_down"], "keys_extra": "MOUSE"})), "R STICK / MOUSE",
			"either way on the stick; the mouse stands in for the keys")


func test_extras_name_what_no_action_binds() -> void:
	var roll: ControlCheck = _check({"actions": ["roll_left", "roll_right"], "pad_extra": "R STICK DIAGONAL"})
	assert_eq(ControlHintText.bindings(roll), "R STICK DIAGONAL / CAPSLOCK or G")


func test_hold_and_tap_lead_the_buttons_as_the_interaction_prompt_does() -> void:
	var hold: ControlCheck = _check({"actions": ["autotrack"], "press": "hold", "label": "RUN IT"})
	assert_eq(ControlHintText.line(hold), "HOLD X / SHIFT / MOUSE 4: RUN IT")
	assert_eq(ControlHintText.bindings(hold), "HOLD " + BindingNames.of_action(InputAdapter.AUTOTRACK), "the prompt line's naming")
	assert_eq(ControlHintText.bindings(_check({"actions": ["target_cycle", "target_next"], "press": "tap"})), "TAP B / B / RMB",
			"the pad's B and its keyboard twin")


func test_an_alternative_shows_each_way_in() -> void:
	assert_eq(ControlHintText.bindings(_check({"actions": ["comms_menu", "wing_form"]})), "D-PAD RIGHT / CTRL or 2")


func test_a_rebind_changes_the_hint() -> void:
	var check: ControlCheck = _check({"actions": ["toggle_flight_assist"], "label": "ASSIST OFF"})
	assert_eq(ControlHintText.line(check), "D-PAD UP / T: ASSIST OFF")
	_rebind({InputAdapter.TOGGLE_ASSIST: ["pad:button:11", "key:F9"]})
	assert_eq(ControlHintText.line(check), "D-PAD UP / F9: ASSIST OFF", "the keyboard's side follows")
	_rebind({InputAdapter.TOGGLE_CAMERA: ["pad:button:11", "key:Tab"], InputAdapter.TOGGLE_ASSIST: ["pad:button:3", "key:F9"]})
	assert_eq(ControlHintText.line(check), "Y / F9: ASSIST OFF", "and the pad's")
	var pods: ControlCheck = _check({"actions": ["main_left", "main_right"], "need": "all"})
	_rebind({InputAdapter.MAIN_LEFT: ["pad:axis:4+", "key:Q"]})
	assert_eq(ControlHintText.bindings(pods), "LT + RT / Q + E", "with no shared key left, each pod's own")


func test_an_unbound_check_says_so_and_counts_as_not_bound() -> void:
	var ahead: ControlCheck = _check({"actions": ["target_ahead"], "label": "TARGET AHEAD"})
	assert_false(ControlHintText.is_bound(ahead), "the default layout binds nothing to it")
	assert_eq(ControlHintText.line(ahead), "NOT BOUND: TARGET AHEAD")
	var prev: ControlCheck = _check({"actions": ["target_prev"], "keys_extra": "MOUSE WHEEL UP"})
	assert_true(ControlHintText.is_bound(prev), "the wheel does it")
	assert_eq(ControlHintText.bindings(prev), "MOUSE WHEEL UP")


func test_injected_events_stand_in_for_the_input_map() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_K
	var axis := InputEventJoypadMotion.new()
	axis.axis = JOY_AXIS_TRIGGER_LEFT
	axis.axis_value = 1.0
	var check: ControlCheck = _check({"actions": ["brake"], "press": "hold"})
	assert_eq(ControlHintText.bindings(check, func(_action: StringName) -> Array: return [key, axis]), "HOLD LT / K")
	assert_eq(BindingNames.pad_name(axis), "LT")
	assert_eq(BindingNames.key_name(axis), "")
