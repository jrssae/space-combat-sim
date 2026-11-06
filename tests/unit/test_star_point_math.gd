extends GutTest
## StarPointMath (M4-T30c): a star is a point with a 1 px floor whose light is the same at every render height, the running
## lights' rule (Q26) applied to the sky.

const RADIUS_RAD: float = 0.0005
const FLOOR_PX: float = 1.0


func test_focal_length_from_the_field_of_view() -> void:
	assert_almost_eq(StarPointMath.focal_px(70.0, 1080.0), 540.0 / tan(deg_to_rad(35.0)), 0.001)
	assert_almost_eq(StarPointMath.focal_px(70.0, 2160.0), 2.0 * StarPointMath.focal_px(70.0, 1080.0), 0.001)


func test_a_star_under_the_floor_is_drawn_at_the_floor_and_dimmed() -> void:
	var focal: float = StarPointMath.focal_px(70.0, 1080.0)
	var real: float = RADIUS_RAD * focal
	assert_lt(real, FLOOR_PX, "half a milliradian is under a pixel at 1 080 lines")
	assert_almost_eq(StarPointMath.footprint_radius_px(RADIUS_RAD, focal, FLOOR_PX), FLOOR_PX, 1e-6)
	assert_almost_eq(StarPointMath.brightness_factor(RADIUS_RAD, focal, FLOOR_PX), pow(real / FLOOR_PX, 2.0), 1e-6)


func test_a_star_over_the_floor_keeps_its_size_and_full_brightness() -> void:
	var focal: float = 4000.0
	assert_almost_eq(StarPointMath.footprint_radius_px(RADIUS_RAD, focal, FLOOR_PX), 2.0, 1e-6)
	assert_eq(StarPointMath.brightness_factor(RADIUS_RAD, focal, FLOOR_PX), 1.0)


func test_a_stars_delivered_light_is_equal_at_1080_and_2160_lines() -> void:
	var at_1080: float = StarPointMath.delivered_light(31.0, RADIUS_RAD, StarPointMath.focal_px(70.0, 1080.0), FLOOR_PX)
	var at_2160: float = StarPointMath.delivered_light(31.0, RADIUS_RAD, StarPointMath.focal_px(70.0, 2160.0), FLOOR_PX)
	assert_gt(at_1080, 0.0)
	assert_almost_eq(at_2160 / at_1080, 1.0, 1e-5)
	# And at a resolution where the disc is over the floor.
	var big: float = StarPointMath.delivered_light(31.0, RADIUS_RAD, 6000.0, FLOOR_PX)
	assert_almost_eq(big / at_1080, 1.0, 1e-5)


func test_delivered_light_is_the_discs_whatever_the_floor() -> void:
	var focal: float = StarPointMath.focal_px(70.0, 1080.0)
	var one: float = StarPointMath.delivered_light(10.0, RADIUS_RAD, focal, 1.0)
	var two: float = StarPointMath.delivered_light(10.0, RADIUS_RAD, focal, 2.0)
	assert_almost_eq(two / one, 1.0, 1e-5, "a wider floor spreads the same light")
	assert_almost_eq(one, 10.0 * StarPointMath.PROFILE_AREA * RADIUS_RAD * RADIUS_RAD, 1e-12)


func test_the_rule_is_the_running_lights_rule() -> void:
	# A star is a running light at 1 m whose radius is its angular radius.
	for focal: float in [400.0, 771.0, 1542.0, 5000.0]:
		assert_almost_eq(StarPointMath.brightness_factor(RADIUS_RAD, focal, FLOOR_PX),
				RunningLightDimming.brightness_factor(RADIUS_RAD, focal, FLOOR_PX, 1.0), 1e-6)


## The summed weight of a star's pixels when its centre sits `offset` px from a pixel centre.
func _pixel_sum(offset: Vector2, footprint: float) -> Array:
	var total: float = 0.0
	var peak: float = 0.0
	for y: int in range(-4, 5):
		for x: int in range(-4, 5):
			var w: float = StarPointMath.kernel_weight((Vector2(x, y) - offset).length(), footprint)
			total += w
			peak = maxf(peak, w)
	return [total, peak]


func test_a_star_keeps_its_light_and_hardly_flickers_wherever_it_lands_on_the_pixels() -> void:
	# Q26 points, but soft: as the camera turns a star crosses pixel centres and corners. Its summed light must hold, and its
	# brightest pixel must not swing four times over as a 2 by 2 px square's did.
	var footprint: float = 1.0
	var area: float = StarPointMath.PROFILE_AREA * footprint * footprint
	var peaks: Array[float] = []
	for offset: Vector2 in [Vector2.ZERO, Vector2(0.5, 0.0), Vector2(0.5, 0.5), Vector2(0.25, 0.75), Vector2(0.1, 0.3)]:
		var result: Array = _pixel_sum(offset, footprint)
		assert_almost_eq(float(result[0]) / area, 1.0, 0.02, "the light at offset %s" % offset)
		peaks.append(float(result[1]))
	assert_lt(peaks.max() / peaks.min(), 2.0, "the brightest pixel varies under 2x")


func test_the_kernel_is_point_sized() -> void:
	assert_eq(StarPointMath.kernel_weight(StarPointMath.kernel_radius_px(1.0) + 0.01, 1.0), 0.0, "nothing past its edge")
	assert_lt(StarPointMath.kernel_radius_px(1.0), 2.5, "a floor-sized star spans a few pixels, not a globe")


func test_a_direction_maps_onto_the_panorama_as_godot_draws_it() -> void:
	# Godot's panorama sky: the image centre looks toward +Z, a quarter turn right toward -X, the top row is +Y.
	assert_almost_eq(StarPointMath.panorama_uv(Vector3(0, 0, 1)), Vector2(0.5, 0.5), Vector2.ONE * 1e-6)
	assert_almost_eq(StarPointMath.panorama_uv(Vector3(-1, 0, 0)), Vector2(0.75, 0.5), Vector2.ONE * 1e-6)
	assert_almost_eq(StarPointMath.panorama_uv(Vector3(1, 0, 0)), Vector2(0.25, 0.5), Vector2.ONE * 1e-6)
	assert_almost_eq(StarPointMath.panorama_uv(Vector3(0, 1, 0)).y, 0.0, 1e-6)
	assert_almost_eq(StarPointMath.panorama_uv(Vector3(0, -1, 0)).y, 1.0, 1e-6)
	# The nebula's centre (35 degrees right of -Z, 12 up) at longitude -145 degrees.
	var nebula := Vector3(sin(deg_to_rad(35.0)) * cos(deg_to_rad(12.0)), sin(deg_to_rad(12.0)), -cos(deg_to_rad(35.0)) * cos(deg_to_rad(12.0)))
	assert_almost_eq(StarPointMath.panorama_uv(nebula), Vector2(-145.0 / 360.0 + 0.5, 0.5 - 12.0 / 180.0), Vector2.ONE * 1e-5)


func test_the_shader_uses_the_same_constants() -> void:
	var source: String = FileAccess.get_file_as_string("res://assets/shaders/star_point.gdshader")
	assert_string_contains(source, "const float SOFTNESS = %s;" % str(StarPointMath.SOFTNESS))
	assert_string_contains(source, "const float KERNEL_SIGMAS = %s;" % str(StarPointMath.KERNEL_SIGMAS))
