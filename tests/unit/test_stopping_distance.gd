extends GutTest
## StoppingDistance (M8-T06, D84): the braking maths the docking autopilot paces its lane with and the approach cue reads.


func test_the_distance_to_rest_grows_with_the_square_of_the_speed() -> void:
	assert_almost_eq(StoppingDistance.distance_m(100.0, 10.0), 500.0, 1e-6)
	assert_almost_eq(StoppingDistance.distance_m(200.0, 10.0), 2000.0, 1e-6)
	assert_almost_eq(StoppingDistance.distance_m(-100.0, 10.0), 500.0, 1e-6, "the sign of the speed does not matter")
	assert_eq(StoppingDistance.distance_m(0.0, 10.0), 0.0)


func test_a_reaction_time_is_flown_at_full_speed_first() -> void:
	assert_almost_eq(StoppingDistance.distance_m(100.0, 10.0, 2.0), 700.0, 1e-6)
	assert_almost_eq(StoppingDistance.time_s(100.0, 10.0, 2.0), 12.0, 1e-6)


func test_the_speed_for_a_distance_is_the_inverse_with_the_margin() -> void:
	var speed: float = StoppingDistance.speed_for_mps(500.0, 10.0, 1.0)
	assert_almost_eq(speed, 100.0, 1e-6)
	assert_almost_eq(StoppingDistance.speed_for_mps(500.0, 10.0), 100.0 * StoppingDistance.PLAN_MARGIN, 1e-6)
	assert_eq(StoppingDistance.speed_for_mps(-5.0, 10.0), 0.0, "past the point: stop")


func test_a_ship_stops_in_time_or_overshoots() -> void:
	assert_true(StoppingDistance.can_stop(100.0, 500.0, 10.0))
	assert_false(StoppingDistance.can_stop(100.0, 499.0, 10.0))
	assert_false(StoppingDistance.can_stop(100.0, 600.0, 10.0, 2.0), "the reaction eats the room")
	assert_almost_eq(StoppingDistance.decel_needed(100.0, 500.0), 10.0, 1e-6)
	assert_eq(StoppingDistance.decel_needed(100.0, 0.0), INF)


func test_no_braking_at_all_never_divides_by_zero() -> void:
	assert_true(is_finite(StoppingDistance.distance_m(100.0, 0.0)))
	assert_true(is_finite(StoppingDistance.time_s(100.0, 0.0)))
