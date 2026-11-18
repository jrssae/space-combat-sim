extends GutTest
## `ControlCheckRunner` (M8 D80, D79, Q3): the checks run in order; a missed check is never failed: its hint is said again
## after its delay, its demo asked for after a second one, and then it waits for as long as the player takes.

const DT: float = 0.5

var runner: ControlCheckRunner
var state: Dictionary


func before_each() -> void:
	runner = ControlCheckRunner.new()
	state = {"lights": true, "assist": true}


func _check(id: String, field: String, demo: String = "") -> ControlCheck:
	var made: Dictionary = ControlCheck.from_dict({"id": id, "label": id.to_upper(), "actions": ["brake"], "events": [],
			"kind": "state", "when": [{"field": field, "op": "changed"}], "hint_line": "say_" + id, "demo": demo, "repeat_s": 10.0})
	assert_true(bool(made["ok"]), str(made["error"]))
	return made["check"] as ControlCheck


func _tick(seconds: float = DT) -> void:
	var sample := ControlCheckSample.new()
	sample.state = state.duplicate()
	var left: float = seconds
	while left > 1e-6:
		runner.tick(DT, sample)
		left -= DT


func _kinds() -> Array:
	return runner.take_requests().map(func(request: Dictionary) -> String: return "%s %s" % [request["kind"], request["check"]])


func test_checks_run_in_order_each_with_its_hint() -> void:
	runner.start([_check("lights", "lights"), _check("assist", "assist")] as Array[ControlCheck])
	assert_true(runner.is_active())
	_tick()
	assert_eq(_kinds(), ["hint lights"], "the hint is said as the check opens")
	assert_eq(runner.remaining(), [&"assist"] as Array[StringName])
	state["assist"] = false
	_tick()
	assert_eq(runner.current.id, &"lights", "the second check's control does not pass the first")
	state["lights"] = false
	_tick()
	assert_eq(_kinds(), ["passed lights"])
	assert_eq(runner.current.id, &"assist", "and what was done before a check opened does not pass it")
	_tick()
	assert_eq(_kinds(), ["hint assist"])
	state["assist"] = true
	_tick()
	assert_eq(_kinds(), ["passed assist"])
	assert_false(runner.is_active())
	assert_eq(runner.passed_ids, [&"lights", &"assist"] as Array[StringName])
	assert_eq(runner.phase(), &"idle")


func test_a_missed_check_repeats_its_hint_then_asks_for_the_demo_then_waits() -> void:
	runner.start([_check("roll", "lights", "roll")] as Array[ControlCheck])
	_tick()
	var first: Array[Dictionary] = runner.take_requests()
	assert_eq(first.size(), 1)
	assert_eq(first[0], {"kind": &"hint", "check": &"roll", "line": &"say_roll", "demo": &"roll"})
	assert_eq(runner.phase(), &"hint")
	_tick(9.0)
	assert_eq(_kinds(), [], "inside the delay nothing is said")
	_tick(1.0)
	assert_eq(_kinds(), ["hint roll"], "missed once: the hint again")
	assert_eq(runner.phase(), &"repeat")
	assert_eq(runner.misses, 1)
	_tick(10.0)
	assert_eq(_kinds(), ["demo roll"], "missed twice: the instructor shows it")
	assert_eq(runner.phase(), &"demo")
	_tick(120.0)
	assert_eq(_kinds(), [], "then it waits: no third reminder, and no failure")
	assert_true(runner.is_active())
	assert_eq([runner.hints, runner.demos, runner.misses], [2, 1, 2])
	state["lights"] = false
	_tick()
	assert_eq(_kinds(), ["passed roll"], "however late, it passes")
	assert_false(runner.is_active())


func test_a_check_without_a_demo_gets_its_hint_a_third_time() -> void:
	runner.start([_check("lights", "lights")] as Array[ControlCheck])
	_tick(20.5)
	assert_eq(_kinds(), ["hint lights", "hint lights", "hint lights"])
	assert_eq(runner.phase(), &"waiting")
	assert_eq(runner.demos, 0)
	_tick(60.0)
	assert_eq(_kinds(), [])


func test_the_delay_starts_over_with_each_check() -> void:
	runner.start([_check("lights", "lights"), _check("assist", "assist")] as Array[ControlCheck])
	_tick(8.0)
	state["lights"] = false
	_tick()
	runner.take_requests()
	_tick(9.0)
	assert_eq(_kinds(), ["hint assist"], "9 s into the second check: only its opening hint")
	assert_eq(runner.misses, 0)


func test_passing_from_outside_and_stopping() -> void:
	runner.start([_check("lights", "lights"), _check("assist", "assist")] as Array[ControlCheck])
	assert_false(runner.pass_current(&"assist"), "another check is open")
	assert_true(runner.pass_current(&"lights"))
	assert_eq(runner.current.id, &"assist")
	assert_eq(_kinds(), ["passed lights"])
	runner.pass_all()
	assert_false(runner.is_active())
	assert_false(runner.pass_current(), "nothing open")
	assert_eq(_kinds(), ["passed assist"])
	runner.start([_check("lights", "lights")] as Array[ControlCheck])
	_tick()
	runner.stop()
	assert_false(runner.is_active())
	assert_eq(_kinds(), [], "a stopped list asks for nothing more")
	assert_eq(runner.passed_ids, [&"lights", &"assist"] as Array[StringName], "what was passed stays on the record")


func test_a_tick_without_a_sample_changes_nothing() -> void:
	runner.start([_check("lights", "lights")] as Array[ControlCheck])
	runner.tick(100.0, null)
	assert_eq(_kinds(), [])
	assert_eq(runner.misses, 0)
