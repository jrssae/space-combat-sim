class_name HitBroadPhase
extends RefCounted
## The hit resolver's broad phase (M4-T08, architecture §17.7). Surface only, for the tests written first: it tests every pair.

const NATIVE_CLASS: StringName = &"ScsHitSweep"

var use_native: bool = true
var visited: int = 0


func path() -> StringName:
	return &"gdscript"


func pairs(bolt_mids: PackedVector3Array, bolt_reach: PackedFloat64Array, hull_mids: PackedVector3Array,
		hull_reach: PackedFloat64Array) -> PackedInt64Array:
	var out := PackedInt64Array()
	visited = bolt_mids.size() * hull_mids.size()
	for i: int in bolt_mids.size():
		for j: int in hull_mids.size():
			var reach: float = bolt_reach[i] + hull_reach[j]
			if bolt_mids[i].distance_squared_to(hull_mids[j]) > reach * reach:
				continue
			out.append(i * hull_mids.size() + j)
	return out
