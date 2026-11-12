extends GutTest
## Where the scaled-space layer draws a far body (M6-T10, D68, AC7): its true direction and angular size from the camera's
## place against the anchor, inside a bounded depth, the same after any rebase.

const PLANET_RADIUS_M: float = 4.78e6
const STATION_ORBIT_M: float = 2.75e7
const STAR_RADIUS_M: float = 5.11e8
const STAR_DISTANCE_M: float = 8.976e10


func _at(x: float, y: float, z: float) -> PackedFloat64Array:
	return PackedFloat64Array([x, y, z])


func test_a_body_is_drawn_in_its_true_direction_at_its_true_distance() -> void:
	var placed: ScaledPlacement = ScaledPlacement.place(_at(1000.0, 0.0, 0.0), _at(1000.0, 3.0e6, -4.0e6), 1.0e5)
	assert_almost_eq(placed.distance_m, 5.0e6, 1.0e-6, "the true distance, in 64-bit")
	assert_almost_eq(placed.direction, Vector3(0.0, 0.6, -0.8), Vector3.ONE * 1.0e-6, "the direction from the camera")
	assert_almost_eq(placed.direction.length(), 1.0, 1.0e-6, "a unit vector")


func test_epsilon_iii_is_about_20_degrees_across_from_the_station() -> void:
	var placed: ScaledPlacement = ScaledPlacement.place(_at(0.0, 0.0, 0.0), _at(-STATION_ORBIT_M, 0.0, 0.0), PLANET_RADIUS_M)
	assert_almost_eq(placed.angular_size_deg(), 20.02, 0.02, "2 asin(4 780 / 27 500)")
	assert_almost_eq(placed.direction, Vector3.LEFT, Vector3.ONE * 1.0e-6)


func test_the_star_is_two_thirds_of_a_degree_across_from_the_planet() -> void:
	var placed: ScaledPlacement = ScaledPlacement.place(_at(0.0, 0.0, 0.0), _at(0.0, 0.0, STAR_DISTANCE_M), STAR_RADIUS_M)
	assert_almost_eq(placed.angular_size_deg(), 0.6524, 0.001, "2 asin(5.11e8 / 8.976e10)")


func test_the_drawn_sphere_keeps_the_true_angular_size_inside_the_bounded_depth() -> void:
	var cases: Array[Array] = [
		[STATION_ORBIT_M, PLANET_RADIUS_M], [PLANET_RADIUS_M + 4.0e5, PLANET_RADIUS_M], [PLANET_RADIUS_M + 1000.0, PLANET_RADIUS_M],
		[STAR_DISTANCE_M, STAR_RADIUS_M], [1.0e9, PLANET_RADIUS_M],
	]
	for case: Array in cases:
		var distance: float = case[0]
		var radius: float = case[1]
		var placed: ScaledPlacement = ScaledPlacement.place(_at(0.0, 0.0, 0.0), _at(0.0, distance, 0.0), radius)
		var drawn_distance: float = placed.offset.length()
		assert_almost_eq(asin(placed.radius / drawn_distance), asin(radius / distance), 1.0e-6, "angular radius at %s m" % distance)
		assert_almost_eq(placed.angular_radius_rad, asin(radius / distance), 1.0e-9, "the reported angular radius at %s m" % distance)
		assert_lte(drawn_distance, ScaledPlacement.MAX_DEPTH_M + 0.01, "inside the bounded depth at %s m" % distance)
		assert_lt(drawn_distance + placed.radius, 50000.0, "inside the cameras' far plane at %s m" % distance)
		assert_almost_eq(placed.offset.normalized(), placed.direction, Vector3.ONE * 1.0e-6, "drawn along the true direction")


func test_a_near_body_is_drawn_at_distance_over_scale() -> void:
	var placed: ScaledPlacement = ScaledPlacement.place(_at(0.0, 0.0, 0.0), _at(5.18e6, 0.0, 0.0), PLANET_RADIUS_M)
	assert_almost_eq(placed.offset.x, 5180.0, 0.01, "5 180 km at 1:1000")
	assert_almost_eq(placed.radius, 4780.0, 0.01, "its radius at 1:1000")


func test_a_rebase_changes_nothing() -> void:
	var planet: PackedFloat64Array = _at(-STATION_ORBIT_M, 250.0, 9000.0)
	var origin := UniversePos.new(1200.0, -300.0, 50.0)
	var camera_local := Vector3(4000.0, 120.0, -2500.0)
	var before: ScaledPlacement = ScaledPlacement.place(ScaledPlacement.camera_from_anchor(origin, camera_local), planet,
			PLANET_RADIUS_M)
	# The rebase: the origin takes the offset, every local position gives it up.
	var offset := Vector3(4000.0, 0.0, -2500.0)
	var after: ScaledPlacement = ScaledPlacement.place(
			ScaledPlacement.camera_from_anchor(origin.plus_local(offset), camera_local - offset), planet, PLANET_RADIUS_M)
	assert_almost_eq(after.direction.angle_to(before.direction), 0.0, 1.0e-6, "the same direction")
	assert_almost_eq(after.distance_m, before.distance_m, 1.0e-3, "the same distance")
	assert_almost_eq(after.angular_radius_rad, before.angular_radius_rad, 1.0e-10, "the same size")
	assert_almost_eq(after.offset, before.offset, Vector3.ONE * 1.0e-3, "the same drawn place from the camera")


func test_the_planet_keeps_its_digits_against_the_anchor() -> void:
	# One metre of camera motion 400 km above the surface must show: the sum never passes through a 1e11 m barycentric number.
	var planet: PackedFloat64Array = _at(0.0, -5.18e6, 0.0)
	var a: ScaledPlacement = ScaledPlacement.place(_at(0.0, 0.0, 0.0), planet, PLANET_RADIUS_M)
	var b: ScaledPlacement = ScaledPlacement.place(_at(0.0, 1.0, 0.0), planet, PLANET_RADIUS_M)
	assert_almost_eq(b.distance_m - a.distance_m, 1.0, 1.0e-8, "a metre is a metre at planetary range")
	# The same step taken through barycentric numbers would be lost in their 1.5e-5 m grain, and worse in float32.
	var far: ScaledPlacement = ScaledPlacement.place(_at(0.0, 0.001, 0.0), planet, PLANET_RADIUS_M)
	assert_almost_eq(far.distance_m - a.distance_m, 0.001, 1.0e-8, "and a millimetre a millimetre")


func test_kernel_axes_map_to_the_games() -> void:
	# kernel (x, y, z) = game (x, -z, y): the kernel's north is the game's up, the kernel's y the game's forward (-z).
	assert_eq(ScaledPlacement.to_game(_at(1.0, 2.0, 3.0)), _at(1.0, 3.0, -2.0))
	assert_eq(ScaledPlacement.to_game(PackedFloat64Array([5.0, 2.0, 1.0, 7.0, 8.0, 9.0])), _at(5.0, 1.0, -2.0), "the position alone")


func test_nearer_bodies_get_the_nearer_layer_depth() -> void:
	var planet: float = ScaledPlacement.layer_depth(STATION_ORBIT_M)
	var star: float = ScaledPlacement.layer_depth(STAR_DISTANCE_M)
	assert_gt(planet, star, "reversed depth: the planet hides the star")
	for distance: float in [1.0, 1.0e4, 1.0e7, 1.0e11, 1.0e15]:
		var depth: float = ScaledPlacement.layer_depth(distance)
		assert_between(depth, ScaledPlacement.DEPTH_BACK, ScaledPlacement.DEPTH_FRONT, "inside the layer's slab at %s m" % distance)


func test_inside_a_body_the_placement_stays_finite() -> void:
	var placed: ScaledPlacement = ScaledPlacement.place(_at(0.0, 0.0, 0.0), _at(0.0, 0.0, 0.0), PLANET_RADIUS_M)
	assert_true(is_finite(placed.offset.length()) and is_finite(placed.radius), "no NaN at the centre")
	assert_almost_eq(placed.angular_radius_rad, PI / 2.0, 1.0e-9, "the body fills half the sky and more")
