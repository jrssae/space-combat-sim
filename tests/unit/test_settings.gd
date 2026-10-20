extends GutTest
## Settings autoload behaviour on a scratch config file: session vs saved, round trips, rejection.

const SettingsScript := preload("res://src/autoload/settings.gd")
const CONFIG_PATH := "user://test_settings.cfg"

var settings: Node


func before_each() -> void:
	_delete_config()
	settings = SettingsScript.new()
	settings.config_path = CONFIG_PATH
	settings.joy_mappings_path = "user://test_no_such_gamecontrollerdb.txt"
	add_child_autofree(settings)


func after_all() -> void:
	_delete_config()


func test_defaults_without_a_file() -> void:
	for key: StringName in settings.keys():
		assert_eq(settings.get_value(key), settings.schema.get_default(key), String(key))
	assert_false(settings.has_unsaved())


func test_set_value_applies_but_never_writes() -> void:
	watch_signals(settings)
	assert_eq(settings.set_value(&"stick_deadzone", 0.2), OK)
	assert_almost_eq(float(settings.get_value(&"stick_deadzone")), 0.2, 1e-9)
	assert_true(settings.is_unsaved(&"stick_deadzone"))
	assert_signal_emitted_with_parameters(settings, "changed", [&"stick_deadzone", 0.2])
	assert_false(FileAccess.file_exists(CONFIG_PATH), "set_value alone must not write the config file")


func test_rejected_values_keep_old_value_and_explain() -> void:
	assert_eq(settings.set_value(&"stick_deadzone", 0.9), ERR_INVALID_PARAMETER)
	assert_string_contains(settings.get_last_error(), "stick_deadzone")
	assert_eq(settings.set_value(&"invert_y", "yes"), ERR_INVALID_PARAMETER)
	assert_string_contains(settings.get_last_error(), "bool")
	assert_eq(settings.set_value(&"nope", true), ERR_INVALID_PARAMETER)
	assert_almost_eq(float(settings.get_value(&"stick_deadzone")), 0.15, 1e-9)
	assert_false(settings.has_unsaved())


func test_every_key_round_trips_through_save_and_revert() -> void:
	var changed_values: Dictionary = {}
	for key: StringName in settings.keys():
		var value: Variant = _non_default_value(key)
		assert_eq(settings.set_value(key, value), OK, String(key))
		changed_values[key] = settings.get_value(key)
	assert_eq(settings.save(), OK)
	assert_false(settings.has_unsaved())
	# A fresh instance reading the same file sees every value.
	var fresh: Node = SettingsScript.new()
	fresh.config_path = CONFIG_PATH
	fresh.joy_mappings_path = "user://test_no_such_gamecontrollerdb.txt"
	add_child_autofree(fresh)
	for key: StringName in changed_values.keys():
		assert_eq(fresh.get_value(key), changed_values[key], String(key))


func test_revert_drops_unsaved_changes() -> void:
	settings.set_value(&"invert_y", true)
	settings.save()
	settings.set_value(&"invert_y", false)
	settings.set_value(&"camera_default", &"cockpit")
	assert_eq(settings.revert(), OK)
	assert_eq(settings.get_value(&"invert_y"), true)
	assert_eq(settings.get_value(&"camera_default"), &"chase")
	assert_false(settings.has_unsaved())


func test_reset_restores_default_for_session() -> void:
	settings.set_value(&"yaw_ramp_s", 0.5)
	settings.save()
	assert_eq(settings.reset(&"yaw_ramp_s"), OK)
	assert_almost_eq(float(settings.get_value(&"yaw_ramp_s")), 0.25, 1e-9)
	assert_true(settings.is_unsaved(&"yaw_ramp_s"))


func test_set_from_text() -> void:
	assert_eq(settings.set_from_text(&"show_fps", "on"), OK)
	assert_eq(settings.get_value(&"show_fps"), true)
	assert_eq(settings.set_from_text(&"stick_deadzone", "0.9"), ERR_INVALID_PARAMETER)


func test_renamed_key_in_an_old_file_is_migrated() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "roll_ramp_s", 0.5)  # saved before the yaw/roll swap
	cfg.save(CONFIG_PATH)
	settings.revert()
	assert_almost_eq(float(settings.get_value(&"yaw_ramp_s")), 0.5, 1e-9, "the old value carries over")
	assert_false(settings.has_unsaved())
	assert_eq(settings.save(), OK)
	var saved := ConfigFile.new()
	assert_eq(saved.load(CONFIG_PATH), OK)
	assert_false(saved.has_section_key("settings", "roll_ramp_s"), "save writes only the current name")
	assert_almost_eq(float(saved.get_value("settings", "yaw_ramp_s")), 0.5, 1e-9)


func test_current_key_wins_over_a_renamed_one() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "roll_ramp_s", 0.5)
	cfg.set_value("settings", "yaw_ramp_s", 0.75)
	cfg.save(CONFIG_PATH)
	settings.revert()
	assert_almost_eq(float(settings.get_value(&"yaw_ramp_s")), 0.75, 1e-9)


func test_invalid_file_values_fall_back_to_defaults() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "stick_deadzone", 5.0)
	cfg.set_value("settings", "invert_y", true)
	cfg.save(CONFIG_PATH)
	settings.revert()
	assert_almost_eq(float(settings.get_value(&"stick_deadzone")), 0.15, 1e-9)
	assert_eq(settings.get_value(&"invert_y"), true)


func test_pad_calibration_is_data_and_persists() -> void:
	assert_eq(settings.get_trigger_rest("abc", 0.0), 0.0)
	settings.set_trigger_rest("abc", -1.0)
	settings.save()
	var fresh: Node = SettingsScript.new()
	fresh.config_path = CONFIG_PATH
	fresh.joy_mappings_path = "user://test_no_such_gamecontrollerdb.txt"
	add_child_autofree(fresh)
	assert_eq(fresh.get_trigger_rest("abc", 0.0), -1.0)
	assert_false(fresh.schema.has_key(&"abc"))


func _non_default_value(key: StringName) -> Variant:
	var schema: SettingsSchema = settings.schema
	var entry: Dictionary = schema.get_entry(key)
	match schema.get_type(key):
		TYPE_BOOL:
			return not bool(entry["default"])
		TYPE_FLOAT:
			return (float(entry["min"]) + float(entry["max"])) * 0.5 + 0.01
		SettingsSchema.TYPE_ENUM:
			for choice: StringName in entry["choices"]:
				if choice != entry["default"]:
					return choice
	return entry["default"]


func _delete_config() -> void:
	if FileAccess.file_exists(CONFIG_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CONFIG_PATH))
