class_name BuoyRing
extends RefCounted
## Nav buoys strung evenly round a ring, as if round a planet (architecture §18, M5-T10, Q21): where each one sits and what it
## is called, so a scenario declares a ring instead of typing every coordinate. Pure.
##
## The ring lies in the plane square to `normal`. The first buoy sits along `first` from the centre (`first` is flattened into
## the plane), and the rest follow at equal angles, turning from `first` towards `normal × first`. Sums are 64-bit: a ring
## tens of thousands of kilometres across keeps every buoy to the millimetre.

## Buoy names in ring order, after the prefix.
const PHONETIC: PackedStringArray = ["ALPHA", "BRAVO", "CHARLIE", "DELTA", "ECHO", "FOXTROT", "GOLF", "HOTEL", "INDIA",
		"JULIETT", "KILO", "LIMA", "MIKE", "NOVEMBER", "OSCAR", "PAPA", "QUEBEC", "ROMEO", "SIERRA", "TANGO", "UNIFORM",
		"VICTOR", "WHISKEY", "XRAY", "YANKEE", "ZULU"]
const MIN_COUNT: int = 3


## Why a ring cannot be built, or "".
static func problem(radius_m: float, count: int, normal: Vector3, first: Vector3) -> String:
	if not (radius_m > 0.0) or is_inf(radius_m):
		return "radius_m must be a number above 0"
	if count < MIN_COUNT or count > PHONETIC.size():
		return "count must be %d to %d (one name each)" % [MIN_COUNT, PHONETIC.size()]
	if normal.is_zero_approx():
		return "normal must be a non-zero [x, y, z]"
	var n: Vector3 = normal.normalized()
	if (first - n * first.dot(n)).length() < 1e-6:
		return "first must point somewhere in the ring's plane, not along its normal"
	return ""


## Every buoy's universe position, in ring order. Check `problem` first.
static func positions(centre: UniversePos, radius_m: float, count: int, normal: Vector3, first: Vector3) -> Array[UniversePos]:
	var n: PackedFloat64Array = _unit(PackedFloat64Array([normal.x, normal.y, normal.z]))
	var along: float = first.x * n[0] + first.y * n[1] + first.z * n[2]
	var flat := PackedFloat64Array([first.x - n[0] * along, first.y - n[1] * along, first.z - n[2] * along])
	var u: PackedFloat64Array = _unit(flat)
	var v := PackedFloat64Array([n[1] * u[2] - n[2] * u[1], n[2] * u[0] - n[0] * u[2], n[0] * u[1] - n[1] * u[0]])
	var out: Array[UniversePos] = []
	for i: int in count:
		var angle: float = TAU * i / count
		var c: float = cos(angle) * radius_m
		var s: float = sin(angle) * radius_m
		out.append(UniversePos.new(centre.x + u[0] * c + v[0] * s, centre.y + u[1] * c + v[1] * s,
				centre.z + u[2] * c + v[2] * s, centre.system_id))
	return out


## The buoys' names in ring order: `prefix` and a phonetic word ("NAV ALPHA", "NAV BRAVO", ...).
static func names(count: int, prefix: String = "NAV ") -> PackedStringArray:
	var out := PackedStringArray()
	for i: int in mini(count, PHONETIC.size()):
		out.append(prefix + PHONETIC[i])
	return out


## How many of `buoys` a ship at `point` hears when each broadcasts to `range_m` (the edge counts).
static func count_in_range(point: UniversePos, buoys: Array[UniversePos], range_m: float) -> int:
	var heard: int = 0
	for buoy: UniversePos in buoys:
		if point.distance_to(buoy) <= range_m:
			heard += 1
	return heard


static func _unit(v: PackedFloat64Array) -> PackedFloat64Array:
	var length: float = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
	return PackedFloat64Array([v[0] / length, v[1] / length, v[2] / length])
