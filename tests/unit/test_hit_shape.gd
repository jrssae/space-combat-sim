extends GutTest
## HitShape (architecture §15.4, §15.5): a box or capsule in the ship's body frame, built from `Hardpoints.collision`
## entries, swept in the body frame. Uses the static hardpoints fixture, never the generated assets.

const FIXTURE: String = "res://tests/fixtures/hardpoints_nominal.json"
const EPS: float = 1e-4
const RANDOM_SEGMENTS: int = 600
const SEED: int = 20261021
## Sampling check: the true volume is entered within this of the reported point, and no sample before it is inside.
const SURFACE_BAND: float = 1e-4
const SAMPLES: int = 2000

var hp: Hardpoints


func before_each() -> void:
	hp = Hardpoints.load_file(FIXTURE)


func _entry(entry_name: String) -> Dictionary:
	for entry: Dictionary in hp.collision:
		if entry["name"] == entry_name:
			return entry
	fail_test("no collision entry %s in the fixture" % entry_name)
	return {}


# --- construction --------------------------------------------------------------------------------------------


func test_make_box_stores_half_the_size() -> void:
	var xform := Transform3D(Basis.IDENTITY, Vector3(1, 2, 3))
	var shape := HitShape.make_box(xform, Vector3(2, 4, 6), "crate")
	assert_eq(shape.kind, HitShape.Kind.BOX)
	assert_eq(shape.half_extents, Vector3(1, 2, 3))
	assert_eq(shape.transform, xform)
	assert_eq(shape.shape_name, "crate")


func test_make_capsule_axis_runs_height_over_two_minus_radius() -> void:
	var shape := HitShape.make_capsule(Transform3D.IDENTITY, 0.5, 3.5)
	assert_eq(shape.kind, HitShape.Kind.CAPSULE)
	assert_eq(shape.radius, 0.5)
	assert_almost_eq(shape.half_segment, 1.25, 1e-9)
	var ball := HitShape.make_capsule(Transform3D.IDENTITY, 0.5, 0.8)
	assert_eq(ball.half_segment, 0.0, "a height below 2 * radius is a sphere")


func test_from_collision_copies_every_fixture_entry() -> void:
	assert_true(hp.valid, hp.error)
	assert_gt(hp.collision.size(), 0)
	for entry: Dictionary in hp.collision:
		var shape: HitShape = HitShape.from_collision(entry)
		assert_not_null(shape, str(entry["name"]))
		if shape == null:
			continue
		assert_eq(shape.shape_name, entry["name"])
		assert_eq(shape.transform, entry["transform"], "%s keeps the capsule axis turn" % entry["name"])
		if entry["type"] == "box":
			assert_eq(shape.kind, HitShape.Kind.BOX)
			assert_eq(shape.half_extents, (entry["shape"] as BoxShape3D).size * 0.5)
		else:
			var capsule: CapsuleShape3D = entry["shape"]
			assert_eq(shape.kind, HitShape.Kind.CAPSULE)
			assert_almost_eq(shape.radius, capsule.radius, 1e-9)
			assert_almost_eq(shape.half_segment, capsule.height * 0.5 - capsule.radius, 1e-6)


func test_from_collision_rejects_other_shapes_and_empty_entries() -> void:
	assert_null(HitShape.from_collision({"name": "ball", "shape": SphereShape3D.new(), "transform": Transform3D.IDENTITY}))
	assert_null(HitShape.from_collision({}))


# --- sweep ---------------------------------------------------------------------------------------------------


func test_sweep_box_in_the_body_frame() -> void:
	var entry: Dictionary = _entry("fuselage")
	var shape: HitShape = HitShape.from_collision(entry)
	var centre: Vector3 = (entry["transform"] as Transform3D).origin
	var half: Vector3 = (entry["shape"] as BoxShape3D).size * 0.5
	# 10 m out along +X, flying at the centre: the face is half.x (plus inflation) from the centre.
	var a: Vector3 = centre + Vector3(10, 0, 0)
	assert_almost_eq(shape.sweep(a, centre), (10.0 - half.x) / 10.0, EPS)
	assert_almost_eq(shape.sweep(a, centre, 0.25), (10.0 - half.x - 0.25) / 10.0, EPS)
	assert_eq(shape.sweep(a, a + Vector3(0, 0, 20)), -1.0, "parallel past the side")


func test_sweep_capsule_with_its_axis_turned_onto_z() -> void:
	var entry: Dictionary = _entry("pod_ur")
	var shape: HitShape = HitShape.from_collision(entry)
	var centre: Vector3 = (entry["transform"] as Transform3D).origin
	var capsule: CapsuleShape3D = entry["shape"]
	# Along +Y at the pod's mid-length: the side of the cylinder, `radius` from the axis.
	var a: Vector3 = centre + Vector3(0, 10, 0)
	assert_almost_eq(shape.sweep(a, centre), (10.0 - capsule.radius) / 10.0, EPS)
	assert_almost_eq(shape.sweep(a, centre, 0.25), (10.0 - capsule.radius - 0.25) / 10.0, EPS, "capsules grow exactly")
	# Along the pod's own axis (z) from behind: the end cap sits height / 2 from the centre.
	var behind: Vector3 = centre + Vector3(0, 0, 10)
	assert_almost_eq(shape.sweep(behind, centre), (10.0 - capsule.height * 0.5) / 10.0, EPS)
	# A segment past the nose of the pod misses.
	assert_eq(shape.sweep(centre + Vector3(0, 10, -3), centre + Vector3(0, -10, -3)), -1.0)


func test_sweep_rotated_box_follows_its_own_axes() -> void:
	# strut_ur is a box turned 45 degrees about Z: flying along its local X axis enters at half.x.
	var entry: Dictionary = _entry("strut_ur")
	var shape: HitShape = HitShape.from_collision(entry)
	var xform: Transform3D = entry["transform"]
	var half: Vector3 = (entry["shape"] as BoxShape3D).size * 0.5
	var axis: Vector3 = xform.basis.x.normalized()
	var a: Vector3 = xform.origin + axis * 10.0
	assert_almost_eq(shape.sweep(a, xform.origin), (10.0 - half.x) / 10.0, EPS)
	# The same world segment shifted sideways by more than the strut's thickness misses.
	var side: Vector3 = xform.basis.y.normalized() * (half.y + 0.5)
	assert_eq(shape.sweep(a + side, xform.origin + side), -1.0)


func test_sweep_capsule_with_the_axis_on_x_and_y() -> void:
	for axis_name: String in ["x", "y", "z"]:
		var xform := Transform3D(Hardpoints.capsule_axis_basis(axis_name), Vector3(1, 2, 3))
		var shape := HitShape.make_capsule(xform, 0.5, 4.0)  # half_segment 1.5
		var axis: Vector3 = xform.basis.y
		var across: Vector3 = Vector3.UP if absf(axis.y) < 0.5 else Vector3.RIGHT
		var centre: Vector3 = xform.origin
		assert_almost_eq(shape.sweep(centre + across * 10.0, centre), 0.95, EPS, "side hit, axis %s" % axis_name)
		assert_almost_eq(shape.sweep(centre + axis * 10.0, centre), (10.0 - 2.0) / 10.0, EPS, "cap hit, axis %s" % axis_name)
		assert_eq(shape.sweep(centre + axis * 10.0 + across * 0.6, centre + axis * -10.0 + across * 0.6), -1.0,
				"parallel to axis %s, outside" % axis_name)


func test_sweep_start_inside_is_zero_and_miss_is_minus_one() -> void:
	var shape := HitShape.make_box(Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(5, 0, 0)), Vector3(2, 2, 6))
	assert_eq(shape.sweep(Vector3(5, 0, 0), Vector3(20, 0, 0)), 0.0)
	assert_eq(shape.sweep(Vector3(0, 10, 0), Vector3(0, 20, 0)), -1.0)


func test_sweep_uses_the_transform_set_after_construction() -> void:
	var shape := HitShape.make_box(Transform3D.IDENTITY, Vector3(2, 2, 2))
	var a := Vector3(-10, 0, 0)
	var b := Vector3(10, 0, 0)
	assert_almost_eq(shape.sweep(a, b), 0.45, EPS)
	shape.transform = Transform3D(Basis.IDENTITY, Vector3(5, 0, 0))
	assert_almost_eq(shape.sweep(a, b), 0.7, EPS, "entry at x = 4")


func test_sweep_box_quarter_turn_swaps_the_extents() -> void:
	# Long on local Z (6 m); a quarter turn about Y lays it along body X.
	var shape := HitShape.make_box(Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3.ZERO), Vector3(2, 2, 6))
	assert_almost_eq(shape.sweep(Vector3(-10, 0, 0), Vector3(10, 0, 0)), 0.35, EPS, "enters at x = -3")
	assert_almost_eq(shape.sweep(Vector3(0, 0, -10), Vector3(0, 0, 10)), 0.45, EPS, "enters at z = -1")


# --- extent_radius and contains ------------------------------------------------------------------------------


func test_extent_radius_of_a_centred_box_is_its_half_diagonal() -> void:
	var shape := HitShape.make_box(Transform3D.IDENTITY, Vector3(2, 4, 6))
	assert_almost_eq(shape.extent_radius(), sqrt(14.0), 1e-5)


func test_extent_radius_of_an_offset_turned_box() -> void:
	var shifted := HitShape.make_box(Transform3D(Basis.IDENTITY, Vector3(10, 0, 0)), Vector3(2, 4, 6))
	assert_almost_eq(shifted.extent_radius(), sqrt(11.0 * 11.0 + 2.0 * 2.0 + 3.0 * 3.0), 1e-5)
	# A quarter turn about Y puts the 3 m half extent on X: the farthest corner is (13, 2, 1).
	var turned := HitShape.make_box(Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(10, 0, 0)), Vector3(2, 4, 6))
	assert_almost_eq(turned.extent_radius(), sqrt(13.0 * 13.0 + 2.0 * 2.0 + 1.0), 1e-4)


func test_extent_radius_of_capsules_is_the_far_cap_tip() -> void:
	var on_z := HitShape.make_capsule(Transform3D(Hardpoints.capsule_axis_basis("z"), Vector3(0, 0, 2)), 0.5, 3.0)
	assert_almost_eq(on_z.extent_radius(), 3.0 + 0.5, 1e-5, "axis ends at z = 1 and z = 3")
	var on_y := HitShape.make_capsule(Transform3D(Basis.IDENTITY, Vector3(3, 4, 0)), 0.5, 3.0)
	assert_almost_eq(on_y.extent_radius(), sqrt(3.0 * 3.0 + 5.0 * 5.0) + 0.5, 1e-5, "far end at (3, 5, 0)")


func test_extent_radius_bounds_every_contained_point() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for entry: Dictionary in hp.collision:
		var shape: HitShape = HitShape.from_collision(entry)
		var radius: float = shape.extent_radius()
		var farthest: float = 0.0
		for i: int in 3000:
			var p := Vector3(rng.randf_range(-8, 8), rng.randf_range(-8, 8), rng.randf_range(-8, 8))
			if shape.contains(p):
				farthest = maxf(farthest, p.length())
		assert_lte(farthest, radius + 1e-4, "%s lies inside its extent radius" % entry["name"])


func test_contains_box_and_inflation() -> void:
	var shape := HitShape.make_box(Transform3D(Basis.IDENTITY, Vector3(1, 0, 0)), Vector3(2, 2, 2))
	assert_true(shape.contains(Vector3(1, 0, 0)))
	assert_true(shape.contains(Vector3(1.9, 0.9, -0.9)))
	assert_true(shape.contains(Vector3(2, 0, 0)), "the surface counts")
	assert_false(shape.contains(Vector3(2.1, 0, 0)))
	assert_true(shape.contains(Vector3(2.1, 0, 0), 0.25))
	assert_false(shape.contains(Vector3(2.3, 0, 0), 0.25))


func test_contains_capsule_and_inflation() -> void:
	# Axis along body X, from x = 1 to x = 3, radius 0.5.
	var shape := HitShape.make_capsule(Transform3D(Hardpoints.capsule_axis_basis("x"), Vector3(2, 0, 0)), 0.5, 3.0)
	assert_true(shape.contains(Vector3(2, 0.4, 0)))
	assert_false(shape.contains(Vector3(2, 0.6, 0)))
	assert_true(shape.contains(Vector3(3.4, 0, 0)), "inside the cap")
	assert_false(shape.contains(Vector3(3.6, 0, 0)))
	assert_true(shape.contains(Vector3(3.6, 0, 0), 0.25), "capsule inflation is spherical")
	assert_false(shape.contains(Vector3(3.4, 0.4, 0.4)), "outside the rounded cap, inside its bounding box")
	assert_true(shape.contains(Vector3(2, 0.6, 0), 0.25))


# --- random segments against sampling ------------------------------------------------------------------------


func _random_vec(rng: RandomNumberGenerator, extent: float) -> Vector3:
	return Vector3(rng.randf_range(-extent, extent), rng.randf_range(-extent, extent), rng.randf_range(-extent, extent))


func _random_transform(rng: RandomNumberGenerator) -> Transform3D:
	var axis: Vector3 = _random_vec(rng, 1.0)
	if axis.length() < 0.1:
		axis = Vector3.UP
	return Transform3D(Basis(axis.normalized(), rng.randf_range(0.0, TAU)), _random_vec(rng, 1.5))


# Empty when `sweep` agrees with sampling `contains`: the entry point is on the surface, no earlier sample is
# inside, and a miss leaves every sample outside.
func _disagreement(shape: HitShape, a: Vector3, b: Vector3, inflate: float, t: float) -> String:
	if t < 0.0:
		for i: int in SAMPLES + 1:
			if shape.contains(a.lerp(b, float(i) / SAMPLES), inflate - SURFACE_BAND):
				return "reported a miss but sample %d is inside" % i
		return ""
	var entry_point: Vector3 = a.lerp(b, t)
	if not shape.contains(entry_point, inflate + SURFACE_BAND):
		return "entry point %s at t %.6f is outside the volume" % [entry_point, t]
	if t > 0.0:
		if shape.contains(entry_point, inflate - SURFACE_BAND):
			return "entry point %s at t %.6f is deep inside the volume" % [entry_point, t]
		for i: int in SAMPLES + 1:
			var earlier: float = float(i) / SAMPLES
			if earlier >= t - 1e-6:
				break
			if shape.contains(a.lerp(b, earlier), inflate - SURFACE_BAND):
				return "t %.6f but sample %d (t %.6f) is already inside" % [t, i, earlier]
	elif not shape.contains(a, inflate + SURFACE_BAND):
		return "t 0 but the start is outside"
	return ""


func _random_sweeps(make_shape: Callable, label: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var entering: int = 0
	var inside: int = 0
	var misses: int = 0
	var failures: Array[String] = []
	for i: int in RANDOM_SEGMENTS:
		var shape: HitShape = make_shape.call(rng)
		var inflate: float = [0.0, 0.1, 0.25][i % 3]
		var a: Vector3 = _random_vec(rng, 1.5 if i % 2 == 0 else 5.0)
		var b: Vector3 = _random_vec(rng, 5.0)
		var t: float = shape.sweep(a, b, inflate)
		if t < 0.0:
			misses += 1
		elif t == 0.0:
			inside += 1
		else:
			entering += 1
		var problem: String = _disagreement(shape, a, b, inflate, t)
		if not problem.is_empty():
			failures.append("#%d inflate %s %s -> %s: %s" % [i, inflate, a, b, problem])
			if failures.size() >= 5:
				break
	gut.p("%s: %d random sweeps: %d entering, %d starting inside, %d missing" % [
			label, RANDOM_SEGMENTS, entering, inside, misses])
	assert_eq(failures.size(), 0, "%s: %s" % [label, failures])
	assert_gt(entering, 60, "%s: enough entering segments" % label)
	assert_gt(misses, 60, "%s: enough missing segments" % label)
	assert_gt(inside, 10, "%s: enough segments starting inside" % label)


func _random_box(rng: RandomNumberGenerator) -> HitShape:
	var size := Vector3(rng.randf_range(0.5, 5.0), rng.randf_range(0.5, 5.0), rng.randf_range(0.5, 5.0))
	return HitShape.make_box(_random_transform(rng), size)


func _random_capsule(rng: RandomNumberGenerator) -> HitShape:
	var radius: float = rng.randf_range(0.5, 1.5)
	return HitShape.make_capsule(_random_transform(rng), radius, 2.0 * radius + rng.randf_range(0.0, 4.0))


func test_random_box_sweeps_match_sampling() -> void:
	_random_sweeps(_random_box, "box")


func test_random_capsule_sweeps_match_sampling() -> void:
	_random_sweeps(_random_capsule, "capsule")
