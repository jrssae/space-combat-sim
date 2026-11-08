extends GutTest

var schema: SettingsSchema


func before_each() -> void:
	schema = SettingsSchema.new()


func test_every_key_has_a_valid_default() -> void:
	assert_gt(schema.keys().size(), 0)
	for key: StringName in schema.keys():
		var result: Dictionary = schema.validate(key, schema.get_default(key))
		assert_true(result["ok"], "default of %s validates: %s" % [key, result["error"]])


func test_m1_schema_keys_present() -> void:
	for key: StringName in [&"invert_y", &"stick_deadzone", &"trigger_deadzone", &"target_hold_s",
			&"assist_default", &"camera_default", &"show_overlay", &"show_fps", &"console_enabled",
			&"console_pause_on_open", &"camera_chase_smoothing_s"]:
		assert_true(schema.has_key(key), "schema has %s" % key)


func test_fuel_unlimited_is_a_bool_that_defaults_to_true() -> void:
	assert_true(schema.has_key(&"fuel_unlimited"))
	assert_eq(schema.get_type(&"fuel_unlimited"), TYPE_BOOL)
	assert_true(schema.get_default(&"fuel_unlimited"), "the M1 decision: unlimited fuel for now")
	assert_eq(schema.parse(&"fuel_unlimited", "off")["value"], false)
	assert_eq(schema.parse(&"fuel_unlimited", "on")["value"], true)
	assert_false(schema.parse(&"fuel_unlimited", "maybe")["ok"])


func test_renamed_keys_point_at_current_keys() -> void:
	for old: StringName in SettingsSchema.RENAMED.keys():
		assert_false(schema.has_key(old), "%s is no longer a key" % old)
		assert_true(schema.has_key(SettingsSchema.RENAMED[old]), "%s maps to a current key" % old)
	assert_eq(schema.old_names(&"invert_y"), [] as Array[StringName])


func test_the_dpad_yaw_ramp_is_gone() -> void:
	# M3-T15: the right stick yaws, so the D-pad ramp (yaw_ramp_s, before it roll_ramp_s) has no user left.
	assert_false(schema.has_key(&"yaw_ramp_s"))
	assert_false(schema.has_key(&"roll_ramp_s"))
	assert_false(SettingsSchema.RENAMED.has(&"roll_ramp_s"))


func test_target_hold_range() -> void:
	assert_almost_eq(float(schema.get_default(&"target_hold_s")), 0.35, 1e-9)
	assert_true(schema.parse(&"target_hold_s", "0.5")["ok"])
	assert_false(schema.parse(&"target_hold_s", "0.05")["ok"], "too short to tell from a tap")
	assert_false(schema.parse(&"target_hold_s", "2")["ok"])


func test_chase_camera_smoothing_is_rigid_by_default_and_limited_to_half_a_second() -> void:
	assert_eq(schema.get_default(&"camera_chase_smoothing_s"), 0.0, "locked to the ship unless asked otherwise")
	assert_true(schema.parse(&"camera_chase_smoothing_s", "0")["ok"])
	assert_true(schema.parse(&"camera_chase_smoothing_s", "0.5")["ok"])
	assert_false(schema.parse(&"camera_chase_smoothing_s", "0.6")["ok"])
	assert_false(schema.parse(&"camera_chase_smoothing_s", "-0.1")["ok"])
	assert_eq(schema.describe(&"camera_chase_smoothing_s"), "float 0.0..0.5")


func test_bool_parse_accepts_words() -> void:
	for word: String in ["true", "on", "1", "ON", " yes "]:
		assert_eq(schema.parse(&"invert_y", word)["value"], true, word)
	for word: String in ["false", "off", "0", "No"]:
		assert_eq(schema.parse(&"invert_y", word)["value"], false, word)
	var bad: Dictionary = schema.parse(&"invert_y", "maybe")
	assert_false(bad["ok"])
	assert_string_contains(bad["error"], "invert_y")


func test_float_range_enforced() -> void:
	assert_true(schema.parse(&"stick_deadzone", "0.2")["ok"])
	assert_almost_eq(float(schema.parse(&"stick_deadzone", "0.2")["value"]), 0.2, 1e-9)
	var too_big: Dictionary = schema.parse(&"stick_deadzone", "0.9")
	assert_false(too_big["ok"])
	assert_string_contains(too_big["error"], "0.3")
	assert_false(schema.parse(&"stick_deadzone", "fast")["ok"])
	assert_false(schema.validate(&"stick_deadzone", -0.01)["ok"])


func test_int_is_coerced_to_float() -> void:
	var result: Dictionary = schema.validate(&"target_hold_s", 1)
	assert_true(result["ok"])
	assert_eq(typeof(result["value"]), TYPE_FLOAT)


func test_wrong_type_rejected_with_message() -> void:
	var result: Dictionary = schema.validate(&"invert_y", 1.0)
	assert_false(result["ok"])
	assert_string_contains(result["error"], "bool")
	assert_false(schema.validate(&"stick_deadzone", "0.1")["ok"])


func test_enum_choices() -> void:
	assert_eq(schema.parse(&"camera_default", "Cockpit")["value"], &"cockpit")
	var bad: Dictionary = schema.parse(&"camera_default", "orbit")
	assert_false(bad["ok"])
	assert_string_contains(bad["error"], "chase|cockpit")


func test_unknown_key() -> void:
	assert_false(schema.validate(&"warp_drive", true)["ok"])
	assert_false(schema.has_key(&"warp_drive"))
	assert_eq(schema.describe(&"warp_drive"), "unknown")


func test_control_profile_is_a_string_with_a_pattern() -> void:
	assert_true(schema.has_key(&"control_profile"))
	assert_eq(schema.get_type(&"control_profile"), TYPE_STRING)
	assert_eq(schema.get_default(&"control_profile"), "default")
	assert_eq(schema.describe(&"control_profile"), "string ^[a-z0-9_]{1,32}$")
	for good: String in ["default", "m1_classic", "mine2", "a"]:
		var result: Dictionary = schema.parse(&"control_profile", good)
		assert_true(result["ok"], good)
		assert_eq(result["value"], good)
	for bad: String in ["", "Mine", "two words", "x".repeat(33), "../evil", "a-b"]:
		var result: Dictionary = schema.parse(&"control_profile", bad)
		assert_false(result["ok"], "'%s'" % bad)
		assert_string_contains(result["error"], "control_profile must match ^[a-z0-9_]{1,32}$")
	assert_true(schema.validate(&"control_profile", &"mine")["ok"], "a StringName is text too")
	assert_eq(schema.validate(&"control_profile", &"mine")["value"], "mine", "and is stored as a String")
	assert_false(schema.validate(&"control_profile", 3)["ok"])
	assert_string_contains(schema.validate(&"control_profile", 3)["error"], "expects text")


func test_an_int_setting_validates_parses_and_describes() -> void:
	assert_eq(schema.get_type(&"ai_nearest_k"), TYPE_INT)
	assert_eq(schema.get_default(&"ai_nearest_k"), 12)
	assert_eq(schema.describe(&"ai_nearest_k"), "int 0..64")
	assert_eq(schema.validate(&"ai_nearest_k", 30)["value"], 30)
	assert_eq(typeof(schema.validate(&"ai_nearest_k", 30.0)["value"]), TYPE_INT, "a whole float is an int")
	assert_false(schema.validate(&"ai_nearest_k", 30.5)["ok"])
	assert_false(schema.validate(&"ai_nearest_k", -1)["ok"])
	assert_false(schema.validate(&"ai_nearest_k", 65)["ok"])
	assert_false(schema.validate(&"ai_nearest_k", "many")["ok"])
	assert_eq(schema.parse(&"ai_nearest_k", "20")["value"], 20)
	assert_false(schema.parse(&"ai_nearest_k", "1.5")["ok"])
	assert_false(schema.parse(&"ai_nearest_k", "many")["ok"])


# --- M4-T24: the simulation step's schedule and the catch-up cap --------------------------------------------------------


func test_sim_step_is_an_enum_of_the_two_schedules_and_defaults_to_threaded() -> void:
	assert_true(schema.has_key(&"sim_step"), "sim_step is a setting")
	assert_eq(schema.get_type(&"sim_step"), SettingsSchema.TYPE_ENUM)
	assert_eq(schema.get_choices(&"sim_step"), [&"delayed", &"threaded"])
	assert_eq(schema.get_default(&"sim_step"), &"threaded", "the AI step runs on the worker thread by default (Q53)")
	assert_false(schema.parse(&"sim_step", "inline")["ok"], "the single-thread inline step is gone (M4-T37)")
	assert_false(schema.parse(&"sim_step", "parallel")["ok"])


func test_the_catch_up_cap_is_an_int_of_at_least_one_tick_a_frame() -> void:
	assert_true(schema.has_key(&"physics_max_steps_per_frame"), "physics_max_steps_per_frame is a setting")
	assert_eq(schema.get_type(&"physics_max_steps_per_frame"), TYPE_INT)
	assert_eq(schema.get_default(&"physics_max_steps_per_frame"), 3)
	assert_false(schema.validate(&"physics_max_steps_per_frame", 0)["ok"], "a frame runs at least one tick")
	assert_true(schema.validate(&"physics_max_steps_per_frame", 8)["ok"], "Godot's default of 8 stays allowed")


# --- Menu metadata (M5-T03, D57): every entry has a category, debug switches stay out of the menu ---------------------


func test_every_entry_has_a_known_category() -> void:
	for key: StringName in schema.keys():
		var category: Variant = schema.get_entry(key).get("category")
		assert_true(category is StringName, "%s has a category" % key)
		assert_true(SettingsSchema.CATEGORIES.has(category), "%s: '%s' is a known category" % [key, category])
		assert_eq(schema.category_of(key), category)


func test_every_category_is_used() -> void:
	for category: StringName in SettingsSchema.CATEGORIES:
		var used: bool = false
		for key: StringName in schema.keys():
			used = used or schema.category_of(key) == category
		assert_true(used, "nothing is filed under %s" % category)


func test_the_menu_flag_is_a_bool_and_defaults_to_shown() -> void:
	for key: StringName in schema.keys():
		var entry: Dictionary = schema.get_entry(key)
		assert_true(not entry.has("menu") or entry["menu"] is bool, "%s: menu is a bool" % key)
		assert_eq(schema.is_menu(key), bool(entry.get("menu", true)))


func test_the_debug_switches_stay_console_only() -> void:
	for key: StringName in [&"physics_jitter_fix", &"show_fps", &"show_overlay",
			&"debug_text_size", &"console_enabled", &"console_pause_on_open", &"scenario", &"skip_front_end", &"control_profile"]:
		assert_false(schema.is_menu(key), "%s is not in the menu" % key)
	for key: StringName in [&"invert_y", &"sfx_volume", &"camera_default", &"show_hud", &"lens_flare", &"friendly_fire"]:
		assert_true(schema.is_menu(key), "%s is in the menu" % key)


func test_a_menu_entry_has_a_control_the_pad_can_use() -> void:
	# Text has no pad editor (the controls page owns the profile name), so a string setting must stay out of the menu.
	for key: StringName in schema.menu_keys():
		assert_ne(schema.get_type(key), TYPE_STRING, "%s is text and cannot be edited on a pad" % key)
		assert_false(schema.label_of(key).is_empty(), "%s has a label" % key)
		if schema.get_type(key) == TYPE_FLOAT or schema.get_type(key) == TYPE_INT:
			assert_gt(schema.step_of(key), 0.0, "%s has a step" % key)


func test_the_steps_fit_the_ranges() -> void:
	for key: StringName in schema.keys():
		var type: int = schema.get_type(key)
		if type != TYPE_FLOAT and type != TYPE_INT:
			continue
		var entry: Dictionary = schema.get_entry(key)
		var span: float = float(entry["max"]) - float(entry["min"])
		assert_gt(schema.step_of(key), 0.0, "%s: step above zero" % key)
		assert_lte(schema.step_of(key), span, "%s: a step fits in the range" % key)
		assert_gte(span / schema.step_of(key), 4.0, "%s: at least four steps, or a slider is pointless" % key)
		assert_lte(span / schema.step_of(key), 100.0, "%s: at most a hundred steps, or the D-pad takes forever" % key)


func test_menu_keys_come_in_declaration_order_within_a_category() -> void:
	var flight: Array[StringName] = schema.menu_keys(&"flight")
	assert_eq(flight, [&"assist_default", &"fuel_unlimited"] as Array[StringName])
	assert_eq(schema.menu_keys(&"none_such"), [] as Array[StringName])
	assert_eq(schema.menu_keys().size(), _count_menu_entries())


func test_the_four_bus_volumes_are_settings_from_zero_to_one() -> void:
	for key: StringName in [&"master_volume", &"sfx_volume", &"ui_volume", &"comms_volume"]:
		assert_true(schema.has_key(key), key)
		assert_eq(schema.get_type(key), TYPE_FLOAT)
		assert_eq(schema.category_of(key), &"audio")
		assert_true(schema.is_menu(key))
		assert_true(schema.validate(key, 0.0)["ok"])
		assert_true(schema.validate(key, 1.0)["ok"])
		assert_false(schema.validate(key, 1.01)["ok"])


func _count_menu_entries() -> int:
	var n: int = 0
	for key: StringName in schema.keys():
		n += 1 if bool(schema.get_entry(key).get("menu", true)) else 0
	return n
