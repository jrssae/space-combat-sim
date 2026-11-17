extends GutTest
## The running lights' point-size rule (M4-T28): a marker keeps a one pixel footprint once its real disc is smaller than that, and its
## brightness follows the inverse square of distance, so the light it delivers is what its real disc would deliver.

const RADIUS_M: float = 0.1
const FLOOR_PX: float = 1.0
# A 1080p view at 75 degrees vertical: half the height over tan(37.5 deg).
const FOCAL_PX: float = 540.0 / 0.767327


func _crossover_m() -> float:
	return RunningLightDimming.crossover_distance_m(RADIUS_M, FOCAL_PX, FLOOR_PX)


func test_the_crossover_is_where_the_real_disc_is_the_floor_wide() -> void:
	assert_almost_eq(RunningLightDimming.real_radius_px(RADIUS_M, FOCAL_PX, _crossover_m()), FLOOR_PX, 1e-4)


func test_a_light_closer_than_the_crossover_is_not_dimmed() -> void:
	assert_eq(RunningLightDimming.brightness_factor(RADIUS_M, FOCAL_PX, FLOOR_PX, 1.0), 1.0, "1 m away")
	assert_eq(RunningLightDimming.brightness_factor(RADIUS_M, FOCAL_PX, FLOOR_PX, _crossover_m() * 0.5), 1.0, "half way out")


func test_the_factor_is_exactly_one_at_the_crossover() -> void:
	assert_almost_eq(RunningLightDimming.brightness_factor(RADIUS_M, FOCAL_PX, FLOOR_PX, _crossover_m()), 1.0, 1e-6)


func test_twice_the_crossover_distance_gives_a_quarter() -> void:
	assert_almost_eq(RunningLightDimming.brightness_factor(RADIUS_M, FOCAL_PX, FLOOR_PX, _crossover_m() * 2.0), 0.25, 1e-6)


func test_ten_times_the_crossover_distance_gives_a_hundredth() -> void:
	assert_almost_eq(RunningLightDimming.brightness_factor(RADIUS_M, FOCAL_PX, FLOOR_PX, _crossover_m() * 10.0), 0.01, 1e-6)


func test_the_footprint_never_drops_under_the_floor() -> void:
	assert_eq(RunningLightDimming.footprint_radius_px(RADIUS_M, FOCAL_PX, FLOOR_PX, _crossover_m() * 50.0), FLOOR_PX)
	assert_gt(RunningLightDimming.footprint_radius_px(RADIUS_M, FOCAL_PX, FLOOR_PX, 1.0), FLOOR_PX, "up close it is the real size")


func test_a_larger_floor_moves_the_crossover_in() -> void:
	assert_almost_eq(RunningLightDimming.crossover_distance_m(RADIUS_M, FOCAL_PX, 3.0), _crossover_m() / 3.0, 1e-3)


# The station's beacons (M7-T69): 4.5 m, the marker's 2 px floor, peak 4 at full fade.
func test_a_station_beacon_follows_the_inverse_square_and_is_gone_far_out() -> void:
	var cross: float = RunningLightDimming.crossover_distance_m(4.5, FOCAL_PX, 2.0)
	assert_almost_eq(RunningLightDimming.brightness_factor(4.5, FOCAL_PX, 2.0, cross * 4.0), 1.0 / 16.0, 1e-6, "4x out is 1/16")
	assert_almost_eq(RunningLightDimming.brightness_factor(4.5, FOCAL_PX, 2.0, 10000.0) * 4.0, 4.0 * pow(cross / 10000.0, 2.0), 1e-6)
	assert_false(RunningLightDimming.is_culled(4.5, FOCAL_PX, 2.0, 10000.0, 4.0), "a beacon still reads at 10 km")
	assert_true(RunningLightDimming.is_culled(4.5, FOCAL_PX, 2.0, 100000.0, 4.0), "gone at 100 km")
	assert_true(RunningLightDimming.is_culled(4.5, FOCAL_PX, 2.0, 1.0e6, 4.0), "gone at 1 000 km")
	assert_true(RunningLightDimming.is_culled(4.5, FOCAL_PX, 2.0, 2.7e7, 4.0), "gone at 27 000 km")
