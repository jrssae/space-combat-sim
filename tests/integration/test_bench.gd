extends TestSteps
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
	for key: String in ["hit", "ram"]:
		assert_true(((s["stages"] as Dictionary).get(key, {}) as Dictionary).has("mean_us"), "the resolvers split: %s" % key)
	assert_true(s.has("sync_timed_share"), "how often the body sync was timed")
	assert_true((s.get("rebase", {}) as Dictionary).has("tick_max_us"), "the worst tick that held a rebase")
	assert_true((s.get("machine", {}) as Dictionary).has("godot_binary"), "which Godot binary ran")
	assert_false(bool(s.get("n_includes_player", true)), "N counts the layout's ships, not the player")
	_assert_stages_are_consistent(main.perf_probe.series)
	assert_eq(main.ships.alive().size(), 12)
	for c: Combatant in main.ships.alive():
		assert_true(c.damageable.invulnerable, "%s holds the count steady" % c.display_name)
		assert_true(c.driver.brain is AiPilot, "%s flies an AiPilot" % c.display_name)
	assert_eq(main.world.auto_rebase_distance_m, 5000.0, "the rebase threshold is back")
	assert_false(bool(_read("perf.enabled")), "the probe is off again")


# Per tick, every stage timed inside another is no larger than it, and the stages split the tick.
func _assert_stages_are_consistent(series: Array[PackedInt64Array]) -> void:
	var ticks: int = series[PerfProbe.Field.TICK].size()
	assert_gt(ticks, 0, "ticks were recorded")
	var broken := PackedStringArray()
	for i: int in ticks:
		var v: Callable = func(field: int) -> int: return series[field][i]
		if v.call(PerfProbe.Field.STAGES_ON) != 1:
			continue
		if v.call(PerfProbe.Field.SCAN) > v.call(PerfProbe.Field.AI):
			broken.append("tick %d: scan %d over ai %d" % [i, v.call(PerfProbe.Field.SCAN), v.call(PerfProbe.Field.AI)])
		if v.call(PerfProbe.Field.THINK) > v.call(PerfProbe.Field.AI):
			broken.append("tick %d: think %d over ai %d" % [i, v.call(PerfProbe.Field.THINK), v.call(PerfProbe.Field.AI)])
		if v.call(PerfProbe.Field.SCAN) > v.call(PerfProbe.Field.THINK):
			broken.append("tick %d: scan %d over think %d" % [i, v.call(PerfProbe.Field.SCAN), v.call(PerfProbe.Field.THINK)])
		if v.call(PerfProbe.Field.HIT) + v.call(PerfProbe.Field.RAM) > v.call(PerfProbe.Field.RESOLVERS):
			broken.append("tick %d: hit %d + ram %d over resolvers %d" % [i, v.call(PerfProbe.Field.HIT), v.call(PerfProbe.Field.RAM),
					v.call(PerfProbe.Field.RESOLVERS)])
		if v.call(PerfProbe.Field.SYNC) > v.call(PerfProbe.Field.PHYSICS):
			broken.append("tick %d: sync over physics" % i)
		if v.call(PerfProbe.Field.REBASE) > v.call(PerfProbe.Field.FLIGHT) + v.call(PerfProbe.Field.LATE):
			broken.append("tick %d: rebase %d over flight + late" % [i, v.call(PerfProbe.Field.REBASE)])
		var parts: int = 0
		for f: int in [PerfProbe.Field.AI, PerfProbe.Field.FLIGHT, PerfProbe.Field.TARGETING, PerfProbe.Field.RESOLVERS,
				PerfProbe.Field.LATE, PerfProbe.Field.PHYSICS, PerfProbe.Field.OTHER]:
			parts += v.call(f)
		if parts != v.call(PerfProbe.Field.TICK):
			broken.append("tick %d: stages %d, tick %d" % [i, parts, v.call(PerfProbe.Field.TICK)])
	assert_eq(broken.size(), 0, "stages nest inside the stage that contains them: %s" % "; ".join(broken.slice(0, 6)))
	# Every driver hosted in the native brain host (M4-T35): its perception runs inside the native think, counted in
	# `think`, and no GDScript contact scan is built in the measured ticks, so `scan` reads 0.
	assert_gt(PerfStats.max_value(_floats(series[PerfProbe.Field.THINK])), 0.0, "the hosted drivers' think was timed")
	assert_gt(PerfStats.max_value(_floats(series[PerfProbe.Field.THINK])), 0.0, "the drivers were timed")


static func _floats(values: PackedInt64Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for x: int in values:
		out.append(float(x))
	return out


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
			"rebase_m=90", "sleep=keep"]))
	assert_true(o["ok"], String(o.get("error", "")))
	assert_eq(float(o["seconds"]), 12.0)
	assert_eq(float(o["warmup"]), 2.0)
	assert_eq(int(o["seed"]), 4)
	assert_eq(String(o["label"]), "a/b")
	assert_true(bool(o["paired"]))
	assert_eq(float(o["rebase_m"]), 90.0)
	assert_true(bool(o["keep_sleep"]), "sleep=keep leaves the engine's frame sleep alone")
	assert_false(bool(BenchRunner.parse_options(PackedStringArray())["keep_sleep"]))
	assert_false(bool(BenchRunner.parse_options(PackedStringArray(["sleep=forever"]))["ok"]))
	var defaults: Dictionary = BenchRunner.parse_options(PackedStringArray())
	assert_eq(float(defaults["seconds"]), BenchRunner.DEFAULT_SECONDS)
	assert_eq(float(defaults["warmup"]), BenchRunner.DEFAULT_WARMUP_S)
	assert_eq(float(defaults["rebase_m"]), BenchRunner.REBASE_THRESHOLD_M)
	assert_false(bool(BenchRunner.parse_options(PackedStringArray(["seed=x"]))["ok"]))
	assert_false(bool(BenchRunner.parse_options(PackedStringArray(["0"]))["ok"]), "no zero-length window")


func test_the_capital_share_is_an_option_from_0_to_1() -> void:
	assert_eq(float(BenchRunner.parse_options(PackedStringArray())["capitals"]), -1.0, "the mix's share by default")
	var o: Dictionary = BenchRunner.parse_options(PackedStringArray(["capitals=0.2"]))
	assert_true(o["ok"], String(o.get("error", "")))
	assert_eq(float(o["capitals"]), 0.2)
	assert_false(bool(BenchRunner.parse_options(PackedStringArray(["capitals=1.5"]))["ok"]))
	assert_false(bool(BenchRunner.parse_options(PackedStringArray(["capitals=x"]))["ok"]))


func test_the_frame_boost_is_an_option_in_m_per_s() -> void:
	assert_eq(float(BenchRunner.parse_options(PackedStringArray())["boost"]), 0.0, "riding the anchor by default")
	var o: Dictionary = BenchRunner.parse_options(PackedStringArray(["boost=50"]))
	assert_true(o["ok"], String(o.get("error", "")))
	assert_eq(float(o["boost"]), 50.0)
	assert_false(bool(BenchRunner.parse_options(PackedStringArray(["boost=-1"]))["ok"]))
	assert_false(bool(BenchRunner.parse_options(PackedStringArray(["boost=x"]))["ok"]))


# --- battle and typical (M4-T07) ---------------------------------------------------------------------------------


const ENTITY_KEYS: Array[String] = ["fighters_near", "fighters_far", "capitals", "turrets", "interceptors", "beams", "missiles",
		"mines", "bolts", "asteroids", "launches", "sides"]


func test_a_short_battle_writes_every_entity_count_and_puts_the_factions_back() -> void:
	var game_table: FactionTable = Factions.table()
	var anchor_before: String = main.world.anchor_text()
	assert_true(_exec("bench battle 50 3 warmup=0.5 seed=1 label=battle_test").ok)
	await _ticks(2)
	var sides: Array[StringName] = BenchLayout.sides(BenchLayout.BATTLE)
	for a: StringName in sides:
		for b: StringName in sides:
			if a != b:
				assert_true(Factions.is_hostile(a, b), "during the run %s and %s fight" % [a, b])
	var mix: Dictionary = BenchLayout.mix(BenchLayout.BATTLE, 50)
	assert_eq(main.bench.standins.capitals().size(), int(mix["capitals"]), "the capitals are in play")
	assert_eq(main.bench.standins.asteroid_count(), int(mix["asteroids"]), "and the rocks")
	assert_eq(main.world.anchor_text(), "orbit %s" % BenchLayout.GRAVITY_BODY, "the battle is flown in a low orbit of a body of the data")
	assert_true(main.world.gravity_active(), "so it pulls")
	assert_gt(main.world.environment_accel(Vector3(0.0, 0.0, -5000.0)).length(), 1e-3, "5 km out: the tide of a real body")
	var by_faction: Dictionary = {}
	for c: Combatant in main.ships.alive():
		by_faction[c.faction] = int(by_faction.get(c.faction, 0)) + 1
		assert_eq(c.targetable.faction, c.faction)
		assert_eq(c.damageable.faction, c.faction)
		assert_eq(c.cannon.faction, c.faction)
	assert_eq(by_faction.size(), 4, "fighters of four sides: %s" % by_faction)
	await wait_for_signal(main.bench.finished, 90.0, "the bench finishes")
	var s: Dictionary = _summary_of("battle_test")
	assert_eq(String(s.get("layout", "")), "battle")
	var entities: Dictionary = s.get("entities", {})
	for key: String in ENTITY_KEYS:
		assert_true(entities.has(key), "the summary counts %s" % key)
	assert_eq(int(entities.get("capitals", 0)), int(mix["capitals"]))
	assert_eq(int(entities.get("turrets", 0)), int(mix["turrets"]))
	assert_eq(int(entities.get("interceptors", 0)), int(mix["interceptors"]))
	assert_eq(int(entities.get("asteroids", 0)), int(mix["asteroids"]))
	assert_eq(int(entities.get("beams", 0)), int(mix["beams"]), "every capital's beam emitters (M4-T12)")
	assert_between(int(entities.get("mines", 0)), roundi(0.9 * int(mix["mines"])), int(mix["mines"]), "the belts hold the mix")
	assert_between(int(entities.get("missiles", 0)), 1, int(mix["missiles"]), "missiles in flight, up to the mix")
	assert_eq(int(entities.get("sides", 0)), 4)
	assert_eq(int(entities.get("fighters_near", 0)) + int(entities.get("fighters_far", 0)), int(mix["fighters"]),
			"every fighter is near or far")
	assert_true((s.get("mix", {}) as Dictionary).has("turrets"), "the mix the run asked for")
	assert_true((s.get("stages", {}) as Dictionary).has("standins"), "the stand-ins' own stage")
	assert_true(FileAccess.get_file_as_string(ROOT.path_join("battle_test/summary.md")).contains("turrets"), "the page lists them")
	assert_eq(Factions.table(), game_table, "the game's faction table is back")
	assert_false(Factions.is_known(sides[2]), "the bench factions are gone")
	for c: Combatant in main.ships.alive():
		assert_true(c.faction == Factions.EARTH_ALLIANCE or c.faction == Factions.RAIDERS, "%s flies for a game faction again" % c.display_name)
	assert_eq(main.bench.standins.capitals().size(), 0, "the stand-ins are gone")
	assert_eq(main.bench.standins.asteroid_count(), 0)
	assert_eq(main.world.anchor_text(), anchor_before, "the frame's anchor is back (%s)" % anchor_before)
	assert_eq(main.world.environment_accel(Vector3(0.0, 0.0, -5000.0)), Vector3.ZERO, "and nothing pulls on the station's rail")


func test_a_short_typical_run_writes_its_summary() -> void:
	await _run("bench typical 58 3 warmup=0.5 seed=1 label=typical_test")
	var s: Dictionary = _summary_of("typical_test")
	assert_eq(String(s.get("layout", "")), "typical")
	var entities: Dictionary = s.get("entities", {})
	for key: String in ENTITY_KEYS:
		assert_true(entities.has(key), "the summary counts %s" % key)
	assert_eq(int(entities.get("capitals", 0)), 8)
	assert_eq(int(entities.get("turrets", 0)), 78)
	assert_eq(int(entities.get("sides", 0)), 2)
	assert_gt(int(entities.get("launches", 0)), 0, "the carriers launched")
	assert_eq(int(s.get("ships_max", 0)), 51, "the fighters and the player; capitals are counted apart")


# --- arrivals through jump points (M6-T20) ------------------------------------------------------------------------


func test_a_battle_comes_in_through_jump_points_in_waves() -> void:
	main.bench.wave_points = 12  # a small battle in several waves
	var mix: Dictionary = BenchLayout.mix(BenchLayout.BATTLE, 50)
	assert_true(_exec("bench battle 50 1 warmup=0 seed=1 label=arrivals_test").ok)
	await _ticks(2)
	var arrivals: BattleArrivals = main.bench.arrivals
	assert_not_null(arrivals, "a battle arrives through jump points")
	assert_gt(arrivals.waves, 1, "%d points in waves of 12" % arrivals.points.size())
	var plan: Array[Dictionary] = BenchLayout.plan(BenchLayout.BATTLE, 50, 1)
	var first_fighters: int = 0
	var first_capitals: int = 0
	var first_points: int = 0
	for i: int in arrivals.first_wave_entries():
		if StringName(plan[i]["kind"]) == BenchLayout.KIND_CAPITAL:
			first_capitals += 1
		else:
			first_fighters += 1
	for point: Dictionary in arrivals.points:
		first_points += 1 if int(point["wave"]) == 0 else 0
	assert_eq(main.ships.alive().size(), first_fighters, "only the first wave's fighters are in, none placed ahead of its point")
	assert_eq(main.bench.standins.capitals().size(), first_capitals, "and its capitals")
	assert_lt(first_fighters + first_capitals, plan.size(), "the rest are still to come")
	assert_eq(main.bench.jumps.open_count(), first_points, "a point open for each group of the first wave")
	var transits: VortexTransits = VortexTransits.of(main.world)
	assert_eq(transits.count() + transits.arrivals_unseen, first_fighters + first_capitals,
			"each flies out of its point's funnel, or is too small on screen to and comes out in place (M6-T22)")
	assert_gt(transits.count(), 0, "the near ones fly the funnel")
	for c: Combatant in main.ships.alive():
		assert_true(_inside_a_point(c.ship.global_position), "%s came out of an open point" % c.display_name)
		if transits.is_passing(c.ship):
			assert_lt(transits.scale_of(c.ship), 1.0, "%s comes out of the ring shrunk" % c.display_name)
	await wait_for_signal(main.bench.finished, 120.0, "the bench finishes")
	var s: Dictionary = _summary_of("arrivals_test")
	var came: Dictionary = s.get("arrivals", {})
	assert_eq(String(came.get("mode", "")), "jump")
	assert_eq(int(came.get("points", 0)), arrivals.points.size())
	assert_eq(int(came.get("opened", 0)), arrivals.points.size(), "every point opened before the window")
	assert_lte(int(came.get("max_open", 99)), 12)
	assert_gte(float(came.get("warmup_s", 0.0)), arrivals.last_at_s() + BenchRunner.ARRIVAL_SETTLE_S,
			"the warm-up stretched until the last wave was in")
	var entities: Dictionary = s.get("entities", {})
	assert_eq(int(entities.get("fighters_near", 0)) + int(entities.get("fighters_far", 0)), int(mix["fighters"]),
			"every fighter in by the measured window")
	assert_eq(int(entities.get("capitals", 0)), int(mix["capitals"]), "every capital too")


func test_a_placed_battle_has_every_ship_from_the_start() -> void:
	assert_true(_exec("bench battle 50 1 warmup=0 seed=1 arrive=placed label=placed_test").ok)
	await _ticks(2)
	var mix: Dictionary = BenchLayout.mix(BenchLayout.BATTLE, 50)
	assert_null(main.bench.arrivals)
	assert_eq(main.ships.alive().size(), int(mix["fighters"]), "every fighter in place at once")
	assert_eq(main.bench.standins.capitals().size(), int(mix["capitals"]))
	assert_true(main.bench.jumps == null or main.bench.jumps.open_count() == 0, "no jump point")
	await wait_for_signal(main.bench.finished, 60.0, "the bench finishes")
	assert_eq(String((_summary_of("placed_test").get("arrivals", {}) as Dictionary).get("mode", "")), "placed")
	assert_false(BenchRunner.parse_options(PackedStringArray(["arrive=teleport"]))["ok"], "jump or placed only")


# Whether `at` (World) lies inside the mouth of one of the bench's open points, near its plane.
func _inside_a_point(at: Vector3) -> bool:
	for point: JumpVortex in main.bench.jumps.points():
		if not point.is_active():
			continue
		var axis: Vector3 = -point.global_basis.z.normalized()
		var off: Vector3 = at - point.global_position
		var along: float = off.dot(axis)
		# A group's wingmen come out up to the group's reach in front of the mouth, or a little way down the funnel.
		if (off - axis * along).length() < point.fit.mouth_radius_m and along > -point.fit.depth_m - 1.0 \
				and along < BattleArrivals.SHARE_M + point.fit.mouth_radius_m:
			return true
	return false
