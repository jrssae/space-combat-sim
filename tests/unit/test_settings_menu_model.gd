extends GutTest
## SettingsMenuModel (M5-T03, D57): the settings screen's rows come from the schema, grouped by category with the console-only
## entries left out; each type gets a control kind, and the D-pad steps and the value texts are decided here, not by the screen.

var model: SettingsMenuModel


func before_each() -> void:
	model = SettingsMenuModel.new()


func _row(key: StringName) -> Dictionary:
	return model.row(key)


func test_sections_follow_the_category_order_and_leave_out_the_empty_ones() -> void:
	var sections: Array[Dictionary] = model.sections()
	var seen: Array[StringName] = []
	for section: Dictionary in sections:
		seen.append(section["category"])
		assert_gt((section["rows"] as Array).size(), 0, "%s is not empty" % section["category"])
	var expected: Array[StringName] = []
	for category: StringName in SettingsSchema.CATEGORIES:
		if not model.schema.menu_keys(category).is_empty():
			expected.append(category)
	assert_eq(seen, expected)
	assert_eq(sections[0]["title"], "Flight")


func test_hidden_entries_are_not_rows() -> void:
	var keys: Array[StringName] = model.visible_keys()
	assert_false(keys.has(&"physics_jitter_fix"))
	assert_false(keys.has(&"scenario"))
	assert_false(keys.has(&"control_profile"))
	assert_true(keys.has(&"invert_y"))
	assert_eq(keys.size(), model.schema.menu_keys().size())
	for section: Dictionary in model.sections():
		for row: Dictionary in section["rows"]:
			assert_true(model.schema.is_menu(row["key"]))
			assert_eq(model.schema.category_of(row["key"]), section["category"], "%s sits in its category" % row["key"])


func test_a_row_kind_fits_the_type() -> void:
	assert_eq(_row(&"invert_y")["kind"], SettingsMenuModel.KIND_TOGGLE)
	assert_eq(_row(&"stick_deadzone")["kind"], SettingsMenuModel.KIND_SLIDER)
	assert_eq(_row(&"engine_voice_cap")["kind"], SettingsMenuModel.KIND_SLIDER, "a whole number is a slider too")
	assert_eq(_row(&"camera_default")["kind"], SettingsMenuModel.KIND_CHOICE)
	assert_eq(_row(&"camera_default")["choices"], [&"chase", &"cockpit"])
	assert_eq(_row(&"stick_deadzone")["min"], 0.0)
	assert_eq(_row(&"stick_deadzone")["max"], 0.30)
	assert_eq(_row(&"stick_deadzone")["step"], 0.01)
	assert_eq(_row(&"invert_y")["label"], "Invert pitch")
	assert_eq(_row(&"invert_y")["default"], false)


func test_every_visible_row_has_a_kind_label_and_doc() -> void:
	for key: StringName in model.visible_keys():
		var row: Dictionary = _row(key)
		assert_true([SettingsMenuModel.KIND_TOGGLE, SettingsMenuModel.KIND_SLIDER, SettingsMenuModel.KIND_CHOICE].has(row["kind"]), String(key))
		assert_false(String(row["label"]).is_empty(), String(key))
		assert_false(String(row["doc"]).is_empty(), String(key))


# --- Stepping ----------------------------------------------------------------------------------------------------


func test_left_and_right_set_a_toggle_off_and_on() -> void:
	assert_eq(model.next_value(&"invert_y", false, 1), true)
	assert_eq(model.next_value(&"invert_y", true, 1), true, "right on an on switch leaves it on")
	assert_eq(model.next_value(&"invert_y", true, -1), false)
	assert_eq(model.next_value(&"invert_y", false, -1), false)
	assert_eq(model.flipped(&"invert_y", false), true, "A flips whichever way it stands")
	assert_eq(model.flipped(&"invert_y", true), false)


func test_a_slider_moves_one_step_and_stops_at_its_ends() -> void:
	assert_almost_eq(float(model.next_value(&"stick_deadzone", 0.15, 1)), 0.16, 1e-9)
	assert_almost_eq(float(model.next_value(&"stick_deadzone", 0.15, -1)), 0.14, 1e-9)
	assert_almost_eq(float(model.next_value(&"stick_deadzone", 0.30, 1)), 0.30, 1e-9, "the top stays the top")
	assert_almost_eq(float(model.next_value(&"stick_deadzone", 0.0, -1)), 0.0, 1e-9)


func test_repeated_steps_do_not_drift() -> void:
	var value: float = 0.0
	for i: int in 30:
		value = float(model.next_value(&"stick_deadzone", value, 1))
	assert_almost_eq(value, 0.30, 1e-9, "thirty steps of 0.01 land on the top, not 0.3000000004")
	assert_true(model.schema.validate(&"stick_deadzone", value)["ok"])
	for i: int in 30:
		value = float(model.next_value(&"stick_deadzone", value, -1))
	assert_almost_eq(value, 0.0, 1e-9)


func test_a_value_off_the_grid_snaps_to_it_in_the_direction_of_the_step() -> void:
	assert_almost_eq(float(model.next_value(&"stick_deadzone", 0.123, 1)), 0.13, 1e-9)
	assert_almost_eq(float(model.next_value(&"stick_deadzone", 0.123, -1)), 0.12, 1e-9)


func test_a_slider_starting_from_a_nonzero_minimum_steps_from_it() -> void:
	assert_almost_eq(float(model.next_value(&"target_hold_s", 0.35, 1)), 0.40, 1e-9)
	assert_almost_eq(float(model.next_value(&"target_hold_s", 0.15, -1)), 0.15, 1e-9)
	assert_almost_eq(float(model.next_value(&"target_hold_s", 1.0, 1)), 1.0, 1e-9)


func test_a_whole_number_slider_steps_by_whole_numbers() -> void:
	var up: Variant = model.next_value(&"engine_voice_cap", 24, 1)
	assert_typeof(up, TYPE_INT)
	assert_eq(up, 24 + int(model.schema.step_of(&"engine_voice_cap")))
	assert_eq(model.next_value(&"engine_voice_cap", 8, -1), 8)
	assert_eq(model.next_value(&"engine_voice_cap", 64, 1), 64)


func test_every_slider_can_walk_from_end_to_end_with_values_the_schema_accepts() -> void:
	for key: StringName in model.visible_keys():
		if _row(key)["kind"] != SettingsMenuModel.KIND_SLIDER:
			continue
		var value: Variant = model.schema.get_entry(key)["min"]
		var steps: int = 0
		while steps < 200:
			var next: Variant = model.next_value(key, value, 1)
			assert_true(model.schema.validate(key, next)["ok"], "%s: %s is a legal value" % [key, next])
			if next == value:
				break
			value = next
			steps += 1
		assert_almost_eq(float(value), float(model.schema.get_entry(key)["max"]), 1e-6, "%s reaches its top" % key)
		assert_lt(steps, 200, "%s takes under 200 presses" % key)


func test_a_choice_cycles_and_wraps() -> void:
	assert_eq(model.next_value(&"camera_default", &"chase", 1), &"cockpit")
	assert_eq(model.next_value(&"camera_default", &"cockpit", 1), &"chase", "past the last is the first")
	assert_eq(model.next_value(&"camera_default", &"chase", -1), &"cockpit", "before the first is the last")


# --- Text ------------------------------------------------------------------------------------------------------


func test_values_read_as_words_numbers_or_percentages() -> void:
	assert_eq(model.format_value(&"invert_y", true), "On")
	assert_eq(model.format_value(&"invert_y", false), "Off")
	assert_eq(model.format_value(&"camera_default", &"cockpit"), "Cockpit")
	assert_eq(model.format_value(&"stick_deadzone", 0.15), "0.15")
	assert_eq(model.format_value(&"target_hold_s", 1.0), "1")
	assert_eq(model.format_value(&"sfx_volume", 0.8), "80%", "a volume reads as a percentage")
	assert_eq(model.format_value(&"master_volume", 1.0), "100%")
	assert_eq(model.format_value(&"engine_voice_cap", 24), "24")
	assert_eq(model.format_value(&"splat_budget", 2000000), "2,000,000")


func test_the_help_text_says_what_the_entry_does_its_default_and_range() -> void:
	var text: String = model.help_text(&"stick_deadzone")
	assert_string_contains(text, "deadzone")
	assert_string_contains(text, "Default: 0.15")
	assert_string_contains(text, "Range: 0 to 0.3")
	assert_string_contains(model.help_text(&"camera_default"), "Default: Chase")
	assert_string_contains(model.help_text(&"invert_y"), "Default: Off")
	assert_string_contains(model.help_text(&"sfx_volume"), "Range: 0% to 100%")


func test_task_ids_are_not_shown_to_the_player() -> void:
	for key: StringName in model.visible_keys():
		var text: String = model.help_text(key)
		var tag := RegEx.create_from_string("M\\d+-T\\d+")
		assert_null(tag.search(text), "%s: '%s' has no task id" % [key, text])
