extends GutTest
## PadLayout (M10-T63): the layout a pad is guessed to have, the printed labels per layout, the face-button swap for pads
## Godot reports by label, and that names shown to the player follow the active layout.

const SWITCH_GUID: String = "0500d71f7e0500000920000000006803"  # the maintainer's pad in Switch mode (Bluetooth, hid-nintendo)
const XBOX_360_GUID: String = "030000005e0400008e02000014010000"
const XBOX_ONE_GUID: String = "030000005e040000130b000001050000"
const DUALSENSE_GUID: String = "030000004c050000e60c000011810000"

var _saved: StringName


func before_each() -> void:
	_saved = PadLayout.active


func after_each() -> void:
	PadLayout.active = _saved


func test_a_nintendo_pad_is_found_by_its_guid_vendor_or_its_name() -> void:
	assert_eq(PadLayout.vendor_of(SWITCH_GUID), 0x057e)
	assert_eq(PadLayout.detect("Nintendo Switch Pro Controller", SWITCH_GUID), PadLayout.SWITCH)
	assert_eq(PadLayout.detect("Whatever", SWITCH_GUID), PadLayout.SWITCH, "the vendor alone is enough")
	assert_eq(PadLayout.detect("Pro Controller", ""), PadLayout.SWITCH, "so is the name")


func test_the_other_families_are_found() -> void:
	assert_eq(PadLayout.detect("Xbox 360 Controller", XBOX_360_GUID), PadLayout.XBOX_360)
	assert_eq(PadLayout.detect("Xbox Wireless Controller", XBOX_ONE_GUID), PadLayout.XBOX_ONE)
	assert_eq(PadLayout.detect("Microsoft X-Box pad", ""), PadLayout.XBOX_360)
	assert_eq(PadLayout.detect("Sony DualSense", DUALSENSE_GUID), PadLayout.PLAYSTATION)
	assert_eq(PadLayout.detect("Wireless Controller", DUALSENSE_GUID), PadLayout.PLAYSTATION)
	assert_eq(PadLayout.detect("Some Pad", "03000000aaaaaaaaaaaaaaaaaaaaaaaa"), PadLayout.GENERIC)
	assert_eq(PadLayout.detect("", ""), PadLayout.GENERIC)


func test_a_guid_without_ids_gives_no_vendor() -> void:
	assert_eq(PadLayout.vendor_of("4d6f636b6564205061640000000000ff"), 0, "the name bytes are not a vendor")
	assert_eq(PadLayout.vendor_of("short"), 0)


func test_auto_follows_the_pad_and_a_manual_pick_wins() -> void:
	assert_eq(PadLayout.resolve(PadLayout.AUTO, PadLayout.SWITCH), PadLayout.SWITCH)
	assert_eq(PadLayout.resolve(PadLayout.PLAYSTATION, PadLayout.SWITCH), PadLayout.PLAYSTATION)
	assert_eq(PadLayout.resolve(PadLayout.AUTO, &""), PadLayout.XBOX_360, "no pad: the layout the game was built on")
	assert_eq(PadLayout.setting_text(PadLayout.AUTO, PadLayout.SWITCH), "Auto (detected: Nintendo Switch)")
	assert_eq(PadLayout.setting_text(PadLayout.XBOX_ONE, PadLayout.SWITCH), "Xbox One/Series")


func test_every_layout_prints_its_own_labels_by_position() -> void:
	var expected: Dictionary = {
		PadLayout.XBOX_360: ["A", "B", "X", "Y", "LB", "RB", "LT", "RT", "Back", "Start"],
		PadLayout.XBOX_ONE: ["A", "B", "X", "Y", "LB", "RB", "LT", "RT", "View", "Menu"],
		PadLayout.SWITCH: ["B", "A", "Y", "X", "L", "R", "ZL", "ZR", "-", "+"],
		PadLayout.PLAYSTATION: ["Cross", "Circle", "Square", "Triangle", "L1", "R1", "L2", "R2", "Share", "Options"],
		PadLayout.GENERIC: ["A", "B", "X", "Y", "LB", "RB", "LT", "RT", "Back", "Start"],
	}
	var parts: Array[StringName] = [&"a", &"b", &"x", &"y", &"lb", &"rb", &"lt", &"rt", &"back", &"start"]
	for layout: StringName in expected:
		for i: int in parts.size():
			assert_eq(PadLegend.tag_of(parts[i], layout), expected[layout][i], "%s %s" % [layout, parts[i]])
	assert_eq(PadLegend.tag_of(&"ls", PadLayout.SWITCH), "L stick", "sticks are named the same on every pad")


func test_only_a_pad_that_reports_by_label_swaps_its_face_buttons() -> void:
	for index: int in 15:
		assert_eq(PadLayout.button_index(PadLayout.XBOX_360, index), index)
	assert_eq([0, 1, 2, 3, 4, 9, 11].map(func(i: int) -> int: return PadLayout.button_index(PadLayout.SWITCH, i)), [1, 0, 3, 2, 4, 9, 11])
	assert_eq(PadLayout.button_index(PadLayout.SWITCH, PadLayout.button_index(PadLayout.SWITCH, 2)), 2, "its own inverse")


func test_prompts_name_the_button_of_the_active_layout() -> void:
	var fire: Array[InputEvent] = []
	var press := InputEventJoypadButton.new()
	press.button_index = JOY_BUTTON_A
	fire.append(press)
	PadLayout.active = PadLayout.XBOX_360
	assert_eq(BindingNames.short(fire), "A")
	PadLayout.active = PadLayout.SWITCH
	assert_eq(BindingNames.short(fire), "B", "the bottom button of a Switch pad is printed B")
	PadLayout.active = PadLayout.PLAYSTATION
	assert_eq(BindingNames.short(fire), "CROSS")
	var trigger := InputEventJoypadMotion.new()
	trigger.axis = JOY_AXIS_TRIGGER_LEFT
	trigger.axis_value = 1.0
	PadLayout.active = PadLayout.SWITCH
	assert_eq(BindingNames.pad_name(trigger), "ZL")
	assert_eq(ControlsModel.binding_text("pad:button:6"), "+")


func test_the_menus_own_actions_follow_a_swapping_layout_and_back() -> void:
	var accept: InputEventJoypadButton = null
	for event: InputEvent in InputMap.action_get_events(&"ui_accept"):
		if event is InputEventJoypadButton:
			accept = event as InputEventJoypadButton
	assert_not_null(accept, "Godot binds ui_accept to a pad button")
	var before: int = accept.button_index
	PadUiBindings.retarget(PadLayout.XBOX_360, PadLayout.PLAYSTATION)
	assert_eq(accept.button_index, before, "no change between layouts that read alike")
	PadUiBindings.retarget(PadLayout.XBOX_360, PadLayout.SWITCH)
	assert_eq(accept.button_index, PadLayout.button_index(PadLayout.SWITCH, before))
	PadUiBindings.retarget(PadLayout.SWITCH, PadLayout.XBOX_360)
	assert_eq(accept.button_index, before, "restored")


func test_the_setting_accepts_every_choice() -> void:
	var schema := SettingsSchema.new()
	assert_eq(schema.get_default(&"pad_layout"), &"auto")
	for choice: StringName in PadLayout.CHOICES:
		assert_true(schema.validate(&"pad_layout", String(choice))["ok"], String(choice))
	assert_false(schema.validate(&"pad_layout", "atari")["ok"])
