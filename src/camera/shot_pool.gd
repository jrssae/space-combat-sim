class_name ShotPool
extends RefCounted
## A pool of short camera takes for a cinematic, by stage (M8-T31; the gate's `GateShotPool` is its sibling): read from a data file
## whose every array of `{id, keys, when?, feature?}` is a stage, so a sequence never shows the same few angles twice. Pure: which
## take comes next and how long it may be held; `ShotSequencer` plays them. Every take lasts 1 s or more and under 3 s, or under 5 s
## when marked `"feature": true` (maintainer, 2026-11-19; `test_cinematic_shot_lengths` checks the data).

## A take is cut no later than this, or this for a feature take ...
const TAKE_MAX_S: float = 2.8
const FEATURE_MAX_S: float = 4.8
## ... and held at least this.
const MIN_HOLD_S: float = 1.0
## ... and a feature take at least this, so its moment plays out.
const FEATURE_MIN_S: float = 2.5

## `{id, keys, when?, feature?}` per take, by stage.
var takes: Dictionary = {}
var error: String = ""


## The pool in `path` (with `error` set when it holds no stage).
static func load_file(path: String) -> ShotPool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	var pool := from_dict(parsed if parsed is Dictionary else {})
	if pool.takes.is_empty():
		pool.error = "%s holds no takes" % path
	return pool


static func from_dict(data: Dictionary) -> ShotPool:
	var pool := ShotPool.new()
	for stage: String in data:
		if not data[stage] is Array:
			continue
		var list: Array[Dictionary] = []
		for entry: Variant in data[stage]:
			if entry is Dictionary and (entry as Dictionary).get("id") is String and (entry as Dictionary).get("keys") is Array:
				list.append(entry)
		if not list.is_empty():
			pool.takes[StringName(stage)] = list
	return pool


func stages() -> Array[StringName]:
	var out: Array[StringName] = []
	for stage: StringName in takes:
		out.append(stage)
	return out


func ids(stage: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	for entry: Dictionary in takes.get(stage, []):
		out.append(String(entry["id"]))
	return out


func is_feature(stage: StringName, id: String) -> bool:
	return bool(_entry(stage, id).get("feature", false))


## The longest the take is held.
func max_s(stage: StringName, id: String) -> float:
	return FEATURE_MAX_S if is_feature(stage, id) else TAKE_MAX_S


## The next take for `stage`: one `usable(stage, id) -> bool` passes and the sequence has not `used` yet, never `previous` (the take
## just before) and never `avoid` (the last sequence's opening) while another is left. "" when the stage has none.
func next(rng: RandomNumberGenerator, stage: StringName, used: PackedStringArray, previous: String, avoid: String,
		usable: Callable) -> String:
	var clear := PackedStringArray()
	for id: String in ids(stage):
		if bool(usable.call(stage, id)):
			clear.append(id)
	if clear.is_empty():
		clear = ids(stage)
	for rule: int in 3:  # the strictest choice first, then one rule fewer each time
		var choices := PackedStringArray()
		for id: String in clear:
			if id == previous and clear.size() > 1:
				continue
			if rule < 2 and id == avoid:
				continue
			if rule < 1 and used.has(id):
				continue
			choices.append(id)
		if not choices.is_empty():
			return choices[rng.randi_range(0, choices.size() - 1)]
	return clear[0] if not clear.is_empty() else ""


## A take's keys as written.
func keys(stage: StringName, id: String) -> Array:
	return (_entry(stage, id).get("keys", []) as Array).duplicate(true)


func _entry(stage: StringName, id: String) -> Dictionary:
	for e: Dictionary in takes.get(stage, []):
		if String(e["id"]) == id:
			return e
	return {}
