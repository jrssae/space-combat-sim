extends GutTest
## A jump vortex's timing (M6-T14, T19, D69): the opener's lead-in, the centre flash, the unfolding, the hold, the close and the
## closing flash, from the age alone. A gate's lead-in is its arm activation (1 s, so it still opens in T14's 3.5 s); a ship-made point has none.

const EPS: float = 1e-4


func test_phases_follow_the_reference_order_at_a_gate() -> void:
	var t := VortexTiming.new(4.0, GateActivation.DURATION_S)
	assert_eq(t.phase(-0.1), VortexTiming.Phase.CLOSED, "before it starts")
	assert_eq(t.phase(0.5), VortexTiming.Phase.ACTIVATE, "the gate's arms light up first")
	assert_eq(t.phase(1.5), VortexTiming.Phase.FLASH, "then the flash at the centre")
	assert_eq(t.phase(2.5), VortexTiming.Phase.GROW, "then the funnel unfolds")
	assert_almost_eq(t.open_at_s, 3.5, EPS, "1 s activation, 1 s flash, 1.5 s growth: T14's timing")
	assert_eq(t.phase(t.open_at_s), VortexTiming.Phase.OPEN, "fully open at 3.5 s")
	assert_eq(t.phase(t.open_at_s + 3.9), VortexTiming.Phase.OPEN, "open for the hold")
	assert_eq(t.phase(t.open_at_s + 4.5), VortexTiming.Phase.CLOSING, "then it closes")
	assert_eq(t.phase(t.open_at_s + 5.1), VortexTiming.Phase.END_FLASH, "folded back within a second, it flashes")
	assert_eq(t.phase(t.open_at_s + 6.1), VortexTiming.Phase.CLOSED, "gone once the flash is out")
	assert_false(t.is_done(t.open_at_s + 5.9))
	assert_true(t.is_done(t.open_at_s + 6.0))
	assert_almost_eq(t.done_at_s(), t.open_at_s + 5.0 + VortexTiming.END_FLASH_S, EPS)
	assert_eq(t.phase_name(t.open_at_s + 5.5), "end_flash")


func test_a_ship_made_point_starts_at_the_flash() -> void:
	var t := VortexTiming.new()
	assert_eq(t.phase(0.0), VortexTiming.Phase.FLASH, "no lead-in: the flash comes first")
	assert_almost_eq(t.open_at_s, 2.5, EPS)
	assert_gt(t.flash(0.2), 0.0)
	assert_eq(t.growth(0.9), 0.0)


func test_growth_unfolds_holds_and_folds_back() -> void:
	var t := VortexTiming.new(2.0, 1.0)
	assert_eq(t.growth(1.9), 0.0, "nothing before the flash ends")
	assert_almost_eq(t.growth(2.75), 0.5, EPS, "half way out half way through the growth")
	assert_eq(t.growth(3.5), 1.0)
	assert_eq(t.growth(5.4), 1.0)
	assert_almost_eq(t.growth(6.0), 0.5, EPS, "half way through the close")
	assert_eq(t.growth(6.6), 0.0)
	var last: float = 0.0
	for i: int in 16:
		var r: float = t.growth(2.0 + 0.1 * float(i))
		assert_true(r >= last - EPS, "the unfolding never goes back")
		last = r


func test_the_flash_follows_the_lead_in() -> void:
	var t := VortexTiming.new(4.0, 1.0)
	assert_eq(t.flash(0.9), 0.0, "no flash during the lead-in")
	assert_almost_eq(t.flash(1.0 + 1.0 / 3.0), 1.0, EPS, "the flash peaks a third of the way in")
	assert_eq(t.flash(2.6), 0.0, "and is out early in the growth")


func test_extend_keeps_it_open_and_close_now_waits_for_open() -> void:
	var t := VortexTiming.new(1.0, 1.0)
	t.extend(4.0, 3.0)
	assert_true(t.is_open(6.9), "kept open 3 s past the extend")
	assert_eq(t.phase(7.1), VortexTiming.Phase.CLOSING)
	var early := VortexTiming.new(10.0, 1.0)
	early.close_now(1.0)
	assert_true(early.is_open(early.open_at_s - EPS) == false and early.growth(3.4) > 0.0,
			"a close asked for while it forms lets it finish forming")
	assert_eq(early.phase(early.open_at_s + 0.1), VortexTiming.Phase.CLOSING, "then it closes at once")
	var closing := VortexTiming.new(1.0, 1.0)
	closing.extend(4.8, 5.0)
	assert_eq(closing.phase(5.0), VortexTiming.Phase.CLOSING, "a vortex already closing is not held open again")


func test_open_in_s_counts_down_to_open() -> void:
	var t := VortexTiming.new(4.0, 1.0)
	assert_almost_eq(t.open_in_s(0.0), 3.5, EPS)
	assert_almost_eq(t.open_in_s(2.0), 1.5, EPS)
	assert_eq(t.open_in_s(5.0), 0.0)


func test_the_close_ends_in_a_flash_like_the_opening() -> void:
	# The maintainer (2026-11-12): a flash when the vortex closes as when it opens, for arrivals and departures alike.
	var t := VortexTiming.new(2.0, 1.0)
	var folded: float = t.close_from_s + VortexTiming.CLOSE_S
	assert_eq(t.flash(t.close_from_s + 0.1), 0.0, "no flash early in the fold")
	assert_gt(t.flash(folded - 0.1), 0.0, "it rises through the last third of the fold")
	assert_almost_eq(t.flash(folded), 1.0, EPS, "at its peak as the funnel reaches the centre")
	assert_eq(t.growth(folded), 0.0, "the funnel is gone by then")
	assert_almost_eq(t.flash(folded + VortexTiming.END_FLASH_S * 0.5), 0.5, EPS, "dying away")
	assert_eq(t.flash(t.done_at_s()), 0.0, "out when the opening is over")
	assert_false(t.is_open(folded + 0.1), "no ship passes during it")
	assert_eq(t.open_in_s(folded + 0.1), 0.0)
	var last: float = 2.0
	for i: int in 11:
		var level: float = t.flash(folded + 0.1 * float(i))
		assert_true(level <= last + EPS, "it only fades after the peak")
		last = level
	var never_held := VortexTiming.new(0.0, 0.0)
	assert_eq(never_held.flash(never_held.open_at_s), 0.0, "an opening held for no time keeps its two flashes apart")


func test_extend_and_close_now_leave_the_closing_flash_alone() -> void:
	var t := VortexTiming.new(1.0, 1.0)
	var flash_at: float = t.close_from_s + VortexTiming.CLOSE_S + 0.2
	t.extend(flash_at, 5.0)
	t.close_now(flash_at)
	assert_eq(t.phase(flash_at), VortexTiming.Phase.END_FLASH, "a vortex in its closing flash is not held open again")
