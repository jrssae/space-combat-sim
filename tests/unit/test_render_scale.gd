extends GutTest
## RenderScale: a window whose frame would exceed the splat renderer's 65 535-tile sort key is rendered smaller.


func test_common_sizes_are_untouched() -> void:
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]:
		assert_eq(RenderScale.scale_for(size.x, size.y), 1.0, str(size))


func test_the_maximized_6k_window_from_the_play_test_is_scaled() -> void:
	assert_gt(RenderScale.tile_count(6144, 3382), 65535, "that frame wraps the tile index")
	var s: float = RenderScale.scale_for(6144, 3382)
	assert_lt(s, 1.0)
	assert_gt(s, 0.8, "only a little smaller")
	assert_lte(RenderScale.tile_count(int(ceilf(6144 * s)), int(ceilf(3382 * s))), RenderScale.MAX_TILES)


func test_the_result_always_fits_and_degenerate_sizes_are_safe() -> void:
	for size: Vector2i in [Vector2i(7680, 4320), Vector2i(10000, 5000), Vector2i(8192, 8192)]:
		var s: float = RenderScale.scale_for(size.x, size.y)
		assert_lte(RenderScale.tile_count(int(ceilf(size.x * s)), int(ceilf(size.y * s))), RenderScale.MAX_TILES, str(size))
	assert_eq(RenderScale.scale_for(0, 0), 1.0)
	assert_eq(RenderScale.tile_count(-1, 5), 0)
