class_name StationHardpoints
extends RefCounted
## The station's hardpoints as its generator writes them (M7-T05, D72; `tools/procgen/parts/station_hardpoints.py`): the Cobra bays'
## launch positions, the main docking bay (in the drum) and the cargo bay (zero-gravity, on the spine between the bow's forks), the defence
## grid's mounts (D75), the lights, the tour points and the damage sections.
## Each sits in the frame of the piece that carries it (`body`): `drum` (the drum node's frame, turning with it) or `frame` (the
## station node's). Pure: T06 places them, T07 binds the mounts, T08 launches from the bays, T12 tours the points, T18 lights them.
##
## A malformed section is not fatal: `valid` is false and `error` says why.

const DRUM: String = "drum"
const FRAME: String = "frame"

var valid: bool = false
var error: String = ""
## The drum's spin, rad/s about +Z.
var spin_rad_s: float = 0.0
## Each launch door (`cobra_bay_alpha_1` to `cobra_bay_zeta_6`: six an arm, one wing an arm), one Starfury each: `name`, `wing`,
## `arm`, `door_number`, `body`, and as Vector3 `door`, `normal`, `across`, `rail_start` (where the fighter hangs), `rail_end` (the
## door), `release`, `release_direction`, `surface_velocity`, `forward`, `up`, `staging` (where the second row's fighter waits) and
## `staging_path` (Array[Vector3] onto the rack); `door_half_m` a Vector2; `leaves` (each `leaf`, `point`, `axis`: its hinge).
var cobra_bays: Array[Dictionary] = []
## The doors' layout on one arm and each arm's wing (`cobra_arm`, as the manifest writes it), for the hangar's refit (T20).
var cobra_arm: Dictionary = {}
## Where a launch must wait (M7-T08): `blocked_sectors_deg` (each [from, to], counter-clockwise), `clear_distance_m`, `margin_deg`;
## see `launch_blocked`.
var launch_clearance: Dictionary = {}
## The main docking bay (in the drum, turning with it): `main_docking_bay_approach` and `_path` (Array[Vector3]), `_mouth`, `_airlock`,
## `_clear_half_m` (Vector2), and the drum's `spin_axis`, `spin_rad_s` and `pivot` a ship matches to fly in.
var main_docking_bay: Dictionary = {}
## The cargo bay (zero-gravity, on the frame): `cargo_bay_approach` and `_path` (Array[Vector3]), `_hold`, `_hold_forward`, `_release`,
## `_entry`, `_clear_min`, `_clear_max`.
var cargo_bay: Dictionary = {}
## D75's mounts: `name`, `kind` (`light_pulse`, `heavy_cannon`, `interceptor`), `body`, Vector3 `position` (the pivot) and `up`.
var grid_mounts: Array[Dictionary] = []
## Lights: `name`, `kind` (`beacon`, `running`, `ring`, `bay`, `aperture`), `body`, Vector3 `position`, `colour` (Color), and
## for a ring `radius` and Vector3 `axis`, `dashes`; `blink` true on beacons.
var lights: Array[Dictionary] = []
## Tour stops: `name`, `body`, Vector3 `position`, `look_at`, `direction`.
var tour_points: Array[Dictionary] = []
## Damage sections (Q5): `name`, `body`, `sections` (PackedStringArray of render sections), `aabb` (in the body's frame).
var damage_sections: Array[Dictionary] = []

## The hardpoints of a station manifest (its `hardpoints` section).
static func from_manifest(manifest: Dictionary) -> StationHardpoints:
	var made := StationHardpoints.new()
	var section: Variant = manifest.get("hardpoints")
	if not section is Dictionary:
		made.error = "the manifest has no hardpoints"
		return made
	made.error = made._parse(section as Dictionary)
	made.valid = made.error.is_empty()
	return made


## A point given in `body`'s frame, in the station node's frame, with the drum node at `drum_pivot` turned by `drum_turn_rad`
## about +Z (how T06 holds it).
static func to_station(point: Vector3, body: String, drum_pivot: Vector3, drum_turn_rad: float) -> Vector3:
	if body == DRUM:
		return drum_pivot + Basis(Vector3.BACK, drum_turn_rad) * point
	return point


func bay(name: String) -> Dictionary:
	return _named(cobra_bays, name)


## A wing's launch doors (`alpha`, `beta`, `delta`, `zeta`: one Cobra arm each), door 1 (nearest the bow) first.
func bays_of(wing: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for bay: Dictionary in cobra_bays:
		if bay.get("wing", "") == wing:
			out.append(bay)
	return out


## Whether an arm whose outward normal points at `arm_angle_deg` (its `cobra_arm` angle plus the drum's turn, degrees, about +Z
## from +X toward +Y) has the stationary frame in its doors' drop path: a launch from it waits.
func launch_blocked(arm_angle_deg: float) -> bool:
	var a: float = fposmod(arm_angle_deg, 360.0)
	for sector: Variant in launch_clearance.get("blocked_sectors_deg", []):
		var a0: float = fposmod(float(sector[0]), 360.0)
		var a1: float = fposmod(float(sector[1]), 360.0)
		if (a0 <= a1 and a >= a0 and a <= a1) or (a0 > a1 and (a >= a0 or a <= a1)):
			return true
	return false


func mount(name: String) -> Dictionary:
	return _named(grid_mounts, name)


func tour(name: String) -> Dictionary:
	return _named(tour_points, name)


func lights_of(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for light: Dictionary in lights:
		if light["kind"] == kind:
			out.append(light)
	return out


func _named(list: Array[Dictionary], name: String) -> Dictionary:
	for entry: Dictionary in list:
		if entry["name"] == name:
			return entry
	return {}


func _parse(section: Dictionary) -> String:
	spin_rad_s = float(section.get("spin_rad_s", 0.0))
	for pair: Array in [[cobra_bays, "cobra_bays"], [grid_mounts, "grid_mounts"], [lights, "lights"], [tour_points, "tour_points"],
			[damage_sections, "damage_sections"]]:
		var list: Variant = section.get(pair[1])
		if not list is Array:
			return "hardpoints.%s is missing" % pair[1]
		for value: Variant in list as Array:
			var entry: Variant = _entry(value)
			if entry is String:
				return "hardpoints.%s: %s" % [pair[1], entry]
			(pair[0] as Array[Dictionary]).append(entry as Dictionary)
	cobra_arm = section.get("cobra_arm", {})
	launch_clearance = section.get("launch_clearance", {})
	for key: String in ["main_docking_bay", "cargo_bay"]:
		var bay: Variant = _entry(section.get(key))
		if bay is String:
			return "hardpoints.%s: %s" % [key, bay]
		if key == "main_docking_bay":
			main_docking_bay = bay
		else:
			cargo_bay = bay
	return ""


# One entry with its points as Godot types (three numbers a Vector3, a list of them an Array[Vector3], a `*_half_m` pair a Vector2,
# a colour a Color, nested entries likewise), or a String saying what is wrong.
static func _entry(value: Variant) -> Variant:
	if not value is Dictionary:
		return "an entry is not an object"
	var raw: Dictionary = value
	var name: String = str(raw.get("name", ""))
	var body: String = str(raw.get("body", ""))
	if name.is_empty() or (body != DRUM and body != FRAME):
		return "entry '%s' needs a name and a body (drum or frame)" % name
	var out: Variant = _typed(raw, name)
	if out is String:
		return out
	var made: Dictionary = out
	if raw.has("aabb_min") and raw.has("aabb_max"):
		made["aabb"] = AABB(made["aabb_min"], made["aabb_max"] - made["aabb_min"])
	return made


static func _typed(raw: Dictionary, name: String) -> Variant:
	var out: Dictionary = {}
	for key: Variant in raw:
		var v: Variant = raw[key]
		var k: String = str(key)
		if k == "colour":
			out[k] = Color.html(str(v))
		elif k == "sections":
			out[k] = PackedStringArray(v as Array)
		elif k.ends_with("_half_m") and v is Array:
			if (v as Array).size() != 2:
				return "%s.%s is not [x, y]" % [name, k]
			out[k] = Vector2(float(v[0]), float(v[1]))
		elif v is Array and not (v as Array).is_empty() and (v as Array)[0] is Array:
			var path: Array[Vector3] = []
			for p: Variant in v as Array:
				if not _is_vec3(p):
					return "%s.%s has a point that is not [x, y, z]" % [name, k]
				path.append(_vec(p))
			out[k] = path
		elif v is Array and not (v as Array).is_empty() and (v as Array)[0] is Dictionary:
			var nested: Array[Dictionary] = []
			for item: Variant in v as Array:
				var typed: Variant = _typed(item as Dictionary, name)
				if typed is String:
					return typed
				nested.append(typed as Dictionary)
			out[k] = nested
		elif v is Array and (v as Array).size() == 3:
			if not _is_vec3(v):
				return "%s.%s is not [x, y, z]" % [name, k]
			out[k] = _vec(v)
		elif v is Array and (v as Array).size() != 3 and _is_point_key(k):
			return "%s.%s is not [x, y, z]" % [name, k]
		else:
			out[k] = v
	return out


# Keys that always hold a point, so a malformed one is refused rather than passed through.
static func _is_point_key(k: String) -> bool:
	return k in ["position", "door", "normal", "across", "release", "rail_start", "rail_end", "staging", "point", "look_at",
			"direction"]


static func _is_vec3(value: Variant) -> bool:
	if not value is Array or (value as Array).size() != 3:
		return false
	for c: Variant in value as Array:
		if not (c is float or c is int):
			return false
	return true


static func _vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
