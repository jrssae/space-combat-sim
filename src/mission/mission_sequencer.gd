class_name MissionSequencer
extends RefCounted
## Runs a mission script's steps in order (architecture §18 D51). Pure: no tree. Each step is a coroutine; the API's waits
## resume on `wake`, which the runner emits once per physics tick after the world moved, so a step runs on sim time only.
##
## Skipping: `skip` marks the current step skipped and wakes it at once. Every API wait in a skipped step returns immediately
## (an awaited trigger is first made true), so the step runs to its end inside that call, and the next step starts and runs to
## its first wait. `goto` does the same for every step before the named one. A signal emission calls only the connections it
## had when it began, so a step that starts waiting during the skip waits for the next tick.
##
## Lifetime: a waiting step holds the API and the script; `release` drops the wait (and with it the step), so nothing is kept
## alive after the mission's node leaves the tree.

## Each physics tick, and on a skip: waiting steps look again.
signal wake
## A step began (its index and name).
signal step_started(index: int, step: StringName)
## The last step returned.
signal finished

var steps: Array[StringName] = []
## The step running: -1 before `start`, `steps.size()` after the last.
var index: int = -1
## The current step is being skipped: waits return at once.
var skipping: bool = false
## No more ticks (the mission ended): waits never return, `release` drops them.
var stopped: bool = false
## Waits that returned at once in the current skip (the API's guard against a polling loop).
var skip_returns: int = 0

var _script: MissionScript = null
var _api: MissionApi = null
var _goto: int = -1


## Starts the first step (it runs until its first wait). The script's steps must have their methods (`check_steps`).
func start(script: MissionScript, api: MissionApi) -> void:
	_script = script
	_api = api
	steps = script.steps()
	_run()


func is_running() -> bool:
	return index >= 0 and index < steps.size() and not stopped


func is_finished() -> bool:
	return index >= steps.size()


## The current step's name (&"" before the first and after the last).
func step_name() -> StringName:
	return steps[index] if index >= 0 and index < steps.size() else &""


## One physics tick: waiting steps look again.
func tick() -> void:
	if not stopped:
		wake.emit()


## Fast-forwards the current step. Returns "" or why not.
func skip() -> String:
	var problem: String = _refusal()
	if not problem.is_empty():
		return problem
	skipping = true
	skip_returns = 0
	wake.emit()
	return ""


## Skips every step until `step`, which then runs normally. Returns "" or why not.
func goto(step: StringName) -> String:
	var problem: String = _refusal()
	if not problem.is_empty():
		return problem
	var target: int = steps.find(step)
	if target < 0:
		return "no step %s (steps: %s)" % [step, ", ".join(PackedStringArray(steps))]
	if target <= index:
		return "step %s is already %s" % [step, "running" if target == index else "done"]
	_goto = target
	skipping = true
	skip_returns = 0
	wake.emit()
	return ""


## No more ticks: the mission is over. Steps stay where they wait until `release`.
func stop() -> void:
	stopped = true
	skipping = false


## Drops whatever waits and lets go of the script and the API.
func release() -> void:
	stop()
	for connection: Dictionary in wake.get_connections():
		wake.disconnect(connection["callable"] as Callable)
	_script = null
	_api = null


func _run() -> void:
	for i: int in steps.size():
		if stopped:
			return
		index = i
		skipping = i < _goto
		skip_returns = 0
		step_started.emit(i, steps[i])
		await _script.call(MissionScript.STEP_PREFIX + String(steps[i]), _api)
		if stopped:
			return
	index = steps.size()
	skipping = false
	finished.emit()


func _refusal() -> String:
	if stopped:
		return "the mission has ended"
	if is_finished():
		return "the script has finished: no step to skip"
	if index < 0:
		return "the script has not started"
	return ""
