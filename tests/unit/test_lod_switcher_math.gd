extends GutTest
## LodSwitcherMath (M3-T19, Q22, AC28): the projected size, the levels by size, hysteresis that switches each boundary once
## each way on a slow sweep and never flaps on a threshold, and the tester's bias inside the ship's chain.


func test_the_projected_size_follows_distance_fov_and_viewport() -> void:
	# A Starfury (about 9 m radius) 2 km away at 70 degrees on a 1080 px viewport: about 7 px across.
	var px: float = LodSwitcherMath.projected_px(9.0, 2000.0, 70.0, 1080.0)
	assert_almost_eq(px, 9.0 * 1080.0 / (2000.0 * tan(deg_to_rad(35.0))), 1e-6)
	assert_between(px, 6.0, 8.0)
	assert_almost_eq(LodSwitcherMath.projected_px(9.0, 1000.0, 70.0, 1080.0), 2.0 * px, 1e-6, "half the distance, twice the size")
	assert_eq(LodSwitcherMath.projected_px(9.0, 5.0, 70.0, 1080.0), INF, "inside the hull")


func test_levels_by_size_from_nothing() -> void:
	assert_eq(LodSwitcherMath.next_level(500.0, -1), 0)
	assert_eq(LodSwitcherMath.next_level(200.0, -1), 0, "200 px is LOD0")
	assert_eq(LodSwitcherMath.next_level(199.0, -1), 1)
	assert_eq(LodSwitcherMath.next_level(60.0, -1), 1)
	assert_eq(LodSwitcherMath.next_level(30.0, -1), 2)
	assert_eq(LodSwitcherMath.next_level(15.9, -1), 3)


func _sweep(from_px: float, to_px: float, steps: int, start: int) -> Array[int]:
	var level: int = start
	var switches: Array[int] = []  # the level after each switch
	for i: int in steps + 1:
		var px: float = lerpf(from_px, to_px, float(i) / float(steps))
		var next: int = LodSwitcherMath.next_level(px, level)
		if next != level:
			switches.append(next)
			level = next
	return switches


func test_a_slow_sweep_switches_every_boundary_exactly_once_each_way() -> void:
	assert_eq(_sweep(400.0, 5.0, 4000, 0), [1, 2, 3] as Array[int], "moving away: each boundary once")
	assert_eq(_sweep(5.0, 400.0, 4000, 3), [2, 1, 0] as Array[int], "coming back: each boundary once")


func test_a_ship_held_on_a_threshold_never_flaps() -> void:
	for threshold: float in LodSwitcherMath.THRESHOLDS_PX:
		var level: int = LodSwitcherMath.next_level(threshold * 0.99, -1)
		var changes: int = 0
		for i: int in 1000:
			var jitter: float = threshold * (1.0 + 0.02 * sin(float(i)))  # +-2 % around it, for ever
			var next: int = LodSwitcherMath.next_level(jitter, level)
			changes += 1 if next != level else 0
			level = next
		assert_lte(changes, 1, "at most the one switch down onto it (%.0f px)" % threshold)


func test_finer_needs_a_quarter_more_than_the_threshold() -> void:
	assert_eq(LodSwitcherMath.next_level(70.0, 2), 2, "70 px is LOD1 from nothing, but not yet from LOD2")
	assert_eq(LodSwitcherMath.next_level(75.0, 2), 1, "75 px: 60 x 1.25")
	assert_eq(LodSwitcherMath.next_level(1000.0, 3), 0, "a jump closer can skip levels")
	assert_eq(LodSwitcherMath.next_level(10.0, 0), 3, "and so can a jump away")


func test_the_bias_moves_whole_levels_inside_the_chain() -> void:
	assert_eq(LodSwitcherMath.applied(1, 0.0, 0, 3), 1)
	assert_eq(LodSwitcherMath.applied(1, 1.0, 0, 3), 2, "+1: coarser")
	assert_eq(LodSwitcherMath.applied(1, -1.0, 0, 3), 0, "-1: finer")
	assert_eq(LodSwitcherMath.applied(0, -1.0, 1, 3), 1, "an ally never goes below its LOD1")
	assert_eq(LodSwitcherMath.applied(3, 1.0, 0, 3), 3)
