extends GutTest
## ConvexSweep (M3-T04, architecture §16 D32): do two hit volumes meet while one moves in a straight line. Hand cases for boxes
## and capsules (through, beside, edges, shrinking), the bounding-sphere filter, placing a volume, and seeded cross-checks against independent
## oracles evaluated at many instants of the move: the separating-axis test for two boxes, exact point-to-shape distances along
## a capsule's segment otherwise.

const SEED: int = 20261023
const CASES: int = 300
const INSTANTS: int = 240
## Oracle verdicts this close to touching are skipped: the cross-checks test the sweep, not float rounding at tangency.
const MARGIN: float = 0.03

var rng := RandomNumberGenerator.new()


func before_each() -> void:
	rng.seed = SEED


func _box(centre: Vector3, size: Vector3, basis: Basis = Basis.IDENTITY, shrink: float = 0.0) -> ConvexSweep.Convex:
	return ConvexSweep.Convex.of(HitShape.make_box(Transform3D(basis, centre), size), Transform3D.IDENTITY, shrink)


func _capsule(centre: Vector3, radius: float, height: float, basis: Basis = Basis.IDENTITY,
		shrink: float = 0.0) -> ConvexSweep.Convex:
	return ConvexSweep.Convex.of(HitShape.make_capsule(Transform3D(basis, centre), radius, height), Transform3D.IDENTITY, shrink)


# --- hand cases --------------------------------------------------------------------------------------------------


func test_volumes_at_rest_meet_when_they_overlap() -> void:
	var b: ConvexSweep.Convex = _box(Vector3.ZERO, Vector3(2.0, 2.0, 2.0))
	assert_true(ConvexSweep.overlaps(_box(Vector3(1.9, 0.0, 0.0), Vector3(2.0, 2.0, 2.0)), Vector3.ZERO, b))
	assert_false(ConvexSweep.overlaps(_box(Vector3(2.1, 0.0, 0.0), Vector3(2.0, 2.0, 2.0)), Vector3.ZERO, b))
	assert_true(ConvexSweep.overlaps(_box(Vector3(0.2, 0.1, 0.0), Vector3(0.5, 0.5, 0.5)), Vector3.ZERO, b), "one inside the other")


func test_a_box_that_crosses_another_in_one_move_meets_it() -> void:
	var b: ConvexSweep.Convex = _box(Vector3.ZERO, Vector3(2.0, 0.6, 2.0))
	var a: ConvexSweep.Convex = _box(Vector3(0.5, -6.0, 0.3), Vector3(1.0, 1.0, 1.0))
	assert_false(ConvexSweep.overlaps(a, Vector3.ZERO, b), "apart at the start")
	assert_false(ConvexSweep.overlaps(_box(Vector3(0.5, 6.0, 0.3), Vector3(1.0, 1.0, 1.0)), Vector3.ZERO, b), "and at the end")
	assert_true(ConvexSweep.overlaps(a, Vector3(0.0, 12.0, 0.0), b), "12 m straight through a 0.6 m plate")
	assert_false(ConvexSweep.overlaps(_box(Vector3(2.05, -6.0, 0.0), Vector3(2.0, 1.0, 1.0)), Vector3(0.0, 12.0, 0.0), b),
			"0.05 m beside it")


func test_an_edge_is_round_to_a_moving_sphere_not_square() -> void:
	# A sphere (a capsule with no segment) passing a box edge diagonally, 0.2 m clear in true distance. Growing the box by the
	# radius on each axis would call this a hit (the grown corner is square); the swept test must not.
	var b: ConvexSweep.Convex = _box(Vector3.ZERO, Vector3(2.0, 2.0, 2.0))
	var radius: float = 1.0
	var clear: float = 0.2
	var along: float = (1.0 + (radius + clear) / sqrt(2.0))
	var a: ConvexSweep.Convex = _capsule(Vector3(along, along, -6.0), radius, 2.0 * radius)
	assert_false(ConvexSweep.overlaps(a, Vector3(0.0, 0.0, 12.0), b), "0.2 m clear of the edge")
	var close: float = (1.0 + (radius - 0.05) / sqrt(2.0))
	assert_true(ConvexSweep.overlaps(_capsule(Vector3(close, close, -6.0), radius, 2.0 * radius), Vector3(0.0, 0.0, 12.0), b))


func test_capsules_cross_or_pass() -> void:
	var b: ConvexSweep.Convex = _capsule(Vector3.ZERO, 0.5, 6.0)  # axis along y
	var lying := Basis(Vector3.FORWARD, PI / 2.0)  # axis along x
	assert_true(ConvexSweep.overlaps(_capsule(Vector3(0.0, 1.0, -5.0), 0.5, 6.0, lying), Vector3(0.0, 0.0, 10.0), b))
	# The upright capsule's cap tops out at y = 3.0; the lying one's underside at 3.6 - 0.5 = 3.1.
	assert_false(ConvexSweep.overlaps(_capsule(Vector3(0.0, 3.6, -5.0), 0.5, 6.0, lying), Vector3(0.0, 0.0, 10.0), b),
			"0.1 m above the end cap")


func test_shrinking_keeps_only_the_points_that_deep() -> void:
	# Two 2 m boxes overlapping by 0.25 m, then by 0.35 m: with one shrunk by 0.3 m only the deeper overlap meets.
	var b: ConvexSweep.Convex = _box(Vector3.ZERO, Vector3(2.0, 2.0, 2.0), Basis.IDENTITY, 0.3)
	assert_false(ConvexSweep.overlaps(_box(Vector3(1.75, 0.0, 0.0), Vector3(2.0, 2.0, 2.0)), Vector3.ZERO, b))
	assert_true(ConvexSweep.overlaps(_box(Vector3(1.65, 0.0, 0.0), Vector3(2.0, 2.0, 2.0)), Vector3.ZERO, b))
	var thin: ConvexSweep.Convex = _box(Vector3.ZERO, Vector3(4.0, 0.5, 4.0), Basis.IDENTITY, 0.3)
	assert_true(thin.empty, "0.5 m thick has no point 0.3 m deep")
	assert_false(ConvexSweep.overlaps(_box(Vector3.ZERO, Vector3(1.0, 1.0, 1.0)), Vector3.ZERO, thin))
	assert_almost_eq(_capsule(Vector3.ZERO, 0.82, 5.0, Basis.IDENTITY, 0.3).radius, 0.52, 1e-6)
	assert_true(_capsule(Vector3.ZERO, 0.25, 5.0, Basis.IDENTITY, 0.3).empty)


func test_bounding_spheres_say_when_two_volumes_can_first_be_near() -> void:
	var b: ConvexSweep.Convex = _box(Vector3.ZERO, Vector3(2.0, 2.0, 2.0))
	assert_eq(ConvexSweep.spheres_meet(_box(Vector3(10.0, 0.0, -5.0), Vector3(1.0, 1.0, 1.0)), Vector3(0.0, 0.0, 10.0), b), -1.0)
	# Reaches sqrt(3) and sqrt(0.75): the spheres meet 2.598 m from b's centre, the faces only at 1.5 m.
	var a: ConvexSweep.Convex = _box(Vector3(-5.0, 0.0, 0.0), Vector3(1.0, 1.0, 1.0))
	var t: float = ConvexSweep.spheres_meet(a, Vector3(10.0, 0.0, 0.0), b)
	assert_almost_eq(t, (5.0 - sqrt(3.0) - sqrt(0.75)) / 10.0, 1e-5)
	assert_false(ConvexSweep.overlaps(a, Vector3(10.0, 0.0, 0.0) * t, b), "never later than the volumes' own touch")


func test_a_placed_volume_is_the_volume_built_in_place() -> void:
	var pose := Transform3D(Basis(Vector3(0.3, 1.0, -0.2).normalized(), 0.7), Vector3(4.0, -1.0, 2.5))
	var shape := HitShape.make_capsule(Transform3D(Basis(Vector3.RIGHT, 0.4), Vector3(0.5, 0.2, -1.0)), 0.6, 3.0)
	var placed: ConvexSweep.Convex = ConvexSweep.Convex.of(shape, Transform3D.IDENTITY).placed(pose)
	var built: ConvexSweep.Convex = ConvexSweep.Convex.of(shape, pose)
	assert_almost_eq(placed.p0, built.p0, Vector3.ONE * 1e-5)
	assert_almost_eq(placed.p1, built.p1, Vector3.ONE * 1e-5)
	assert_eq(placed.reach, built.reach)
	var box := HitShape.make_box(Transform3D(Basis(Vector3.UP, 1.1), Vector3(-2.0, 0.0, 1.0)), Vector3(3.0, 0.6, 1.5))
	var placed_box: ConvexSweep.Convex = ConvexSweep.Convex.of(box, Transform3D.IDENTITY, 0.1).placed(pose)
	var built_box: ConvexSweep.Convex = ConvexSweep.Convex.of(box, pose, 0.1)
	assert_almost_eq(placed_box.centre, built_box.centre, Vector3.ONE * 1e-5)
	for n: Vector3 in [Vector3.RIGHT, Vector3(0.2, -0.7, 0.4), Vector3(-1.0, 1.0, 1.0)]:
		assert_almost_eq(placed_box.support(n), built_box.support(n), Vector3.ONE * 1e-4)


# --- cross-checks against independent oracles ----------------------------------------------------------------------


func _random_basis() -> Basis:
	var axis := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
	if axis.length() < 1e-3:
		return Basis.IDENTITY
	return Basis(axis.normalized(), rng.randf_range(-PI, PI))


func _random_size() -> Vector3:
	return Vector3(rng.randf_range(0.2, 3.0), rng.randf_range(0.2, 3.0), rng.randf_range(0.2, 3.0))


## Separating-axis depth of two boxes at rest: positive = overlapping by about that much, negative = apart.
static func _sat_depth(ca: Vector3, ba: Basis, ha: Vector3, cb: Vector3, bb: Basis, hb: Vector3) -> float:
	var axes: Array[Vector3] = [ba.x, ba.y, ba.z, bb.x, bb.y, bb.z]
	for i: Vector3 in [ba.x, ba.y, ba.z]:
		for j: Vector3 in [bb.x, bb.y, bb.z]:
			var c: Vector3 = i.cross(j)
			if c.length() > 1e-4:
				axes.append(c.normalized())
	var depth: float = INF
	for n: Vector3 in axes:
		var ra: float = ha.x * absf(ba.x.dot(n)) + ha.y * absf(ba.y.dot(n)) + ha.z * absf(ba.z.dot(n))
		var rb: float = hb.x * absf(bb.x.dot(n)) + hb.y * absf(bb.y.dot(n)) + hb.z * absf(bb.z.dot(n))
		depth = minf(depth, ra + rb - absf((cb - ca).dot(n)))
	return depth


func test_box_pairs_agree_with_the_separating_axis_test_at_every_instant() -> void:
	var checked: int = 0
	var mismatches: Array[String] = []
	for i: int in CASES:
		var ba: Basis = _random_basis()
		var bb: Basis = _random_basis()
		var sa: Vector3 = _random_size()
		var sb: Vector3 = _random_size()
		var start := Vector3(rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0))
		var move := Vector3(rng.randf_range(-12.0, 12.0), rng.randf_range(-12.0, 12.0), rng.randf_range(-12.0, 12.0))
		var best: float = -INF
		for k: int in INSTANTS + 1:
			best = maxf(best, _sat_depth(start + move * (float(k) / INSTANTS), ba, sa * 0.5, Vector3.ZERO, bb, sb * 0.5))
		if absf(best) < MARGIN:
			continue
		checked += 1
		var swept: bool = ConvexSweep.overlaps(_box(start, sa, ba), move, _box(Vector3.ZERO, sb, bb))
		if swept != (best > 0.0):
			mismatches.append("case %d: sweep %s, oracle depth %.3f" % [i, swept, best])
	assert_eq(mismatches, [] as Array[String])
	assert_gt(checked, CASES / 2, "most cases are clear-cut")


## Exact distance from a point to a convex volume made by `_box` or `_capsule` (in the frame they share).
static func _distance(shape: HitShape, p: Vector3) -> float:
	var q: Vector3 = shape.transform.affine_inverse() * p
	if shape.kind == HitShape.Kind.BOX:
		var out := Vector3(maxf(absf(q.x) - shape.half_extents.x, 0.0), maxf(absf(q.y) - shape.half_extents.y, 0.0),
				maxf(absf(q.z) - shape.half_extents.z, 0.0))
		return out.length()
	var y: float = clampf(q.y, -shape.half_segment, shape.half_segment)
	return maxf((q - Vector3(0.0, y, 0.0)).length() - shape.radius, 0.0)


func test_capsules_agree_with_point_distances_along_their_segments() -> void:
	var checked: int = 0
	var mismatches: Array[String] = []
	for i: int in CASES:
		var radius: float = rng.randf_range(0.1, 1.2)
		var height: float = 2.0 * radius + rng.randf_range(0.0, 5.0)
		var ba: Basis = _random_basis()
		var start := Vector3(rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0))
		var move := Vector3(rng.randf_range(-12.0, 12.0), rng.randf_range(-12.0, 12.0), rng.randf_range(-12.0, 12.0))
		var other: HitShape
		if i % 2 == 0:
			other = HitShape.make_box(Transform3D(_random_basis(), Vector3.ZERO), _random_size())
		else:
			var other_radius: float = rng.randf_range(0.1, 1.2)
			other = HitShape.make_capsule(Transform3D(_random_basis(), Vector3.ZERO), other_radius,
					2.0 * other_radius + rng.randf_range(0.0, 5.0))
		var half: float = maxf(height * 0.5 - radius, 0.0)
		# Clearance at an instant: the capsule's segment, sampled finely, against the other volume's exact distance.
		var best: float = INF
		for k: int in INSTANTS + 1:
			var centre: Vector3 = start + move * (float(k) / INSTANTS)
			for s: int in 41:
				var p: Vector3 = centre + ba * Vector3(0.0, lerpf(-half, half, float(s) / 40.0), 0.0)
				best = minf(best, _distance(other, p) - radius)
		# Sampling along the segment overestimates the clearance by at most this much.
		var slack: float = (half / 40.0 + move.length() / INSTANTS) * 0.5
		if best > -MARGIN and best < MARGIN + slack:
			continue
		checked += 1
		var swept: bool = ConvexSweep.overlaps(_capsule(start, radius, height, ba), move,
				ConvexSweep.Convex.of(other, Transform3D.IDENTITY))
		if swept != (best <= 0.0):
			mismatches.append("case %d: sweep %s, oracle clearance %.3f" % [i, swept, best])
	assert_eq(mismatches, [] as Array[String])
	assert_gt(checked, CASES / 2, "most cases are clear-cut")
