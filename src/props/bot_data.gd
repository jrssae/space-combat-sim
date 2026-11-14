class_name BotData
extends RefCounted
## The maintenance bots' loops, read from `data/station/bot_points.json` (M7-T11, Q11): per loop the body it belongs to (`frame`:
## the station's own frame, `drum`: the drum's, which turns), its control points in that body's frame, how fast and how many
## bots fly it, which way is out from the hull and where its hatches are. Pure; a malformed file is not fatal: `valid` is false
## and `error` says why.

const PATH: String = "res://data/station/bot_points.json"

var valid: bool = false
var error: String = ""
## The least distance a loop keeps from the hull, metres (the test holds it).
var clearance_m: float = 0.0
## Each loop: `name`, `body`, `speed_mps`, `bots`, `up` (Vector3), `points` (PackedVector3Array) and `hatches` (each `name`, `at`
## (a control point's index), `inside` (Vector3)).
var loops: Array[Dictionary] = []


static func load_file(path: String = PATH) -> BotData:
	var made := BotData.new()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		made.error = "no %s" % path
		return made
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		made.error = "%s is not a JSON object" % path
		return made
	made.error = made._parse(parsed as Dictionary)
	made.valid = made.error.is_empty()
	return made


static func from_dict(data: Dictionary) -> BotData:
	var made := BotData.new()
	made.error = made._parse(data)
	made.valid = made.error.is_empty()
	return made


## How many bots the loops fly in all.
func bot_count() -> int:
	var count: int = 0
	for loop: Dictionary in loops:
		count += int(loop["bots"])
	return count


func _parse(data: Dictionary) -> String:
	clearance_m = float(data.get("clearance_m", 0.0))
	var raw_loops: Variant = data.get("loops")
	if not raw_loops is Array or (raw_loops as Array).is_empty():
		return "bot_points has no loops[]"
	var names := {}
	for raw: Variant in raw_loops as Array:
		if not raw is Dictionary:
			return "a loop is not an object"
		var entry: Dictionary = raw
		var label: String = str(entry.get("name", ""))
		var body: String = str(entry.get("body", ""))
		if label.is_empty() or names.has(label):
			return "loop %d needs its own name" % loops.size()
		names[label] = true
		if body != StationHardpoints.FRAME and body != StationHardpoints.DRUM:
			return "loop %s: body must be frame or drum" % label
		var points := PackedVector3Array()
		for p: Variant in entry.get("points", []) as Array:
			if not _is_vec3(p):
				return "loop %s: a point is not three numbers" % label
			points.append(_vec3(p))
		if points.size() < 3:
			return "loop %s needs at least three points" % label
		var speed: float = float(entry.get("speed_mps", 0.0))
		var count: int = int(entry.get("bots", 1))
		if speed <= 0.0 or count < 1 or not _is_vec3(entry.get("up")):
			return "loop %s needs speed_mps above 0, bots of 1 or more and an up" % label
		var hatches: Array[Dictionary] = []
		for h: Variant in entry.get("hatches", []) as Array:
			var hatch: Dictionary = h if h is Dictionary else {}
			var at: int = int(hatch.get("at", -1))
			if at < 0 or at >= points.size() or not _is_vec3(hatch.get("inside")):
				return "loop %s: a hatch needs a control point `at` and an `inside`" % label
			hatches.append({"name": str(hatch.get("name", "")), "at": at, "inside": _vec3(hatch["inside"])})
		if hatches.is_empty():
			return "loop %s has no hatch" % label
		loops.append({"name": label, "body": body, "speed_mps": speed, "bots": count, "up": _vec3(entry["up"]).normalized(),
				"points": points, "hatches": hatches})
	return ""


static func _is_vec3(value: Variant) -> bool:
	if not value is Array or (value as Array).size() != 3:
		return false
	for v: Variant in value as Array:
		if not (v is float or v is int):
			return false
	return true


static func _vec3(value: Variant) -> Vector3:
	var a: Array = value
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
