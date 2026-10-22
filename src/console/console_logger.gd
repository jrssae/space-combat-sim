class_name ConsoleLogger
extends Logger
## Routes engine errors and warnings into the console log (architecture §6.4). Registered with `OS.add_logger()`.
## Godot calls `_log_error` from any thread, possibly at the same time, so this only appends to a Mutex-guarded
## queue; the DebugConsole drains it on the main thread each frame. Plain prints (`_log_message`) are not captured:
## they include the console's own `[console]` mirror on stdout.

## Oldest entries are dropped beyond this, so a flood of errors cannot grow memory without bound.
const MAX_QUEUED: int = 256

var _mutex: Mutex = Mutex.new()
var _queue: Array[Dictionary] = []
var _dropped: int = 0


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	var entry: Dictionary = {
		"text": format_error(function, file, line, code, rationale, error_type, script_backtraces),
		"warning": error_type == ERROR_TYPE_WARNING,
	}
	_mutex.lock()
	if _queue.size() >= MAX_QUEUED:
		_queue.pop_front()
		_dropped += 1
	_queue.append(entry)
	_mutex.unlock()


## Everything queued since the last drain, oldest first: [{"text": String, "warning": bool}]. Main thread only.
func drain() -> Array[Dictionary]:
	_mutex.lock()
	var out: Array[Dictionary] = _queue
	_queue = []
	var dropped: int = _dropped
	_dropped = 0
	_mutex.unlock()
	if dropped > 0:
		out.push_front({"text": "(%d older engine messages dropped)" % dropped, "warning": true})
	return out


## "ERROR: message (res://file.gd:12)", preferring the script location when there is one.
static func format_error(function: String, file: String, line: int, code: String, rationale: String,
		error_type: int, script_backtraces: Array[ScriptBacktrace]) -> String:
	var prefix: String = "ERROR"
	match error_type:
		ERROR_TYPE_WARNING:
			prefix = "WARNING"
		ERROR_TYPE_SCRIPT:
			prefix = "SCRIPT ERROR"
		ERROR_TYPE_SHADER:
			prefix = "SHADER ERROR"
	var message: String = rationale if not rationale.is_empty() else code
	var where: String = "%s:%d" % [file, line]
	for backtrace: ScriptBacktrace in script_backtraces:
		if backtrace != null and backtrace.get_frame_count() > 0:
			where = "%s:%d" % [backtrace.get_frame_file(0), backtrace.get_frame_line(0)]
			break
	if function.is_empty() and file.is_empty():
		return "%s: %s" % [prefix, message]
	return "%s: %s (%s)" % [prefix, message, where]
