extends GutTest
## ConsoleRegistry, ConsoleCommand, ConsoleArg, ConsoleVars, ConsoleFormat and ConsoleResult (architecture §6.4):
## typed arguments and their errors, suggestions, help, the provider whitelist, owner pruning, control flow.


## Stands in for a subsystem node: has state, a setter, and methods the console must never reach by reflection.
class FakeShip:
	extends Node

	var speed: float = 42.1
	var assist_on: bool = true
	var mode: StringName = &"alternating"
	var aim: Vector3 = Vector3.ZERO
	var last_args: Dictionary = {}

	func set_assist(value: bool) -> void:
		assist_on = value

	func vars() -> ConsoleVars:
		return ConsoleVars.new({
			&"speed": {"get": func() -> float: return speed, "type": TYPE_FLOAT, "unit": "m/s"},
			&"assist_on": {"get": func() -> bool: return assist_on, "set": set_assist, "type": TYPE_BOOL},
			&"mode": {"get": func() -> StringName: return mode,
					"set": func(v: StringName) -> void: mode = v, "type": TYPE_STRING_NAME,
					"choices": [&"alternating", &"linked"]},
			&"throttle": {"get": func() -> float: return 0.5, "set": func(_v: float) -> String: return "",
					"type": TYPE_FLOAT, "min": 0.0, "max": 1.0, "reset": func() -> void: pass,
					"modified": func() -> bool: return true},
			&"aim": {"get": func() -> Vector3: return aim, "set": func(v: Vector3) -> void: aim = v,
					"type": TYPE_VECTOR3},
			&"stubborn": {"get": func() -> int: return 3, "set": func(_v: int) -> String: return "engines are offline",
					"type": TYPE_INT},
		})

	func cmd_record(args: Dictionary) -> ConsoleResult:
		last_args = args
		return ConsoleResult.line("recorded")


var registry: ConsoleRegistry
var ship: FakeShip


func before_each() -> void:
	registry = ConsoleRegistry.new()
	ship = FakeShip.new()
	autofree(ship)
	registry.register_provider(&"ship", ship.vars(), ship)


func _register_typed_command() -> void:
	registry.register_command(ConsoleCommand.new(&"probe", "Typed argument probe", [
		ConsoleArg.bool_required(&"flag"),
		ConsoleArg.int_required(&"count", 0, 10),
		ConsoleArg.float_required(&"scale", 0.05, 1.0),
		ConsoleArg.enum_required(&"mode", [&"chase", &"cockpit"]),
		ConsoleArg.vec3_required(&"offset"),
		ConsoleArg.string_optional(&"label", "none"),
	]), ship.cmd_record, ship)


func _run(line: String) -> ConsoleResult:
	var results: Array[ConsoleResult] = registry.execute(line)
	assert_eq(results.size(), 1, "one statement: %s" % line)
	return results[0]


# --- typed arguments ---------------------------------------------------------------------------------------------


func test_typed_arguments_are_parsed_to_values() -> void:
	_register_typed_command()
	var result: ConsoleResult = _run("probe on 7 0.5 COCKPIT 1 -2.5 3e3")
	assert_true(result.ok, result.text())
	assert_eq(ship.last_args[&"flag"], true)
	assert_eq(ship.last_args[&"count"], 7)
	assert_eq(typeof(ship.last_args[&"count"]), TYPE_INT)
	assert_almost_eq(float(ship.last_args[&"scale"]), 0.5, 1e-9)
	assert_eq(ship.last_args[&"mode"], &"cockpit", "enum matches case-insensitively, returns the canonical choice")
	assert_eq(ship.last_args[&"offset"], Vector3(1.0, -2.5, 3000.0))
	assert_eq(ship.last_args[&"label"], "none", "omitted optional argument gets its fallback")
	assert_eq(result.command_text, "probe on 7 0.5 COCKPIT 1 -2.5 3e3")


func test_vec3_accepts_one_comma_token_and_rest_strings() -> void:
	_register_typed_command()
	assert_true(_run("probe off 0 1 chase 1,2,3 \"two words\"").ok)
	assert_eq(ship.last_args[&"offset"], Vector3(1.0, 2.0, 3.0))
	assert_eq(ship.last_args[&"label"], "two words")


func test_typed_argument_errors_are_clear() -> void:
	_register_typed_command()
	var cases: Dictionary = {
		"probe maybe 1 0.5 chase 0 0 0": "<flag> expects on/off",
		"probe on x 0.5 chase 0 0 0": "<count> expects an integer, got 'x'",
		"probe on 11 0.5 chase 0 0 0": "<count> must be in 0..10, got 11",
		"probe on 1 abc chase 0 0 0": "<scale> expects a number, got 'abc'",
		"probe on 1 2 chase 0 0 0": "<scale> must be in 0.05..1.0, got 2.0",
		"probe on 1 0.5 cockpt 0 0 0": "<mode> expects one of chase|cockpit, got 'cockpt' (did you mean cockpit?)",
		"probe on 1 0.5 chase 0 0": "<offset> expects three numbers",
		"probe on 1 0.5 chase 0 zero 0": "<offset> expects three numbers",
		"probe on": "missing <count>",
		"probe on 1 0.5 chase 0 0 0 label extra": "too many arguments",
	}
	for line: String in cases.keys():
		var result: ConsoleResult = _run(line)
		assert_false(result.ok, line)
		assert_string_contains(result.error, cases[line])
		assert_string_contains(result.error, "(usage: probe <on|off> <count> <scale> <chase|cockpit>")
	assert_eq(ship.last_args, {}, "the handler never ran")


func test_arg_usage_strings() -> void:
	assert_eq(ConsoleArg.bool_optional(&"state").usage(), "[on|off]")
	assert_eq(ConsoleArg.path_required(&"path").usage(), "<path>")
	assert_eq(ConsoleArg.float_required(&"scale").with_hint("0.05..1").usage(), "<0.05..1>")
	assert_eq(ConsoleArg.enum_optional(&"mode", [&"cockpit", &"chase"]).usage(), "[cockpit|chase]")
	assert_eq(ConsoleArg.vec3_required(&"offset", PackedStringArray(["dx", "dy", "dz"])).usage(), "<dx> <dy> <dz>")
	var command := ConsoleCommand.new(&"quit", "Quit", [ConsoleArg.int_optional(&"code", 0)])
	assert_eq(command.usage(), "quit [code]")


func test_arg_validate_typed_values() -> void:
	var f: ConsoleArg = ConsoleArg.float_required(&"x", 0.0, 1.0)
	assert_true(f.validate(1)["ok"], "int is a valid float")
	assert_false(f.validate(1.5)["ok"])
	assert_false(f.validate(NAN)["ok"])
	assert_false(f.validate("0.5")["ok"], "validate takes typed values, not text")
	var i: ConsoleArg = ConsoleArg.int_required(&"n")
	assert_eq(i.validate(3.0)["value"], 3, "a whole float is a lossless int")
	assert_false(i.validate(3.5)["ok"])
	assert_false(ConsoleArg.bool_required(&"b").validate(1)["ok"])


# --- commands, suggestions, help ---------------------------------------------------------------------------------


func test_unknown_command_suggests_the_closest() -> void:
	registry.register_command(ConsoleCommand.new(&"help", "Help"), func(_a: Dictionary) -> String: return "", null)
	registry.register_command(ConsoleCommand.new(&"state", "State"), func(_a: Dictionary) -> String: return "", null)
	var result: ConsoleResult = _run("hepl")
	assert_false(result.ok)
	assert_string_contains(result.error, "unknown command 'hepl' (did you mean help?)")
	assert_string_contains(_run("stat").error, "did you mean state?")
	assert_false(_run("xyzzy").error.contains("did you mean"), "no wild guesses")


func test_command_names_are_case_insensitive() -> void:
	registry.register_command(ConsoleCommand.new(&"help", "Help"), func(_a: Dictionary) -> String: return "hi", null)
	assert_eq(_run("HELP").lines, PackedStringArray(["hi"]))


func test_help_lists_usage_and_summary() -> void:
	_register_typed_command()
	registry.register_command(ConsoleCommand.new(&"quit", "Quit with an exit code",
			[ConsoleArg.int_optional(&"code", 0)]), func(_a: Dictionary) -> String: return "", null)
	var lines: PackedStringArray = registry.help()
	assert_string_contains(lines[0], "commands")
	var text: String = "\n".join(lines)
	assert_string_contains(text, "quit [code]")
	assert_string_contains(text, "Quit with an exit code")
	assert_string_contains(text, "probe <on|off> <count> <scale> <chase|cockpit> <offset_x> <offset_y> <offset_z> [label]")
	var one: PackedStringArray = registry.help(&"quit")
	assert_eq(one[0], "usage: quit [code]")
	assert_string_contains(registry.help(&"quitt")[0], "did you mean quit?")


func test_handler_return_values_are_normalised() -> void:
	registry.register_command(ConsoleCommand.new(&"a", ""), func(_x: Dictionary) -> String: return "one", null)
	registry.register_command(ConsoleCommand.new(&"b", ""),
			func(_x: Dictionary) -> PackedStringArray: return PackedStringArray(["x", "y"]), null)
	registry.register_command(ConsoleCommand.new(&"c", ""), func(_x: Dictionary) -> void: pass, null)
	registry.register_command(ConsoleCommand.new(&"d", ""),
			func(_x: Dictionary) -> ConsoleResult: return ConsoleResult.failure("nope"), null)
	assert_eq(_run("a").lines, PackedStringArray(["one"]))
	assert_eq(_run("b").lines, PackedStringArray(["x", "y"]))
	assert_true(_run("c").ok)
	assert_eq(_run("c").lines.size(), 0)
	assert_eq(_run("d").error, "nope")


# --- providers ---------------------------------------------------------------------------------------------------


func test_get_formats_with_units() -> void:
	assert_eq(registry.format_path("ship.speed"), "ship.speed = 42.10 m/s")
	assert_eq(registry.format_path("ship.assist_on"), "ship.assist_on = true")


func test_provider_whitelist_never_reflects() -> void:
	var result: Dictionary = registry.resolve("ship.queue_free")
	assert_false(result["ok"])
	assert_string_contains(result["error"], "unknown key 'ship.queue_free'")
	assert_false(registry.read("ship.set_assist")["ok"], "methods are not keys")
	assert_false(registry.read("ship.last_args")["ok"], "members that were not listed are not keys")
	assert_false(registry.write_text("ship.queue_free", "1").ok)
	assert_true(is_instance_valid(ship), "nothing was called on the owner")
	assert_false(ship.is_queued_for_deletion())


func test_unknown_key_and_provider_suggest() -> void:
	assert_eq(registry.resolve("ship.sped")["error"], "unknown key 'ship.sped' (did you mean ship.speed?)")
	assert_eq(registry.resolve("shp.speed")["error"], "unknown provider 'shp' (did you mean ship?)")
	assert_string_contains(registry.resolve("ship")["error"], "is a provider, not a path")


func test_set_validates_type_range_and_choices() -> void:
	assert_true(registry.write_text("ship.assist_on", "off").ok)
	assert_false(ship.assist_on)
	assert_eq(registry.write_text("ship.mode", "LINKED").lines, PackedStringArray(["ship.mode = linked"]))
	assert_eq(ship.mode, &"linked")
	var bad_choice: ConsoleResult = registry.write_text("ship.mode", "lnked")
	assert_string_contains(bad_choice.error, "ship.mode expects one of alternating|linked, got 'lnked'")
	assert_string_contains(bad_choice.error, "did you mean linked?")
	assert_eq(registry.write_text("ship.throttle", "1.5").error, "ship.throttle must be in 0.0..1.0, got 1.5")
	assert_eq(registry.write_text("ship.speed", "3").error, "ship.speed is read-only")
	assert_eq(registry.write_text("ship.assist_on", "maybe").error,
			"ship.assist_on expects on/off (or true/false, 1/0), got 'maybe'")
	assert_true(registry.write_text("ship.aim", "1 2 3").ok)
	assert_eq(ship.aim, Vector3(1.0, 2.0, 3.0))
	assert_eq(registry.write_text("ship.stubborn", "4").error, "ship.stubborn: engines are offline",
			"a setter's refusal is reported")


func test_toggle_and_reset() -> void:
	assert_eq(registry.toggle("ship.assist_on").lines, PackedStringArray(["ship.assist_on = false"]))
	assert_eq(registry.toggle("ship.assist_on", true).lines, PackedStringArray(["ship.assist_on = true"]))
	assert_eq(registry.toggle("ship.speed").error, "ship.speed is not a bool")
	assert_true(registry.reset("ship.throttle").ok)
	assert_eq(registry.reset("ship.speed").error, "ship.speed has no default")


func test_describe_provider_marks_modified_keys() -> void:
	var lines: PackedStringArray = registry.describe_provider(&"ship")
	assert_eq(lines[0], "ship.speed = 42.10 m/s", "keys keep their declaration order")
	assert_has(Array(lines), "ship.throttle = 0.50 *")


func test_path_filters_are_checked_before_the_handler() -> void:
	registry.register_command(ConsoleCommand.new(&"flip", "",
			[ConsoleArg.path_required(&"path", ConsoleArg.PathFilter.WRITABLE_BOOL)]), ship.cmd_record, ship)
	assert_eq(_run("flip ship.speed").error, "ship.speed is not a writable bool")
	assert_eq(_run("flip ship.queue_free").error, "unknown key 'ship.queue_free'")
	assert_true(_run("flip ship.assist_on").ok)
	assert_eq(ship.last_args[&"path"], "ship.assist_on")
	var bool_keys: Array[StringName] = registry.provider_keys(&"ship", ConsoleArg.PathFilter.WRITABLE_BOOL)
	assert_eq(bool_keys.size(), 1)
	assert_eq(bool_keys[0], &"assist_on")


# --- owners ------------------------------------------------------------------------------------------------------


func test_freed_owner_is_pruned() -> void:
	var owner := FakeShip.new()
	registry.register_command(ConsoleCommand.new(&"ping", "Ping"), owner.cmd_record, owner)
	registry.register_provider(&"temp", owner.vars(), owner)
	assert_true(registry.has_command(&"ping"))
	assert_true(registry.has_provider(&"temp"))
	owner.free()
	assert_false(registry.has_command(&"ping"), "command of a freed owner is gone")
	assert_false(registry.has_provider(&"temp"), "provider of a freed owner is gone")
	assert_string_contains(_run("ping").error, "unknown command 'ping'")
	assert_true(registry.has_provider(&"ship"), "other owners are untouched")


func test_freed_refcounted_owner_is_pruned() -> void:
	var owner: RefCounted = RefCounted.new()
	registry.register_provider(&"rc", ConsoleVars.new({&"x": {"get": func() -> int: return 1}}), owner)
	assert_true(registry.has_provider(&"rc"))
	owner = null
	assert_false(registry.has_provider(&"rc"), "the registry holds owners weakly")


func test_unregister_owner_drops_only_its_entries() -> void:
	var other := FakeShip.new()
	autofree(other)
	registry.register_command(ConsoleCommand.new(&"mine", ""), ship.cmd_record, ship)
	registry.register_command(ConsoleCommand.new(&"theirs", ""), other.cmd_record, other)
	registry.unregister_owner(ship)
	assert_false(registry.has_command(&"mine"))
	assert_false(registry.has_provider(&"ship"))
	assert_true(registry.has_command(&"theirs"))


func test_replaced_entry_survives_the_old_owner_leaving() -> void:
	var newer := FakeShip.new()
	autofree(newer)
	registry.register_provider(&"ship", newer.vars(), newer)
	registry.unregister_owner(ship)
	assert_true(registry.has_provider(&"ship"), "the newer owner's provider stays")


# --- control flow ------------------------------------------------------------------------------------------------


func _register_control_commands() -> void:
	registry.register_command(ConsoleCommand.new(&"echo", "", [ConsoleArg.string_rest(&"text")]), _cmd_echo, null)
	registry.register_command(ConsoleCommand.new(&"fail", ""), _cmd_fail, null)
	registry.register_command(ConsoleCommand.new(&"wait", "", [ConsoleArg.int_required(&"frames", 0)]), _cmd_wait,
			null)
	registry.register_command(ConsoleCommand.new(&"quit", "", [ConsoleArg.int_optional(&"code", 0)]), _cmd_quit, null)
	registry.register_command(ConsoleCommand.new(&"include", ""), _cmd_include, null)


func _cmd_echo(args: Dictionary) -> String:
	return args[&"text"]


func _cmd_fail(_args: Dictionary) -> ConsoleResult:
	return ConsoleResult.failure("failed")


func _cmd_wait(args: Dictionary) -> ConsoleResult:
	var result := ConsoleResult.success()
	result.wait_frames = args[&"frames"]
	return result


func _cmd_quit(args: Dictionary) -> ConsoleResult:
	var result := ConsoleResult.success()
	result.quit_code = args[&"code"]
	return result


func _cmd_include(_args: Dictionary) -> ConsoleResult:
	var result := ConsoleResult.success()
	var injected: Array[PackedStringArray] = [PackedStringArray(["echo", "from", "file"])]
	result.inject = injected
	return result


func test_execute_runs_every_statement_in_order() -> void:
	_register_control_commands()
	var results: Array[ConsoleResult] = registry.execute("echo a; fail; echo b")
	assert_eq(results.size(), 3, "errors do not stop a line unless asked")
	assert_eq(results[0].lines, PackedStringArray(["a"]))
	assert_false(results[1].ok)
	assert_eq(results[2].lines, PackedStringArray(["b"]))
	assert_eq(registry.execute("echo a; fail; echo b", true).size(), 2, "stop_on_error stops at the error")


func test_execute_stops_at_wait_and_hands_back_the_rest() -> void:
	_register_control_commands()
	var results: Array[ConsoleResult] = registry.execute("echo a; wait 30; echo b; quit 2")
	assert_eq(results.size(), 2)
	assert_eq(results[1].wait_frames, 30)
	assert_eq(results[1].remaining.size(), 2)
	assert_eq(Array(results[1].remaining[0]), ["echo", "b"])
	var resumed: Array[ConsoleResult] = registry.execute_statements(results[1].remaining)
	assert_eq(resumed[0].lines, PackedStringArray(["b"]))
	assert_eq(resumed[1].quit_code, 2)


func test_execute_stops_at_quit_and_runs_injected_statements_first() -> void:
	_register_control_commands()
	var results: Array[ConsoleResult] = registry.execute("include; echo after; quit 3; echo never")
	assert_eq(results.size(), 4)
	assert_eq(results[1].lines, PackedStringArray(["from file"]), "injected statements run before the rest")
	assert_eq(results[2].lines, PackedStringArray(["after"]))
	assert_eq(results[3].quit_code, 3)


func test_tokenizer_errors_become_a_failed_result() -> void:
	var results: Array[ConsoleResult] = registry.execute("echo \"open")
	assert_eq(results.size(), 1)
	assert_eq(results[0].error, "unterminated quote")


# --- formatting --------------------------------------------------------------------------------------------------


func test_format_values() -> void:
	assert_eq(ConsoleFormat.value(42.1, "m/s"), "42.10 m/s")
	assert_eq(ConsoleFormat.value(Vector3(1.0, -2.345, 0.0)), "(1.00, -2.35, 0.00)")
	assert_eq(ConsoleFormat.value(Vector2(0.5, 3.0)), "(0.50, 3.00)")
	assert_eq(ConsoleFormat.value(true), "true")
	assert_eq(ConsoleFormat.value(7), "7")
	assert_eq(ConsoleFormat.value(-0.0), "0.00")
	assert_eq(ConsoleFormat.value(null), "none")
	assert_eq(ConsoleFormat.value(null, "m"), "none", "no unit after a missing value")
	assert_eq(ConsoleFormat.value(&"chase"), "chase")
	assert_eq(ConsoleFormat.value(PackedFloat64Array([1.5e11, 0.0, 2.0]), "m"), "[150000000000.00, 0.00, 2.00] m")
	assert_eq(ConsoleFormat.value({"name": "Pad", "rest": -1.0}), "{name: Pad, rest: -1.00}")
	assert_ne(ConsoleFormat.value(0.0001), "0.00", "tiny values keep their magnitude")
	assert_eq(ConsoleFormat.value(0.0001).to_float(), 0.0001)
	assert_eq(ConsoleFormat.key_value("settings.invert_y", false, "", true), "settings.invert_y = false *")


func test_suggestions() -> void:
	var words := PackedStringArray(["help", "state", "set", "save", "timescale"])
	assert_eq(ConsoleFormat.suggest("hepl", words), "help", "a transposition is one edit")
	assert_eq(ConsoleFormat.suggest("timescal", words), "timescale")
	assert_eq(ConsoleFormat.suggest("qqqq", words), "")
	assert_eq(ConsoleFormat.edit_distance("kitten", "sitting"), 3)
	assert_eq(ConsoleFormat.edit_distance("", "abc"), 3)
