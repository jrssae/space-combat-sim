class_name ControlCheckRunner
extends RefCounted
## Runs a list of control checks in order (M8 D80, D79, Q3). A check never fails: when it opens the instructor says its hint;
## still open after its delay, the hint is said again; still open after a second delay, the demo is asked for (the hint once
## more for a check without one); then it waits for as long as the player takes. Pure: `tick` takes one `ControlCheckSample` per
## physics tick, and what the mission must do (say a line, fly a demo) comes back from `take_requests`.
##
## A request is `{kind, check, line, demo}`: `hint` (say `line`), `demo` (the instructor flies `demo`) or `passed`.

const HINT: StringName = &"hint"
const DEMO: StringName = &"demo"
const PASSED: StringName = &"passed"
## An open check is asked for again this often before it is left to wait: the repeated hint, then the demo.
const MISSES_BEFORE_WAITING: int = 2

## The check open now, or null.
var current: ControlCheck = null
## How often the open check ran out its delay, and the seconds since its last hint or demo.
var misses: int = 0
var waited_s: float = 0.0
## Every check passed since the first `start`, in order, and the hints and demos asked for.
var passed_ids: Array[StringName] = []
var hints: int = 0
var demos: int = 0

var _queue: Array[ControlCheck] = []
var _requests: Array[Dictionary] = []


## Starts on `checks`, in order, dropping any list still running.
func start(checks: Array[ControlCheck]) -> void:
	_queue = checks.duplicate()
	current = null
	_next()


## Checks are open: the hint shows and `tick` wants samples.
func is_active() -> bool:
	return current != null


## One physics tick with this tick's measured state.
func tick(dt: float, sample: ControlCheckSample) -> void:
	if current == null or sample == null:
		return
	if not current.started:
		current.begin(sample)
		_ask(HINT)
	if current.observe(sample, dt):
		_pass()
		return
	if misses >= MISSES_BEFORE_WAITING:
		return
	waited_s += dt
	if waited_s < current.repeat_s - 1e-6:
		return
	waited_s = 0.0
	misses += 1
	_ask(DEMO if misses == MISSES_BEFORE_WAITING and current.demo != &"" else HINT)


## Passes the open check without the player (the console, a skipped step). False when none is open, or `id` is another's.
func pass_current(id: StringName = &"") -> bool:
	if current == null or (id != &"" and current.id != id):
		return false
	current.force()
	_pass()
	return true


## Passes every check still to come (a skipped step).
func pass_all() -> void:
	while current != null:
		pass_current()


## Drops the list (the mission ended).
func stop() -> void:
	_queue.clear()
	current = null
	_requests.clear()


## What the mission must do since the last call, in order.
func take_requests() -> Array[Dictionary]:
	var out: Array[Dictionary] = _requests
	_requests = []
	return out


## The checks still to come after the open one.
func remaining() -> Array[StringName]:
	var out: Array[StringName] = []
	for check: ControlCheck in _queue:
		out.append(check.id)
	return out


## What the open check waits for: `hint` (the first), `repeat` (said again), `demo` or `waiting` (asked twice); `idle` with none.
func phase() -> StringName:
	if current == null:
		return &"idle"
	if misses == 0:
		return &"hint"
	if misses < MISSES_BEFORE_WAITING:
		return &"repeat"
	return &"demo" if current.demo != &"" else &"waiting"


func _pass() -> void:
	passed_ids.append(current.id)
	_ask(PASSED)
	_next()


func _next() -> void:
	current = _queue.pop_front() if not _queue.is_empty() else null
	misses = 0
	waited_s = 0.0


func _ask(kind: StringName) -> void:
	if kind == HINT:
		hints += 1
	elif kind == DEMO:
		demos += 1
	_requests.append({"kind": kind, "check": current.id, "line": current.hint_line, "demo": current.demo})
