extends GutTest
## PerfStats (M4-T01, AC1): the statistics behind the benchmark, pure. Median and p99 of a run's ticks, the budget verdict
## (median, p99, rebase ticks, real time kept) and the max-N search over a sweep (two passing runs of three, stop after two
## failing ship counts in a row, the headline is the lower of furball and spread).


func _values(list: Array) -> PackedFloat64Array:
	return PackedFloat64Array(list)


func _ramp(count: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for i: int in count:
		out.append(float(i + 1))
	return out


# --- median and percentiles ---------------------------------------------------------------------------------------


func test_median_of_an_odd_count_is_the_middle_value() -> void:
	assert_eq(PerfStats.median(_values([5.0, 1.0, 3.0])), 3.0)


func test_median_of_an_even_count_is_the_mean_of_the_two_middle_values() -> void:
	assert_eq(PerfStats.median(_values([4.0, 1.0, 3.0, 2.0])), 2.5)


func test_median_of_nothing_is_zero() -> void:
	assert_eq(PerfStats.median(PackedFloat64Array()), 0.0)


func test_median_does_not_reorder_the_callers_samples() -> void:
	var samples: PackedFloat64Array = _values([3.0, 1.0, 2.0])
	PerfStats.median(samples)
	assert_eq(samples, _values([3.0, 1.0, 2.0]))


func test_p99_is_the_nearest_rank() -> void:
	# Nearest rank: the smallest value with at least 99 % of the samples at or below it.
	assert_eq(PerfStats.percentile(_ramp(100), 0.99), 99.0)
	assert_eq(PerfStats.percentile(_ramp(1800), 0.99), 1782.0, "a 30 s window's p99 is its 19th worst tick")
	assert_eq(PerfStats.percentile(_ramp(10), 0.99), 10.0, "with few samples p99 is the worst")


func test_percentile_ends_and_empty() -> void:
	assert_eq(PerfStats.percentile(_values([7.0, 2.0, 9.0]), 0.0), 2.0)
	assert_eq(PerfStats.percentile(_values([7.0, 2.0, 9.0]), 1.0), 9.0)
	assert_eq(PerfStats.percentile(PackedFloat64Array(), 0.99), 0.0)


func test_one_slow_tick_in_a_hundred_moves_p99_but_not_the_median() -> void:
	var samples := PackedFloat64Array()
	for i: int in 99:
		samples.append(5000.0)
	samples.append(40000.0)
	assert_eq(PerfStats.median(samples), 5000.0)
	assert_eq(PerfStats.percentile(samples, 0.99), 5000.0, "the 1 % worst is above the p99")
	samples.append(40000.0)
	assert_eq(PerfStats.percentile(samples, 0.99), 40000.0, "two in 101 reach it")


func test_mean_and_max() -> void:
	assert_eq(PerfStats.mean(_values([1.0, 2.0, 6.0])), 3.0)
	assert_eq(PerfStats.mean(PackedFloat64Array()), 0.0)
	assert_eq(PerfStats.max_value(_values([1.0, 8.0, 6.0])), 8.0)
	assert_eq(PerfStats.max_value(PackedFloat64Array()), 0.0)


# --- real time kept --------------------------------------------------------------------------------------------------


func test_lag_is_the_share_of_wall_time_the_simulation_fell_behind() -> void:
	assert_almost_eq(PerfStats.lag(30.0, 30.0), 0.0, 1e-9)
	assert_almost_eq(PerfStats.lag(30.0, 60.0), 0.5, 1e-9, "half speed")
	assert_almost_eq(PerfStats.lag(30.0, 30.3), 0.3 / 30.3, 1e-9)
	assert_eq(PerfStats.lag(30.0, 0.0), 0.0, "no wall time measured")


func test_a_simulation_ahead_of_the_wall_clock_has_no_lag() -> void:
	assert_eq(PerfStats.lag(30.0, 29.9), 0.0)


# --- the budget verdict ----------------------------------------------------------------------------------------------


func test_a_run_inside_every_budget_passes() -> void:
	var v: Dictionary = PerfStats.verdict(7000.0, 11000.0, 9000.0, 0.002)
	assert_true(v["pass"])
	assert_eq((v["failures"] as PackedStringArray).size(), 0)


func test_the_budget_numbers_are_the_milestones() -> void:
	assert_eq(PerfStats.TICK_MEDIAN_BUDGET_US, 8000.0)
	assert_eq(PerfStats.TICK_P99_BUDGET_US, 12000.0)
	assert_almost_eq(PerfStats.REBASE_BUDGET_US, 16666.7, 0.1, "one 60 Hz frame")
	assert_eq(PerfStats.LAG_BUDGET, 0.01)


func test_the_budget_edges_pass() -> void:
	assert_true(PerfStats.verdict(8000.0, 12000.0, PerfStats.REBASE_BUDGET_US, 0.0099)["pass"])


func test_each_budget_fails_on_its_own_and_says_which() -> void:
	var slow_median: Dictionary = PerfStats.verdict(8001.0, 11000.0, 0.0, 0.0)
	assert_false(slow_median["pass"])
	assert_eq((slow_median["failures"] as PackedStringArray).size(), 1)
	assert_string_contains((slow_median["failures"] as PackedStringArray)[0], "median")
	var slow_p99: Dictionary = PerfStats.verdict(7000.0, 12001.0, 0.0, 0.0)
	assert_false(slow_p99["pass"])
	assert_string_contains((slow_p99["failures"] as PackedStringArray)[0], "p99")
	var slow_rebase: Dictionary = PerfStats.verdict(7000.0, 11000.0, 16700.0, 0.0)
	assert_false(slow_rebase["pass"])
	assert_string_contains((slow_rebase["failures"] as PackedStringArray)[0], "rebase")
	var behind: Dictionary = PerfStats.verdict(7000.0, 11000.0, 0.0, 0.01)
	assert_false(behind["pass"])
	assert_string_contains((behind["failures"] as PackedStringArray)[0], "real time")


func test_every_failure_is_listed() -> void:
	var v: Dictionary = PerfStats.verdict(9000.0, 20000.0, 30000.0, 0.4)
	assert_false(v["pass"])
	assert_eq((v["failures"] as PackedStringArray).size(), 4)


# --- max N over a sweep ----------------------------------------------------------------------------------------------


func test_two_passing_runs_of_three_pass_a_ship_count() -> void:
	assert_eq(PerfStats.runs_needed(3), 2)
	assert_eq(PerfStats.runs_needed(1), 1, "a single quick run decides alone")
	assert_true(PerfStats.count_passes([true, false, true]))
	assert_false(PerfStats.count_passes([true, false, false]))
	assert_false(PerfStats.count_passes([]))


func test_max_n_is_the_largest_passing_ship_count() -> void:
	var results: Dictionary = {
		25: [true, true, true],
		50: [true, true, false],
		100: [false, true, false],
		150: [false, false, false],
	}
	assert_eq(PerfStats.max_n(results), 50)


func test_max_n_takes_a_later_pass_after_a_failure() -> void:
	# A noisy failure below a pass does not cap the count: the largest passing count in the sweep wins.
	var results: Dictionary = {25: [true, true, true], 50: [false, false, true], 100: [true, true, false], 150: [false, false, false]}
	assert_eq(PerfStats.max_n(results), 100)


func test_max_n_is_zero_when_nothing_passes() -> void:
	assert_eq(PerfStats.max_n({25: [false, false, false]}), 0)
	assert_eq(PerfStats.max_n({}), 0)


func test_the_sweep_stops_after_two_failing_ship_counts_in_a_row() -> void:
	assert_false(PerfStats.should_stop([25, 50], {25: [true, true, true], 50: [false, false, false]}))
	assert_true(PerfStats.should_stop([25, 50, 100], {25: [true, true, true], 50: [false, false, false], 100: [false, true, false]}))
	assert_false(PerfStats.should_stop([25, 50, 100], {25: [false, false, false], 50: [true, true, false], 100: [false, false, false]}),
			"a pass in between restarts the count")
	assert_false(PerfStats.should_stop([], {}))


func test_the_headline_is_the_lower_of_furball_and_spread() -> void:
	assert_eq(PerfStats.headline({&"furball": 100, &"spread": 300, &"transit": 500}), 100)
	assert_eq(PerfStats.headline({&"furball": 400, &"spread": 150, &"transit": 25}), 150, "transit is recorded, not counted")
	assert_eq(PerfStats.headline({&"spread": 150}), 0, "a layout not measured counts as nothing")


# --- paired blocks (the probe's own cost) ----------------------------------------------------------------------------


func test_paired_difference_brackets_each_off_block_between_two_on_blocks() -> void:
	# On, off, on, off, on: each off block against the mean of its neighbours, the median of those differences.
	assert_almost_eq(PerfStats.paired_difference(_values([10.0, 10.0, 10.0]), _values([8.0, 8.0])), 2.0, 1e-9)


func test_paired_difference_cancels_a_steady_drift() -> void:
	assert_almost_eq(PerfStats.paired_difference(_values([10.0, 12.0, 14.0]), _values([9.0, 11.0])), 2.0, 1e-9,
			"the machine slowing down over the run is not the probe's cost")


func test_paired_difference_needs_one_more_on_block_than_off_blocks() -> void:
	assert_eq(PerfStats.paired_difference(_values([10.0, 10.0]), _values([8.0, 8.0])), 0.0)
	assert_eq(PerfStats.paired_difference(PackedFloat64Array(), PackedFloat64Array()), 0.0)
