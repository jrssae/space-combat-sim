extends GutTest
## The hit resolver's broad phase (M4-T08, architecture §17.7): `HitBroadPhase` must hand the resolver exactly the projectile
## and hull pairs its bounding-sphere test accepts (never fewer, so no hit is lost; never more, so the native and GDScript paths
## agreed bit for bit), in the resolver's order, for hulls from 5 m to 1 km, near the origin and far from it. The native sweep
## (`ScsHitSweep`) must do the work the GDScript reference did, recorded in `tests/fixtures/parity/hit_broad_phase.json`
## before M4-T37 removed that reference.

const FIXTURE: String = "hit_broad_phase"
const CROWDS: int = 40
const FAR_M: float = 45000.0

# The pairs the resolver's sphere test accepts, by testing every pair: the reference.
static func _every_pair(bolt_mids: PackedVector3Array, bolt_reach: PackedFloat64Array, hull_mids: PackedVector3Array,
		hull_reach: PackedFloat64Array) -> PackedInt64Array:
	var out := PackedInt64Array()
	for i: int in bolt_mids.size():
		for j: int in hull_mids.size():
			var reach: float = bolt_reach[i] + hull_reach[j]
			if bolt_mids[i].distance_squared_to(hull_mids[j]) > reach * reach:
				continue
			out.append(i * hull_mids.size() + j)
	return out


# A seeded crowd: hulls of 5 m to 1 km (some moving fast) and bolts, beams and missiles among them, near the origin or 45 km out.
static func _crowd(rng: RandomNumberGenerator, index: int) -> Dictionary:
	var centre := Vector3.ZERO
	if index % 2 == 1:
		centre = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized() * FAR_M
	var box_m: float = [600.0, 2000.0, 6000.0][index % 3]
	var hull_mids := PackedVector3Array()
	var hull_reach := PackedFloat64Array()
	for j: int in rng.randi_range(1, 120):
		hull_mids.append(centre + _in_box(rng, box_m))
		var radius: float = [5.0, 12.0, 30.0, 150.0, 600.0, 1000.0][rng.randi_range(0, 5)] if rng.randf() < 0.3 \
				else rng.randf_range(5.0, 15.0)
		hull_reach.append(radius + rng.randf_range(0.0, 400.0) / 60.0 * 0.5)
	var bolt_mids := PackedVector3Array()
	var bolt_reach := PackedFloat64Array()
	for i: int in rng.randi_range(0, 400):
		var roll: float = rng.randf()
		var at: Vector3
		if roll < 0.5 and hull_mids.size() > 0:
			# Near a hull, often right on the edge of the sphere test.
			var j: int = rng.randi_range(0, hull_mids.size() - 1)
			at = hull_mids[j] + _direction(rng) * float(hull_reach[j]) * rng.randf_range(0.9, 1.1)
		else:
			at = centre + _in_box(rng, box_m)
		bolt_mids.append(at)
		if roll > 0.98:
			bolt_reach.append(1500.0 + 0.5)  # a 3 km beam
		elif roll > 0.9:
			bolt_reach.append(rng.randf_range(2.0, 6.0) + 2.0)  # a missile
		else:
			bolt_reach.append(rng.randf_range(400.0, 1400.0) / 60.0 * 0.5 + 0.25)
	return {"bolt_mids": bolt_mids, "bolt_reach": bolt_reach, "hull_mids": hull_mids, "hull_reach": hull_reach}


static func _in_box(rng: RandomNumberGenerator, box_m: float) -> Vector3:
	var half: float = box_m * 0.5
	return Vector3(rng.randf_range(-half, half), rng.randf_range(-half, half), rng.randf_range(-half, half))


static func _direction(rng: RandomNumberGenerator) -> Vector3:
	var v := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
	return v.normalized() if v.length_squared() > 1e-6 else Vector3.UP


static func _pairs(phase: HitBroadPhase, crowd: Dictionary) -> PackedInt64Array:
	return phase.pairs(crowd["bolt_mids"], crowd["bolt_reach"], crowd["hull_mids"], crowd["hull_reach"])


static func _ascending(keys: PackedInt64Array) -> bool:
	for k: int in range(1, keys.size()):
		if keys[k] <= keys[k - 1]:
			return false
	return true


# --- what the resolver gets ---------------------------------------------------------------------------------------


func test_the_native_path_gives_the_same_pairs_and_work_as_gdscript() -> void:
	var recorded: Variant = ParityFixture.stored(FIXTURE, "work_seed_20261103")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261103
	var native := HitBroadPhase.new()
	assert_eq(native.path(), &"native", "%s answers (%s)" % [HitBroadPhase.NATIVE_CLASS, NativeLib.version(HitBroadPhase.NATIVE_CLASS)])
	assert_not_null(recorded, "the GDScript path's work was recorded")
	for index: int in CROWDS:
		var crowd: Dictionary = _crowd(rng, index)
		assert_eq(_pairs(native, crowd), _every_pair(crowd["bolt_mids"], crowd["bolt_reach"], crowd["hull_mids"],
				crowd["hull_reach"]), "crowd %d: every pair the sphere test accepts, and no other" % index)
		assert_eq(float(native.visited), float(recorded[index]), "crowd %d: the GDScript path's work (recorded)" % index)


func test_pairs_right_on_the_edge_of_the_sphere_test_are_the_sphere_test_s() -> void:
	# 3 000 projectiles 45 km out, each with a reach within a few parts in ten million of its distance to a hull, so a different
	# rounding of the distance (64-bit maths, another order of operations) puts many pairs on the other side of the line.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4508
	var hull_mids := PackedVector3Array()
	var hull_reach := PackedFloat64Array()
	var bolt_mids := PackedVector3Array()
	var bolt_reach := PackedFloat64Array()
	for j: int in 60:
		hull_mids.append(Vector3(45000.0, -45000.0, 30000.0) + _in_box(rng, 3000.0))
		hull_reach.append(rng.randf_range(5.0, 40.0))
	for i: int in 3000:
		var j: int = i % hull_mids.size()
		var at: Vector3 = hull_mids[j] + _direction(rng) * rng.randf_range(6.0, 50.0)
		var distance: float = sqrt(at.distance_squared_to(hull_mids[j])) * (1.0 + rng.randf_range(-3e-7, 3e-7))
		bolt_mids.append(at)
		bolt_reach.append(distance - hull_reach[j])
	var expected: PackedInt64Array = _every_pair(bolt_mids, bolt_reach, hull_mids, hull_reach)
	gut.p("%d of 3000 edge pairs pass the sphere test" % expected.size())
	assert_between(expected.size(), 300, 2700, "the edge splits the pairs")
	var phase := HitBroadPhase.new()
	assert_eq(phase.pairs(bolt_mids, bolt_reach, hull_mids, hull_reach), expected, "native")


func test_odd_inputs_give_what_the_sphere_test_gives() -> void:
	# Not finite, negative, beyond the grid and larger than the top level: each falls back to testing everything it must.
	var hull_mids := PackedVector3Array([Vector3.ZERO, Vector3(NAN, 0, 0), Vector3(30, 0, 0), Vector3(1.0e12, 0, 0),
			Vector3(INF, 0, 0), Vector3(-200, 0, 0), Vector3(0, 9000, 0)])
	var hull_reach := PackedFloat64Array([10.0, 10.0, -20.0, 10.0, 10.0, NAN, 20000.0])
	var bolt_mids := PackedVector3Array([Vector3(5, 0, 0), Vector3(1.0e12 + 4.0, 0, 0), Vector3(NAN, NAN, NAN),
			Vector3(-195, 0, 0), Vector3(25, 0, 0), Vector3(0, 0, 0)])
	var bolt_reach := PackedFloat64Array([1.0, 1.0, 1.0, 1.0, INF, -3.0])
	var expected: PackedInt64Array = _every_pair(bolt_mids, bolt_reach, hull_mids, hull_reach)
	var phase := HitBroadPhase.new()
	assert_eq(phase.path(), &"native")
	assert_eq(phase.pairs(bolt_mids, bolt_reach, hull_mids, hull_reach), expected, "native")


func test_nothing_to_pair_gives_no_pairs_and_no_work() -> void:
	var phase := HitBroadPhase.new()
	assert_eq(phase.pairs(PackedVector3Array(), PackedFloat64Array(), PackedVector3Array([Vector3.ZERO]),
			PackedFloat64Array([10.0])).size(), 0)
	assert_eq(phase.visited, 0)
	assert_eq(phase.pairs(PackedVector3Array([Vector3.ZERO]), PackedFloat64Array([1.0]), PackedVector3Array(),
			PackedFloat64Array()).size(), 0)
	assert_eq(phase.visited, 0)


func test_the_native_sweep_refuses_arrays_that_do_not_line_up() -> void:
	var sweep: Object = NativeLib.instantiate(HitBroadPhase.NATIVE_CLASS)
	assert_not_null(sweep, "the library provides %s" % HitBroadPhase.NATIVE_CLASS)
	if sweep == null:
		return
	var out: PackedInt64Array = sweep.pairs(PackedVector3Array([Vector3.ZERO]), PackedFloat64Array(),
			PackedVector3Array([Vector3.ZERO]), PackedFloat64Array([1.0]))
	assert_engine_error("lengths", "it says why")
	assert_eq(out.size(), 0, "no pairs")
	assert_eq(sweep.visited(), -1, "and no work count")


# --- the work ------------------------------------------------------------------------------------------------------


func test_a_capital_hull_is_found_from_anywhere_it_reaches_without_testing_the_fighters() -> void:
	# One 1 km hull among 200 fighters 250 m apart: a bolt anywhere in the hull's reach finds it, and tests few fighters.
	var hull_mids := PackedVector3Array([Vector3(1000, 0, 0)])
	var hull_reach := PackedFloat64Array([600.0])
	for k: int in 200:
		hull_mids.append(Vector3(float(k % 10) * 250.0, float((k / 10) % 5) * 250.0, float(k / 50) * 250.0) + Vector3(0, 0, 40))
		hull_reach.append(12.0)
	var bolt_mids := PackedVector3Array()
	var bolt_reach := PackedFloat64Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i: int in 300:
		bolt_mids.append(Vector3(1000, 0, 0) + _direction(rng) * rng.randf_range(0.0, 600.0))
		bolt_reach.append(4.0)
	var phase := HitBroadPhase.new()
	var got: PackedInt64Array = phase.pairs(bolt_mids, bolt_reach, hull_mids, hull_reach)
	assert_eq(got, _every_pair(bolt_mids, bolt_reach, hull_mids, hull_reach), "%s: the same as every pair" % phase.path())
	var capital_hits: int = 0
	for key: int in got:
		if key % hull_mids.size() == 0:
			capital_hits += 1
	assert_eq(capital_hits, 300, "%s: every bolt finds the capital" % phase.path())
	gut.p("%s: %d pairs tested for 300 bolts (every pair: %d)" % [phase.path(), phase.visited, 300 * hull_mids.size()])
	assert_lte(phase.visited, 300 * 3, "%s: at most 3 pairs a bolt" % phase.path())


# --- kept hulls: the static rows (M4-T29) -------------------------------------------------------------------------


func test_kept_hulls_give_the_same_pairs_as_handing_them_over_every_call() -> void:
	# Rocks do not move, so the resolvers keep them in the grid between ticks: the pairs must be exactly what the sphere test
	# accepts with the same hulls, and the work what the GDScript path did (recorded, M4-T37).
	var recorded: Variant = ParityFixture.stored(FIXTURE, "kept_work_seed_20261129")
	assert_not_null(recorded, "the GDScript path's work was recorded")
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026_11_29
	for index: int in CROWDS:
		var crowd: Dictionary = _crowd(rng, index)
		var expected: PackedInt64Array = _every_pair(crowd["bolt_mids"], crowd["bolt_reach"], crowd["hull_mids"], crowd["hull_reach"])
		var phase := HitBroadPhase.new()
		phase.keep(crowd["hull_mids"], crowd["hull_reach"])
		assert_eq(phase.kept_count(), (crowd["hull_mids"] as PackedVector3Array).size())
		var got: PackedInt64Array = phase.kept_pairs(crowd["bolt_mids"], crowd["bolt_reach"])
		assert_eq(got, expected, "crowd %d, %s: the kept grid gives the pairs the sphere test accepts" % [index, phase.path()])
		assert_eq(float(phase.visited), float(recorded[index]), "crowd %d: the GDScript path's work (recorded)" % index)
		# Asked again without keeping again: the grid was not rebuilt and answers the same.
		assert_eq(phase.kept_pairs(crowd["bolt_mids"], crowd["bolt_reach"]), expected, "crowd %d: and again" % index)


func test_a_bolt_far_from_a_thousand_kept_rocks_visits_none() -> void:
	# A rock slab kept once: a bolt among the ships 30 km away tests no rock, one inside the slab only its neighbours.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var rock_mids := PackedVector3Array()
	var rock_reach := PackedFloat64Array()
	for s: int in 1000:
		rock_mids.append(Vector3(rng.randf_range(-10000.0, 10000.0), rng.randf_range(-2500.0, 2500.0),
				rng.randf_range(-10000.0, 10000.0)))
		rock_reach.append(exp(rng.randf_range(log(20.0), log(200.0))))
	var phase := HitBroadPhase.new()
	phase.keep(rock_mids, rock_reach)
	phase.kept_pairs(PackedVector3Array([Vector3(30000.0, 0.0, 0.0)]), PackedFloat64Array([10.0]))
	assert_eq(phase.visited, 0, "%s: no rock tested for a bolt 30 km away" % phase.path())
	phase.kept_pairs(PackedVector3Array([Vector3(0.0, 0.0, 0.0)]), PackedFloat64Array([10.0]))
	gut.p("%s: %d of 1 000 rocks tested for a bolt in the slab" % [phase.path(), phase.visited])
	assert_lt(phase.visited, 40, "%s: a bolt in the slab tests its neighbours, not the slab" % phase.path())
