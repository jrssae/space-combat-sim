extends GutTest
## ConsoleCompleter (architecture §6.4): command names, then provider paths, setting keys and enum values.

const DebugConsoleScript := preload("res://src/autoload/debug_console.gd")
const SettingsScript := preload("res://src/autoload/settings.gd")

var registry: ConsoleRegistry


func before_each() -> void:
	registry = ConsoleRegistry.new()
	# Settings is not added to the tree, so it never reads or writes a config file.
	var settings: Node = SettingsScript.new()
	autofree(settings)
	registry.register_provider(&"settings", DebugConsoleScript.settings_vars(settings), settings)
	registry.register_provider(&"ship", ConsoleVars.new({
		&"speed": {"get": func() -> float: return 1.0, "unit": "m/s"},
		&"spin": {"get": func() -> float: return 0.0},
	}))
	var value_arg: ConsoleArg = ConsoleArg.string_rest(&"value")
	value_arg.value_of = 0
	var commands: Array[ConsoleCommand] = [
		ConsoleCommand.new(&"help", "", [ConsoleArg.string_optional(&"command").with_suggestions(_names)]),
		ConsoleCommand.new(&"get", "", [ConsoleArg.path_required(&"path")]),
		ConsoleCommand.new(&"set", "", [ConsoleArg.path_required(&"path", ConsoleArg.PathFilter.WRITABLE), value_arg]),
		ConsoleCommand.new(&"toggle", "", [ConsoleArg.path_required(&"path", ConsoleArg.PathFilter.WRITABLE_BOOL)]),
		ConsoleCommand.new(&"state", "", [ConsoleArg.string_optional(&"provider")]),
		ConsoleCommand.new(&"camera", "", [ConsoleArg.enum_optional(&"mode", [&"cockpit", &"chase"])]),
		ConsoleCommand.new(&"fps", "", [ConsoleArg.bool_optional(&"state")]),
		ConsoleCommand.new(&"rebase", "", [ConsoleArg.vec3_required(&"offset")]),
	]
	for command: ConsoleCommand in commands:
		registry.register_command(command, func(_a: Dictionary) -> void: pass)


func _names() -> PackedStringArray:
	var out := PackedStringArray()
	for command_name: StringName in registry.command_names():
		out.append(String(command_name))
	return out


func _complete(partial: String) -> Array:
	return Array(registry.complete(partial))


func test_command_names() -> void:
	assert_eq(_complete("he"), ["help "])
	assert_eq(_complete("s"), ["set ", "state "], "sorted")
	assert_eq(_complete("").size(), 8, "an empty line offers every command")
	assert_eq(_complete("HE"), ["help "], "case-insensitive")
	assert_eq(_complete("zz"), [])


func test_provider_paths_then_keys() -> void:
	assert_eq(_complete("get "), ["get settings.", "get ship."])
	assert_eq(_complete("get se"), ["get settings."], "a provider continues into its keys: no trailing space")
	assert_eq(_complete("get ship."), ["get ship.speed ", "get ship.spin "])
	assert_eq(_complete("get ship.sp"), ["get ship.speed ", "get ship.spin "])
	assert_eq(_complete("get ship.spe"), ["get ship.speed "])
	assert_eq(_complete("get nope."), [], "unknown provider")


func test_setting_keys() -> void:
	assert_eq(_complete("get settings.stick"), ["get settings.stick_deadzone "])
	var keys: Array = _complete("get settings.")
	assert_eq(keys.size(), SettingsSchema.ENTRIES.size(), "every schema key completes")
	assert_has(keys, "get settings.console_pause_on_open ")


func test_path_filters_narrow_candidates() -> void:
	assert_eq(_complete("set "), ["set settings."], "ship has no writable keys")
	assert_does_not_have(_complete("toggle settings."), "toggle settings.stick_deadzone ", "floats do not toggle")
	assert_has(_complete("toggle settings."), "toggle settings.invert_y ")


func test_enum_and_bool_values_of_the_key_being_set() -> void:
	assert_eq(_complete("set settings.camera_default "),
			["set settings.camera_default chase ", "set settings.camera_default cockpit "])
	assert_eq(_complete("set settings.camera_default co"), ["set settings.camera_default cockpit "])
	assert_eq(_complete("set settings.invert_y o"), ["set settings.invert_y off ", "set settings.invert_y on "])
	assert_eq(_complete("set settings.stick_deadzone "), [], "free-form numbers have no candidates")


func test_enum_and_bool_arguments() -> void:
	assert_eq(_complete("camera c"), ["camera chase ", "camera cockpit "])
	assert_eq(_complete("fps o"), ["fps off ", "fps on "])
	assert_eq(_complete("rebase 1 "), [], "numbers have no candidates")
	assert_eq(_complete("camera chase "), [], "nothing after the last argument")


func test_suggestion_callables() -> void:
	assert_eq(_complete("help ge"), ["help get "])


func test_completes_the_last_statement_only() -> void:
	assert_eq(_complete("help; get sh"), ["help; get ship."])
	assert_eq(_complete("help # get sh"), [], "nothing completes inside a comment")


func test_unknown_command_has_no_argument_candidates() -> void:
	assert_eq(_complete("nope "), [])


func test_candidates_with_spaces_are_quoted() -> void:
	registry.register_command(ConsoleCommand.new(&"target", "",
			[ConsoleArg.enum_required(&"name", func() -> Array: return ["NAV ALPHA", "NAV BRAVO", "none"])]),
			func(_a: Dictionary) -> void: pass)
	assert_eq(_complete("target N"), ["target \"NAV ALPHA\" ", "target \"NAV BRAVO\" ", "target none "])
	assert_eq(_complete("target \"NAV B"), ["target \"NAV BRAVO\" "], "an open quote completes")
