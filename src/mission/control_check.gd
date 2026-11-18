class_name ControlCheck
extends RefCounted
## One control check of the tutorial (M8 D80, AC3): the actions it watches, a pass condition on the ship's measured state, the
## instructor's hint line, an optional demo move (D37's `Manoeuvres`) and how long to wait before repeating. Pure: it reads
## `ControlCheckSample`s, one per physics tick, and never `Input`. `ControlCheckBook` builds them from
## `data/checks/controls.json`; `ControlCheckRunner` runs them. A check never fails: it passes, or it is still open.
##
## Kinds (the pass condition):
## - `velocity`: the ship gained `min_mps` along `direction` of its own frame (forward, back, left, right, up, down) on ticks
##   its events were held: the thrusters pushed it, however it was turned meanwhile.
## - `rotation`: it turned `min_deg` about its `turn` axis (pitch, yaw, roll), either way, on ticks its events were held.
## - `brake`: the events were held `hold_s` and the speed fell by `min_drop_mps` or to `stop_mps`.
## - `state`: every condition of `when` holds on one tick, after the events were seen (`held`: on that same tick). A condition
##   is `{field, op, value}` on `ControlCheckSample.FIELDS`: `equals`, `at_least`, `set` (not zero, empty or false), and
##   against the value the field had when the check began, `changed` and `increased`.
##
## `events` are the command events the check needs (`ControlCheckSample.event_names`; default: its `actions`), `need` says
## whether all of them or any one. `actions` are the `InputMap` actions whose live bindings the hint shows, `press` how they
## are pressed there (press, hold, tap), and `pad_extra` / `keys_extra` name what no action binds (the mouse's motion, the
## wheel, the stick's diagonals).

const VELOCITY: StringName = &"velocity"
const ROTATION: StringName = &"rotation"
const BRAKE: StringName = &"brake"
const STATE: StringName = &"state"
const KINDS: Array[StringName] = [VELOCITY, ROTATION, BRAKE, STATE]
## A `velocity` check's direction in the ship's frame (+X right, +Y up, -Z forward).
const DIRECTIONS: Dictionary = {&"forward": Vector3.FORWARD, &"back": Vector3.BACK, &"left": Vector3.LEFT,
		&"right": Vector3.RIGHT, &"up": Vector3.UP, &"down": Vector3.DOWN}
## A `rotation` check's axis in the ship's frame; a turn either way about it counts.
const TURNS: Dictionary = {&"pitch": Vector3.RIGHT, &"yaw": Vector3.UP, &"roll": Vector3.BACK}
const OPS: Array[StringName] = [&"equals", &"at_least", &"set", &"changed", &"increased"]
const PRESSES: Array[StringName] = [&"press", &"hold", &"tap"]
const DEFAULT_REPEAT_S: float = 20.0

const _KEYS: Array[String] = ["id", "label", "actions", "need", "press", "pad_extra", "keys_extra", "events", "held", "kind",
		"direction", "min_mps", "turn", "min_deg", "hold_s", "min_drop_mps", "stop_mps", "when", "hint_line", "demo", "repeat_s"]
const _ID_PATTERN: String = "^[a-z0-9_]+$"

var id: StringName = &""
## What the hint asks for, in the HUD's capitals (`FIRE BOTH MAIN PODS`).
var label: String = ""
var actions: Array[StringName] = []
var press: StringName = &"press"
var pad_extra: String = ""
var keys_extra: String = ""
var events: Array[StringName] = []
var need_all: bool = false
var held: bool = false
var kind: StringName = STATE
var direction: StringName = &"forward"
var min_mps: float = 0.0
var turn: StringName = &"pitch"
var min_deg: float = 0.0
var hold_s: float = 0.0
var min_drop_mps: float = 0.0
var stop_mps: float = 0.0
var when: Array[Dictionary] = []
## The dialog line the instructor says as the hint, the demo move he flies after two misses (&"" for none), and the seconds
## an open check waits before each.
var hint_line: StringName = &""
var demo: StringName = &""
var repeat_s: float = DEFAULT_REPEAT_S

## Progress: the first sample was taken; the check has passed (`forced`: by a skip or the console); how far it is, 0..1.
var started: bool = false
var passed: bool = false
var forced: bool = false
var progress: float = 0.0

var _seen: Dictionary = {}
var _start: Dictionary = {}
var _last_velocity: Vector3 = Vector3.ZERO
var _was_held: bool = false
var _gain: float = 0.0
var _held_s: float = 0.0
var _speed0: float = 0.0


## Builds a check from its JSON entry; `defaults` fills what it leaves out. Returns {"ok", "check", "error"}.
static func from_dict(raw: Variant, defaults: Dictionary = {}) -> Dictionary:
	if not (raw is Dictionary):
		return _fail("a check must be an object")
	var entry: Dictionary = defaults.duplicate()
	entry.merge(raw as Dictionary, true)
	for key: Variant in entry:
		if not _KEYS.has(str(key)):
			return _fail("unknown key '%s'" % key)
	var check := ControlCheck.new()
	var id_text: String = str(entry.get("id", ""))
	var pattern := RegEx.create_from_string(_ID_PATTERN)
	if pattern.search(id_text) == null:
		return _fail("id must be lower case letters, digits and underscores, got '%s'" % id_text)
	check.id = StringName(id_text)
	check.label = str(entry.get("label", "")).strip_edges()
	if check.label.is_empty():
		return _fail("%s: label is missing" % id_text)
	var problem: String = check._read_inputs(entry)
	if problem.is_empty():
		problem = check._read_condition(entry)
	if problem.is_empty():
		problem = check._read_teaching(entry)
	if not problem.is_empty():
		return _fail("%s: %s" % [id_text, problem])
	return {"ok": true, "check": check, "error": ""}


## Takes the starting state, against which `changed` and `increased` are read. `observe` does it on its first sample.
func begin(sample: ControlCheckSample) -> void:
	started = true
	_start = sample.state.duplicate()
	_last_velocity = sample.velocity
	_was_held = false


## One physics tick. Returns whether the check has passed (and stays passed).
func observe(sample: ControlCheckSample, dt: float) -> bool:
	if passed:
		return true
	if not started:
		begin(sample)
	for event: StringName in events:
		if sample.events.has(event):
			_seen[event] = true
	var now: bool = _events_now(sample)
	# The motion a command causes shows a tick after it, so the tick after a release still counts.
	var pushing: bool = now or _was_held
	match kind:
		VELOCITY:
			var gained: Vector3 = sample.basis.inverse() * (sample.velocity - _last_velocity)
			if pushing:
				_gain += gained.dot(DIRECTIONS[direction] as Vector3)
			_measure(_gain, min_mps)
		ROTATION:
			var rate: Vector3 = sample.basis.inverse() * sample.angular_velocity
			if pushing:
				_gain += absf(rad_to_deg(rate.dot(TURNS[turn] as Vector3))) * dt
			_measure(_gain, min_deg)
		BRAKE:
			_observe_brake(sample, dt, now)
		STATE:
			passed = (now if held else _events_seen()) and _conditions_hold(sample)
			progress = 1.0 if passed else 0.0
	_last_velocity = sample.velocity
	_was_held = now
	return passed


## Passes the check without the player (a skipped step, the console's `checks pass`).
func force() -> void:
	passed = true
	forced = true
	progress = 1.0


## What was measured so far, for the console: `velocity forward 12.0/30.0 m/s`.
func describe() -> String:
	match kind:
		VELOCITY:
			return "velocity %s %.1f/%.1f m/s" % [direction, _gain, min_mps]
		ROTATION:
			return "rotation %s %.0f/%.0f deg" % [turn, _gain, min_deg]
		BRAKE:
			return "brake held %.1f/%.1f s" % [_held_s, hold_s]
	var parts := PackedStringArray()
	for condition: Dictionary in when:
		parts.append("%s %s%s" % [condition["field"], condition["op"],
				" %s" % str(condition["value"]) if condition.has("value") else ""])
	return "state %s" % ", ".join(parts)


# --- the pass conditions -----------------------------------------------------------------------------------------------


func _measure(value: float, wanted: float) -> void:
	progress = clampf(value / wanted, 0.0, 1.0)
	passed = value >= wanted


# The brake is held and the ship slows: the hold restarts when it is let go.
func _observe_brake(sample: ControlCheckSample, dt: float, now: bool) -> void:
	var speed: float = sample.speed_mps()
	if not now:
		_held_s = 0.0
		progress = 0.0
		return
	if _held_s <= 0.0:
		_speed0 = speed
	_held_s += dt
	var slowed: bool = speed <= stop_mps or _speed0 - speed >= min_drop_mps
	progress = clampf(_held_s / hold_s, 0.0, 1.0) if hold_s > 0.0 else 1.0
	passed = slowed and _held_s >= hold_s - 1e-6


func _events_now(sample: ControlCheckSample) -> bool:
	return _events_in(sample.events)


func _events_seen() -> bool:
	return _events_in(_seen)


# All of the events (or any one) are in `present`; a check with no events needs none.
func _events_in(present: Dictionary) -> bool:
	if events.is_empty():
		return true
	for event: StringName in events:
		if present.has(event) != need_all:
			return not need_all
	return need_all


func _conditions_hold(sample: ControlCheckSample) -> bool:
	for condition: Dictionary in when:
		if not _holds(condition, sample):
			return false
	return true


func _holds(condition: Dictionary, sample: ControlCheckSample) -> bool:
	var field: StringName = condition["field"]
	if not sample.state.has(field):
		return false
	var value: Variant = sample.state[field]
	match condition["op"] as StringName:
		&"equals":
			return _same(value, condition["value"])
		&"at_least":
			return _is_number(value) and float(value) >= float(condition["value"])
		&"set":
			return _is_set(value)
		&"changed":
			return _start.has(field) and not _same(value, _start[field])
		&"increased":
			return _start.has(field) and _is_number(value) and _is_number(_start[field]) and float(value) > float(_start[field])
	return false


static func _is_number(value: Variant) -> bool:
	return value is int or value is float


static func _is_text(value: Variant) -> bool:
	return value is String or value is StringName


static func _is_set(value: Variant) -> bool:
	if value is bool:
		return value as bool
	if _is_number(value):
		return float(value) != 0.0
	return _is_text(value) and not str(value).is_empty()


# Values from the game and from JSON compare by meaning: a StringName with a String, an int with a float.
static func _same(a: Variant, b: Variant) -> bool:
	if a is bool and b is bool:
		return (a as bool) == (b as bool)
	if _is_number(a) and _is_number(b):
		return is_equal_approx(float(a), float(b))
	if _is_text(a) and _is_text(b):
		return str(a) == str(b)
	return false


# --- reading the entry -------------------------------------------------------------------------------------------------


func _read_inputs(entry: Dictionary) -> String:
	var problem: String = _names(entry.get("actions", []), "actions", InputAdapter.ACTIONS, actions)
	if not problem.is_empty():
		return problem
	if actions.is_empty():
		return "actions is empty: the hint has no binding to show"
	if entry.has("events"):
		problem = _names(entry["events"], "events", ControlCheckSample.event_names(), events)
		if not problem.is_empty():
			return problem
	else:
		for action: StringName in actions:
			if not PlayerActions.NAMES.has(action):
				return "action %s is no command event: name the check's events" % action
			events.append(action)
	var need: String = str(entry.get("need", "any"))
	if need != "any" and need != "all":
		return "need must be any or all, got '%s'" % need
	need_all = need == "all"
	press = StringName(str(entry.get("press", "press")))
	if not PRESSES.has(press):
		return "press must be one of %s, got '%s'" % [PRESSES, press]
	if not (entry.get("held", false) is bool):
		return "held must be true or false"
	held = entry.get("held", false)
	pad_extra = str(entry.get("pad_extra", "")).strip_edges()
	keys_extra = str(entry.get("keys_extra", "")).strip_edges()
	return ""


func _read_condition(entry: Dictionary) -> String:
	kind = StringName(str(entry.get("kind", "")))
	match kind:
		VELOCITY:
			direction = StringName(str(entry.get("direction", "")))
			if not DIRECTIONS.has(direction):
				return "direction must be one of %s, got '%s'" % [DIRECTIONS.keys(), direction]
			return _positive(entry, "min_mps")
		ROTATION:
			turn = StringName(str(entry.get("turn", "")))
			if not TURNS.has(turn):
				return "turn must be one of %s, got '%s'" % [TURNS.keys(), turn]
			return _positive(entry, "min_deg")
		BRAKE:
			for key: String in ["hold_s", "min_drop_mps", "stop_mps"]:
				var problem: String = _positive(entry, key)
				if not problem.is_empty():
					return problem
			return ""
		STATE:
			return _read_when(entry.get("when", []))
	return "kind must be one of %s, got '%s'" % [KINDS, kind]


func _read_when(raw: Variant) -> String:
	if not (raw is Array) or (raw as Array).is_empty():
		return "a state check needs its conditions in when"
	for item: Variant in raw as Array:
		if not (item is Dictionary):
			return "a condition must be an object {field, op, value}"
		var condition: Dictionary = item
		var field := StringName(str(condition.get("field", "")))
		var op := StringName(str(condition.get("op", "")))
		if not ControlCheckSample.FIELDS.has(field):
			return "no state field '%s' (%s)" % [field, ControlCheckSample.FIELDS]
		if not OPS.has(op):
			return "no condition '%s' (%s)" % [op, OPS]
		var read: Dictionary = {"field": field, "op": op}
		if op == &"equals" or op == &"at_least":
			if not condition.has("value") or (op == &"at_least" and not _is_number(condition["value"])):
				return "%s %s needs a value" % [field, op]
			read["value"] = condition["value"]
		when.append(read)
	return ""


func _read_teaching(entry: Dictionary) -> String:
	hint_line = StringName(str(entry.get("hint_line", "")))
	demo = StringName(str(entry.get("demo", "")))
	if demo != &"" and not Manoeuvres.NAMES.has(demo):
		return "no demo '%s' (%s)" % [demo, Manoeuvres.NAMES]
	if not _is_number(entry.get("repeat_s", DEFAULT_REPEAT_S)) or float(entry.get("repeat_s", DEFAULT_REPEAT_S)) <= 0.0:
		return "repeat_s must be a number above 0"
	repeat_s = float(entry.get("repeat_s", DEFAULT_REPEAT_S))
	return ""


# Reads a number above zero into the member of the same name.
func _positive(entry: Dictionary, key: String) -> String:
	var value: Variant = entry.get(key)
	if not _is_number(value) or float(value) <= 0.0:
		return "%s must be a number above 0" % key
	set(key, float(value))
	return ""


# Reads a list of names, each one of `known`, into `into`.
static func _names(raw: Variant, what: String, known: Array[StringName], into: Array[StringName]) -> String:
	if not (raw is Array):
		return "%s must be a list" % what
	for item: Variant in raw as Array:
		var name := StringName(str(item))
		if not known.has(name):
			return "%s: unknown name '%s'" % [what, name]
		if not into.has(name):
			into.append(name)
	return ""


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "check": null, "error": message}
