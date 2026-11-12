extends GutTest
## PadLegend (architecture §18, D57, Q15): which pad button does what, read from a control profile, so the diagram in the
## menu frame follows a rebind. Pure: handcrafted profiles, no InputMap.


func _profile(table: Dictionary) -> ControlProfile:
	var profile := ControlProfile.new()
	profile.name = "test"
	for action: StringName in table:
		profile.bindings[action] = table[action]
	return profile


# --- Descriptors to widgets --------------------------------------------------------------------------------------


func test_buttons_map_to_the_xinput_layout() -> void:
	var expected: Dictionary = {
		0: &"a", 1: &"b", 2: &"x", 3: &"y", 4: &"back", 6: &"start", 7: &"l3", 8: &"r3", 9: &"lb", 10: &"rb",
		11: &"dpad_up", 12: &"dpad_down", 13: &"dpad_left", 14: &"dpad_right",
	}
	for index: int in expected:
		assert_eq(PadLegend.widget_of("pad:button:%d" % index), expected[index], "button %d" % index)


func test_axes_map_to_sticks_and_triggers() -> void:
	for descriptor: String in ["pad:axis:0-", "pad:axis:0+", "pad:axis:1-", "pad:axis:1+"]:
		assert_eq(PadLegend.widget_of(descriptor), &"ls", descriptor)
	for descriptor: String in ["pad:axis:2-", "pad:axis:2+", "pad:axis:3-", "pad:axis:3+"]:
		assert_eq(PadLegend.widget_of(descriptor), &"rs", descriptor)
	assert_eq(PadLegend.widget_of("pad:axis:4+"), &"lt")
	assert_eq(PadLegend.widget_of("pad:axis:5+"), &"rt")


func test_keys_mouse_and_nonsense_have_no_pad_widget() -> void:
	for descriptor: String in ["key:Space", "mouse:1", "pad:button:5", "pad:button:15", "pad:axis:7+", "pad:", "", "pad:button:x"]:
		assert_eq(PadLegend.widget_of(descriptor), &"", descriptor)


# --- Labels ------------------------------------------------------------------------------------------------------


func test_a_button_shows_the_action_bound_to_it() -> void:
	var legend: PadLegend = PadLegend.from_profile(_profile({
		&"fire": ["pad:button:0", "key:Space", "mouse:1"],
		&"toggle_camera": ["pad:button:3"],
	}))
	assert_eq(legend.label_for(&"a"), "Fire")
	assert_eq(legend.label_for(&"y"), "Camera")
	assert_eq(legend.actions_for(&"a"), [&"fire"] as Array[StringName])
	assert_eq(legend.label_for(&"b"), "", "nothing is bound to B")


func test_keyboard_and_mouse_bindings_do_not_reach_the_pad() -> void:
	var legend: PadLegend = PadLegend.from_profile(_profile({&"fire": ["key:Space", "mouse:1"]}))
	assert_eq(legend.widgets().size(), 0)


func test_the_four_strafe_actions_make_one_stick_label() -> void:
	var legend: PadLegend = PadLegend.from_profile(_profile({
		&"strafe_left": ["pad:axis:0-"], &"strafe_right": ["pad:axis:0+"],
		&"strafe_down": ["pad:axis:1+"], &"strafe_up": ["pad:axis:1-"],
	}))
	assert_eq(legend.label_for(&"ls"), "Strafe", "a label once, however many directions")
	assert_eq(legend.widgets(), [&"ls"] as Array[StringName])


func test_one_widget_with_several_actions_lists_them_in_action_order() -> void:
	var legend: PadLegend = PadLegend.from_profile(_profile({
		&"yaw_left": ["pad:axis:2-"], &"pitch_up": ["pad:axis:3-"], &"roll_left": ["pad:axis:2-"],
	}))
	assert_eq(legend.label_for(&"rs"), "Pitch / Yaw / Roll", "the order of InputAdapter.ACTIONS, not of the profile")


func test_an_action_on_two_buttons_shows_on_both() -> void:
	var legend: PadLegend = PadLegend.from_profile(_profile({&"retro_left": ["pad:button:9", "pad:button:13"]}))
	assert_eq(legend.label_for(&"lb"), "Left retro")
	assert_eq(legend.label_for(&"dpad_left"), "Left retro")
	assert_eq(legend.widgets_for(&"retro_left"), [&"lb", &"dpad_left"] as Array[StringName])


func test_widgets_come_in_diagram_order() -> void:
	var legend: PadLegend = PadLegend.from_profile(_profile({
		&"pause": ["pad:button:6"], &"main_right": ["pad:axis:5+"], &"fire": ["pad:button:0"], &"main_left": ["pad:axis:4+"],
	}))
	assert_eq(legend.widgets(), [&"lt", &"rt", &"a", &"start"] as Array[StringName], "PadLegend.WIDGETS order")


func test_widgets_for_names_where_an_action_sits_and_nothing_for_the_unbound() -> void:
	var legend: PadLegend = PadLegend.from_profile(_profile({&"fire": ["pad:button:0"]}))
	assert_eq(legend.widgets_for(&"fire"), [&"a"] as Array[StringName])
	assert_eq(legend.widgets_for(&"brake"), [] as Array[StringName])
	assert_eq(legend.widgets_for(&"no_such_action"), [] as Array[StringName])


# --- Following a rebind ------------------------------------------------------------------------------------------


func test_a_rebind_moves_the_label_to_the_new_button() -> void:
	var profile: ControlProfile = _profile({&"fire": ["pad:button:0"]})
	assert_eq(PadLegend.from_profile(profile).label_for(&"a"), "Fire")
	profile.bindings[&"fire"] = ["pad:button:2"]
	var after: PadLegend = PadLegend.from_profile(profile)
	assert_eq(after.label_for(&"a"), "", "A no longer fires")
	assert_eq(after.label_for(&"x"), "Fire", "X does")


# --- Wording -----------------------------------------------------------------------------------------------------


func test_every_game_action_has_a_menu_label() -> void:
	for action: StringName in InputAdapter.ACTIONS:
		assert_true(PadLegend.ACTION_LABELS.has(action), "%s needs a label in PadLegend.ACTION_LABELS" % action)


func test_an_action_without_a_label_shows_a_readable_name() -> void:
	assert_eq(PadLegend.label_of_action(&"toggle_something_new"), "Toggle Something New")
	assert_eq(PadLegend.label_of_action(&"fire"), "Fire")


func test_every_widget_has_a_tag_for_the_diagram() -> void:
	for widget: StringName in PadLegend.WIDGETS:
		assert_false(PadLegend.tag_of(widget).is_empty(), String(widget))
	assert_eq(PadLegend.tag_of(&"dpad_up"), "D-pad up")
