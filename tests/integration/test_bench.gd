extends GutTest
## The benchmark harness on the real main scene (M4-T01, AC1): the `perf` provider shows the last tick's stages, and `bench
## <layout> <n> [seconds]` flies a layout from the pools, measures it and writes `summary.json` and `summary.md`. Only that the
## numbers are there and add up is checked, never what they are: timings on this machine are the sweep's job
## (`scripts/bench.sh`), not a pass-or-fail test's.

const ROOT: String = "user://test_bench"
const STAGE_KEYS: Array[StringName] = [&"tick_us", &"ai_us", &"scan_us", &"physics_us", &"resolvers_us", &"targeting_us",
		&"rebase_us", &"ships"]

var main: Main


func before_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.waves_auto_start = false
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	add_child_autofree(main)
	main.bench.report_root = ROOT
	await _ticks(2)


func after_each() -> void:
	DebugConsole.flags.invulnerable = false
	ContactScan.invalidate()
	Factions.reset()


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _exec(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


func _read(path: String) -> Variant:
	return DebugConsole.registry.read(path)["value"]


func _summary_of(label: String) -> Dictionary:
	var path: String = ROOT.path_join(label).path_join("summary.json")
	assert_true(FileAccess.file_exists(path), "%s written" % path)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(parsed is Dictionary, "summary.json is a JSON object")
	return parsed if parsed is Dictionary else {}


func _run(line: String) -> void:
	var result: ConsoleResult = _exec(line)
	assert_true(result.ok, "%s: %s" % [line, result.text()])
	await wait_for_signal(main.bench.finished, 60.0, "the bench finishes")


func test_the_perf_provider_shows_the_last_ticks_stages() -> void:
	for key: StringName in STAGE_KEYS:
		assert_true(DebugConsole.registry.read("perf." + String(key))["ok"], "perf.%s exists" % key)
	assert_false(bool(_read("perf.enabled")), "the probe is off unless asked")
	assert_true(_exec("perf on").ok)
	await _ticks(10)
	assert_true(bool(_read("perf.enabled")))
	assert_gt(int(_read("perf.tick_us")), 0, "a tick took time")
	assert_eq(int(_read("perf.ships")), 1, "free flight: the player alone")
	# The stages split the tick: every part of it is in exactly one stage or the named remainder.
	var parts: int = 0
	for key: String in ["ai_us", "flight_us", "targeting_us", "resolvers_us", "late_us", "physics_us", "other_us"]:
		var v: int = int(_read("perf." + key))
		assert_gte(v, 0, "perf.%s is not negative" % key)
		parts += v
	assert_eq(parts, int(_read("perf.tick_us")), "the stages add up to the tick")
	assert_true(ContactScan.timing, "the scan is timed while the probe is on")
	assert_true(_exec("perf off").ok)
	await _ticks(2)
	assert_false(bool(_read("perf.enabled")))
	assert_false(ContactScan.timing, "and costs nothing when it is off")


func test_a_short_furball_bench_writes_its_report() -> void:
	await _run("bench furball 12 1 warmup=0.5 seed=3 label=furball_test rebase_m=20")
	var s: Dictionary = _summary_of("furball_test")
	assert_eq(String(s.get("layout", "")), "furball")
	assert_eq(int(s.get("n", 0)), 12)
	assert_eq(int(s.get("seed", 0)), 3)
	assert_eq(int(s.get("ticks", 0)), 60, "one second of ticks measured")
	for key: String in ["tick", "physics", "ai", "scan", "targeting", "resolvers", "flight", "late", "other"]:
		var stage: Dictionary = (s.get("stages", {}) as Dictionary).get(key, {})
		assert_true(stage.has("median_us") and stage.has("p99_us"), "stage %s has its median and p99" % key)
	assert_gt(float(((s["stages"] as Dictionary)["tick"] as Dictionary)["median_us"]), 0.0)
	assert_gt(int((s.get("rebase", {}) as Dictionary).get("count", 0)), 0, "the player's cruise rebased the world")
	assert_true((s.get("verdict", {}) as Dictionary).has("pass"), "a budget verdict")
	assert_true((s.get("machine", {}) as Dictionary).has("cpu"), "the machine is recorded")
	assert_true((s.get("machine", {}) as Dictionary).has("godot"))
	assert_true(s.has("load_ms") and s.has("lag"), "load time and real time kept")
	assert_eq(int(s.get("ships_min", 0)), 13, "all twelve and the player stayed in play")
	assert_true(FileAccess.file_exists(ROOT.path_join("furball_test/summary.md")), "summary.md written")
	assert_eq(main.ships.alive().size(), 12)
	for c: Combatant in main.ships.alive():
		assert_true(c.damageable.invulnerable, "%s holds the count steady" % c.display_name)
		assert_true(c.driver.brain is AiPilot, "%s flies an AiPilot" % c.display_name)
	assert_eq(main.world.auto_rebase_distance_m, 5000.0, "the rebase threshold is back")
	assert_false(bool(_read("perf.enabled")), "the probe is off again")


func test_transit_flies_wings_of_four_with_the_sides_neutral() -> void:
	assert_true(_exec("bench transit 8 1 warmup=0.2 label=transit_test").ok)
	await _ticks(2)
	assert_eq(Factions.relation(Factions.EARTH_ALLIANCE, Factions.RAIDERS), Factions.Relation.NEUTRAL, "no fight in transit")
	for wing_name: String in ["TRANSIT 1", "TRANSIT 2"]:
		var wing: Wing = main.wings.wing_named(wing_name)
		assert_not_null(wing, "%s formed" % wing_name)
		if wing != null:
			assert_not_null(wing.leader)
			assert_eq(wing.members().size(), 3, "%s: a leader and three wingmen" % wing_name)
	await wait_for_signal(main.bench.finished, 60.0, "the bench finishes")
	assert_eq(Factions.relation(Factions.EARTH_ALLIANCE, Factions.RAIDERS), Factions.Relation.HOSTILE, "the sides are restored")
	assert_eq(int(_summary_of("transit_test").get("n", 0)), 8)


func test_paired_probe_blocks_report_the_probes_own_cost() -> void:
	await _run("bench spread 12 2 warmup=0.2 label=paired_test probe=paired")
	var probe: Dictionary = _summary_of("paired_test").get("probe_cost", {})
	assert_true(probe.has("paired_us"), "the stage timers' cost against the same ticks without them")
	assert_gt(int(probe.get("on_blocks", 0)), 1)
	assert_eq(int(probe.get("on_blocks", 0)), int(probe.get("off_blocks", 0)) + 1, "on, off, ..., on")


func test_bad_requests_are_refused() -> void:
	assert_false(_exec("bench parade 10").ok, "an unknown layout")
	assert_false(_exec("bench furball 10 1 colour=red").ok, "an unknown option")
	assert_true(_exec("bench furball 4 1 warmup=0 label=twice_test").ok)
	assert_false(_exec("bench furball 4 1").ok, "one bench at a time")
	await wait_for_signal(main.bench.finished, 60.0, "the bench finishes")


func test_options_are_read_from_key_value_words() -> void:
	var o: Dictionary = BenchRunner.parse_options(PackedStringArray(["12", "warmup=2", "seed=4", "label=a/b", "probe=paired",
			"rebase_m=90"]))
	assert_true(o["ok"], String(o.get("error", "")))
	assert_eq(float(o["seconds"]), 12.0)
	assert_eq(float(o["warmup"]), 2.0)
	assert_eq(int(o["seed"]), 4)
	assert_eq(String(o["label"]), "a/b")
	assert_true(bool(o["paired"]))
	assert_eq(float(o["rebase_m"]), 90.0)
	var defaults: Dictionary = BenchRunner.parse_options(PackedStringArray())
	assert_eq(float(defaults["seconds"]), BenchRunner.DEFAULT_SECONDS)
	assert_eq(float(defaults["warmup"]), BenchRunner.DEFAULT_WARMUP_S)
	assert_eq(float(defaults["rebase_m"]), BenchRunner.REBASE_THRESHOLD_M)
	assert_false(bool(BenchRunner.parse_options(PackedStringArray(["seed=x"]))["ok"]))
	assert_false(bool(BenchRunner.parse_options(PackedStringArray(["0"]))["ok"]), "no zero-length window")
