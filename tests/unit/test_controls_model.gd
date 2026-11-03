extends GutTest
## ControlsModel (architecture §18, D57; M5-T04): the words the controls page uses. Pure: handcrafted profiles, no InputMap.


func _profile(table: Dictionary) -> ControlProfile:
	var profile := ControlProfile.new()
	profile.name = "test"
	for action: StringName in table:
		profile.bindings[action] = table[action]
		profile.deadzones[action] = 0.5
	return profile


# --- Action names ------------------------------------------------------------------------------------------------


func test_an_action_with_its_own_menu_name_keeps_it() -> void:
	assert_eq(ControlsModel.action_title(InputAdapter.FIRE), "Fire")
	assert_eq(ControlsModel.action_title(InputAdapter.MAIN_RIGHT), "Right main pod")


func test_actions_that_share_a_menu_name_are_told_apart_by_direction() -> void:
	assert_eq(ControlsModel.action_title(InputAdapter.PITCH_DOWN), "Pitch down")
	assert_eq(ControlsModel.action_title(InputAdapter.YAW_LEFT), "Yaw left")
	assert_eq(ControlsModel.action_title(InputAdapter.ROLL_RIGHT), "Roll right")
	assert_eq(ControlsModel.action_title(InputAdapter.STRAFE_UP), "Strafe up")


func test_every_game_action_has_a_name_of_its_own() -> void:
	var seen: Dictionary = {}
	for action: StringName in InputAdapter.ACTIONS:
		var title: String = ControlsModel.action_title(action)
		assert_false(title.is_empty(), String(action))
		assert_false(seen.has(title), "%s is the name of %s and %s" % [title, seen.get(title), action])
		seen[title] = action


# --- Bindings in words -------------------------------------------------------------------------------------------


func test_pad_buttons_are_named_as_printed_on_the_pad() -> void:
	assert_eq(ControlsModel.binding_text("pad:button:0"), "A")
	assert_eq(ControlsModel.binding_text("pad:button:9"), "LB")
	assert_eq(ControlsModel.binding_text("pad:button:11"), "D-pad up")
	assert_eq(ControlsModel.binding_text("pad:button:6"), "Start")


func test_sticks_and_triggers_are_named_with_their_direction() -> void:
	assert_eq(ControlsModel.binding_text("pad:axis:0-"), "L stick left")
	assert_eq(ControlsModel.binding_text("pad:axis:0+"), "L stick right")
	assert_eq(ControlsModel.binding_text("pad:axis:1-"), "L stick up")
	assert_eq(ControlsModel.binding_text("pad:axis:3+"), "R stick down")
	assert_eq(ControlsModel.binding_text("pad:axis:4+"), "LT")
	assert_eq(ControlsModel.binding_text("pad:axis:5+"), "RT")


func test_keys_and_mouse_buttons_are_named() -> void:
	assert_eq(ControlsModel.binding_text("key:Space"), "Key Space")
	assert_eq(ControlsModel.binding_text("mouse:1"), "Mouse left")
	assert_eq(ControlsModel.binding_text("mouse:2"), "Mouse right")
	assert_eq(ControlsModel.binding_text("mouse:3"), "Mouse middle")
	assert_eq(ControlsModel.binding_text("mouse:8"), "Mouse side 1")
	assert_eq(ControlsModel.binding_text("mouse:9"), "Mouse side 2")


func test_a_binding_it_cannot_name_is_shown_as_it_is() -> void:
	assert_eq(ControlsModel.binding_text("?Shift+E"), "?Shift+E")
	assert_eq(ControlsModel.binding_text("pad:button:99"), "pad:button:99")


func test_a_row_lists_the_action_and_all_its_bindings() -> void:
	var profile: ControlProfile = _profile({&"fire": ["pad:button:0", "key:Space", "mouse:1"], &"brake": []})
	assert_eq(ControlsModel.row_text(profile, InputAdapter.FIRE), "Fire: A, Key Space, Mouse left")
	assert_eq(ControlsModel.row_text(profile, InputAdapter.BRAKE), "Brake: (unbound)")
	assert_eq(ControlsModel.row_text(profile, InputAdapter.AUTOTRACK), "Auto-track: (unbound)", "an action the profile lacks")


func test_the_profile_row_flags_unsaved_changes() -> void:
	assert_eq(ControlsModel.profile_row_text("default", false), "Profile: default")
	assert_eq(ControlsModel.profile_row_text("mine", true), "Profile: mine (unsaved changes)")


# --- Profile names -----------------------------------------------------------------------------------------------


func test_a_new_profile_is_suggested_a_free_name() -> void:
	var builtin := PackedStringArray(["default", "m1_classic"])
	assert_eq(ControlsModel.suggested_name("default", builtin, builtin), "my_controls")
	var taken := PackedStringArray(["default", "m1_classic", "my_controls", "my_controls_2"])
	assert_eq(ControlsModel.suggested_name("default", builtin, taken), "my_controls_3")


func test_saving_over_the_profile_in_use_is_suggested_when_it_is_the_users_own() -> void:
	var builtin := PackedStringArray(["default", "m1_classic"])
	var all := PackedStringArray(["default", "m1_classic", "pilot"])
	assert_eq(ControlsModel.suggested_name("pilot", builtin, all), "pilot")
	assert_eq(ControlsModel.suggested_name("m1_classic", builtin, all), "my_controls", "a built-in cannot be saved over")


func test_a_typed_name_is_tidied_into_a_profile_name() -> void:
	assert_eq(ControlsModel.clean_name("  Pilot One "), "pilot_one")
	assert_eq(ControlsModel.clean_name("ace_1"), "ace_1")
	assert_eq(ControlsModel.clean_name(""), "")


# --- The right panel and refusals --------------------------------------------------------------------------------


func test_a_refusal_names_every_reason() -> void:
	assert_eq(ControlsModel.refusal_text(PackedStringArray(["no pad binding"])), "Not changed: no pad binding")
	assert_eq(ControlsModel.refusal_text(PackedStringArray(["one", "two"])), "Not changed:\none\ntwo")


func test_the_panel_has_the_shape_the_frame_draws() -> void:
	var panel: Dictionary = ControlsModel.panel("FIRE", ["fire: pad:button:0", "A"])
	assert_eq(panel["title"], "FIRE")
	var lines: Array = panel["lines"]
	assert_eq(lines.size(), 2)
	assert_eq(lines[0]["text"], "fire: pad:button:0")
	assert_eq(lines[1]["mark"], "")


func test_an_actions_panel_gives_the_exact_bindings_and_the_names() -> void:
	var profile: ControlProfile = _profile({&"fire": ["pad:button:0", "key:Space"]})
	var panel: Dictionary = ControlsModel.action_panel(profile, InputAdapter.FIRE)
	assert_eq(panel["title"], "FIRE")
	var texts: PackedStringArray = []
	for line: Dictionary in panel["lines"]:
		texts.append(String(line["text"]))
	assert_has(texts, "fire: pad:button:0 key:Space (deadzone 0.50)")
