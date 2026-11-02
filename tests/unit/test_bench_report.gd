extends GutTest
## BenchReport (M4-T01): a run's summary from the probe's recorded ticks, and a sweep's from its runs. Pure dictionaries, no
## files.


func _series(ticks: Array, stage_us: int = 100) -> Array[PackedInt64Array]:
	var out: Array[PackedInt64Array] = []
	for i: int in PerfProbe.FIELD_NAMES.size():
		out.append(PackedInt64Array())
	for t: Variant in ticks:
		for i: int in PerfProbe.FIELD_NAMES.size():
			var v: int = stage_us
			match i:
				PerfProbe.Field.TICK:
					v = int(t)
				PerfProbe.Field.STAGES_ON:
					v = 1
				PerfProbe.Field.REBASE:
					v = 0
				PerfProbe.Field.SHIPS:
					v = 13
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
