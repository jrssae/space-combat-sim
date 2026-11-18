extends GutTest
## A test run never sees the player's saved settings (M7-T47): GUT starts from the schema's defaults whatever
## `user://settings.cfg` holds, and never writes it. The player's file is stood in for by a scratch file here, so the real
## one is never touched.

const SettingsScript := preload("res://src/autoload/settings.gd")
const PLAYER_PATH := "user://test_settings_isolation_player.cfg"
const NO_PADS := "user://test_no_such_gamecontrollerdb.txt"

## Values a player might have saved, each off its default.
const ODD: Dictionary = {
	&"friendly_fire": false,
	&"motion_blur": false,
	&"stick_deadzone": 0.27,
	&"camera_default": &"cockpit",
	&"scenario": &"station_launch",
	&"chase_bolt_scale": 7.5,
	&"invert_y": true,
}


func before_each() -> void:
	_delete_player_file()


func after_all() -> void:
	_delete_player_file()


func test_this_gut_run_is_a_test_run() -> void:
	assert_true(Settings.test_run, "the Settings autoload knows it runs under GUT")
	assert_eq(OS.get_environment(SettingsScript.TEST_RUN_ENV), "1", "Godot processes the run starts inherit it")


func test_what_counts_as_a_test_run() -> void:
	assert_true(SettingsScript.is_test_run(PackedStringArray(["--headless", "-s", "addons/gut/gut_cmdln.gd", "-gexit"]), ""))
	assert_true(SettingsScript.is_test_run(PackedStringArray(["-s", "res://addons/gut/gut_cmdln.gd"]), ""))
	assert_true(SettingsScript.is_test_run(PackedStringArray(["--headless", "--", "--console-strict"]), "1"))
	assert_false(SettingsScript.is_test_run(PackedStringArray(["--path", "."]), ""))
	assert_false(SettingsScript.is_test_run(PackedStringArray(["--path", "."]), "0"))


func test_a_saved_player_file_with_odd_values_does_not_reach_a_test_run() -> void:
	_write_player_file()
	var saved_text: String = FileAccess.get_file_as_string(PLAYER_PATH)
	# The file is a real saved settings file: the game outside a test run would load it.
	var game: Node = _settings(false)
	for key: StringName in ODD.keys():
		assert_eq(game.get_value(key), ODD[key], "outside a test run %s comes from the file" % key)
	var under_test: Node = _settings(true)
	for key: StringName in under_test.keys():
		assert_eq(under_test.get_value(key), under_test.schema.get_default(key), "a test run starts %s at its default" % key)
	assert_eq(under_test.get_trigger_rest("pad-guid", 0.0), 0.0, "nor does the file's pad calibration reach it")
	# Saving and reverting leave the player's file alone.
	assert_eq(under_test.set_value(&"stick_deadzone", 0.05), OK)
	assert_eq(under_test.save(), OK)
	assert_false(under_test.has_unsaved())
	assert_eq(FileAccess.get_file_as_string(PLAYER_PATH), saved_text, "a test run never writes the player's file")
	assert_eq(under_test.revert(), OK)
	assert_eq(under_test.get_value(&"stick_deadzone"), under_test.schema.get_default(&"stick_deadzone"))


func test_a_test_with_a_file_of_its_own_still_saves_and_loads_it() -> void:
	var own_path: String = "user://test_settings_isolation_own.cfg"
	var first: Node = _settings(true, own_path)
	assert_eq(first.set_value(&"friendly_fire", false), OK)
	assert_eq(first.save(), OK)
	var fresh: Node = _settings(true, own_path)
	assert_false(bool(fresh.get_value(&"friendly_fire")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(own_path))


# A Settings node whose player's file is the scratch stand-in, reading `config_path` (the player's by default).
func _settings(test_run: bool, config_path: String = PLAYER_PATH) -> Node:
	var made: Node = SettingsScript.new()
	made.test_run = test_run
	made.player_config_path = PLAYER_PATH
	made.config_path = config_path
	made.joy_mappings_path = NO_PADS
	add_child_autofree(made)
	return made


# Saves the odd values the way the game saves the player's settings.
func _write_player_file() -> void:
	var writer: Node = _settings(false)
	for key: StringName in ODD.keys():
		assert_eq(writer.set_value(key, ODD[key]), OK, String(key))
	writer.set_trigger_rest("pad-guid", -1.0)
	assert_eq(writer.save(), OK)
	assert_true(FileAccess.file_exists(PLAYER_PATH))


func _delete_player_file() -> void:
	if FileAccess.file_exists(PLAYER_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PLAYER_PATH))
