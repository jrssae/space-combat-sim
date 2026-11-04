extends GutTest
## LodSwitcherMath (M4-T11): a ship turns into a far dot past the distance and back a tenth inside, so it never flaps.


func test_a_far_dot_starts_past_the_distance_and_ends_a_tenth_inside() -> void:
	# M4-T11: past far_m a ship is a dot; once a dot, it shows its detail again only at 90 % of far_m, so it never flaps.
	assert_false(LodSwitcherMath.far_dot(3000.0, false, 3000.0), "on the line it is not a dot yet")
	assert_true(LodSwitcherMath.far_dot(3000.1, false, 3000.0))
	assert_true(LodSwitcherMath.far_dot(2900.0, true, 3000.0), "a dot stays one just inside")
	assert_true(LodSwitcherMath.far_dot(2700.0, true, 3000.0), "down to 90 %")
	assert_false(LodSwitcherMath.far_dot(2699.0, true, 3000.0))
	assert_false(LodSwitcherMath.far_dot(2900.0, false, 3000.0), "and no dot inside from the near side")
