class_name MissionConsole
extends RefCounted
## The console side of a running mission (architecture §18.4, M5-T05): provider `mission` and the command
## `mission [status|skip|goto <step>|objectives|journal]`. Registered by the `MissionRunner` while a mission runs, so in free
## flight and the sandbox neither exists and `mission ...` is an unknown command.

const ACTIONS: Array[StringName] = [&"status", &"skip", &"goto", &"objectives", &"journal"]
const JOURNAL_TAIL: int = 8


## Registers the provider and the command on `registry`, owned by `runner`.
static func register(registry: ConsoleRegistry, runner: MissionRunner) -> void:
	registry.register_provider(&"mission", provider(runner), runner)
	registry.register_command(ConsoleCommand.new(&"mission",
			"The running mission: status, skip (fast-forward this step, making what it waits for true), goto <step> (skip "
			+ "every step before it), objectives, journal (the world changes so far)",
			[ConsoleArg.enum_optional(&"action", ACTIONS, &"status"),
			ConsoleArg.string_optional(&"step", "").with_suggestions(func() -> PackedStringArray: return _step_names(runner))]),
			func(args: Dictionary) -> ConsoleResult: return run(runner, args), runner)


static func provider(runner: MissionRunner) -> ConsoleVars:
	return ConsoleVars.new({
		&"id": {"get": func() -> String: return String(runner.api.scenario_id), "doc": "The mission's scenario"},
		&"title": {"get": func() -> String: return runner.api.title, "doc": "The mission's title"},
		&"state": {"get": runner.state_name, "doc": "running, success, failure, or error (it could not start)"},
		&"result": {"get": func() -> String: return GameFlow.describe_result(runner.api.result),
				"doc": "How it ended (success or failure and why); none while it runs"},
		&"step": {"get": func() -> String: return _step_text(runner), "doc": "The step running (n/N), or done"},
		&"steps": {"get": func() -> PackedStringArray: return _step_names(runner), "doc": "Every step, in order"},
		&"time_s": {"get": func() -> float: return runner.api.time_s(), "unit": "s", "doc": "Sim time since it began"},
		&"objectives": {"get": func() -> PackedStringArray: return runner.api.book.describe_lines(),
				"doc": "Every objective: [state] id: text"},
		&"live_triggers": {"get": func() -> int: return runner.api.live_trigger_count(),
				"doc": "Triggers evaluated each tick: the awaited one and the active objectives'"},
		&"tick_work": {"get": func() -> int: return runner.api.tick_work,
				"doc": "Lookups and trigger checks in the last tick (D52's cost, counted)"},
		&"skipping": {"get": func() -> bool: return runner.api.is_skipping(), "doc": "The current step is being skipped"},
		&"waypoint": {"get": func() -> String: return runner.api.waypoint_name if not runner.api.waypoint_name.is_empty() else "none",
				"doc": "The actor the HUD's waypoint marks"},
		&"controls_locked": {"get": func() -> bool: return runner.api.controls_locked, "doc": "The script holds the player's controls"},
		&"jump_points": {"get": func() -> int: return runner.jumps.opened if runner.jumps != null else 0,
				"doc": "Jump points opened so far"},
	})


## Handler of `mission ...`.
static func run(runner: MissionRunner, args: Dictionary) -> ConsoleResult:
	var action := StringName(args[&"action"])
	var step: String = String(args[&"step"]).strip_edges()
	if not step.is_empty() and action != &"goto":
		return ConsoleResult.failure("mission %s takes no step (only mission goto <step>)" % action)
	var api: MissionApi = runner.api
	match action:
		&"status":
			return ConsoleResult.success(PackedStringArray([
				"%s: %s" % [api.scenario_id, api.title if not api.title.is_empty() else "(untitled)"],
				"state %s, step %s, %.1f s" % [runner.state_name(), _step_text(runner), api.time_s()],
				"result %s" % GameFlow.describe_result(api.result)]))
		&"skip":
			var was: String = String(api.step_name())
			var problem: String = api.skip()
			if not problem.is_empty():
				return ConsoleResult.failure(problem)
			return ConsoleResult.line("skipped %s; now %s" % [was, _step_text(runner)])
		&"goto":
			if step.is_empty():
				return ConsoleResult.failure("usage: mission goto <step> (steps: %s)" % ", ".join(_step_names(runner)))
			var problem: String = api.goto(StringName(step))
			if not problem.is_empty():
				return ConsoleResult.failure(problem + ConsoleFormat.did_you_mean(step, _step_names(runner)))
			return ConsoleResult.line("now %s" % _step_text(runner))
		&"objectives":
			var lines: PackedStringArray = api.book.describe_lines()
			return ConsoleResult.success(lines if not lines.is_empty() else PackedStringArray(["no objectives"]))
		&"journal":
			var tail := PackedStringArray()
			for i: int in range(maxi(api.journal.size() - JOURNAL_TAIL, 0), api.journal.size()):
				tail.append(api.journal[i])
			return ConsoleResult.success(tail if not tail.is_empty() else PackedStringArray(["nothing yet"]))
	return ConsoleResult.failure("unknown action %s" % action)


static func _step_names(runner: MissionRunner) -> PackedStringArray:
	var out := PackedStringArray()
	if runner.api != null:
		for step: StringName in runner.api.steps():
			out.append(String(step))
	return out


static func _step_text(runner: MissionRunner) -> String:
	var api: MissionApi = runner.api
	if api.has_ended():
		return "ended"
	var count: int = api.steps().size()
	if api.step_index() >= count and count > 0:
		return "done (the script has finished)"
	if api.step_index() < 0:
		return "not started"
	return "%s (%d/%d)" % [api.step_name(), api.step_index() + 1, count]
