class_name ControlCheckConsole
extends RefCounted
## The console side of the control checks (M8 D80): provider `checks` and the command
## `checks [status|list|pass|start|stop] [id]`. Registered by the `MissionRunner`, so both exist while a mission runs.

const ACTIONS: Array[StringName] = [&"status", &"list", &"pass", &"start", &"stop"]


static func register(registry: ConsoleRegistry, runner: MissionRunner) -> void:
	registry.register_provider(&"checks", provider(runner), runner)
	registry.register_command(ConsoleCommand.new(&"checks",
			"The tutorial's control checks: status (the open one), list (every check with its live bindings), pass [id] (pass "
			+ "the open check, for scripts), start <id> (open one outside the script), stop (drop the open ones)",
			[ConsoleArg.enum_optional(&"action", ACTIONS, &"status"),
			ConsoleArg.string_optional(&"id", "").with_suggestions(func() -> PackedStringArray: return _ids(runner))]),
			func(args: Dictionary) -> ConsoleResult: return run(runner, args), runner)


static func provider(runner: MissionRunner) -> ConsoleVars:
	return ConsoleVars.new({
		&"active": {"get": func() -> bool: return runner.api.checks.is_active(), "doc": "A check is open"},
		&"current": {"get": func() -> String: return _current_id(runner), "doc": "The open check, or none"},
		&"hint": {"get": func() -> String: return _hint(runner), "doc": "The HUD's hint for it, with the live bindings"},
		&"measured": {"get": func() -> String: return _measured(runner), "doc": "What the open check has measured so far"},
		&"progress": {"get": func() -> float: return runner.api.checks.current.progress if runner.api.checks.is_active() else 0.0,
				"doc": "How far the open check has come, 0..1"},
		&"phase": {"get": func() -> String: return String(runner.api.checks.phase()),
				"doc": "hint, repeat (said again), demo or waiting (asked twice), idle"},
		&"misses": {"get": func() -> int: return runner.api.checks.misses, "doc": "Times the open check ran out its delay"},
		&"waited_s": {"get": func() -> float: return runner.api.checks.waited_s, "unit": "s",
				"doc": "Since the open check's last hint or demo"},
		&"remaining": {"get": func() -> PackedStringArray: return _names(runner.api.checks.remaining()),
				"doc": "The checks still to come"},
		&"passed": {"get": func() -> PackedStringArray: return _names(runner.api.checks.passed_ids), "doc": "The checks passed so far"},
		&"hints": {"get": func() -> int: return runner.api.checks.hints, "doc": "Hints said"},
		&"demos": {"get": func() -> int: return runner.api.checks.demos, "doc": "Demos asked of the instructor"},
		&"count": {"get": func() -> int: return _ids(runner).size(), "doc": "Checks in data/checks/controls.json"},
	})


## Handler of `checks ...`.
static func run(runner: MissionRunner, args: Dictionary) -> ConsoleResult:
	var action := StringName(args[&"action"])
	var id := StringName(String(args[&"id"]).strip_edges())
	var api: MissionApi = runner.api
	if id != &"" and action != &"pass" and action != &"start":
		return ConsoleResult.failure("checks %s takes no id" % action)
	match action:
		&"status":
			if not api.checks.is_active():
				return ConsoleResult.line("no check open; %d passed" % api.checks.passed_ids.size())
			return ConsoleResult.success(PackedStringArray([
				"%s: %s" % [_current_id(runner), _hint(runner)],
				"%s; %s, %d missed, %.1f s" % [_measured(runner), api.checks.phase(), api.checks.misses, api.checks.waited_s],
				"then %s" % (", ".join(_names(api.checks.remaining())) if not api.checks.remaining().is_empty() else "nothing")]))
		&"list":
			var lines := PackedStringArray()
			for check_id: String in _ids(runner):
				lines.append("%s  %s" % [check_id, ControlHintText.line(api.check_book.make(StringName(check_id)))])
			return ConsoleResult.success(lines if not lines.is_empty() else PackedStringArray(["no checks loaded"]))
		&"pass":
			var was: String = _current_id(runner)
			if not api.checks.pass_current(id):
				return ConsoleResult.failure("no check open" if not api.checks.is_active() else "the open check is %s, not %s" % [was, id])
			return ConsoleResult.line("passed %s; now %s" % [was, _current_id(runner)])
		&"start":
			var made: ControlCheck = api.check_book.make(id) if api.check_book != null else null
			if made == null:
				return ConsoleResult.failure("usage: checks start <id>" if id == &"" else "no check '%s'%s" % [id,
						ConsoleFormat.did_you_mean(String(id), _ids(runner))])
			if api.checks.is_active():
				return ConsoleResult.failure("check %s is open: pass or stop it first" % _current_id(runner))
			api.checks.start([made] as Array[ControlCheck])
			return ConsoleResult.line("%s: %s" % [id, ControlHintText.line(made)])
		&"stop":
			api.checks.stop()
			return ConsoleResult.line("no check open")
	return ConsoleResult.failure("unknown action %s" % action)


static func _current_id(runner: MissionRunner) -> String:
	return String(runner.api.checks.current.id) if runner.api.checks.is_active() else "none"


static func _hint(runner: MissionRunner) -> String:
	return ControlHintText.line(runner.api.checks.current) if runner.api.checks.is_active() else "none"


static func _measured(runner: MissionRunner) -> String:
	return runner.api.checks.current.describe() if runner.api.checks.is_active() else "none"


static func _ids(runner: MissionRunner) -> PackedStringArray:
	return _names(runner.api.check_book.ids()) if runner.api != null and runner.api.check_book != null else PackedStringArray()


static func _names(ids: Array[StringName]) -> PackedStringArray:
	var out := PackedStringArray()
	for id: StringName in ids:
		out.append(String(id))
	return out
