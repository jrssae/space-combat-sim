class_name GateShotPool
extends RefCounted
## The gate jump's camera takes (M8-T29, maintainer 2026-11-19): so jumps do not all look alike, and no angle is held 3 s or more,
## each stage of the jump is cut into short takes picked from a pool in `data/jump/gate_shots.json`. Pure: the takes, how a
## stage is sliced into takes, and which take comes next; `GateShotDirector` plays them and supplies the clearance test.

const PATH: String = "res://data/jump/gate_shots.json"
## The pools, one per stage: the run-in, the mouth, the arrival side opening, the ship bursting back out.
const APPROACH: StringName = &"approach"
const MOUTH: StringName = &"mouth"
const ARRIVAL_OPEN: StringName = &"arrival_open"
const ARRIVAL_OUT: StringName = &"arrival_out"
const SLOTS: Array[StringName] = [APPROACH, MOUTH, ARRIVAL_OPEN, ARRIVAL_OUT]
const DEFAULT_CUT_LEAD_S: float = 3.5
## A take is cut no later than this (the maintainer: an angle under 3 s, with room for the ring's 0.3 s flash at the end) ...
const TAKE_MAX_S: float = 2.6
## ... or this for a take marked `"feature": true` (maintainer, 2026-11-19: an interesting angle may run up to 5 s) ...
const FEATURE_MAX_S: float = 4.6
## ... and held at least this (M7-T08), unless the stage itself is shorter.
const MIN_HOLD_S: float = 1.0
## What the data's gate actor is called; `keys` swaps it for the caller's name.
const GATE_ACTOR: String = "gate"
## A mouth take's tag: made for the moment the ship enters the mouth, or only for before it (a close take whose view the core
## would fill); a take with neither goes anywhere. A stage's slices are `BEFORE`, `ENTRY` or `AFTER` the entry ("" elsewhere).
const ENTRY: String = "entry"
const BEFORE: String = "before"
const AFTER: String = "after"

## `{id, keys, when?}` per take, by slot.
var takes: Dictionary = {}
var cut_lead_s: float = DEFAULT_CUT_LEAD_S
var error: String = ""


## The pool in the data file (with `error` set when a stage has no takes).
static func load_file(path: String = PATH) -> GateShotPool:
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	return from_dict(parsed if parsed is Dictionary else {})


static func from_dict(data: Dictionary) -> GateShotPool:
	var pool := GateShotPool.new()
	var lead: Variant = data.get("cut_lead_s")
	pool.cut_lead_s = float(lead) if (lead is float or lead is int) and float(lead) >= 0.0 else DEFAULT_CUT_LEAD_S
	for slot: StringName in SLOTS:
		var list: Array[Dictionary] = []
		var raw: Variant = data.get(String(slot))
		if raw is Array:
			for entry: Variant in raw:
				if entry is Dictionary and (entry as Dictionary).get("id") is String and (entry as Dictionary).get("keys") is Array:
					list.append(entry)
		if list.is_empty():
			pool.error = "no %s takes" % slot
		pool.takes[slot] = list
	return pool


func ids(slot: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	for entry: Dictionary in takes.get(slot, []):
		out.append(String(entry["id"]))
	return out


## The take's tag (`entry`, `before`, or "").
func when(slot: StringName, id: String) -> String:
	return String(_entry(slot, id).get("when", ""))


## Whether the take is marked a feature, allowed to run longer.
func is_feature(slot: StringName, id: String) -> bool:
	return bool(_entry(slot, id).get("feature", false))


## The longest the take is held.
func max_s(slot: StringName, id: String) -> float:
	return FEATURE_MAX_S if is_feature(slot, id) else TAKE_MAX_S


## When the run-in's approach takes give way to the mouth's, s after its start, for an arrival `arrival_s` out.
func cut_s(arrival_s: float) -> float:
	return maxf(arrival_s - cut_lead_s, MIN_HOLD_S)


## How long a take starting at `start_s` is held in a stage ending at `end_s` (INF: open-ended): all of what is left when it fits
## in `longest_s`, else an even share of it, so the takes left are alike and a late or early end still leaves the last one its
## second (no take under `MIN_HOLD_S`).
static func take_length(start_s: float, end_s: float, longest_s: float) -> float:
	var left: float = end_s - start_s
	if not is_finite(left):
		return longest_s
	if left <= longest_s:
		return maxf(left, 0.0)
	return maxf(left / ceilf(left / longest_s), minf(MIN_HOLD_S, longest_s))


## The next take for `slot`: one `usable(slot, id) -> bool` passes and the sequence has not `used` yet, never `previous` (the take
## just before) and never `avoid` (the last jump's opening take) while another is left. `slice` (`BEFORE`, `ENTRY`, `AFTER` or "")
## says where the take goes: an entry slice wants an entry take, and a take tagged for the entry or for before it waits elsewhere
## while others are left. "" when the stage has none.
func next(rng: RandomNumberGenerator, slot: StringName, used: PackedStringArray, previous: String, avoid: String,
		usable: Callable, slice: String = "") -> String:
	var clear := PackedStringArray()
	for id: String in ids(slot):
		if bool(usable.call(slot, id)):
			clear.append(id)
	if clear.is_empty():
		clear = ids(slot)
	for rule: int in 4:  # the strictest choice first, then one rule fewer each time
		var choices := PackedStringArray()
		for id: String in clear:
			if id == previous and clear.size() > 1:
				continue
			if rule < 3 and id == avoid:
				continue
			if rule < 2 and used.has(id):
				continue
			if rule < 1 and not fits(when(slot, id), slice):
				continue
			if rule < 3 and when(slot, id) == BEFORE and slice != BEFORE:
				continue
			choices.append(id)
		if not choices.is_empty():
			return choices[rng.randi_range(0, choices.size() - 1)]
	return clear[0] if not clear.is_empty() else ""


## Whether a take tagged `tag` belongs in a slice of kind `slice`.
static func fits(tag: String, slice: String) -> bool:
	if slice == ENTRY:
		return tag == ENTRY
	return tag.is_empty() or tag == slice


## A take's keys as written, the gate's actor named `gate_actor`. Empty for an unknown take.
func keys(slot: StringName, id: String, gate_actor: String) -> Array:
	var out: Array = []
	for raw: Variant in _entry(slot, id).get("keys", []):
		var key: Dictionary = (raw as Dictionary).duplicate(true)
		for part: String in ["position", "look_at"]:
			if key.get(part) is Dictionary and String((key[part] as Dictionary).get("actor", "")) == GATE_ACTOR:
				key[part]["actor"] = gate_actor
		out.append(key)
	return out


## The camera's positions at `times` (s into the take), with `pose_at(actor, i)` the actors' predicted poses at `times[i]`: what a
## clearance test reads.
static func camera_path(shot: CinematicShot, times: PackedFloat32Array, pose_at: Callable) -> PackedVector3Array:
	var camera := PackedVector3Array()
	for i: int in times.size():
		var poses: Callable = func(actor: String) -> Variant: return pose_at.call(actor, i)
		camera.append(shot.pose_at(times[i], poses, func(_o: PackedFloat64Array) -> Vector3: return Vector3.ZERO).transform.origin)
	return camera


func _entry(slot: StringName, id: String) -> Dictionary:
	for e: Dictionary in takes.get(slot, []):
		if String(e["id"]) == id:
			return e
	return {}
