class_name BotData
extends RefCounted
## The maintenance crew's tunables and ways round the station, read from `data/station/bot_points.json` (M7-T35, after T11's
## loops): how many bots fly and how fast, the shared roads out of the cargo bay (the trunk through the bow, the high road over the
## spine, the low road under the drum), the peace patrol areas (the spine, the fins, the drum, the jumpgate), the drum's riding
## radius along its green zone and each damage section's work spot. Points are in the station's frame. Pure; a malformed file is
## not fatal: `valid` is false and `error` says why.

const PATH: String = "res://data/station/bot_points.json"
const PEACE_KINDS: Array[String] = ["spine", "fins", "drum", "gate"]

var valid: bool = false
var error: String = ""
## The least distance every route keeps from the hull, metres (the clearance test holds it).
var clearance_m: float = 8.0

## The crew (`crew` in the file).
var pool: int = 12
var peace_min: int = 3
var peace_max: int = 6
var battle_max: int = 12
var repair_hp_s: float = 10.0
var cruise_mps: float = 25.0
var patrol_mps: float = 8.0
var transit_mps: float = 250.0
var accel_mps2: float = 4.0
var transit_accel_mps2: float = 10.0
var spin_s: float = 20.0
## A peace area's wait between trips and a patrol's stop at its far end, seconds `[least, most]`.
var peace_wait_s: Vector2 = Vector2(60.0, 400.0)
var peace_hold_s: Vector2 = Vector2(4.0, 15.0)
## A repair bot backs off `duck_m` while a hit landed within `duck_radius_m` of it in the last `duck_s`.
var duck_m: float = 40.0
var duck_radius_m: float = 100.0
var duck_s: float = 4.0

## The roads: the trunk from the cargo bay out past the bow, the climb from its end to the high road (flown at `top_y`) and the
## drop from its end to the low road (at `lower_y`).
var trunk := PackedVector3Array()
var climb := PackedVector3Array()
var top_y: float = 640.0
var lower_y: float = -500.0
## Corner rounding on the roads, metres.
var corner_m: float = 30.0
## Each peace area: `name`, `kind` (`PEACE_KINDS`) and its own keys (see the file's comment).
var peace: Array[Dictionary] = []
## The drum's riding radius along its green zone: x the station z, y the radius (sorted by z).
var drum_profile := PackedVector2Array()
## Each damage section by name: `work` (Vector3) and `via` (PackedVector3Array, may be empty) on the frame, or `z` and `r` on
## the drum.
var sections: Dictionary = {}
## How far out along its up a bot works on a grid mount, metres, by the mount's kind name; and mounts whose spot is given
## instead (`work`, `via`), by name, where the straight drop from the high road would pass too near the hull.
var mount_offset_m: Dictionary = {}
var mount_work: Dictionary = {}


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


## How many bots the crew has (the pool in the cargo bay).
func bot_count() -> int:
	return pool


## The peace area called `area_name`, or an empty one.
func peace_area(area_name: String) -> Dictionary:
	for a: Dictionary in peace:
		if a["name"] == area_name:
			return a
	return {}


## The drum's riding radius at station `z` (held at the profile's ends).
func drum_radius(z: float) -> float:
	var n: int = drum_profile.size()
	if n == 0:
		return 0.0
	if z <= drum_profile[0].x:
		return drum_profile[0].y
	for i: int in range(1, n):
		if z <= drum_profile[i].x:
			var a: Vector2 = drum_profile[i - 1]
			var b: Vector2 = drum_profile[i]
			return lerpf(a.y, b.y, (z - a.x) / maxf(b.x - a.x, 1e-6))
	return drum_profile[n - 1].y


func _parse(data: Dictionary) -> String:
	clearance_m = float(data.get("clearance_m", clearance_m))
	var crew: Dictionary = data.get("crew", {}) if data.get("crew") is Dictionary else {}
	pool = int(crew.get("pool", pool))
	peace_min = int(crew.get("peace_min", peace_min))
	peace_max = int(crew.get("peace_max", peace_max))
	battle_max = int(crew.get("battle_max", battle_max))
	repair_hp_s = float(crew.get("repair_hp_s", repair_hp_s))
	cruise_mps = float(crew.get("cruise_mps", cruise_mps))
	patrol_mps = float(crew.get("patrol_mps", patrol_mps))
	transit_mps = float(crew.get("transit_mps", transit_mps))
	accel_mps2 = float(crew.get("accel_mps2", accel_mps2))
	transit_accel_mps2 = float(crew.get("transit_accel_mps2", transit_accel_mps2))
	spin_s = float(crew.get("spin_s", spin_s))
	peace_wait_s = _range(crew.get("peace_wait_s"), peace_wait_s)
	peace_hold_s = _range(crew.get("peace_hold_s"), peace_hold_s)
	duck_m = float(crew.get("duck_m", duck_m))
	duck_radius_m = float(crew.get("duck_radius_m", duck_radius_m))
	duck_s = float(crew.get("duck_s", duck_s))
	if pool < 1 or peace_max < peace_min or battle_max < 1 or repair_hp_s <= 0.0 or cruise_mps <= 0.0 or patrol_mps <= 0.0 \
			or transit_mps <= 0.0 or accel_mps2 <= 0.0 or transit_accel_mps2 <= 0.0 or spin_s <= 0.0:
		return "crew: pool, counts, rates and speeds must be positive (peace_max at least peace_min)"
	var roads: Dictionary = data.get("roads", {}) if data.get("roads") is Dictionary else {}
	trunk = _points(roads.get("trunk"))
	climb = _points(roads.get("climb"))
	if trunk.size() < 2 or climb.size() < 1:
		return "roads need a trunk of two points or more and a climb"
	top_y = float(roads.get("top_y", top_y))
	lower_y = float(roads.get("lower_y", lower_y))
	corner_m = float(roads.get("corner_m", corner_m))
	var raw_peace: Variant = data.get("peace")
	if not raw_peace is Array or (raw_peace as Array).is_empty():
		return "bot_points has no peace[] areas"
	var names := {}
	for raw: Variant in raw_peace as Array:
		if not raw is Dictionary:
			return "a peace area is not an object"
		var entry: Dictionary = (raw as Dictionary).duplicate()
		var label: String = str(entry.get("name", ""))
		if label.is_empty() or names.has(label):
			return "peace area %d needs its own name" % peace.size()
		names[label] = true
		if not PEACE_KINDS.has(str(entry.get("kind", ""))):
			return "peace area %s: kind must be one of %s" % [label, PEACE_KINDS]
		if entry.has("points"):
			entry["points"] = _points(entry["points"])
		peace.append(entry)
	for raw: Variant in data.get("drum_profile", []) as Array:
		if raw is Array and (raw as Array).size() == 2:
			drum_profile.append(Vector2(float(raw[0]), float(raw[1])))
	if drum_profile.size() < 2:
		return "drum_profile needs two [z, r] pairs or more"
	var raw_sections: Variant = data.get("sections", {})
	if raw_sections is Dictionary:
		for key: Variant in raw_sections as Dictionary:
			var s: Dictionary = (raw_sections as Dictionary)[key]
			if s.has("work"):
				if not _is_vec3(s["work"]):
					return "section %s: work is not three numbers" % key
				sections[str(key)] = {"work": _vec3(s["work"]), "via": _points(s.get("via", []))}
			elif s.has("z") and s.has("r"):
				sections[str(key)] = {"z": float(s["z"]), "r": float(s["r"])}
			else:
				return "section %s needs a work point or a drum z and r" % key
	var raw_mounts: Variant = data.get("mount_work", {})
	if raw_mounts is Dictionary:
		for key: Variant in raw_mounts as Dictionary:
			var m: Dictionary = (raw_mounts as Dictionary)[key]
			if not _is_vec3(m.get("work")):
				return "mount_work %s needs a work point" % key
			mount_work[str(key)] = {"work": _vec3(m["work"]), "via": _points(m.get("via", []))}
	var offsets: Variant = data.get("mount_offset_m", {})
	if offsets is Dictionary:
		for key: Variant in offsets as Dictionary:
			mount_offset_m[str(key)] = float((offsets as Dictionary)[key])
	return ""


static func _range(value: Variant, fallback: Vector2) -> Vector2:
	if value is Array and (value as Array).size() == 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback


static func _points(value: Variant) -> PackedVector3Array:
	var out := PackedVector3Array()
	if value is Array:
		for p: Variant in value as Array:
			if _is_vec3(p):
				out.append(_vec3(p))
	return out


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
