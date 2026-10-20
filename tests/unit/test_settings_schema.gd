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
	for key: StringName in [&"invert_y", &"stick_deadzone", &"trigger_deadzone", &"roll_ramp_s",
			&"assist_default", &"camera_default", &"show_overlay", &"show_fps", &"console_enabled",
			&"console_pause_on_open", &"camera_chase_smoothing_s"]:
		assert_true(schema.has_key(key), "schema has %s" % key)


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
	var result: Dictionary = schema.validate(&"roll_ramp_s", 1)
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
