extends GutTest
## LodSwitcherMath (M4-T11): a ship turns into a far dot past the distance and back a tenth inside, so it never flaps; the
## distance is where its radius covers the dot size on screen (M7-T26).


func test_a_far_dot_starts_past_the_distance_and_ends_a_tenth_inside() -> void:
	# M4-T11: past far_m a ship is a dot; once a dot, it shows its detail again only at 90 % of far_m, so it never flaps.
	assert_false(LodSwitcherMath.far_dot(3000.0, false, 3000.0), "on the line it is not a dot yet")
	assert_true(LodSwitcherMath.far_dot(3000.1, false, 3000.0))
	assert_true(LodSwitcherMath.far_dot(2900.0, true, 3000.0), "a dot stays one just inside")
	assert_true(LodSwitcherMath.far_dot(2700.0, true, 3000.0), "down to 90 %")
	assert_false(LodSwitcherMath.far_dot(2699.0, true, 3000.0))
	assert_false(LodSwitcherMath.far_dot(2900.0, false, 3000.0), "and no dot inside from the near side")


func test_the_dot_distance_is_where_the_radius_covers_the_dot_size() -> void:
	# M7-T26: 704 px per radian (1 080 lines, 75 degrees), a 2 px dot: a 10 m fighter turns at 3.5 km, a 70 m freighter at 24.6 km.
	var k: float = FarPropMath.px_per_rad(1080.0, 75.0)
	assert_almost_eq(k, 703.8, 0.1)
	assert_almost_eq(LodSwitcherMath.dot_distance_m(10.0, k, 2.0), 3519.0, 1.0)
	assert_almost_eq(LodSwitcherMath.dot_distance_m(70.0, k, 2.0), 7.0 * LodSwitcherMath.dot_distance_m(10.0, k, 2.0), 1e-3,
			"in proportion to the hull's size")
	assert_almost_eq(LodSwitcherMath.dot_distance_m(10.0, k, 4.0), 1759.5, 1.0, "a bigger dot size turns it nearer")
	assert_almost_eq(LodSwitcherMath.dot_distance_m(10.0, 2.0 * k, 2.0), 7038.0, 1.0, "twice the lines, twice as far")
