extends GutTest
## The ram broad phase (M4-T03): every pair the resolver's exact test could find meeting is a candidate, checked against that
## test's own first step (the two bounding spheres meeting over the tick, relative motion, `SweepMath.segment_sphere`) on seeded
## crowds near the origin and 45 km out; pairs come in a full pass's order, without repeats; far pairs are skipped; the pairs
## Jolt holds in contact are always in.

const SEED: int = 20261102
const CROWDS: int = 40
const HULLS: int = 60
const DELTA: float = 1.0 / 60.0


## Whether the resolver's sphere test finds hulls `i` and `j` near each other over the tick (as in `RamResolver._sweep_pair`,
## without the rotation into the second's frame, which keeps distances).
static func _spheres_meet(starts: PackedVector3Array, ends: PackedVector3Array, radii: PackedFloat32Array, i: int, j: int) -> bool:
	var start: Vector3 = starts[i] - starts[j]
	var move: Vector3 = (ends[i] - starts[i]) - (ends[j] - starts[j])
	return SweepMath.segment_sphere(start, start + move, Vector3.ZERO, radii[i] + radii[j]) >= 0.0


## A seeded crowd of HULLS round `centre`: ships a few to 15 m across in a 300 m box, at up to 1 500 m/s (25 m per tick).
static func _crowd(rng: RandomNumberGenerator, centre: Vector3) -> Array:
	var starts := PackedVector3Array()
	var ends := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i: int in HULLS:
		var at: Vector3 = centre + Vector3(rng.randf_range(-150.0, 150.0), rng.randf_range(-150.0, 150.0), rng.randf_range(-150.0, 150.0))
		var velocity := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * rng.randf_range(0.0, 1500.0)
		starts.append(at)
		ends.append(at + velocity * DELTA)
		radii.append(rng.randf_range(1.0, 15.0))
	return [starts, ends, radii]


func _check_crowds(centre: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var missed: Array[String] = []
	var meeting: int = 0
	var candidates: int = 0
	for crowd: int in CROWDS:
		var made: Array = _crowd(rng, centre)
		var starts: PackedVector3Array = made[0]
		var ends: PackedVector3Array = made[1]
		var radii: PackedFloat32Array = made[2]
		var found: PackedInt64Array = RamBroadPhase.pairs(starts, ends, radii)
		candidates += found.size()
		for i: int in HULLS:
			for j: int in range(i + 1, HULLS):
				if _spheres_meet(starts, ends, radii, i, j):
					meeting += 1
					var key: int = i * HULLS + j
					var at: int = found.bsearch(key)
					if at >= found.size() or found[at] != key:
						missed.append("crowd %d: %d-%d" % [crowd, i, j])
	assert_eq(missed, [] as Array[String], "every pair whose spheres meet is a candidate")
	assert_gt(meeting, CROWDS, "the crowds are dense enough to have meetings to miss (%d)" % meeting)
	assert_lt(candidates, CROWDS * HULLS * (HULLS - 1) / 4.0, "and most pairs are skipped (%d candidates)" % candidates)


func test_every_pair_whose_spheres_meet_in_the_tick_is_a_candidate() -> void:
	_check_crowds(Vector3.ZERO)


func test_and_so_it_is_45_km_from_the_origin() -> void:
	_check_crowds(Vector3(45000.0, -3000.0, 12000.0))


func test_pairs_come_in_a_full_pass_order_without_repeats() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 1
	var made: Array = _crowd(rng, Vector3.ZERO)
	var found: PackedInt64Array = RamBroadPhase.pairs(made[0], made[1], made[2], PackedInt64Array([5 * HULLS + 7, 5 * HULLS + 7]))
	assert_gt(found.size(), 1)
	for k: int in found.size():
		var i: int = floori(float(found[k]) / HULLS)
		var j: int = found[k] - i * HULLS
		assert_lt(i, j, "i < j in %d" % found[k])
		if k > 0:
			assert_gt(found[k], found[k - 1], "ascending, no repeats")


func test_still_hulls_whose_spheres_touch_are_a_candidate_and_far_ones_are_not() -> void:
	var radii := PackedFloat32Array([10.0, 5.0, 10.0])
	var starts := PackedVector3Array([Vector3.ZERO, Vector3(0.0, 15.0, 0.0), Vector3(0.0, 0.0, 250.0)])
	assert_eq(RamBroadPhase.pairs(starts, starts, radii), PackedInt64Array([0 * 3 + 1]), "only the touching pair")


func test_hulls_far_apart_at_both_ends_of_the_tick_that_cross_in_it_are_a_candidate() -> void:
	# 50 m per tick each way, 25 m apart before and after: only the paths through the tick meet.
	var radii := PackedFloat32Array([10.0, 10.0])
	var starts := PackedVector3Array([Vector3(0.0, 0.0, 25.0), Vector3(0.0, 0.0, -25.0)])
	var ends := PackedVector3Array([Vector3(0.0, 0.0, -25.0), Vector3(0.0, 0.0, 25.0)])
	assert_eq(RamBroadPhase.pairs(starts, ends, radii), PackedInt64Array([1]))


func test_a_spread_out_lattice_has_no_candidates() -> void:
	var starts := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i: int in 48:
		starts.append(Vector3(float(i % 8) * 250.0, 0.0, floorf(float(i) / 8.0) * 250.0))
		radii.append(10.0)
	assert_eq(RamBroadPhase.pairs(starts, starts, radii).size(), 0)


func test_the_pairs_jolt_holds_in_contact_are_always_in() -> void:
	var radii := PackedFloat32Array([10.0, 10.0, 10.0])
	var starts := PackedVector3Array([Vector3.ZERO, Vector3(500.0, 0.0, 0.0), Vector3(0.0, 0.0, 15.0)])
	var found: PackedInt64Array = RamBroadPhase.pairs(starts, starts, radii, PackedInt64Array([0 * 3 + 1, 0 * 3 + 2]))
	assert_eq(found, PackedInt64Array([1, 2]), "the far contact pair, and the near pair once")


func test_no_hulls_no_pairs() -> void:
	assert_eq(RamBroadPhase.pairs(PackedVector3Array(), PackedVector3Array(), PackedFloat32Array()).size(), 0)
