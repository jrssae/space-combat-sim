class_name ConsoleResult
extends RefCounted
## What one console statement produced (architecture §6.4): an ok flag, output lines, an error message, and the
## control requests that only the caller can carry out (wait, inject statements, quit), so the registry stays pure.

var ok: bool = true
## Error message when `ok` is false (printed as `[console] error: ...` on stderr).
var error: String = ""
## Normal output lines (printed as `[console] ...` on stdout).
var lines: PackedStringArray = PackedStringArray()
## The statement as it was run, re-quoted from its tokens (the `> ...` echo).
var command_text: String = ""
## Control: suspend the rest of the queue for this many physics frames (`wait`).
var wait_frames: int = 0
## Control: quit with this exit code (`quit`); -1 means no quit.
var quit_code: int = -1
## Control: statements to run next, before anything already queued (`exec`).
var inject: Array[PackedStringArray] = []
## Set by `ConsoleRegistry.execute` when it stops at a `wait`: the statements it did not run yet.
var remaining: Array[PackedStringArray] = []


static func success(output: PackedStringArray = PackedStringArray()) -> ConsoleResult:
	var result := ConsoleResult.new()
	result.lines = output
	return result


static func line(text: String) -> ConsoleResult:
	return ConsoleResult.success(PackedStringArray([text]))


static func failure(message: String, output: PackedStringArray = PackedStringArray()) -> ConsoleResult:
	var result := ConsoleResult.new()
	result.ok = false
	result.error = message
	result.lines = output
	return result


## Normalises whatever a command handler returned: a ConsoleResult, a String (one line, empty for none), an
## Array/PackedStringArray of lines, or null (success without output). Errors must be `ConsoleResult.failure`.
static func from_value(value: Variant) -> ConsoleResult:
	if value is ConsoleResult:
		return value as ConsoleResult
	match typeof(value):
		TYPE_NIL:
			return ConsoleResult.success()
		TYPE_STRING, TYPE_STRING_NAME:
			var text := String(value)
			return ConsoleResult.success() if text.is_empty() else ConsoleResult.line(text)
		TYPE_PACKED_STRING_ARRAY:
			return ConsoleResult.success(value as PackedStringArray)
		TYPE_ARRAY:
			var out := PackedStringArray()
			for item: Variant in value as Array:
				out.append(str(item))
			return ConsoleResult.success(out)
	return ConsoleResult.line(str(value))


## Everything the result printed, error last, one line each (tests and logs).
func text() -> String:
	var all := PackedStringArray(lines)
	if not ok:
		all.append("error: " + error)
	return "\n".join(all)
