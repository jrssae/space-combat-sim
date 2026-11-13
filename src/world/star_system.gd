class_name StarSystem
extends RefCounted
## One star system's bodies and places (M6-T03, D65), read from `data/star_systems.json` and handed to the native ephemeris.
## GDScript never computes an orbit: every position comes from `ScsEphemeris`, so there is one implementation of the maths.
##
## File units: metres, seconds, degrees (the loader turns angles into radians); `gm` is authoritative (m^3/s^2, from g*r^2
## for a planet) and no mass is stored. A place is a point on a rail with no pull: on its own orbit around a body, or on
## another place's orbit at a phase offset (the jumpgate rides the station's). Positions are the kernel's axes
## (reference plane xy, z north), not the game's.

const PATH: String = "res://data/star_systems.json"
const NATIVE_CLASS: StringName = &"ScsEphemeris"
const KINDS: Dictionary = {"star": 0, "planet": 1, "moon": 2}
const MINOR_KIND: int = 3
## Matches the kernel's `MAX_ECCENTRICITY`.
const MAX_ECCENTRICITY: float = 0.99
const A_MIN_DEFAULT: float = 0.5

var id: StringName = &""
var title: String = ""
## Why the system was rejected; empty when it loaded.
var errors: PackedStringArray = PackedStringArray()
## The weakest pull that still counts, m/s^2 (D66).
var a_min: float = A_MIN_DEFAULT
## Body and place ids in file order.
var body_ids: Array[StringName] = []
var place_ids: Array[StringName] = []

var _native: RefCounted = null
var _index: Dictionary = {}  # StringName -> the kernel's index
var _info: Dictionary = {}  # StringName -> {kind, parent, gm, radius_m, atmosphere_top_m}
var _names: Dictionary = {}  # StringName -> the optional display name of a body or place


## The system `system_id` of the shipped file, or one with `errors` when it cannot be used.
static func load_system(system_id: StringName, path: String = PATH) -> StarSystem:
	var system := StarSystem.new()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		system.errors.append("%s cannot be read" % path)
		return system
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not (json.data is Dictionary):
		system.errors.append("%s is not a JSON object" % path)
		return system
	var systems: Variant = (json.data as Dictionary).get("systems")
	if not (systems is Dictionary) or not (systems as Dictionary).has(String(system_id)):
		system.errors.append("%s lists no system %s" % [path, system_id])
		return system
	system.build(system_id, (systems as Dictionary)[String(system_id)])
	return system


func is_valid() -> bool:
	return errors.is_empty() and _native != null


## Validates `entry` (one system's table) and fills the native ephemeris; every rejection adds a reason to `errors`.
func build(system_id: StringName, entry: Variant) -> void:
	id = system_id
	if not (entry is Dictionary):
		errors.append("system %s is not an object" % system_id)
		return
	var table: Dictionary = entry
	title = str(table.get("name", system_id))
	var floor_value: Variant = table.get("a_min", A_MIN_DEFAULT)
	if not _is_number(floor_value) or float(floor_value) < 0.0:
		errors.append("a_min must be a number of at least 0")
	else:
		a_min = float(floor_value)
	if not ClassDB.class_exists(NATIVE_CLASS):
		errors.append("the native library lacks %s (rebuild it with scripts/build_native.sh)" % NATIVE_CLASS)
		return
	var native: RefCounted = ClassDB.instantiate(NATIVE_CLASS)
	var bodies: Variant = table.get("bodies")
	if not (bodies is Array) or (bodies as Array).is_empty():
		errors.append("bodies must be a list with the star first")
		return
	for i: int in (bodies as Array).size():
		_add_body(native, i, (bodies as Array)[i])
	var places: Variant = table.get("places", [])
	if not (places is Array):
		errors.append("places must be a list")
	else:
		for i: int in (places as Array).size():
			_add_place(native, i, (places as Array)[i])
	if errors.is_empty():
		_native = native


## Where `body` (a body or place id) is against the root at `time_s`: position then velocity, six numbers in metres and m/s.
func state(body: StringName, time_s: float) -> PackedFloat64Array:
	if _native == null or not _index.has(body):
		return PackedFloat64Array()
	return _native.call(&"state", _index[body], time_s)


## The same, seen from `reference`'s centre, with no large subtraction (a place from its planet keeps its digits).
func relative_state(body: StringName, reference: StringName, time_s: float) -> PackedFloat64Array:
	if _native == null or not _index.has(body) or not _index.has(reference):
		return PackedFloat64Array()
	return _native.call(&"relative_state", _index[body], _index[reference], time_s)


## The straight-line distance between two bodies or places, metres.
func distance_m(a: StringName, b: StringName, time_s: float) -> float:
	var rel: PackedFloat64Array = relative_state(a, b, time_s)
	if rel.size() < 3:
		return NAN
	return sqrt(rel[0] * rel[0] + rel[1] * rel[1] + rel[2] * rel[2])


## The orbit period of a body or place, seconds; 0 for the star.
func period_s(body: StringName) -> float:
	if _native == null or not _index.has(body):
		return 0.0
	return _native.call(&"period_s", _index[body])


## How far a body's pull reaches (where its pull falls to `a_min`), metres.
func zone_radius_m(body: StringName) -> float:
	if _native == null or not _index.has(body):
		return 0.0
	return _native.call(&"zone_radius", _index[body], a_min)


## The body that pulls hardest at `point` (three numbers against `reference`'s centre), or an empty name where none does.
func dominant_body(point: PackedFloat64Array, reference: StringName, time_s: float) -> StringName:
	if _native == null or not _index.has(reference) or point.size() != 3:
		return &""
	var found: int = _native.call(&"dominant", point, _index[reference], time_s, a_min)
	for key: StringName in body_ids:
		if _index[key] == found:
			return key
	return &""


func has_id(name: StringName) -> bool:
	return _index.has(name)


## The body or place at the ephemeris's `index`, or an empty name.
func id_at(index: int) -> StringName:
	for key: StringName in _index:
		if int(_index[key]) == index:
			return key
	return &""


## What the HUD calls a body or place: its `name` in the file, else its id in capitals with spaces.
func display_name(body: StringName) -> String:
	if _names.has(body):
		return String(_names[body])
	return String(body).to_upper().replace("_", " ")


## How close to each body's centre a ship is destroyed (M6-T08, D67): its radius plus its atmosphere's top, by ephemeris
## index; 0 for a place.
func impact_radii() -> PackedFloat64Array:
	var radii := PackedFloat64Array()
	radii.resize(body_ids.size() + place_ids.size())
	radii.fill(0.0)
	for key: StringName in body_ids:
		var row: Dictionary = _info[key]
		var index: int = int(_index[key])
		if index >= radii.size():
			radii.resize(index + 1)
		radii[index] = float(row["radius_m"]) + float(row["atmosphere_top_m"])
	return radii


## The native ephemeris (`ScsEphemeris`) the frame copies its bodies from (M6-T04); null when the system did not load.
func ephemeris() -> RefCounted:
	return _native


## The ephemeris's index of a body or place, or -1 for an unknown id.
func index_of(name: StringName) -> int:
	return int(_index.get(name, -1))


## What the file says about a body: kind, parent, gm, radius_m, atmosphere_top_m. Empty for a place or an unknown id.
func info(body: StringName) -> Dictionary:
	return (_info.get(body, {}) as Dictionary).duplicate()


func _add_body(native: RefCounted, position: int, raw: Variant) -> void:
	var where: String = "bodies[%d]" % position
	if not (raw is Dictionary):
		errors.append("%s is not an object" % where)
		return
	var row: Dictionary = raw
	var key: StringName = _new_id(row, where)
	if key == &"":
		return
	where = "body %s" % key
	var kind_name: String = str(row.get("kind", ""))
	if not KINDS.has(kind_name):
		errors.append("%s: kind must be star, planet or moon, not '%s'" % [where, kind_name])
		return
	if not _is_number(row.get("gm")) or float(row["gm"]) <= 0.0:
		errors.append("%s: gm must be a positive number" % where)
		return
	if not _is_number(row.get("radius_m")) or float(row["radius_m"]) <= 0.0:
		errors.append("%s: radius_m must be a positive number" % where)
		return
	var atmosphere: Variant = row.get("atmosphere_top_m", 0.0)
	if not _is_number(atmosphere) or float(atmosphere) < 0.0:
		errors.append("%s: atmosphere_top_m must be a number of at least 0" % where)
		return
	var gm: float = float(row["gm"])
	var index: int
	var parent_name: StringName = StringName(str(row.get("parent", "")))
	if kind_name == "star":
		if parent_name != &"" or not body_ids.is_empty():
			errors.append("%s: the star is the first body and has no parent" % where)
			return
		index = native.call(&"add_root", KINDS[kind_name], gm)
	else:
		if not _index.has(parent_name) or not _info.has(parent_name):
			errors.append("%s: unknown parent '%s' (a parent is listed before its children)" % [where, parent_name])
			return
		var orbit: PackedFloat64Array = _orbit(row.get("orbit"), _info[parent_name], where)
		if orbit.is_empty():
			return
		index = native.call(&"add_body", KINDS[kind_name], gm, _index[parent_name], orbit)
	if index < 0:
		errors.append("%s: the ephemeris refused it" % where)
		return
	_index[key] = index
	body_ids.append(key)
	_keep_name(key, row)
	_info[key] = {"kind": StringName(kind_name), "parent": parent_name, "gm": gm, "radius_m": float(row["radius_m"]),
			"atmosphere_top_m": float(atmosphere)}


func _add_place(native: RefCounted, position: int, raw: Variant) -> void:
	var where: String = "places[%d]" % position
	if not (raw is Dictionary):
		errors.append("%s is not an object" % where)
		return
	var row: Dictionary = raw
	var key: StringName = _new_id(row, where)
	if key == &"":
		return
	where = "place %s" % key
	var index: int
	if row.has("same_orbit_as"):
		var leader: StringName = StringName(str(row["same_orbit_as"]))
		if not _index.has(leader):
			errors.append("%s: it rides the orbit of unknown '%s'" % [where, leader])
			return
		if not _is_number(row.get("phase_rad")):
			errors.append("%s: phase_rad must be a number" % where)
			return
		index = native.call(&"add_place", _index[leader], float(row["phase_rad"]))
	else:
		var parent_name: StringName = StringName(str(row.get("parent", "")))
		if not _info.has(parent_name):
			errors.append("%s: unknown parent '%s'" % [where, parent_name])
			return
		var orbit: PackedFloat64Array = _orbit(row.get("orbit"), _info[parent_name], where)
		if orbit.is_empty():
			return
		index = native.call(&"add_body", MINOR_KIND, 0.0, _index[parent_name], orbit)
	if index < 0:
		errors.append("%s: the ephemeris refused it (a place needs an orbit to ride)" % where)
		return
	_index[key] = index
	place_ids.append(key)
	_keep_name(key, row)


func _keep_name(key: StringName, row: Dictionary) -> void:
	if row.get("name") is String and not String(row["name"]).is_empty():
		_names[key] = String(row["name"])


# The id of a row, or "" with a reason when it is missing or used already.
func _new_id(row: Dictionary, where: String) -> StringName:
	var raw: String = str(row.get("id", ""))
	if raw.is_empty():
		errors.append("%s has no id" % where)
		return &""
	if _index.has(StringName(raw)):
		errors.append("%s: duplicate id '%s'" % [where, raw])
		return &""
	return StringName(raw)


# An orbit's seven kernel numbers (radians), or an empty array with a reason.
func _orbit(raw: Variant, parent: Dictionary, where: String) -> PackedFloat64Array:
	if not (raw is Dictionary):
		errors.append("%s: orbit must be an object" % where)
		return PackedFloat64Array()
	var orbit: Dictionary = raw
	for key: String in ["a_m", "e", "i_deg", "node_deg", "peri_deg", "m0_deg", "epoch_s"]:
		if orbit.has(key) and not _is_number(orbit[key]):
			errors.append("%s: orbit.%s must be a number" % [where, key])
			return PackedFloat64Array()
	if not orbit.has("a_m") or float(orbit["a_m"]) <= 0.0:
		errors.append("%s: orbit.a_m must be a positive number" % where)
		return PackedFloat64Array()
	var e: float = float(orbit.get("e", 0.0))
	if e < 0.0 or e > MAX_ECCENTRICITY:
		errors.append("%s: orbit.e %s is out of range (0 to %s; 1 or more is not an ellipse)" % [where, e, MAX_ECCENTRICITY])
		return PackedFloat64Array()
	if float(orbit["a_m"]) * (1.0 - e) <= float(parent["radius_m"]):
		errors.append("%s: the orbit dips inside its parent's surface" % where)
		return PackedFloat64Array()
	return PackedFloat64Array([float(orbit["a_m"]), e, deg_to_rad(float(orbit.get("i_deg", 0.0))),
			deg_to_rad(float(orbit.get("node_deg", 0.0))), deg_to_rad(float(orbit.get("peri_deg", 0.0))),
			deg_to_rad(float(orbit.get("m0_deg", 0.0))), float(orbit.get("epoch_s", 0.0))])


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT
