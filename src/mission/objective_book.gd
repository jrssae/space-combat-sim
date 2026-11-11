class_name ObjectiveBook
extends RefCounted
## A mission's objectives (architecture §18 D52). Pure. Each objective is `{id, text, primary, state, success, fail}`: the state
## moves hidden -> active -> done or failed (done and failed are final), and `success` and `fail` are optional triggers the runner
## evaluates each tick while the objective is active, fail first. A scenario declares them (`mission.objectives[]`); the script
## shows one with `m.objective_add(id)` and may complete or fail it itself.
##
## The result rules (D51) read primaries only: every primary done is a success, any primary failed a failure. The HUD lists the
## active ones; the pause menu and the debrief read `snapshot()`.

const HIDDEN: StringName = &"hidden"
const ACTIVE: StringName = &"active"
const DONE: StringName = &"done"
const FAILED: StringName = &"failed"

## Why the last refused call was refused ("" after one that went through).
var error: String = ""

var _entries: Array[Entry] = []
var _by_id: Dictionary = {}  # StringName -> Entry


## One objective.
class Entry extends RefCounted:
	var id: StringName = &""
	var text: String = ""
	var primary: bool = true
	var state: StringName = ObjectiveBook.HIDDEN
	var success: Trigger = null
	var fail: Trigger = null


## Adds the scenario's `mission.objectives[]`: `{id, text?, primary? (true), active? (false), success?, fail?}`, the triggers in
## `TriggerSpec` JSON. Returns "" or what is wrong (nothing is added then).
func declare(entries: Variant, system: StringName = &"local") -> String:
	if not (entries is Array):
		return "objectives must be an array"
	var staged: Array[Entry] = []
	var seen: Dictionary = {}
	for i: int in (entries as Array).size():
		var where: String = "objectives[%d]" % i
		var raw: Variant = (entries as Array)[i]
		if not (raw is Dictionary):
			return "%s must be an object" % where
		var d: Dictionary = raw
		var id: Variant = d.get("id")
		if not (id is String) or (id as String).strip_edges().is_empty():
			return "%s.id must be a non-empty string" % where
		var key := StringName((id as String).strip_edges())
		if seen.has(key) or _by_id.has(key):
			return "%s.id '%s' is declared twice" % [where, key]
		seen[key] = true
		var text: Variant = d.get("text", "")
		if not (text is String):
			return "%s.text must be a string" % where
		var primary: Variant = d.get("primary", true)
		if typeof(primary) != TYPE_BOOL:
			return "%s.primary must be true or false" % where
		var active: Variant = d.get("active", false)
		if typeof(active) != TYPE_BOOL:
			return "%s.active must be true or false" % where
		var entry := Entry.new()
		entry.id = key
		entry.text = text as String
		entry.primary = primary as bool
		entry.state = ACTIVE if active else HIDDEN
		for slot: String in ["success", "fail"]:
			if not d.has(slot):
				continue
			var made: Dictionary = TriggerSpec.from_dict(d[slot], system)
			if not bool(made["ok"]):
				return "%s.%s: %s" % [where, slot, made["error"]]
			entry.set(slot, made["trigger"])
		staged.append(entry)
	for entry: Entry in staged:
		_store(entry)
	return ""


## Adds one objective (hidden). False when the id is taken.
func add(id: StringName, text: String, primary: bool = true, success: Trigger = null, fail: Trigger = null) -> bool:
	if _by_id.has(id):
		return _refuse("objective '%s' exists already" % id)
	var entry := Entry.new()
	entry.id = id
	entry.text = text
	entry.primary = primary
	entry.success = success
	entry.fail = fail
	_store(entry)
	error = ""
	return true


func has(id: StringName) -> bool:
	return _by_id.has(id)


## The state of `id`, or &"" when there is none.
func state_of(id: StringName) -> StringName:
	var entry: Entry = _by_id.get(id)
	return entry.state if entry != null else &""


## Shows a hidden objective; its triggers go live from now (a timer counts from here).
func activate(id: StringName, world: MissionWorld) -> bool:
	var entry: Entry = _find(id)
	if entry == null:
		return false
	if entry.state != HIDDEN:
		return _refuse("objective '%s' is already %s" % [id, entry.state])
	entry.state = ACTIVE
	for trigger: Trigger in [entry.success, entry.fail]:
		if trigger != null:
			trigger.arm(world)
	error = ""
	return true


## Marks an objective done (hidden or active).
func complete(id: StringName) -> bool:
	return _finish(id, DONE)


## Marks an objective failed (hidden or active).
func fail(id: StringName) -> bool:
	return _finish(id, FAILED)


## A skip reached this objective (D51): its success trigger is made true in the world and it completes.
func force_success(id: StringName, world: MissionWorld) -> bool:
	var entry: Entry = _find(id)
	if entry == null:
		return false
	if entry.success != null and (entry.state == ACTIVE or entry.state == HIDDEN):
		entry.success.make_true(world)
	return _finish(id, DONE)


## Tests the triggers of every active objective (fail first) and returns the ids whose state changed this time.
func evaluate(world: MissionWorld) -> Array[StringName]:
	var changed: Array[StringName] = []
	for entry: Entry in _entries:
		if entry.state != ACTIVE:
			continue
		if entry.fail != null and entry.fail.check(world):
			entry.state = FAILED
			changed.append(entry.id)
		elif entry.success != null and entry.success.check(world):
			entry.state = DONE
			changed.append(entry.id)
	return changed


## The triggers of the active objectives (they are live: evaluated each tick).
func live_triggers() -> Array[Trigger]:
	var out: Array[Trigger] = []
	for entry: Entry in _entries:
		if entry.state != ACTIVE:
			continue
		if entry.success != null:
			out.append(entry.success)
		if entry.fail != null:
			out.append(entry.fail)
	return out


## Every objective in declaration order: `{id: StringName, text: String, primary: bool, state: StringName}`.
func snapshot() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Entry in _entries:
		out.append({"id": entry.id, "text": entry.text, "primary": entry.primary, "state": entry.state})
	return out


## The active objectives only, as `snapshot` gives them (the HUD's list).
func active() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d: Dictionary in snapshot():
		if d["state"] == ACTIVE:
			out.append(d)
	return out


## What the active objective `id` is about (M5-T25, the target menu's objectives): `{actors: PackedStringArray, point:
## UniversePos or null}`, from its success trigger and then its fail trigger. The actors are in the triggers' order, the
## player left out; `point` is the first fixed place a trigger names. Both empty for an objective that names neither.
func subject(id: StringName) -> Dictionary:
	var actors := PackedStringArray()
	var point: UniversePos = null
	var entry: Entry = _by_id.get(id)
	if entry != null:
		for trigger: Trigger in [entry.success, entry.fail]:
			if trigger == null:
				continue
			if point == null:
				point = trigger.place()
			for actor: String in trigger.actors():
				if MissionWorld.key(actor) != "player" and not actors.has(actor):
					actors.append(actor)
	return {"actors": actors, "point": point}


## Every primary objective is done (and there is at least one).
func all_primaries_done() -> bool:
	var primaries: int = 0
	for entry: Entry in _entries:
		if entry.primary:
			primaries += 1
			if entry.state != DONE:
				return false
	return primaries > 0


## The first failed primary objective's id, or &"".
func failed_primary() -> StringName:
	for entry: Entry in _entries:
		if entry.primary and entry.state == FAILED:
			return entry.id
	return &""


## One console line per objective: `[done] raiders: Destroy the raiders`, optional ones marked.
func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	for entry: Entry in _entries:
		out.append("[%s] %s: %s%s" % [entry.state, entry.id, entry.text, "" if entry.primary else " (optional)"])
	return out


func _store(entry: Entry) -> void:
	_entries.append(entry)
	_by_id[entry.id] = entry


func _find(id: StringName) -> Entry:
	var entry: Entry = _by_id.get(id)
	if entry == null:
		_refuse("no objective '%s'" % id)
	return entry


func _finish(id: StringName, state: StringName) -> bool:
	var entry: Entry = _find(id)
	if entry == null:
		return false
	if entry.state == DONE or entry.state == FAILED:
		return _refuse("objective '%s' is already %s" % [id, entry.state])
	entry.state = state
	error = ""
	return true


func _refuse(reason: String) -> bool:
	error = reason
	return false
