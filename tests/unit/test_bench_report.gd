extends GutTest
## BenchReport (M4-T01): a run's summary from the probe's recorded ticks, and a sweep's from its runs. Pure dictionaries, no
## files.


## Recorded ticks with `ticks` as the tick times; every other stage `stage_us` unless `fields` (Field -> values) says otherwise.
func _series(ticks: Array, stage_us: int = 100, fields: Dictionary = {}) -> Array[PackedInt64Array]:
	var out: Array[PackedInt64Array] = []
	for i: int in PerfProbe.FIELD_NAMES.size():
		out.append(PackedInt64Array())
	for k: int in ticks.size():
		for i: int in PerfProbe.FIELD_NAMES.size():
			var v: int = stage_us
			match i:
				PerfProbe.Field.TICK:
					v = int(ticks[k])
				PerfProbe.Field.STAGES_ON, PerfProbe.Field.SYNC_ON:
					v = 1
				PerfProbe.Field.REBASE:
					v = 0
				PerfProbe.Field.SHIPS:
					v = 13
			if fields.has(i):
				v = int((fields[i] as Array)[k])
			out[i].append(v)
	return out


func _run(layout: String, n: int, tick_median_us: float, passed: bool, ai_mean_us: float) -> Dictionary:
	return {
		"layout": layout, "n": n, "lag": 0.0, "load_ms": 10.0,
		"stages": {"tick": {"median_us": tick_median_us, "p99_us": tick_median_us * 1.2, "mean_us": tick_median_us},
				"ai": {"mean_us": ai_mean_us}, "targeting": {"mean_us": tick_median_us - ai_mean_us}},
		"rebase": {"max_us": 500.0},
		"verdict": {"pass": passed, "failures": [] if passed else ["tick median over 8.0 ms"]},
	}


func test_a_run_summary_takes_its_numbers_from_the_recorded_ticks() -> void:
	var s: Dictionary = BenchReport.run_summary({"sim_s": 1.0, "wall_s": 1.0}, _series([5000, 6000, 7000]))
	assert_eq(int(s["ticks"]), 3)
	assert_eq(float(((s["stages"] as Dictionary)["tick"] as Dictionary)["median_us"]), 6000.0)
	assert_eq(float(((s["stages"] as Dictionary)["ai"] as Dictionary)["mean_us"]), 100.0)
	assert_eq(int(s["ships_min"]), 13)
	assert_true(bool((s["verdict"] as Dictionary)["pass"]))


func test_an_aborted_run_fails_and_says_why() -> void:
	var s: Dictionary = BenchReport.run_summary({"sim_s": 1.0, "wall_s": 1.0, "aborted": "too slow"}, _series([5000]))
	var verdict: Dictionary = s["verdict"]
	assert_false(bool(verdict["pass"]))
	assert_eq((verdict["failures"] as Array).size(), 1, "the reason is listed")
	assert_string_contains(String((verdict["failures"] as Array)[0]), "too slow")


func test_a_sweep_summary_has_each_counts_verdict_and_the_median_stage_means() -> void:
	var runs: Array[Dictionary] = [
		_run("furball", 25, 7000.0, true, 1000.0), _run("furball", 25, 7500.0, true, 2000.0), _run("furball", 25, 9000.0, false, 3000.0),
		_run("furball", 50, 20000.0, false, 4000.0), _run("furball", 50, 21000.0, false, 4000.0), _run("furball", 50, 22000.0, false, 4000.0),
		_run("spread", 25, 9000.0, false, 1000.0),
	]
	var s: Dictionary = BenchReport.sweep_summary(runs, {"label": "t"})
	var furball: Dictionary = (s["layouts"] as Dictionary)["furball"]
	assert_eq(int(furball["max_n"]), 25)
	var first: Dictionary = (furball["counts"] as Array)[0]
	assert_eq(int(first["n"]), 25)
	assert_eq(int(first["passes"]), 2)
	assert_true(bool(first["pass"]))
	assert_eq(float(first["tick_median_us"]), 7500.0, "the median of the runs' medians")
	var means: Dictionary = first["stage_means_us"]
	assert_eq(float(means["ai"]), 2000.0, "the median over runs of each stage's mean")
	assert_eq(float(means["tick"]), 7500.0)
	assert_eq(int(s["headline_max_n"]), 0, "spread passed nothing")
	assert_string_contains(BenchReport.sweep_markdown(s), "4.00 (19 %)", "the breakdown at 50 ships shows the means")


func test_the_rebase_budget_is_the_whole_tick_that_held_a_rebase() -> void:
	# The shift itself is cheap; the tick around it (Jolt moving every body, the reset) is what must fit in a frame.
	var s: Dictionary = BenchReport.run_summary({"sim_s": 1.0, "wall_s": 1.0},
			_series([5000, 20000, 5000, 6000], 100, {PerfProbe.Field.REBASE: [0, 400, 0, 0]}))
	var rebase: Dictionary = s["rebase"]
	assert_eq(int(rebase["count"]), 1)
	assert_eq(float(rebase["tick_max_us"]), 20000.0, "the worst tick holding a rebase")
	assert_eq(float(rebase["shift_max_us"]), 400.0, "the shift's own cost, recorded beside it")
	var failures: Array = (s["verdict"] as Dictionary)["failures"]
	assert_true(failures.any(func(f: Variant) -> bool: return String(f).contains("rebase")), "the rebase budget fails: %s" % [failures])


func test_a_slow_tick_without_a_rebase_is_not_a_rebase_failure() -> void:
	var s: Dictionary = BenchReport.run_summary({"sim_s": 1.0, "wall_s": 1.0},
			_series([5000, 9000, 30000], 100, {PerfProbe.Field.REBASE: [0, 300, 0]}))
	assert_eq(float((s["rebase"] as Dictionary)["tick_max_us"]), 9000.0)
	var failures: Array = (s["verdict"] as Dictionary)["failures"]
	assert_false(failures.any(func(f: Variant) -> bool: return String(f).contains("rebase")), "only the p99 fails: %s" % [failures])


func test_the_resolvers_split_into_hit_and_ram_and_the_sync_share_is_recorded() -> void:
	var s: Dictionary = BenchReport.run_summary({"sim_s": 1.0, "wall_s": 1.0}, _series([5000, 6000, 7000, 8000], 100, {
		PerfProbe.Field.HIT: [30, 30, 30, 30], PerfProbe.Field.RAM: [60, 60, 60, 60], PerfProbe.Field.SYNC_ON: [1, 0, 0, 1]}))
	var stages: Dictionary = s["stages"]
	assert_eq(float((stages["hit"] as Dictionary)["mean_us"]), 30.0)
	assert_eq(float((stages["ram"] as Dictionary)["mean_us"]), 60.0)
	assert_eq(float(s["sync_timed_share"]), 0.5, "the body sync was timed in half the ticks (the others ran back to back)")


func test_a_missing_run_counts_as_a_failure() -> void:
	# A run that crashed or was killed writes no summary; one surviving pass must not pass the count.
	var one: Array[Dictionary] = [_run("furball", 25, 7000.0, true, 1000.0)]
	var s: Dictionary = BenchReport.sweep_summary(one, {}, 3)
	var count: Dictionary = (((s["layouts"] as Dictionary)["furball"] as Dictionary)["counts"] as Array)[0]
	assert_false(bool(count["pass"]), "one pass of three expected runs")
	assert_eq(int(count["missing"]), 2)
	assert_eq(int(count["runs"]), 3, "counted against the runs the sweep asked for")
	assert_eq(int(((s["layouts"] as Dictionary)["furball"] as Dictionary)["max_n"]), 0)
	var two: Array[Dictionary] = [_run("furball", 25, 7000.0, true, 1000.0), _run("furball", 25, 7100.0, true, 1000.0)]
	var count_two: Dictionary = ((((BenchReport.sweep_summary(two, {}, 3)["layouts"] as Dictionary)["furball"] as Dictionary)["counts"]) as Array)[0]
	assert_true(bool(count_two["pass"]), "two passes of three still pass")
	assert_eq(int(count_two["missing"]), 1)
	assert_string_contains(BenchReport.sweep_markdown(BenchReport.sweep_summary(one, {}, 3)), "2 missing")
