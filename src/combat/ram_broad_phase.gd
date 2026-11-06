class_name RamBroadPhase
extends RefCounted
## The ram resolver's broad phase (M4-T03, architecture §17.3), pure: which pairs of hulls could come near each other in the
## coming tick, so that only those get the resolver's exact test. A pair the exact test would find meeting is never left out.
##
## Each hull is its bounding sphere swept along its path through the tick, boxed. Two hulls whose boxes do not overlap cannot
## meet in the tick, so their pair is skipped. The boxes are sorted along x and swept once, so the cost grows with the hulls and
## the pairs near each other, not with every pair.

## Extra room round every box, metres: far more than the float rounding of positions tens of kilometres from the origin.
const MARGIN_M: float = 1.0


## The pairs among `starts.size()` hulls that need the exact test, as `i * count + j` with `i < j`, ascending and without
## repeats, so they come in the order of a pass over every pair. Hull `i` moves in a straight line from `starts[i]` to `ends[i]`
## through the tick and fits in a sphere of `radii[i]` round that point. `always` (keys in the same form) are added whatever
## their distance: the pairs Jolt holds in contact.
static func pairs(starts: PackedVector3Array, ends: PackedVector3Array, radii: PackedFloat32Array,
		always: PackedInt64Array = PackedInt64Array()) -> PackedInt64Array:
	var count: int = starts.size()
	var lows := PackedVector3Array()
	var highs := PackedVector3Array()
	var order := PackedVector2Array()  # (low x, hull index): sorts by x, ties by index
	lows.resize(count)
	highs.resize(count)
	order.resize(count)
	for i: int in count:
		var grow := Vector3.ONE * (radii[i] + MARGIN_M)
		var low: Vector3 = starts[i].min(ends[i]) - grow
		lows[i] = low
		highs[i] = starts[i].max(ends[i]) + grow
		order[i] = Vector2(low.x, i)
	order.sort()
	var out := PackedInt64Array(always)
	for a: int in count:
		var i: int = int(order[a].y)
		var low_i: Vector3 = lows[i]
		var high_i: Vector3 = highs[i]
		for b: int in range(a + 1, count):
			var j: int = int(order[b].y)
			var low_j: Vector3 = lows[j]
			if low_j.x > high_i.x:
				break  # every later box starts farther along x
			var high_j: Vector3 = highs[j]
			if low_j.y > high_i.y or low_i.y > high_j.y or low_j.z > high_i.z or low_i.z > high_j.z:
				continue
			out.append(mini(i, j) * count + maxi(i, j))
	out.sort()
	var unique := PackedInt64Array()
	for key: int in out:
		if unique.is_empty() or unique[unique.size() - 1] != key:
			unique.append(key)
	return unique
