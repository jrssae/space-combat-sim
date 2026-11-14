extends GutTest
## A jump vortex's timing (M6-T14, T19, D69): the opener's lead-in, the centre flash, the unfolding, the hold, the close and the
## closing flash, from the age alone. A gate's lead-in is its arm activation; a ship's own point has none: its star swells straight to its flare (M7-T23). The seconds are data
## (`data/jump/vortex_look.json`), so the tests work from `VortexTiming`'s values.

const EPS: float = 1e-4


func test_phases_follow_the_reference_order_at_a_gate() -> void:
	var lead: float = GateActivation.DURATION_S
	var t := VortexTiming.new(4.0, lead)
	assert_eq(t.phase(-0.1), VortexTiming.Phase.CLOSED, "before it starts")
	assert_eq(t.phase(lead * 0.5), VortexTiming.Phase.ACTIVATE, "the gate's arms light up first")
	assert_eq(t.phase(lead + VortexTiming.FLASH_S * 0.5), VortexTiming.Phase.FLASH, "then the flash at the centre")
	assert_eq(t.phase(lead + VortexTiming.FLASH_S + VortexTiming.GROW_S * 0.5), VortexTiming.Phase.GROW, "then the funnel unfolds")
	assert_almost_eq(t.open_at_s, lead + VortexTiming.FLASH_S + VortexTiming.GROW_S, EPS, "activation, flash, growth")
	assert_eq(t.phase(t.open_at_s), VortexTiming.Phase.OPEN, "fully open")
	assert_eq(t.phase(t.open_at_s + 3.9), VortexTiming.Phase.OPEN, "open for the hold")
	assert_eq(t.phase(t.open_at_s + 4.0 + VortexTiming.CLOSE_S * 0.5), VortexTiming.Phase.CLOSING, "then it closes")
	var folded: float = t.open_at_s + 4.0 + VortexTiming.CLOSE_S
	assert_eq(t.phase(folded + VortexTiming.END_FLASH_S * 0.1), VortexTiming.Phase.END_FLASH, "folded back, it flashes")
	assert_eq(t.phase(folded + VortexTiming.END_FLASH_S + 0.1), VortexTiming.Phase.CLOSED, "gone once the flash is out")
	assert_false(t.is_done(folded + VortexTiming.END_FLASH_S - 0.1))
	assert_true(t.is_done(folded + VortexTiming.END_FLASH_S))
	assert_almost_eq(t.done_at_s(), folded + VortexTiming.END_FLASH_S, EPS)
	assert_eq(t.phase_name(folded + VortexTiming.END_FLASH_S * 0.5), "end_flash")


func test_the_timings_follow_the_gif() -> void:
	# The maintainer's GIF (M7-T23): the arms' chase about 1.2 s and 2 s to the flash, a flash of about 1.4 s, the funnel out in
	# 1 to 1.4 s. A ship's own point does not pause (the maintainer, M6-T19 round 2 and M7-T23).
	assert_between(GateActivation.DURATION_S, 1.6, 2.4)
	assert_between(GateActivation.CHASE_S, 1.0, 1.4)
	assert_between(VortexTiming.FLASH_S, 1.2, 1.6)
	assert_between(VortexTiming.GROW_S, 1.0, 1.4)
	assert_eq(VortexTiming.POINT_LEAD_S, 0.0, "no pause before a point's flare")
	assert_lt(VortexTiming.GATE_FLASH_PEAK, VortexTiming.POINT_FLASH_PEAK, "a gate's flash bursts, a point's star swells")


func test_a_plain_opening_starts_at_the_flash() -> void:
	var t := VortexTiming.new()
	assert_eq(t.phase(0.0), VortexTiming.Phase.FLASH, "no lead-in: the flash comes first")
	assert_almost_eq(t.open_at_s, VortexTiming.FLASH_S + VortexTiming.GROW_S, EPS)
	assert_gt(t.flash(0.1), 0.0)
	assert_eq(t.growth(VortexTiming.FLASH_S - 0.1), 0.0)


func test_a_ships_own_point_swells_from_a_star_to_its_flare() -> void:
	var t := VortexTiming.for_point()
	var lead: float = VortexTiming.POINT_LEAD_S
	assert_true(t.spark)
	assert_almost_eq(t.open_at_s, VortexTiming.point_forming_s(), EPS)
	assert_eq(t.phase(lead), VortexTiming.Phase.FLASH, "the flash straight after its lead-in")
	assert_eq(t.flash(0.0), 0.0, "it fades in, no pop")
	var early: float = t.flash(lead + VortexTiming.SPARK_RISE_S)
	assert_between(early, VortexTiming.SPARK_LEVEL - EPS, 0.5, "a small star first")
	var peak_at: float = lead + VortexTiming.FLASH_S * VortexTiming.POINT_FLASH_PEAK
	var last: float = 0.0
	for i: int in 11:
		var level: float = t.flash(lerpf(lead, peak_at, i / 10.0))
		assert_gte(level, last, "swelling to the flare")
		last = level
	assert_almost_eq(t.flash(peak_at), 1.0, EPS)
	assert_eq(t.growth(peak_at), 0.0, "the funnel opens after the flare")
	# A lead-in, if the data gives one, holds the star small (the GIF's pause).
	var held := VortexTiming.new(4.0, 1.0, true)
	assert_almost_eq(held.flash(0.9), VortexTiming.SPARK_LEVEL, EPS)
	assert_false(VortexTiming.new(4.0, 2.0).spark, "a gate's vortex has no star")
	assert_eq(VortexTiming.new(4.0, 2.0).flash(1.0), 0.0)


func test_growth_unfolds_holds_and_folds_back() -> void:
	var t := VortexTiming.new(2.0, 1.0)
	var from: float = 1.0 + VortexTiming.FLASH_S
	assert_eq(t.growth(from - 0.1), 0.0, "nothing before the flash ends")
	assert_almost_eq(t.growth(from + VortexTiming.GROW_S * 0.5), 0.5, EPS, "half way out half way through the growth")
	assert_eq(t.growth(t.open_at_s), 1.0)
	assert_eq(t.growth(t.open_at_s + 1.9), 1.0)
	assert_almost_eq(t.growth(t.close_from_s + VortexTiming.CLOSE_S * 0.5), 0.5, EPS, "half way through the close")
	assert_eq(t.growth(t.close_from_s + VortexTiming.CLOSE_S + 0.1), 0.0)
	var last: float = 0.0
	for i: int in 16:
		var r: float = t.growth(from + VortexTiming.GROW_S * float(i) / 15.0)
		assert_true(r >= last - EPS, "the unfolding never goes back")
		last = r


func test_the_flash_follows_the_lead_in() -> void:
	var t := VortexTiming.new(4.0, 1.0)
	assert_eq(t.flash(0.9), 0.0, "no flash during the lead-in")
	assert_almost_eq(t.flash(1.0 + VortexTiming.FLASH_S * VortexTiming.GATE_FLASH_PEAK), 1.0, EPS, "a gate's flash bursts early")
	assert_gt(t.flash(1.0 + VortexTiming.FLASH_S), 0.0, "still fading as the funnel starts to unfold")
	assert_eq(t.flash(1.0 + VortexTiming.FLASH_S + VortexTiming.GROW_S / 3.0 + 0.01), 0.0, "and is out early in the growth")


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
	assert_almost_eq(t.open_in_s(0.0), t.open_at_s, EPS)
	assert_almost_eq(t.open_in_s(2.0), t.open_at_s - 2.0, EPS)
	assert_eq(t.open_in_s(t.open_at_s + 1.5), 0.0)


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
