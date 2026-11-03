class_name GameFlow
extends RefCounted
## The game's flow between screens (architecture §18, D50): front end, loading, in space, debrief, and the request
## that travels across them. Pure: the `Game` autoload changes the scenes; this only says which move is allowed.
##
## A run begins at the front end. Boot either stays there or, for a scripted run, enters space directly.

enum State { FRONT_END, LOADING, IN_SPACE, DEBRIEF }

const KINDS: Array[StringName] = [&"free_flight", &"mission", &"sandbox"]
const SCENARIO_DIR: String = "res://data/scenarios/"
const STATE_NAMES: PackedStringArray = ["front_end", "loading", "in_space", "debrief"]

const _ARG_HEADLESS: String = "--headless"
const _ARG_EXEC: String = "--console-exec"
const _ARG_FILE: String = "--console-file"
const _ARG_SCENARIO: String = "--scenario="

var state: State = State.FRONT_END
## What the player (or the console) asked to play last: see `make_request`. Empty before anything was asked for.
var request: Dictionary = {}
## How the last run ended, for the debrief. Empty until a run ends.
var last_result: Dictionary = {}
## Why the last move was refused; empty after a move that went through.
var error: String = ""


## Back to the front end. Always allowed: it is the way out of every screen.
func open_menu() -> bool:
	return _move_to(State.FRONT_END)


## Starts loading a run (the menu, `play`, a restart). Not while something is already loading.
func start_loading(next_request: Dictionary) -> bool:
	if state == State.LOADING:
		return _refuse("a scenario is already loading")
	var problem: String = validate_request(next_request)
	if not problem.is_empty():
		return _refuse(problem)
	request = next_request.duplicate()
	return _move_to(State.LOADING)


## The loaded scenario is in the tree.
func finish_loading() -> bool:
	if state != State.LOADING:
		return _refuse("nothing is loading")
	return _move_to(State.IN_SPACE)


## Boot's route for a scripted run: straight into space, no loading screen.
func enter_directly(next_request: Dictionary) -> bool:
	if state != State.FRONT_END:
		return _refuse("only a fresh start enters space directly")
	var problem: String = validate_request(next_request)
	if not problem.is_empty():
		return _refuse(problem)
	request = next_request.duplicate()
	return _move_to(State.IN_SPACE)


## The run is over; the debrief shows `result`.
func end_run(result: Dictionary) -> bool:
	if state != State.IN_SPACE:
		return _refuse("there is no run to end")
	last_result = result.duplicate()
	return _move_to(State.DEBRIEF)


## Keeps how a run ended without moving: a run the flow did not start (a test's Main) still leaves its result for the console.
func keep_result(result: Dictionary) -> void:
	last_result = result.duplicate()


## From the debrief, the same scenario and seed again.
func retry() -> bool:
	if state != State.DEBRIEF:
		return _refuse("retry is only offered in the debrief")
	return _move_to(State.LOADING)


## A request: what to play, with or without free-flight encounters, and the seed that makes it repeatable.
static func make_request(kind: StringName, scenario_id: StringName, encounters: bool = false, seed_value: int = 0) -> Dictionary:
	return {"kind": kind, "scenario_id": scenario_id, "encounters": encounters, "seed": seed_value}


## Empty when `candidate` is a well-formed request, otherwise what is wrong with it.
static func validate_request(candidate: Dictionary) -> String:
	var kind: Variant = candidate.get("kind")
	if not (kind is StringName or kind is String) or not KINDS.has(StringName(kind)):
		return "a request needs a kind (%s), got %s" % [", ".join(PackedStringArray(KINDS)), kind]
	var scenario_id: Variant = candidate.get("scenario_id")
	if not (scenario_id is StringName or scenario_id is String) or String(scenario_id).is_empty():
		return "a request needs a scenario id"
	if not candidate.get("encounters") is bool:
		return "a request needs encounters on or off"
	if not candidate.get("seed") is int:
		return "a request needs an integer seed"
	return ""


## The kind of run a scenario makes when nothing else says so: `mission` for a scenario with a `mission` block (M5-T05),
## `free_flight` for free flight, else `sandbox`. `scenario_text` is the file's JSON; null reads it from `data/scenarios/`.
static func kind_for(scenario_id: StringName, scenario_text: Variant = null) -> StringName:
	var text: String = scenario_text if scenario_text is String else ""
	if scenario_text == null and FileAccess.file_exists(scenario_path(scenario_id)):
		text = FileAccess.get_file_as_string(scenario_path(scenario_id))
	var json := JSON.new()
	var root: Variant = json.data if not text.is_empty() and json.parse(text) == OK else null
	if root is Dictionary and (root as Dictionary).get("mission") is Dictionary \
			and not ((root as Dictionary)["mission"] as Dictionary).is_empty():
		return &"mission"
	return &"free_flight" if scenario_id == &"free_flight" else &"sandbox"


static func scenario_path(scenario_id: StringName) -> String:
	return SCENARIO_DIR + String(scenario_id) + ".json"


static func state_name(value: State) -> String:
	return STATE_NAMES[value]


static func describe_request(value: Dictionary) -> String:
	if value.is_empty():
		return "none"
	return "%s (%s), encounters %s, seed %d" % [value.get("scenario_id", ""), value.get("kind", ""),
			"on" if bool(value.get("encounters", false)) else "off", int(value.get("seed", 0))]


static func describe_result(value: Dictionary) -> String:
	if value.is_empty():
		return "none"
	var text: String = "success" if bool(value.get("success", false)) else "failure"
	var reason: String = str(value.get("reason", ""))
	return text if reason.is_empty() else "%s: %s" % [text, reason]


## Decides, once at start, whether this run shows the front end or goes straight to Main. Every scripted run
## (headless, a console script, `--scenario=<id>`) and `skip_front_end` go straight, so tools and tests start as
## before. Returns {"straight": bool, "reason": String (the first that applies), "scenario": String ("" if none)}.
static func boot_route(engine_args: PackedStringArray, user_args: PackedStringArray, headless: bool,
		skip_front_end: bool) -> Dictionary:
	var reasons: PackedStringArray = []
	if headless or engine_args.has(_ARG_HEADLESS):
		reasons.append("headless")
	if _has_flag_with_value(user_args, _ARG_EXEC):
		reasons.append("console-exec")
	if _has_flag_with_value(user_args, _ARG_FILE):
		reasons.append("console-file")
	var scenario: String = ""
	var scenario_given: bool = false
	for arg: String in user_args + engine_args:
		if arg.begins_with(_ARG_SCENARIO):
			scenario = arg.substr(_ARG_SCENARIO.length())
			scenario_given = true
			break
	if scenario_given:
		reasons.append("scenario")
	if skip_front_end:
		reasons.append("skip_front_end")
	return {"straight": not reasons.is_empty(), "reason": reasons[0] if not reasons.is_empty() else "",
			"scenario": scenario}


# `--flag=value`, or `--flag value` with something after it (the console reads both forms).
static func _has_flag_with_value(args: PackedStringArray, flag: String) -> bool:
	for i: int in args.size():
		if args[i].begins_with(flag + "=") or (args[i] == flag and i + 1 < args.size()):
			return true
	return false


func _move_to(next: State) -> bool:
	state = next
	error = ""
	return true


func _refuse(reason: String) -> bool:
	error = reason
	return false
