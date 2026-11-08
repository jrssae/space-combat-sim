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
## `ScsHitSweep` (native, required since M4-T37) answers; the GDScript reference it matched lives on at the tag
## `m4-gdscript-reference`, and its work counts are recorded in `tests/fixtures/parity/hit_broad_phase.json`.
##
## Kept hulls (M4-T29): hulls that do not move between ticks (an asteroid field's rocks) are handed over once with `keep` and
## stay in their own grid; `kept_pairs` then finds a tick's pairs against them without handing them over again.
##
## The native core (M4-T15): `pairs_core` and `kept_pairs_core` take the hulls and bolts from the core's rows (the sweep
## builds the same spheres natively), so the resolver hands nothing over.

## The native class that answers.
const NATIVE_CLASS: StringName = &"ScsHitSweep"
# Whether the loaded library provides `NATIVE_CLASS` (-1 until first asked).

## Pairs the last call put to the sphere test (the work count).
var visited: int = 0

var _sweep: Object = null
# The kept hulls (handed to the native sweep on first use after `keep`).
var _kept_mids := PackedVector3Array()
var _kept_reach := PackedFloat64Array()
var _kept_native: bool = false


## Holds hulls that stay put (centres `hull_mids`, reaches `hull_reach`) for `kept_pairs` until the next `keep`.
func keep(hull_mids: PackedVector3Array, hull_reach: PackedFloat64Array) -> void:
	if hull_reach.size() != hull_mids.size():
		push_error("HitBroadPhase.keep: array lengths differ (hulls %d and %d); nothing kept" % [hull_mids.size(),
				hull_reach.size()])
		hull_mids = PackedVector3Array()
		hull_reach = PackedFloat64Array()
	_kept_mids = hull_mids
	_kept_reach = hull_reach
	_kept_native = false


## How many hulls `keep` holds.
func kept_count() -> int:
	return _kept_mids.size()


## `pairs` against the kept hulls: the same pairs, as `bolt * kept_count() + hull`, ascending, with `visited` set.
func kept_pairs(bolt_mids: PackedVector3Array, bolt_reach: PackedFloat64Array) -> PackedInt64Array:
	visited = 0
	if bolt_reach.size() != bolt_mids.size():
		push_error("HitBroadPhase.kept_pairs: array lengths differ (bolts %d and %d)" % [bolt_mids.size(), bolt_reach.size()])
		return PackedInt64Array()
	if _kept_mids.is_empty() or bolt_mids.is_empty():
		return PackedInt64Array()
	var sweep: Object = _native()
	if sweep == null:
		return PackedInt64Array()
	if not _kept_native:
		sweep.keep(_kept_mids, _kept_reach)
		_kept_native = true
	var out: PackedInt64Array = sweep.kept_pairs(bolt_mids, bolt_reach)
	visited = sweep.visited()
	return out


## Which code answers now: &"native", or &"none" when the library lacks the sweep (the game refuses to start then).
func path() -> StringName:
	return &"native" if _native() != null else &"none"


## `pairs` over the core's rows (M4-T15): the hull rows as the resolver's spheres (`position + velocity * (0.5 * delta)`,
## reach `radius + |velocity| * delta * 0.5`) against the bolts' segments, keys as `bolt * hulls + hull`. Nothing without
## the native sweep.
func pairs_core(core: Object, delta: float) -> PackedInt64Array:
	visited = 0
	var sweep: Object = _native()
	if sweep == null or core == null:
		return PackedInt64Array()
	var out: PackedInt64Array = sweep.pairs_core(core, delta)
	visited = sweep.visited()
	return out


## `kept_pairs` with the bolts read from the core's rows (M4-T15); nothing without the native sweep.
func kept_pairs_core(core: Object) -> PackedInt64Array:
	visited = 0
	var sweep: Object = _native()
	if sweep == null or core == null or _kept_mids.is_empty():
		return PackedInt64Array()
	if not _kept_native:
		sweep.keep(_kept_mids, _kept_reach)
		_kept_native = true
	var out: PackedInt64Array = sweep.kept_pairs_core(core)
	visited = sweep.visited()
	return out


## `kept_pairs` with the core's rigid hull rows as the moving spheres (M4-T15, the ram resolver's rocks): each as
## `(start + end) * 0.5` with reach `|end - start| * 0.5 + radius + margin`, keys as `rigid hull * kept + hull` where the
## rigid hulls count in the core's hull order. Nothing without the native sweep.
func kept_pairs_hulls_core(core: Object, delta: float, margin_m: float) -> PackedInt64Array:
	visited = 0
	var sweep: Object = _native()
	if sweep == null or core == null or _kept_mids.is_empty():
		return PackedInt64Array()
	if not _kept_native:
		sweep.keep(_kept_mids, _kept_reach)
		_kept_native = true
	var out: PackedInt64Array = sweep.kept_pairs_hulls_core(core, delta, margin_m)
	visited = sweep.visited()
	return out


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
	if sweep == null:
		return PackedInt64Array()
	var out: PackedInt64Array = sweep.pairs(bolt_mids, bolt_reach, hull_mids, hull_reach)
	visited = sweep.visited()
	return out


func _native() -> Object:
	if _sweep == null:
		_sweep = ClassDB.instantiate(NATIVE_CLASS)
	return _sweep
