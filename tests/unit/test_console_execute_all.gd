extends GutTest
## M4-T40 fix round 1: `ConsoleRegistry.execute_all` runs every statement of a set-up script at once. A command that holds the
## console (`bench` waits until its run ends, `wait` for its frames) must not swallow the statements after it, or a measure tool's
## extra statements (`FULLSCREEN_EXEC`, `RC_EXEC`) never apply during the window they are meant for.

var registry: ConsoleRegistry
var ran: Array[String] = []


func before_each() -> void:
	registry = ConsoleRegistry.new()
	ran.clear()
	registry.register_command(ConsoleCommand.new(&"hold", "Holds the console like bench", []), _cmd_hold, self)
	registry.register_command(ConsoleCommand.new(&"note", "Records its word", [ConsoleArg.string_required(&"word")]), _cmd_note, self)
	registry.register_command(ConsoleCommand.new(&"stop", "Quits", []), _cmd_stop, self)


func _cmd_hold(_args: Dictionary) -> ConsoleResult:
	ran.append("hold")
	var result := ConsoleResult.line("holding")
	result.wait_frames = 1_000_000
	return result


func _cmd_note(args: Dictionary) -> ConsoleResult:
	ran.append(String(args[&"word"]))
	return ConsoleResult.line("noted")


func _cmd_stop(_args: Dictionary) -> ConsoleResult:
	ran.append("stop")
	var result := ConsoleResult.line("bye")
	result.quit_code = 0
	return result


func test_plain_execute_stops_at_a_hold() -> void:
	var results: Array[ConsoleResult] = registry.execute("hold; note a")
	assert_eq(ran, ["hold"] as Array[String], "why execute_all exists: the rest waits for the hold to end")
	assert_eq(results[-1].remaining.size(), 1)


func test_execute_all_runs_the_statements_after_a_hold() -> void:
	var results: Array[ConsoleResult] = registry.execute_all("hold; note a; hold; note b")
	assert_eq(ran, ["hold", "a", "hold", "b"] as Array[String])
	assert_eq(results.size(), 4)
	for result: ConsoleResult in results:
		assert_true(result.remaining.is_empty(), "nothing left over")


func test_execute_all_still_stops_at_a_quit() -> void:
	registry.execute_all("note a; stop; note b")
	assert_eq(ran, ["a", "stop"] as Array[String])


func test_execute_all_reports_errors_and_goes_on() -> void:
	var results: Array[ConsoleResult] = registry.execute_all("hold; nonsense; note c")
	assert_false(results[1].ok)
	assert_eq(ran, ["hold", "c"] as Array[String])
