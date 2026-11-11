extends GutTest
## The jumpgate vortex's timing (M6-T14, D69): the reference video's glow, flash, growth, hold and close, from the age alone.

const EPS: float = 1e-4


func test_phases_follow_the_reference_order() -> void:
	var t := VortexTiming.new(4.0)
	assert_eq(t.phase(-0.1), VortexTiming.Phase.CLOSED, "before it starts")
	assert_eq(t.phase(0.5), VortexTiming.Phase.GLOW, "the inner tips glow for about a second")
	assert_eq(t.phase(1.5), VortexTiming.Phase.FLASH, "then the flash at the centre")
	assert_eq(t.phase(2.5), VortexTiming.Phase.GROW, "then the funnel grows")
	assert_eq(t.phase(VortexTiming.OPEN_AT_S), VortexTiming.Phase.OPEN, "fully open at 3.5 s")
	assert_eq(t.phase(VortexTiming.OPEN_AT_S + 3.9), VortexTiming.Phase.OPEN, "open for the hold")
	assert_eq(t.phase(VortexTiming.OPEN_AT_S + 4.5), VortexTiming.Phase.CLOSING, "then it closes")
	assert_eq(t.phase(VortexTiming.OPEN_AT_S + 5.1), VortexTiming.Phase.CLOSED, "gone within a second")
	assert_true(t.is_done(VortexTiming.OPEN_AT_S + 5.0))
	assert_almost_eq(VortexTiming.OPEN_AT_S, 3.5, EPS, "1 s glow, 1 s flash, 1.5 s growth")


func test_radius_grows_holds_and_shrinks() -> void:
	var t := VortexTiming.new(2.0)
	assert_eq(t.radius_scale(1.9), 0.0, "nothing before the flash ends")
	assert_almost_eq(t.radius_scale(2.75), 0.5, EPS, "half grown half way through the growth")
	assert_eq(t.radius_scale(3.5), 1.0)
	assert_eq(t.radius_scale(5.4), 1.0)
	assert_almost_eq(t.radius_scale(6.0), 0.5, EPS, "half way through the close")
	assert_eq(t.radius_scale(6.6), 0.0)
	var last: float = 0.0
	for i: int in 16:
		var r: float = t.radius_scale(2.0 + 0.1 * float(i))
		assert_true(r >= last - EPS, "the growth never shrinks")
		last = r


func test_tip_glow_and_flash_lead_the_funnel() -> void:
	var t := VortexTiming.new()
	assert_almost_eq(t.tip_glow(1.0), 1.0, EPS, "the tips peak as the flash starts")
	assert_eq(t.tip_glow(3.0), 0.0, "and are gone once the funnel is half grown")
	assert_eq(t.flash(0.9), 0.0, "no flash while the tips glow")
	assert_almost_eq(t.flash(1.0 + 1.0 / 3.0), 1.0, EPS, "the flash peaks a third of the way in")
	assert_eq(t.flash(2.6), 0.0, "and is out early in the growth")


func test_extend_keeps_it_open_and_close_now_waits_for_open() -> void:
	var t := VortexTiming.new(1.0)
	t.extend(4.0, 3.0)
	assert_true(t.is_open(6.9), "kept open 3 s past the extend")
	assert_eq(t.phase(7.1), VortexTiming.Phase.CLOSING)
	var early := VortexTiming.new(10.0)
	early.close_now(1.0)
	assert_true(early.is_open(VortexTiming.OPEN_AT_S - EPS) == false and early.radius_scale(3.4) > 0.0,
			"a close asked for while it forms lets it finish forming")
	assert_eq(early.phase(VortexTiming.OPEN_AT_S + 0.1), VortexTiming.Phase.CLOSING, "then it closes at once")
	var closing := VortexTiming.new(1.0)
	closing.extend(4.8, 5.0)
	assert_eq(closing.phase(5.0), VortexTiming.Phase.CLOSING, "a vortex already closing is not held open again")


func test_open_in_s_counts_down_to_open() -> void:
	var t := VortexTiming.new()
	assert_almost_eq(t.open_in_s(0.0), 3.5, EPS)
	assert_almost_eq(t.open_in_s(2.0), 1.5, EPS)
	assert_eq(t.open_in_s(5.0), 0.0)
