class_name UniversePos
extends RefCounted
## A position in the universe: three 64-bit floats in metres, in the inertial frame of one star system
## (architecture §14.1), plus the id of that system. This is the only type for positions that may be far from the
## `World` origin (spawn points, waypoints, celestial bodies); `Vector3` is float32 and is for `World`-local
## positions only. GDScript `float` is 64-bit in every Godot build, so this costs nothing over a double build.
##
## Instances are treated as values: no method mutates `self`, `plus_local` returns a new object.

var x: float = 0.0
var y: float = 0.0
var z: float = 0.0
var system_id: StringName = &"local"


func _init(px: float = 0.0, py: float = 0.0, pz: float = 0.0, p_system_id: StringName = &"local") -> void:
	x = px
	y = py
	z = pz
	system_id = p_system_id


## Builds a position in the default system from `[x, y, z]` (scenario JSON, where numbers may be ints or floats).
## Returns null and reports an error if `a` is not three numbers.
static func from_array(a: Array) -> UniversePos:
	if a.size() != 3:
		push_error("UniversePos.from_array: expected 3 elements, got %d" % a.size())
		return null
	for v: Variant in a:
		if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
			push_error("UniversePos.from_array: non-numeric element %s" % str(v))
			return null
	return UniversePos.new(float(a[0]), float(a[1]), float(a[2]))


## This position displaced by `v` metres, in the same system. The sum is done in 64-bit.
func plus_local(v: Vector3) -> UniversePos:
	return UniversePos.new(x + v.x, y + v.y, z + v.z, system_id)


## Vector from `self` to `other`. The subtraction is exact in 64-bit but the result is a float32 `Vector3`, so it is
## only meaningful for nearby positions (tens of km: ~1 mm resolution at 10 km). For far-apart positions use
## `distance_to`, which keeps 64-bit precision. Both positions must be in the same system.
func offset_to(other: UniversePos) -> Vector3:
	assert(system_id == other.system_id, "offset_to across systems: %s vs %s" % [system_id, other.system_id])
	return Vector3(other.x - x, other.y - y, other.z - z)


## Straight-line distance in metres, computed in 64-bit end to end. Both positions must be in the same system.
func distance_to(other: UniversePos) -> float:
	assert(system_id == other.system_id, "distance_to across systems: %s vs %s" % [system_id, other.system_id])
	var dx: float = other.x - x
	var dy: float = other.y - y
	var dz: float = other.z - z
	return sqrt(dx * dx + dy * dy + dz * dz)


func _to_string() -> String:
	return "UniversePos(%s: %.3f, %.3f, %.3f)" % [system_id, x, y, z]
