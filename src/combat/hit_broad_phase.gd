class_name HitBroadPhase
extends RefCounted
## The hit resolver's broad phase (M4-T08, architecture §17.7): which projectile and hull pairs pass the resolver's
## bounding-sphere test this tick, found without testing every pair, so the resolver's cost follows the pairs near each other
## rather than projectiles times hulls. The answer is exactly the pairs the sphere test accepts, in the resolver's order.
##
## Hulls of any size, from a 10 m fighter to a 1 km capital ship, sit in a grid of levels: each hull goes into the level whose
## cells are at least twice its reach, at the cell holding its centre. A projectile looks only at the cells of each level its
## reach plus that level's largest hull reach can touch. A projectile whose look would cover more cells than the level has hulls
## (a 3 km beam), and a hull too odd to place (not finite, larger than the top level), are tested against everything instead.
##
## When the native library provides `NATIVE_CLASS` and `perf_native` is on, `ScsHitSweep` answers with the same grid and the same
## maths; the GDScript code here is the reference, and both give the same pairs and the same work count.

## The native class that answers when the library is loaded and `perf_native` is on.
const NATIVE_CLASS: StringName = &"ScsHitSweep"
## The finest level's cell (m), the factor between levels and how many levels there are (the top cell is 16 384 m).
const BASE_CELL_M: float = 64.0
const LEVEL_FACTOR: float = 4.0
const LEVELS: int = 5
## Room added round a projectile's look, so a pair the sphere test accepts is never in an unvisited cell.
const PAD_REL: float = 1e-6
const PAD_M: float = 1.0
## Cell indices past this (in cells from the origin) are not placed in the grid.
const MAX_CELL_INDEX: float = 1073741824.0

# Whether the loaded library provides `NATIVE_CLASS` (-1 until first asked).
static var _native_class_known: int = -1

## False forces the GDScript path, so a test or a bench can pair it with the native one.
var use_native: bool = true
## Pairs the last call put to the sphere test (the work count), whichever path answered.
var visited: int = 0

var _sweep: Object = null


## Which code answers now: &"native" or &"gdscript".
func path() -> StringName:
	return &"native" if _native() != null else &"gdscript"


## The pairs that pass the resolver's sphere test, as `bolt * hull_mids.size() + hull`, ascending. Projectile `i` is a sphere of
## `bolt_reach[i]` round `bolt_mids[i]` and hull `j` one of `hull_reach[j]` round `hull_mids[j]`; a pair passes unless the
## centres are farther apart than the two reaches added.
func pairs(bolt_mids: PackedVector3Array, bolt_reach: PackedFloat64Array, hull_mids: PackedVector3Array,
		hull_reach: PackedFloat64Array) -> PackedInt64Array:
	visited = 0
	if bolt_reach.size() != bolt_mids.size() or hull_reach.size() != hull_mids.size():
		push_error("HitBroadPhase.pairs: array lengths differ (bolts %d and %d, hulls %d and %d)" % [bolt_mids.size(),
				bolt_reach.size(), hull_mids.size(), hull_reach.size()])
		return PackedInt64Array()
	var sweep: Object = _native()
	if sweep != null:
		var out: PackedInt64Array = sweep.pairs(bolt_mids, bolt_reach, hull_mids, hull_reach)
		visited = sweep.visited()
		return out
	return _pairs_gdscript(bolt_mids, bolt_reach, hull_mids, hull_reach)


func _native() -> Object:
	if not use_native or not NativeLib.enabled():
		return null
	if _native_class_known < 0:
		_native_class_known = 1 if NativeLib.has_class(NATIVE_CLASS) else 0
	if _native_class_known == 0:
		return null
	if _sweep == null:
		_sweep = NativeLib.instantiate(NATIVE_CLASS)
	return _sweep


# The reference: the same grid as the native code, step for step, so both visit the same pairs.
func _pairs_gdscript(bolt_mids: PackedVector3Array, bolt_reach: PackedFloat64Array, hull_mids: PackedVector3Array,
		hull_reach: PackedFloat64Array) -> PackedInt64Array:
	var hull_count: int = hull_mids.size()
	var out := PackedInt64Array()
	if hull_count == 0 or bolt_mids.is_empty():
		return out
	var cells: Array[Dictionary] = []  # per level: Vector3i -> PackedInt32Array of hulls
	var members: Array[PackedInt32Array] = []  # per level: its hulls, ascending
	var level_reach := PackedFloat64Array()  # per level: its largest hull reach
	for level: int in LEVELS:
		cells.append({})
		members.append(PackedInt32Array())
		level_reach.append(0.0)
	var loose := PackedInt32Array()
	for j: int in hull_count:
		var reach: float = absf(hull_reach[j])
		var mid: Vector3 = hull_mids[j]
		var level: int = level_for(reach)
		if level < 0 or not _finite(mid):
			loose.append(j)
			continue
		var cell_m: float = cell_size(level)
		var key: Vector3 = Vector3(floorf(mid.x / cell_m), floorf(mid.y / cell_m), floorf(mid.z / cell_m))
		if absf(key.x) > MAX_CELL_INDEX or absf(key.y) > MAX_CELL_INDEX or absf(key.z) > MAX_CELL_INDEX:
			loose.append(j)
			continue
		var cell := Vector3i(int(key.x), int(key.y), int(key.z))
		var held: PackedInt32Array = cells[level].get(cell, PackedInt32Array())
		held.append(j)
		cells[level][cell] = held
		members[level].append(j)
		level_reach[level] = maxf(level_reach[level], reach)
	var candidates := PackedInt32Array()
	for i: int in bolt_mids.size():
		candidates.clear()
		var at: Vector3 = bolt_mids[i]
		var own: float = absf(bolt_reach[i])
		for level: int in LEVELS:
			var count: int = members[level].size()
			if count == 0:
				continue
			var cell_m: float = cell_size(level)
			var half: float = (own + level_reach[level]) * (1.0 + PAD_REL) + PAD_M
			var lx: float = floorf((at.x - half) / cell_m)
			var ly: float = floorf((at.y - half) / cell_m)
			var lz: float = floorf((at.z - half) / cell_m)
			var hx: float = floorf((at.x + half) / cell_m)
			var hy: float = floorf((at.y + half) / cell_m)
			var hz: float = floorf((at.z + half) / cell_m)
			var span: float = (hx - lx + 1.0) * (hy - ly + 1.0) * (hz - lz + 1.0)
			# Not finite, beyond the grid, or more cells than hulls: testing every hull of the level is cheaper and safe.
			if not (span <= float(count)) or not _within_grid(lx, ly, lz) or not _within_grid(hx, hy, hz):
				candidates.append_array(members[level])
				continue
			var level_cells: Dictionary = cells[level]
			for cx: int in range(int(lx), int(hx) + 1):
				for cy: int in range(int(ly), int(hy) + 1):
					for cz: int in range(int(lz), int(hz) + 1):
						var held: Variant = level_cells.get(Vector3i(cx, cy, cz))
						if held != null:
							candidates.append_array(held as PackedInt32Array)
		candidates.append_array(loose)
		candidates.sort()
		visited += candidates.size()
		for j: int in candidates:
			var reach: float = bolt_reach[i] + hull_reach[j]
			if at.distance_squared_to(hull_mids[j]) > reach * reach:
				continue
			out.append(i * hull_count + j)
	return out


## The grid level for a hull of this reach (its magnitude), or -1 when it fits no level.
static func level_for(reach: float) -> int:
	if is_nan(reach) or is_inf(reach):
		return -1
	var cell_m: float = BASE_CELL_M
	for level: int in LEVELS:
		if 2.0 * reach <= cell_m:
			return level
		cell_m *= LEVEL_FACTOR
	return -1


## The cell size of `level`, metres.
static func cell_size(level: int) -> float:
	return BASE_CELL_M * pow(LEVEL_FACTOR, level)


static func _finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


static func _within_grid(x: float, y: float, z: float) -> bool:
	return absf(x) <= MAX_CELL_INDEX and absf(y) <= MAX_CELL_INDEX and absf(z) <= MAX_CELL_INDEX
