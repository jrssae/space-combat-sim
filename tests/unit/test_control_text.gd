extends GutTest
## `ControlText` (M8-T33): a line's `{action:...}` placeholders read as the control bound now, on the device the pilot uses.

const PAD: InputSource.Device = InputSource.Device.PAD
const KEYS: InputSource.Device = InputSource.Device.KEYS

var bound: Dictionary = {}  # action -> Array[InputEvent]


func before_each() -> void:
	bound = {
		&"autotrack": [_button(JOY_BUTTON_X), _key(KEY_SHIFT), _mouse(MOUSE_BUTTON_XBUTTON1)],
		&"target_cycle": [_button(JOY_BUTTON_B)],
		&"target_next": [_key(KEY_B), _mouse(MOUSE_BUTTON_RIGHT)],
		&"toggle_camera": [_key(KEY_V)],
		&"nothing": [],
	}


func _events(action: StringName) -> Array:
	return bound.get(action, [])


func _button(index: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = index
	return e


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


func _mouse(index: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = index
	return e


func _read(text: String, device: InputSource.Device) -> String:
	return ControlText.resolve(text, device, _events)


func test_a_placeholder_reads_as_the_pads_glyph_or_as_the_key_and_the_mouse_button() -> void:
	assert_eq(_read("Tap {action:autotrack}. Auto-track the buoy.", PAD), "Tap X. Auto-track the buoy.")
	assert_eq(_read("Tap {action:autotrack}. Auto-track the buoy.", KEYS), "Tap SHIFT / MOUSE 4. Auto-track the buoy.")
	assert_eq(_read("Hold {action:autotrack} now. Then {action:autotrack} again.", PAD), "Hold X now. Then X again.", "a hold, and twice")


func test_of_several_actions_the_first_the_device_binds_is_named() -> void:
	var line: String = "Hold {action:target_cycle,target_next} and pick NAV ONE."
	assert_eq(_read(line, PAD), "Hold B and pick NAV ONE.")
	assert_eq(_read(line, KEYS), "Hold B / RMB and pick NAV ONE.")
	assert_eq(_read("{action: target_cycle , target_next }", KEYS), "B / RMB", "spaces round the names do not matter")


func test_a_rebind_shows_the_new_control() -> void:
	bound[&"target_next"] = [_key(KEY_K)]
	bound[&"target_cycle"] = [_button(JOY_BUTTON_Y)]
	assert_eq(_read("Hold {action:target_cycle,target_next}.", KEYS), "Hold K.")
	assert_eq(_read("Hold {action:target_cycle,target_next}.", PAD), "Hold Y.")


func test_a_device_with_no_binding_falls_back_to_the_other_and_nothing_bound_says_so() -> void:
	assert_eq(_read("Press {action:toggle_camera}.", PAD), "Press V.", "the pad binds none: the key is still the truth")
	assert_eq(_read("Press {action:nothing}.", PAD), "Press NOT BOUND.")
	assert_eq(_read("Press {action:no_such_action}.", KEYS), "Press NOT BOUND.")


func test_text_without_a_placeholder_or_with_an_open_one_is_left_alone() -> void:
	assert_eq(_read("Alpha One, {instructor}. Form up.", PAD), "Alpha One, {instructor}. Form up.", "other placeholders are not its own")
	assert_eq(_read("Broken {action:autotrack", PAD), "Broken {action:autotrack")


func test_the_placeholders_and_the_prose_of_a_line_can_be_read_apart() -> void:
	var line: String = "Tap {action:autotrack}, then hold {action:target_cycle,target_next}."
	assert_eq(ControlText.placeholders(line), [PackedStringArray(["autotrack"]), PackedStringArray(["target_cycle", "target_next"])])
	assert_eq(ControlText.prose(line), "Tap , then hold .")
	assert_eq(ControlText.placeholders("No control here.").size(), 0)


func test_the_live_input_map_is_read_when_no_events_are_handed_in() -> void:
	ControlProfiles.store.default_profile().apply_to_input_map()
	assert_eq(ControlText.resolve("{action:autotrack}", PAD), BindingNames.first(InputMap.action_get_events(&"autotrack"), BindingNames.pad_name))
	assert_ne(ControlText.resolve("{action:autotrack}", KEYS), ControlText.UNBOUND)
