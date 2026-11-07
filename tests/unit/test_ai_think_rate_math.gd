extends GutTest
## `AiThinkRate` (M4-T04): the far period from the rate, the staggered beat and when a ship thinks.


func test_the_period_is_the_tick_rate_over_the_far_rate() -> void:
	assert_eq(AiThinkRate.period_ticks(20.0, 60), 3, "20 Hz at 60 Hz: every third tick")
	assert_eq(AiThinkRate.period_ticks(30.0, 60), 2)
	assert_eq(AiThinkRate.period_ticks(60.0, 60), 1)
	assert_eq(AiThinkRate.period_ticks(1.0, 60), 60)
	assert_eq(AiThinkRate.period_ticks(25.0, 60), 2, "rounded to whole ticks")


func test_one_beat_per_period_for_every_ordinal() -> void:
	for ordinal: int in 7:
		var beats: int = 0
		for tick: int in 30:
			if AiThinkRate.on_beat(tick, ordinal, 3):
				beats += 1
		assert_eq(beats, 10, "ordinal %d" % ordinal)


func test_consecutive_ordinals_share_the_ticks_evenly() -> void:
	for tick: int in 12:
		var on: int = 0
		for ordinal: int in 30:
			if AiThinkRate.on_beat(tick, ordinal, 3):
				on += 1
		assert_eq(on, 10, "tick %d carries a third of 30 ships" % tick)


func test_a_ship_thinks_with_the_rule_off_when_woken_near_or_on_its_beat() -> void:
	assert_true(AiThinkRate.thinks(false, false, false, 1, 0, 3), "rule off")
	assert_true(AiThinkRate.thinks(true, true, false, 1, 0, 3), "woken")
	assert_true(AiThinkRate.thinks(true, false, true, 1, 0, 3), "near")
	assert_true(AiThinkRate.thinks(true, false, false, 3, 0, 3), "on its beat")
	assert_false(AiThinkRate.thinks(true, false, false, 1, 0, 3), "far, between beats")
	assert_true(AiThinkRate.thinks(true, false, false, 1, 0, 1), "a period of one tick thinks every tick")
