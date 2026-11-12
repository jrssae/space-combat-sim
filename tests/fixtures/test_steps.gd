class_name TestSteps
extends GutTest
## Test fixture (M5-T38): the helpers every scene test used to copy, so a test file extends this instead. `_ticks` waits
## whole physics ticks, `_exec` runs one console line, `_console` also asserts it was a single statement.


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _exec(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


func _console(line: String) -> ConsoleResult:
	var results: Array[ConsoleResult] = DebugConsole.registry.execute(line)
	assert_eq(results.size(), 1, "one statement: " + line)
	return results[0]
