extends GutTest
## The jump flashes' shared lens flare (M7-T23): the brightest flash offered wins, offers last one frame, and only a flash large
## enough on screen earns a flare.


func before_each() -> void:
	FlashFlare.clear()


func after_each() -> void:
	FlashFlare.clear()


func test_the_brightest_offer_of_a_frame_wins() -> void:
	FlashFlare.offer(Vector3(1.0, 0.0, 0.0), Color.RED, 0.3, 10)
	FlashFlare.offer(Vector3(2.0, 0.0, 0.0), Color.BLUE, 0.8, 10)
	FlashFlare.offer(Vector3(3.0, 0.0, 0.0), Color.GREEN, 0.5, 10)
	var best: Array = FlashFlare.brightest(10)
	assert_eq(best[0], 0.8)
	assert_eq(best[1], Vector3(2.0, 0.0, 0.0))
	assert_eq(best[2], Color.BLUE)


func test_an_offer_lasts_into_the_next_frame_and_no_longer() -> void:
	FlashFlare.offer(Vector3.ONE, Color.RED, 0.6, 10)
	assert_eq(FlashFlare.brightest(11)[0], 0.6, "the reader may run before this frame's offers")
	assert_eq(FlashFlare.brightest(12)[0], 0.0, "then it is gone")
	FlashFlare.offer(Vector3.ONE, Color.RED, 0.6, 20)
	assert_eq(FlashFlare.brightest(25)[0], 0.0, "an old offer is not kept")


func test_only_a_flash_large_on_screen_earns_a_flare() -> void:
	assert_eq(FlashFlare.by_size(10.0, 40.0, 160.0), 0.0, "a far point: none")
	assert_eq(FlashFlare.by_size(400.0, 40.0, 160.0), 1.0, "a close one: whole")
	var mid: float = FlashFlare.by_size(100.0, 40.0, 160.0)
	assert_between(mid, 0.01, 0.99, "eased between")


func test_a_flashing_point_offers_its_flare_and_a_far_one_does_not() -> void:
	var world := Node3D.new()
	add_child_autofree(world)
	var point: JumpVortex = JumpVortex.create({}, true, false)
	world.add_child(point)
	point.open(JumpVortex.Direction.ARRIVAL)
	point.advance(point.timing.lead_s + VortexTiming.FLASH_S * VortexTiming.POINT_FLASH_PEAK)
	var px: float = VortexLod.px_per_unit(60.0, 1080.0)
	FlashFlare.clear()
	point.update_visuals_for(Vector3(0.0, 0.0, -100000.0), px)
	assert_eq(FlashFlare.brightest()[0], 0.0, "100 km off: a few pixels, no flare")
	point.update_visuals_for(Vector3(0.0, 0.0, -point.fit.mouth_radius_m * 3.0), px)
	var best: Array = FlashFlare.brightest()
	assert_almost_eq(float(best[0]), point.flare_level, 0.01, "close, at its peak: its whole flare")
	assert_eq(best[2], point.centre_colour, "in the flash's own colour")
	point.advance(point.timing.open_at_s)
	FlashFlare.clear()
	point.update_visuals_for(Vector3(0.0, 0.0, -point.fit.mouth_radius_m * 3.0), px)
	assert_eq(FlashFlare.brightest()[0], 0.0, "open, its flash out: none")
