extends GutTest
## SweepMath (architecture §15.5, AC1): entry fractions of a segment against a sphere, a box and a capsule. Analytic
## cases first (including start inside, parallel, zero-length and tangent), then 1 000 random segments per primitive
## against brute-force sampling of a signed distance field.

const EPS: float = 1e-6
## Sample points per segment for the brute-force cross-check.
const SAMPLES: int = 10000
## Classifications may disagree within this distance of tangency (metres).
const TANGENT_BAND: float = 1e-4
const RANDOM_SEGMENTS: int = 1000
const SEED: int = 20261020

const KIND_SPHERE: int = 0
const KIND_BOX: int = 1
const KIND_CAPSULE: int = 2


# --- sphere --------------------------------------------------------------------------------------------------


func test_sphere_head_on() -> void:
	assert_almost_eq(SweepMath.segment_sphere(Vector3(-10, 0, 0), Vector3(10, 0, 0), Vector3.ZERO, 1.0), 0.45, EPS)


func test_sphere_off_centre() -> void:
	# Entry at x = 4 on a 20 m segment starting at -10.
	assert_almost_eq(SweepMath.segment_sphere(Vector3(-10, 0, 0), Vector3(10, 0, 0), Vector3(5, 0, 0), 1.0), 0.7, EPS)


func test_sphere_grazing_counts_as_a_hit_at_the_middle() -> void:
	var t: float = SweepMath.segment_sphere(Vector3(-10, 1, 0), Vector3(10, 1, 0), Vector3.ZERO, 1.0)
	assert_almost_eq(t, 0.5, EPS)


func test_sphere_just_outside_misses() -> void:
	assert_eq(SweepMath.segment_sphere(Vector3(-10, 1.001, 0), Vector3(10, 1.001, 0), Vector3.ZERO, 1.0), -1.0)


func test_sphere_start_inside_is_zero() -> void:
	assert_eq(SweepMath.segment_sphere(Vector3(0.5, 0, 0), Vector3(10, 0, 0), Vector3.ZERO, 1.0), 0.0)
	assert_eq(SweepMath.segment_sphere(Vector3.ZERO, Vector3(10, 0, 0), Vector3.ZERO, 1.0), 0.0)


func test_sphere_start_on_the_surface_is_zero() -> void:
	assert_eq(SweepMath.segment_sphere(Vector3(-1, 0, 0), Vector3(10, 0, 0), Vector3.ZERO, 1.0), 0.0)


func test_sphere_end_inside_still_reports_the_entry() -> void:
	assert_almost_eq(SweepMath.segment_sphere(Vector3(-10, 0, 0), Vector3(0, 0, 0), Vector3.ZERO, 1.0), 0.9, EPS)


func test_sphere_segment_that_stops_short_misses() -> void:
	assert_eq(SweepMath.segment_sphere(Vector3(-10, 0, 0), Vector3(-5, 0, 0), Vector3.ZERO, 1.0), -1.0)


func test_sphere_moving_away_or_past_misses() -> void:
	assert_eq(SweepMath.segment_sphere(Vector3(-10, 0, 0), Vector3(-20, 0, 0), Vector3.ZERO, 1.0), -1.0, "away")
	assert_eq(SweepMath.segment_sphere(Vector3(10, 0, 0), Vector3(20, 0, 0), Vector3.ZERO, 1.0), -1.0, "sphere behind")


func test_sphere_zero_length_segment() -> void:
	assert_eq(SweepMath.segment_sphere(Vector3(5, 0, 0), Vector3(5, 0, 0), Vector3.ZERO, 1.0), -1.0, "outside")
	assert_eq(SweepMath.segment_sphere(Vector3(0.5, 0, 0), Vector3(0.5, 0, 0), Vector3.ZERO, 1.0), 0.0, "inside")


func test_sphere_a_bolt_longer_than_the_sphere_is_still_one_hit() -> void:
	# The segment passes through the whole sphere: the entry, not the exit, is reported.
	assert_almost_eq(SweepMath.segment_sphere(Vector3(0, 0, -50), Vector3(0, 0, 50), Vector3.ZERO, 3.0), 0.47, EPS)


func test_sphere_far_from_the_origin_keeps_its_precision() -> void:
	# All values are exact in float32 (multiples of 0.25 below 2^15), so the answer is exactly (100 - 1.25) / 200.
	var centre := Vector3(20000, 0, 0)
	var t: float = SweepMath.segment_sphere(centre + Vector3(-100, 0, 0), centre + Vector3(100, 0, 0), centre, 1.25)
	assert_almost_eq(t, 0.49375, 1e-9)


func test_sphere_nan_is_no_hit() -> void:
	assert_eq(SweepMath.segment_sphere(Vector3(NAN, 0, 0), Vector3(10, 0, 0), Vector3.ZERO, 1.0), -1.0)
	assert_eq(SweepMath.segment_sphere(Vector3(-10, 0, 0), Vector3(NAN, 0, 0), Vector3.ZERO, 1.0), -1.0)


func test_sphere_negative_radius_is_a_point() -> void:
	assert_eq(SweepMath.segment_sphere(Vector3(-10, 1, 0), Vector3(10, 1, 0), Vector3.ZERO, -1.0), -1.0)


# --- box -----------------------------------------------------------------------------------------------------


const BOX_HALF := Vector3(1, 2, 3)


func test_box_inflated_head_on_along_x() -> void:
	assert_almost_eq(SweepMath.segment_box(Vector3(-10, 0, 0), Vector3(10, 0, 0), BOX_HALF, 0.1), 0.445, EPS)


func test_box_along_y_and_z() -> void:
	assert_almost_eq(SweepMath.segment_box(Vector3(0, -10, 0), Vector3(0, 10, 0), BOX_HALF, 0.1), 0.395, EPS)
	assert_almost_eq(SweepMath.segment_box(Vector3(0, 0, -10), Vector3(0, 0, 10), BOX_HALF, 0.1), 0.345, EPS)


func test_box_inflate_defaults_to_zero() -> void:
	assert_almost_eq(SweepMath.segment_box(Vector3(-10, 0, 0), Vector3(10, 0, 0), BOX_HALF), 0.45, EPS)


func test_box_from_the_other_side_gives_the_mirror_fraction() -> void:
	assert_almost_eq(SweepMath.segment_box(Vector3(10, 0, 0), Vector3(-10, 0, 0), BOX_HALF, 0.1), 0.445, EPS)


func test_box_diagonal_through_a_corner() -> void:
	var t: float = SweepMath.segment_box(Vector3(-5, -5, 0), Vector3(5, 5, 0), Vector3(1, 1, 1), 0.0)
	assert_almost_eq(t, 0.4, EPS)


func test_box_start_inside_is_zero() -> void:
	assert_eq(SweepMath.segment_box(Vector3(0.5, 0.5, 0.5), Vector3(10, 0, 0), BOX_HALF, 0.1), 0.0)
	assert_eq(SweepMath.segment_box(Vector3(1.05, 0, 0), Vector3(10, 0, 0), BOX_HALF, 0.1), 0.0, "inside only thanks to the inflation")


func test_box_parallel_to_a_face_outside_misses_and_on_it_grazes() -> void:
	assert_eq(SweepMath.segment_box(Vector3(-10, 3, 0), Vector3(10, 3, 0), BOX_HALF, 0.1), -1.0, "outside the y slab")
	# 2.0 + 0.25 is exact: the segment slides along the inflated face and still counts, entering at x = -1.25.
	assert_almost_eq(SweepMath.segment_box(Vector3(-10, 2.25, 0), Vector3(10, 2.25, 0), BOX_HALF, 0.25), 0.4375, EPS)
	assert_eq(SweepMath.segment_box(Vector3(-10, 2.251, 0), Vector3(10, 2.251, 0), BOX_HALF, 0.25), -1.0)


func test_box_segment_that_stops_short_or_points_away_misses() -> void:
	assert_eq(SweepMath.segment_box(Vector3(-10, 0, 0), Vector3(-5, 0, 0), BOX_HALF, 0.1), -1.0, "stops short")
	assert_eq(SweepMath.segment_box(Vector3(-10, 0, 0), Vector3(-20, 0, 0), BOX_HALF, 0.1), -1.0, "away")
	assert_eq(SweepMath.segment_box(Vector3(10, 0, 0), Vector3(20, 0, 0), BOX_HALF, 0.1), -1.0, "box behind")


func test_box_end_inside_still_reports_the_entry() -> void:
	assert_almost_eq(SweepMath.segment_box(Vector3(-10, 0, 0), Vector3(0, 0, 0), BOX_HALF, 0.1), 0.89, EPS)


func test_box_zero_length_segment() -> void:
	assert_eq(SweepMath.segment_box(Vector3(5, 0, 0), Vector3(5, 0, 0), BOX_HALF, 0.1), -1.0, "outside")
	assert_eq(SweepMath.segment_box(Vector3(0.5, 0, 0), Vector3(0.5, 0, 0), BOX_HALF, 0.1), 0.0, "inside")


func test_box_miss_in_the_corner_region() -> void:
	# The line x + y = 2.2 passes the unit square's corner (1, 1): the x and y slabs are crossed at different
	# times (t in [1/6, 1/2] and [0.533, 0.867]), so the intervals do not overlap.
	assert_eq(SweepMath.segment_box(Vector3(-2, 4.2, 0), Vector3(4, -1.8, 0), Vector3(1, 1, 1), 0.0), -1.0)


func test_box_empty_when_the_extent_is_negative() -> void:
	assert_eq(SweepMath.segment_box(Vector3(-10, 0, 0), Vector3(10, 0, 0), Vector3(1, 2, 3), -1.5), -1.0)


func test_box_nan_is_no_hit() -> void:
	assert_eq(SweepMath.segment_box(Vector3(NAN, 0, 0), Vector3(10, 0, 0), BOX_HALF, 0.1), -1.0)
	assert_eq(SweepMath.segment_box(Vector3(-10, 0, 0), Vector3(10, 0, 0), BOX_HALF, NAN), -1.0)


# --- capsule -------------------------------------------------------------------------------------------------


const CAPSULE_H: float = 1.5
const CAPSULE_R: float = 0.5


func test_capsule_along_x_hits_the_cylinder() -> void:
	var t: float = SweepMath.segment_capsule(Vector3(-10, 0, 0), Vector3(10, 0, 0), CAPSULE_H, CAPSULE_R)
	assert_almost_eq(t, 0.475, EPS)


func test_capsule_along_x_above_the_cylinder_hits_the_end_sphere() -> void:
	# y = 1.8 is past the cylinder (|y| <= 1.5) but inside the top sphere's reach: chord half-length 0.4.
	var t: float = SweepMath.segment_capsule(Vector3(-10, 1.8, 0), Vector3(10, 1.8, 0), CAPSULE_H, CAPSULE_R)
	assert_almost_eq(t, 0.48, EPS)
	var below: float = SweepMath.segment_capsule(Vector3(-10, -1.8, 0), Vector3(10, -1.8, 0), CAPSULE_H, CAPSULE_R)
	assert_almost_eq(below, 0.48, EPS)


func test_capsule_along_the_axis_hits_the_cap() -> void:
	var t: float = SweepMath.segment_capsule(Vector3(0, -10, 0), Vector3(0, 10, 0), CAPSULE_H, CAPSULE_R)
	assert_almost_eq(t, 0.4, EPS)
	var down: float = SweepMath.segment_capsule(Vector3(0, 10, 0), Vector3(0, -10, 0), CAPSULE_H, CAPSULE_R)
	assert_almost_eq(down, 0.4, EPS)


func test_capsule_along_z() -> void:
	var t: float = SweepMath.segment_capsule(Vector3(0, 0, -10), Vector3(0, 0, 10), CAPSULE_H, CAPSULE_R)
	assert_almost_eq(t, 0.475, EPS)


func test_capsule_parallel_to_the_axis_outside_misses() -> void:
	assert_eq(SweepMath.segment_capsule(Vector3(0.6, -10, 0), Vector3(0.6, 10, 0), CAPSULE_H, CAPSULE_R), -1.0)
	assert_eq(SweepMath.segment_capsule(Vector3(0, -10, 0.6), Vector3(0, 10, 0.6), CAPSULE_H, CAPSULE_R), -1.0)


func test_capsule_parallel_to_the_axis_grazing_hits_the_side() -> void:
	# x = 0.5 is exactly the radius: the segment runs along the cylinder wall, entering at the lower cap sphere's
	# equator (y = -1.5), t = (10 - 1.5) / 20.
	var t: float = SweepMath.segment_capsule(Vector3(0.5, -10, 0), Vector3(0.5, 10, 0), CAPSULE_H, CAPSULE_R)
	assert_almost_eq(t, 0.425, EPS)


func test_capsule_grazing_the_cylinder_hits_at_the_tangent_point() -> void:
	var t: float = SweepMath.segment_capsule(Vector3(-10, 0, 0.5), Vector3(10, 0, 0.5), CAPSULE_H, CAPSULE_R)
	assert_almost_eq(t, 0.5, EPS)
	assert_eq(SweepMath.segment_capsule(Vector3(-10, 0, 0.501), Vector3(10, 0, 0.501), CAPSULE_H, CAPSULE_R), -1.0)


func test_capsule_grazing_the_end_sphere() -> void:
	# y = h + r touches the top of the cap.
	var t: float = SweepMath.segment_capsule(Vector3(-10, 2.0, 0), Vector3(10, 2.0, 0), CAPSULE_H, CAPSULE_R)
	assert_almost_eq(t, 0.5, EPS)
	assert_eq(SweepMath.segment_capsule(Vector3(-10, 2.001, 0), Vector3(10, 2.001, 0), CAPSULE_H, CAPSULE_R), -1.0)


func test_capsule_start_inside_is_zero() -> void:
	assert_eq(SweepMath.segment_capsule(Vector3(0.2, 0.3, 0.1), Vector3(10, 0, 0), CAPSULE_H, CAPSULE_R), 0.0, "cylinder")
	assert_eq(SweepMath.segment_capsule(Vector3(0, 1.9, 0), Vector3(10, 0, 0), CAPSULE_H, CAPSULE_R), 0.0, "top cap")
	assert_eq(SweepMath.segment_capsule(Vector3(0, -1.9, 0.1), Vector3(10, 0, 0), CAPSULE_H, CAPSULE_R), 0.0, "bottom cap")
	assert_eq(SweepMath.segment_capsule(Vector3.ZERO, Vector3.ZERO, CAPSULE_H, CAPSULE_R), 0.0, "zero-length")


func test_capsule_start_on_the_surface_is_zero() -> void:
	assert_eq(SweepMath.segment_capsule(Vector3(-0.5, 0, 0), Vector3(10, 0, 0), CAPSULE_H, CAPSULE_R), 0.0)


func test_capsule_beyond_a_cap_inside_the_axis_cylinder() -> void:
	# Starts above the top cap on the axis line (inside the infinite cylinder): only the end sphere can be hit.
	assert_almost_eq(SweepMath.segment_capsule(Vector3(0, 5, 0), Vector3(0, 0, 0), CAPSULE_H, CAPSULE_R), 0.6, EPS)
	assert_eq(SweepMath.segment_capsule(Vector3(0, 5, 0), Vector3(0, 10, 0), CAPSULE_H, CAPSULE_R), -1.0, "away")
	assert_eq(SweepMath.segment_capsule(Vector3(0.4, 5, 0), Vector3(0.4, 2.3, 0), CAPSULE_H, CAPSULE_R), -1.0, "stops short")


func test_capsule_diagonal_into_the_cap() -> void:
	# Heading down and to the right at 45 degrees onto the top of the capsule: only the end sphere (centre
	# (0, 1.5, 0), radius 0.5) can be hit, and the entry point lies on its surface.
	var a := Vector3(-3, 4.5, 0)
	var b := Vector3(0.3, 1.2, 0)
	var t: float = SweepMath.segment_capsule(a, b, CAPSULE_H, CAPSULE_R)
	assert_gt(t, 0.0)
	assert_lt(t, 1.0)
	var entry: Vector3 = a.lerp(b, t)
	assert_almost_eq(entry.distance_to(Vector3(0, CAPSULE_H, 0)), CAPSULE_R, 1e-5, "the entry point is on the end sphere")


func test_capsule_miss_past_the_end() -> void:
	assert_eq(SweepMath.segment_capsule(Vector3(-10, 3, 0), Vector3(10, 3, 0), CAPSULE_H, CAPSULE_R), -1.0)
	assert_eq(SweepMath.segment_capsule(Vector3(-10, 0, 0), Vector3(-5, 0, 0), CAPSULE_H, CAPSULE_R), -1.0, "stops short")


func test_capsule_zero_length_outside_misses() -> void:
	assert_eq(SweepMath.segment_capsule(Vector3(3, 0, 0), Vector3(3, 0, 0), CAPSULE_H, CAPSULE_R), -1.0)


func test_capsule_without_a_cylinder_is_a_sphere() -> void:
	var a := Vector3(-10, 0.3, 0.2)
	var b := Vector3(10, -0.4, 0.1)
	assert_almost_eq(SweepMath.segment_capsule(a, b, 0.0, 1.0), SweepMath.segment_sphere(a, b, Vector3.ZERO, 1.0), EPS)


func test_capsule_nan_is_no_hit() -> void:
	assert_eq(SweepMath.segment_capsule(Vector3(-10, NAN, 0), Vector3(10, 0, 0), CAPSULE_H, CAPSULE_R), -1.0)
	assert_eq(SweepMath.segment_capsule(Vector3(-10, 0, 0), Vector3(NAN, 0, 0), CAPSULE_H, CAPSULE_R), -1.0)


# --- brute-force cross-check ---------------------------------------------------------------------------------


# Signed distance to each primitive in its own frame (negative inside), independent of SweepMath. `p` holds the
# primitive parameters: sphere (centre.x, centre.y, centre.z, r), box (hx, hy, hz, 0), capsule (h, r, 0, 0).
func _sdf(kind: int, params: Array, point: Vector3) -> float:
	if kind == KIND_SPHERE:
		var centre: Vector3 = params[0]
		return point.distance_to(centre) - float(params[1])
	if kind == KIND_BOX:
		var half: Vector3 = params[0]
		var qx: float = absf(point.x) - half.x
		var qy: float = absf(point.y) - half.y
		var qz: float = absf(point.z) - half.z
		var outside: float = Vector3(maxf(qx, 0.0), maxf(qy, 0.0), maxf(qz, 0.0)).length()
		return outside + minf(maxf(qx, maxf(qy, qz)), 0.0)
	var h: float = params[0]
	var nearest_y: float = clampf(point.y, -h, h)
	return Vector3(point.x, point.y - nearest_y, point.z).length() - float(params[1])


func _analytic(kind: int, params: Array, a: Vector3, b: Vector3) -> float:
	if kind == KIND_SPHERE:
		return SweepMath.segment_sphere(a, b, params[0], params[1])
	if kind == KIND_BOX:
		return SweepMath.segment_box(a, b, params[0], 0.0)
	return SweepMath.segment_capsule(a, b, params[0], params[1])


# Empty string when the analytic result agrees with sampling the segment at SAMPLES + 1 points, else a description.
func _disagreement(kind: int, params: Array, a: Vector3, b: Vector3, analytic: float) -> String:
	var first_inside: int = -1
	var sdf_at_first: float = 0.0
	var min_sdf: float = INF
	for i: int in SAMPLES + 1:
		var s: float = _sdf(kind, params, a.lerp(b, float(i) / SAMPLES))
		min_sdf = minf(min_sdf, s)
		if s <= 0.0:
			first_inside = i
			sdf_at_first = s
			break
	if analytic >= 0.0:
		if first_inside >= 0:
			var sampled_t: float = float(first_inside) / SAMPLES
			if sampled_t < analytic - 1e-6 or sampled_t - analytic > 1.0 / SAMPLES + 1e-6:
				return "analytic t %.9f, first inside sample at %.9f" % [analytic, sampled_t]
		elif min_sdf > TANGENT_BAND:
			return "analytic hit at %.9f but no sample within %s of the volume (closest %.6f)" % [
					analytic, TANGENT_BAND, min_sdf]
	elif first_inside >= 0 and sdf_at_first < -TANGENT_BAND:
		return "analytic miss but sample %d is %.6f inside" % [first_inside, -sdf_at_first]
	return ""


func _random_vec(rng: RandomNumberGenerator, extent: float) -> Vector3:
	return Vector3(rng.randf_range(-extent, extent), rng.randf_range(-extent, extent), rng.randf_range(-extent, extent))


func _random_primitive(rng: RandomNumberGenerator, kind: int) -> Array:
	if kind == KIND_SPHERE:
		return [_random_vec(rng, 2.0), rng.randf_range(0.6, 2.5)]
	if kind == KIND_BOX:
		return [Vector3(rng.randf_range(0.3, 3.0), rng.randf_range(0.3, 3.0), rng.randf_range(0.3, 3.0))]
	return [rng.randf_range(0.0, 2.0), rng.randf_range(0.5, 1.5)]


func _brute_force(kind: int, label: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + kind
	var hits: int = 0
	var starts_inside: int = 0
	var misses: int = 0
	var failures: Array[String] = []
	for i: int in RANDOM_SEGMENTS:
		var params: Array = _random_primitive(rng, kind)
		# Half of the segments start near the primitive (often inside it), half anywhere in a 10 m cube.
		var a: Vector3 = _random_vec(rng, 1.5 if i % 2 == 0 else 5.0)
		var b: Vector3 = _random_vec(rng, 5.0)
		var analytic: float = _analytic(kind, params, a, b)
		if analytic < 0.0:
			misses += 1
		elif analytic == 0.0:
			starts_inside += 1
		else:
			hits += 1
		var problem: String = _disagreement(kind, params, a, b, analytic)
		if not problem.is_empty():
			failures.append("#%d %s -> %s: %s" % [i, a, b, problem])
			if failures.size() >= 5:
				break
	assert_eq(failures.size(), 0, "%s disagreements with brute force: %s" % [label, failures])
	assert_gt(hits, 100, "%s: enough entering segments to mean something" % label)
	assert_gt(misses, 100, "%s: enough missing segments" % label)
	assert_gt(starts_inside, 20, "%s: enough segments starting inside" % label)
	gut.p("%s: %d random segments: %d entering, %d starting inside, %d missing" % [
			label, RANDOM_SEGMENTS, hits, starts_inside, misses])


func test_sphere_matches_brute_force() -> void:
	_brute_force(KIND_SPHERE, "sphere")


func test_box_matches_brute_force() -> void:
	_brute_force(KIND_BOX, "box")


func test_capsule_matches_brute_force() -> void:
	_brute_force(KIND_CAPSULE, "capsule")
