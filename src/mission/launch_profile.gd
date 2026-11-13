class_name LaunchProfile
extends RefCounted
## How a Cobra-bay launch runs (M7-T08, D76), read from `data/launch/cobra_launch.json`: the steps' timings and the launch camera's
## shots, each played when the player's fighter has been in a step for a while. Data, so M8's squadron launch can bring its own.
##
## Steps of one fighter (`LaunchSequence`): `door` (its door opens), `hold` (waiting under the spine), `drop` (down the rail),
## `release` (the hand-off).

const DEFAULT_PATH: String = "res://data/launch/cobra_launch.json"
const STEPS: Array[StringName] = [&"door", &"hold", &"drop", &"release"]

## Seconds for a door's leaves to swing open, and how far they swing (degrees, outward).
var door_open_s: float = 3.0
var door_open_deg: float = 95.0
## Seconds to close, and how long after its last fighter left a door starts closing.
var door_close_s: float = 3.0
var door_close_after_s: float = 2.0
## Seconds from the rack to the release point, from rest at a steady acceleration.
var drop_s: float = 3.0
## Seconds between one fighter's drop and the next in a wave.
var stagger_s: float = 1.5
## Seconds from the first wave's last release to the second wave's first drop (maintainer, Q3).
var wave_gap_s: float = 10.0
## Seconds for the second row to move from staging onto the racks.
var row_move_s: float = 6.0
## The shots: each `{shot: CinematicShot, step: StringName, at_s: float}`, in file order.
var shots: Array[Dictionary] = []


## The profile in `path`: `{ok: true, profile}` or `{ok: false, error}`.
static func load_file(path: String = DEFAULT_PATH) -> Dictionary:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {"ok": false, "error": "%s: cannot read (%s)" % [path, error_string(FileAccess.get_open_error())]}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"ok": false, "error": "%s: line %d: %s" % [path, json.get_error_line(), json.get_error_message()]}
	return from_dict(json.data, path)


## A profile from its dictionary; every timing is optional (the defaults above).
static func from_dict(data: Variant, source: String = "launch profile") -> Dictionary:
	if not data is Dictionary:
		return {"ok": false, "error": "%s: the root must be an object" % source}
	var raw: Dictionary = data
	var made := LaunchProfile.new()
	for key: String in ["door_open_s", "door_open_deg", "door_close_s", "door_close_after_s", "drop_s", "stagger_s", "wave_gap_s",
			"row_move_s"]:
		var v: Variant = raw.get(key, made.get(key))
		if not (v is float or v is int) or float(v) < 0.0:
			return {"ok": false, "error": "%s: %s must be a number, 0 or more" % [source, key]}
		made.set(key, float(v))
	if made.drop_s <= 0.0 or made.row_move_s <= 0.0:
		return {"ok": false, "error": "%s: drop_s and row_move_s must be more than 0" % source}
	var list: Variant = raw.get("shots", [])
	if not list is Array:
		return {"ok": false, "error": "%s: shots must be an array" % source}
	for i: int in (list as Array).size():
		var entry: Variant = (list as Array)[i]
		if not entry is Dictionary:
			return {"ok": false, "error": "%s: shots[%d] must be an object" % [source, i]}
		var e: Dictionary = entry
		var step := StringName(str(e.get("step", "")))
		if not STEPS.has(step):
			return {"ok": false, "error": "%s: shots[%d].step must be one of %s" % [source, i, STEPS]}
		var at: Variant = e.get("at_s", 0.0)
		if not (at is float or at is int) or float(at) < 0.0:
			return {"ok": false, "error": "%s: shots[%d].at_s must be seconds, 0 or more" % [source, i]}
		var shot: Dictionary = CinematicShot.from_dict(StringName(str(e.get("id", "launch_%d" % i))), e)
		if not bool(shot["ok"]):
			return {"ok": false, "error": "%s: %s" % [source, shot["error"]]}
		made.shots.append({"shot": shot["shot"], "step": step, "at_s": float(at)})
	return {"ok": true, "profile": made}


## The shots that start in `step`, in file order.
func shots_in(step: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in shots:
		if entry["step"] == step:
			out.append(entry)
	return out
