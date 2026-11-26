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
		assert_false(c.damageable.invulnerable, "%s is mortal once the run is over (M7-T59)" % c.display_name)
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
	assert_eq(main.world.anchor_text(), anchor_before, "the frame's anchor is back (%s)" % anchor_before)
	assert_eq(main.world.environment_accel(Vector3(0.0, 0.0, -5000.0)), Vector3.ZERO, "and nothing pulls on the station's rail")
	# M7-T50: the battle flies on after its window, so nothing the player was looking at vanishes when the run ends.
	var standins: StandinDirector = main.bench.standins
	assert_eq(standins.capitals().size(), int(mix["capitals"]), "the capitals stay in play")
	for cap: CapitalStandin in standins.capitals():
		assert_true(cap.is_inside_tree(), "%s is still in the world" % cap.name)
		assert_true(Factions.is_known(cap.faction), "%s flies for a game faction (%s)" % [cap.name, cap.faction])
		assert_eq(cap.targetable.faction, cap.faction)
		assert_eq(cap.damageable.faction, cap.faction)
		assert_false(cap.damageable.invulnerable, "%s is mortal once the run is over (M7-T59)" % cap.name)
	assert_eq(standins.asteroid_count(), int(mix["asteroids"]), "the rocks stay")
	var drawn: int = 0
	for rocks: Node in standins.get_node("Asteroids").get_children():
		if rocks is MultiMeshInstance3D and (rocks as MultiMeshInstance3D).is_visible_in_tree():
			drawn += (rocks as MultiMeshInstance3D).multimesh.instance_count
	assert_eq(drawn, int(mix["asteroids"]), "and are drawn")
	var mines: MineField = standins.mines()
	assert_not_null(mines, "the mines stay")
	if mines != null:
		for i: int in mines.count():
			assert_true(Factions.is_known(mines.faction_of(i)), "mine %d is a game faction's (%s)" % [i, mines.faction_of(i)])
	for k: int in StaticRows.count():
		assert_true(Factions.is_known(StaticRows.factions[k]), "static row %d is a game faction's" % k)
	assert_true(standins.active, "their guns go on")
	assert_false(standins.launcher.is_valid(), "but the carriers no longer swap the run's fighters")
	await _ticks(30)
	assert_eq(standins.weapons_path(), &"native", "the weapons step on the native rows over the game's sides")
	# M7-T59: the fighters are mortal too, near or far, so far deaths can be watched.
	var fighters: Array[Combatant] = main.ships.alive()
	assert_gt(fighters.size(), 1, "fighters are still flying")
	for c: Combatant in fighters:
		assert_false(c.damageable.invulnerable, "%s is mortal once the run is over" % c.display_name)
	assert_false(mines.relays if mines != null else true, "a mine that goes off now stays gone")
	await _assert_mines_go_off_after_the_run(mines)
	await _assert_killed_fighters_leave_play(fighters)
	await _assert_killed_capitals_leave_play(standins)
	# The next run starts clean: nothing of this one flies in it.
	await _run("bench furball 10 1 warmup=0 seed=1 label=after_battle_test")
	assert_eq(standins.capitals().size(), 0, "the next run takes the capitals away")
	assert_eq(standins.asteroid_count(), 0, "and the rocks")
	assert_null(standins.mines(), "and the mines")
	for c: Combatant in main.ships.alive():
		assert_false(c.damageable.hull.destroyed, "the new run starts %s whole" % c.display_name)


# M7-T64: after the run a mine of the player's own side and an enemy's each go off when the player's side shoots it and when the
# player flies into it; a mine of its own side 30 m off, inside the trigger but not touched, stays. M7-T65: each takes its whole
# group with it as a chain, and nothing beyond. Read on the console.
func _assert_mines_go_off_after_the_run(mines: MineField) -> void:
	if mines == null:
		return
	DebugConsole.flags.invulnerable = true  # the blasts would kill the player
	var side: StringName = main.combatant.faction
	var home: Vector3 = main.ship.global_position - mines.global_position  # the mines' node rides the rebases
	var own: Array[PackedInt32Array] = _lone_groups(mines, side, false, 3)
	var foe: Array[PackedInt32Array] = _lone_groups(mines, side, true, 2)
	assert_eq([own.size(), foe.size()], [3, 2], "whole groups of each side clear of the others are left after the run")
	if own.size() < 3 or foe.size() < 2:
		return
	var before: Dictionary = {}
	for key: String in ["mines.by_shot", "mines.by_touch", "mines.by_blast", "combat.mines_struck"]:
		before[key] = int(_read(key))
	var alive_before: int = mines.alive_count()
	for group: PackedInt32Array in [own[0], foe[0]]:
		# The group's mine furthest along +Z, so the bolt flying in along -Z meets it first.
		var i: int = group[0]
		for k: int in group:
			i = k if mines.position_of(k).z > mines.position_of(i).z else i
		var bolt := (load(Projectile.SCENE_PATH) as PackedScene).instantiate() as Projectile
		main.projectiles.add_child(bolt)
		bolt.configure(WeaponSpec.new())
		bolt.faction = side
		bolt.launch(mines.position_of(i) + Vector3(1.0, 0.0, 60.0), Vector3(0.0, 0.0, -600.0), SimClock.now())
		await _ticks(12)
		assert_eq(_alive_in(mines, group), 0, "a %s mine goes off when the player's side shoots it, its group with it" % mines.faction_of(i))
	for group: PackedInt32Array in [own[1], foe[1]]:
		await _hold_player_at(mines.position_of(group[0]) + Vector3(0.0, 2.0, 0.0), 4)
		assert_eq(_alive_in(mines, group), 0, "a %s mine goes off when the player flies into it, its group with it" % mines.faction_of(group[0]))
	# 30 m out from the group, beside its outermost mine.
	var centre := Vector3.ZERO
	for k: int in own[2]:
		centre += mines.position_of(k) / float(own[2].size())
	var outer: int = own[2][0]
	for k: int in own[2]:
		outer = k if mines.position_of(k).distance_to(centre) > mines.position_of(outer).distance_to(centre) else outer
	var out: Vector3 = (mines.position_of(outer) - centre).normalized()
	await _hold_player_at(mines.position_of(outer) + (out if out != Vector3.ZERO else Vector3.UP) * 30.0, 2 * MineKinds.CHECK_TICKS)
	assert_eq(_alive_in(mines, own[2]), own[2].size(), "the player's own mines 30 m off, untouched, stay")
	# The battle flies on around the mines, so the counts are at least these (its fighters may set off others meanwhile).
	var gone: int = own[0].size() + own[1].size() + foe[0].size() + foe[1].size()
	assert_gte(alive_before - mines.alive_count(), gone, "the four groups went off")
	assert_gte(int(_read("mines.by_shot")) - int(before["mines.by_shot"]), 2, "two by a shot")
	assert_gte(int(_read("combat.mines_struck")) - int(before["combat.mines_struck"]), 2, "the bolts stopped on them")
	assert_gte(int(_read("mines.by_touch")) - int(before["mines.by_touch"]), 2, "two by a touch")
	assert_gte(int(_read("mines.by_blast")) - int(before["mines.by_blast"]), gone - 4, "the rest of each group by the chain")
	await _hold_player_beside(mines, home, 30)  # back where the fighters and capitals fly near
	DebugConsole.flags.invulnerable = false
	main.combatant.damageable.restore()


# Up to `n` whole groups of mines in play of `side` (or hostile to it), nearest the player first: mines linked by blasts, none
# of another group or a ship within two blasts of them.
func _lone_groups(mines: MineField, side: StringName, hostile: bool, n: int) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	var seen: Dictionary = {}
	var link_m: float = MineKinds.blast(MineKinds.PROX).radius_m + MineField.BODY_RADIUS_M
	var clear_m: float = 2.0 * MineKinds.blast(MineKinds.PROX).radius_m
	var order: Array[int] = []
	for i: int in mines.count():
		order.append(i)
	var player: Vector3 = main.ship.global_position
	order.sort_custom(func(a: int, b: int) -> bool:
		return mines.position_of(a).distance_squared_to(player) < mines.position_of(b).distance_squared_to(player))
	for i: int in order:
		if out.size() == n:
			break
		if seen.has(i) or not mines.is_alive(i) or Factions.is_hostile(mines.faction_of(i), side) != hostile:
			continue
		var group := PackedInt32Array([i])
		seen[i] = true
		var k: int = 0
		while k < group.size():
			for j: int in mines.count():
				if not seen.has(j) and mines.is_alive(j) and mines.position_of(j).distance_to(mines.position_of(group[k])) <= link_m:
					seen[j] = true
					group.append(j)
			k += 1
		var lone: bool = group.size() >= BenchLayout.MINE_GROUP_MIN
		for m: int in group:
			for j: int in mines.count():
				if lone and not group.has(j) and mines.is_alive(j) and mines.position_of(j).distance_to(mines.position_of(m)) < clear_m:
					lone = false
			for c: Combatant in main.ships.alive():
				if lone and TierDirector.flying_position(c.ship).distance_to(mines.position_of(m)) < clear_m:
					lone = false
		if lone:
			out.append(group)
	return out


func _alive_in(mines: MineField, group: PackedInt32Array) -> int:
	var alive: int = 0
	for i: int in group:
		alive += 1 if mines.is_alive(i) else 0
	return alive


# M7-T65: in a short battle of 300 the mines lie where the fighters fight, so AI fighters set some off (a hull's trigger or touch
# with a fighter beside the mine) and a set-off group goes off as a chain. A slow test.
func test_ai_fighters_set_off_mines_in_a_battle_of_300() -> void:
	if not SlowTests.enabled():
		pending("slow: a battle of 300 (GUT_SLOW=1)")
		return
	assert_true(_exec("bench battle 300 5 warmup=0 seed=1 label=battle_mines_test").ok)
	await _ticks(2)
	var mines: MineField = main.bench.standins.mines()
	assert_not_null(mines, "the mines are laid")
	if mines == null:
		return
	var by_fighters: Array[int] = [0]
	var hulls_before: Array[int] = [mines.by_trigger + mines.by_touch]
	var chained: Array[int] = [0]
	mines.detonated.connect(func(i: int, _kind: int, _at: Vector3) -> void:
		var hulls: int = mines.by_trigger + mines.by_touch
		if hulls == hulls_before[0]:
			chained[0] += 1
			return
		hulls_before[0] = hulls
		var reach: float = MineKinds.number(MineKinds.PROX, "trigger_m") + 30.0  # a fighter's hull and a tick's flight
		for c: Combatant in main.ships.alive():
			if c != main.combatant and TierDirector.flying_position(c.ship).distance_to(mines.position_of(i)) < reach:
				by_fighters[0] += 1
				return)
	await wait_for_signal(main.bench.finished, 240.0, "the bench finishes")
	gut.p("battle 300: %d mines set off by a hull beside an AI fighter, %d by a blast" % [by_fighters[0], chained[0]])
	assert_gt(by_fighters[0], 0, "AI fighters set mines off")
	assert_gt(chained[0], 0, "and their groups went off after them")


# The player held still `offset` from `node` for `ticks` physics ticks: the place is read again each tick, since a rebase moves the
# node (M10-T15: the lone groups the checks fly to are far now, so the way back crosses one).
func _hold_player_beside(node: Node3D, offset: Vector3, ticks: int) -> void:
	for t: int in ticks:
		main.ship.global_position = node.global_position + offset
		main.ship.linear_velocity = main.world.rest_velocity()
		main.ship.angular_velocity = Vector3.ZERO
		await _ticks(1)


# The player held still at `at` for `ticks` physics ticks.
func _hold_player_at(at: Vector3, ticks: int) -> void:
	for t: int in ticks:
		main.ship.global_position = at
		main.ship.linear_velocity = main.world.rest_velocity()  # at rest in the frame: a blast's push may have boosted it (M10-T15)
		main.ship.angular_velocity = Vector3.ZERO
		await _ticks(1)


# M7-T59 fix: after the run a fighter killed by a hit (near) or by the console (in the tier) explodes, leaves play and its row,
# and nothing takes its place.
func _assert_killed_fighters_leave_play(fighters: Array[Combatant]) -> void:
	var tier: TierDirector = TierDirector.current()
	var far: Combatant = null
	var near: Combatant = null
	for c: Combatant in fighters:
		if c.ship.is_tier_parked():
			far = c if far == null else far
		elif near == null:
			near = c
	assert_not_null(far, "a fighter flies in the tier")
	assert_not_null(near, "and one near")
	if far == null or near == null:
		return
	var destroyed: Array[Combatant] = []
	main.director.ship_destroyed.connect(func(c: Combatant, _info: HitInfo) -> void: destroyed.append(c))
	var alive_before: int = main.ships.alive().size()
	var tier_before: int = tier.tier_fighters()
	near.damageable.apply_hit(HitInfo.new(near.ship.get_instance_id(), 0, Factions.RAIDERS, near.damageable.hull.max_hp * 10.0,
			near.ship.global_position, Vector3.ZERO, 0.0, HitInfo.CAUSE_BOLT))
	assert_true(_exec('set targeting.selected "%s"' % far.display_name).ok, "the far fighter can be selected")
	var killed: ConsoleResult = _exec("kill")
	assert_true(killed.ok, "kill: %s" % killed.text())
	await _ticks(2)
	for c: Combatant in [near, far]:
		assert_true(destroyed.has(c), "%s blew up" % c.display_name)
		assert_false(main.ships.alive().has(c), "%s left play" % c.display_name)
		assert_false(c.targetable.is_active(), "%s cannot be targeted" % c.display_name)
		assert_false(c.ship.is_tier_parked(), "%s has no tier row" % c.display_name)
	assert_lte(main.ships.alive().size(), alive_before - 2, "the fighter count dropped by the two")
	assert_lte(tier.tier_fighters(), tier_before - 1, "the tier lost the far one's row")
	var alive_after: int = main.ships.alive().size()
	await _ticks(180)
	assert_false(main.ships.alive().has(near) or main.ships.alive().has(far), "they stay dead")
	assert_lte(main.ships.alive().size(), alive_after, "and no fighter came to replace them")


# M7-T59 fix: the same for capitals, one shot down and one killed on the console.
func _assert_killed_capitals_leave_play(standins: StandinDirector) -> void:
	var living: Array[CapitalStandin] = []
	for cap: CapitalStandin in standins.capitals():
		if is_instance_valid(cap) and not cap.damageable.hull.destroyed:
			living.append(cap)
	assert_gt(living.size(), 1, "capitals are still flying")
	if living.size() < 2:
		return
	var in_play: int = standins.capitals_in_play()
	var shot: CapitalStandin = living[0]
	var named: CapitalStandin = living[1]
	shot.damageable.apply_hit(HitInfo.new(shot.get_instance_id(), 0, Factions.RAIDERS, shot.damageable.hull.max_hp * 10.0,
			shot.global_position, Vector3.ZERO, 0.0, HitInfo.CAUSE_BOLT))
	assert_true(_exec('set targeting.selected "%s"' % named.targetable.display_name).ok, "the capital can be selected")
	assert_true(_exec("kill").ok)
	await _ticks(2)
	for cap: CapitalStandin in [shot, named]:
		assert_true(cap.damageable.hull.destroyed, "%s is destroyed" % cap.name)
		assert_false(cap.targetable.is_active(), "%s cannot be targeted" % cap.name)
		assert_false(cap.is_tier_parked(), "%s has no tier row" % cap.name)
	assert_lte(standins.capitals_in_play(), in_play - 2, "the capital count dropped by the two")
	var after: int = standins.capitals_in_play()
	await _ticks(120)
	assert_lte(standins.capitals_in_play(), after, "and none came back")


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
	# M6-T23: only the capitals open points; each fighter group comes through its side's capital point or the battle's gate.
	main.bench.wave_points = 12  # a small battle in several waves
	var mix: Dictionary = BenchLayout.mix(BenchLayout.BATTLE, 50)
	assert_true(_exec("bench battle 50 1 warmup=0 seed=1 label=arrivals_test").ok)
	await _ticks(2)
	var arrivals: BattleArrivals = main.bench.arrivals
	assert_not_null(arrivals, "a battle arrives through jump points")
	assert_gt(arrivals.waves, 1, "%d units in waves of 12" % arrivals.points.size())
	assert_gt(arrivals.count_via(BattleArrivals.VIA_CAPITAL), 0, "groups through capital points")
	assert_gt(arrivals.count_via(BattleArrivals.VIA_GATE), 0, "and groups through the gate")
	var plan: Array[Dictionary] = BenchLayout.plan(BenchLayout.BATTLE, 50, 1)
	var first_riders: int = 0
	var first_gate: int = 0
	var first_capitals: int = 0
	for point: Dictionary in arrivals.points:
		if int(point["wave"]) != 0:
			continue
		var count: int = (point["members"] as PackedInt32Array).size()
		match StringName(point["via"]):
			BattleArrivals.VIA_OWN:
				first_capitals += count
			BattleArrivals.VIA_CAPITAL:
				first_riders += count
			BattleArrivals.VIA_GATE:
				first_gate += count
	assert_gt(first_gate, 0, "the first wave has gate groups (seed 1)")
	assert_eq(main.bench.standins.capitals().size(), first_capitals, "the first wave's capitals are in")
	assert_eq(main.ships.alive().size(), first_riders, "with the fighters riding their points; the gate's wait for its vortex")
	assert_lt(first_riders + first_gate + first_capitals, plan.size(), "the rest are still to come")
	assert_eq(main.bench.jumps.open_count(), first_capitals, "one point per capital, none for a fighter group")
	for point: JumpVortex in main.bench.jumps.points():
		if point.is_active():
			assert_true(point.held and point.opener is CapitalStandin, "every point is held by the capital that opened it")
	var gate: Jumpgate = main.bench.gate
	assert_not_null(gate, "the battle has its own jumpgate")
	assert_gt(gate.global_position.distance_to(main.ship.global_position),
			TierDirector.radius_m() * (1.0 + TierDirector.HYSTERESIS) + 2000.0,
			"beyond the tier's reach from the player, so its ships come in as far ones (after T23)")
	assert_eq(gate.arrivals_per_tick, BenchRunner.GATE_ARRIVALS_PER_TICK, "a few through it a tick")
	assert_eq(gate.pending_arrivals(), first_gate, "the gate's groups wait for its blue vortex")
	assert_eq(gate.vortex.direction_name(), &"arrival")
	var transits: VortexTransits = VortexTransits.of(main.world)
	assert_eq(transits.count() + transits.arrivals_unseen, first_riders + first_capitals,
			"each flies out of its point's funnel, or is too small on screen to and comes out in place (M6-T22)")
	assert_gt(transits.count(), 0, "the near ones fly the funnel")
	for c: Combatant in main.ships.alive():
		assert_true(_inside_a_point(c.ship.global_position), "%s came out of a capital's open point" % c.display_name)
		if transits.is_passing(c.ship):
			assert_lt(transits.scale_of(c.ship), 1.0, "%s comes out of the ring shrunk" % c.display_name)
	var pool: JumpPointPool = main.bench.jumps
	await wait_for_signal(main.bench.finished, 120.0, "the bench finishes")
	assert_null(main.bench.gate, "the battle's gate goes with the run")
	var s: Dictionary = _summary_of("arrivals_test")
	var came: Dictionary = s.get("arrivals", {})
	# M7-T59 (m6-096): over the whole run only the capitals opened points, and every fighter came by a capital's point or the gate.
	assert_eq(int(came.get("capital_points", -1)), int(mix["capitals"]), "one point per capital")
	assert_eq(pool.opened, int(mix["capitals"]), "the pool opened no point for a fighter")
	assert_eq(pool.refused, 0, "and refused none")
	assert_eq(int(came.get("fighters_via_capital", 0)) + int(came.get("fighters_via_gate", 0)), int(mix["fighters"]),
			"every fighter rode a capital's point or came through the gate")
	assert_eq(String(came.get("mode", "")), "jump")
	assert_eq(int(came.get("points", 0)), arrivals.points.size())
	assert_eq(int(came.get("opened", 0)), arrivals.points.size(), "every unit came in before the window")
	assert_lte(int(came.get("max_open", 99)), 12)
	assert_eq(int(came.get("gate_arrived", 0)), arrivals.ships_via(BattleArrivals.VIA_GATE), "every gate fighter came through it")
	assert_eq(int(came.get("collapses", -1)), 0, "no point collapsed: every capital stayed by its point")
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
		# A rider comes out round the axis just in front of the mouth, or is still a little way down the funnel.
		if (off - axis * along).length() < point.fit.mouth_radius_m and along > -point.fit.depth_m - 1.0 \
				and along < point.fit.mouth_radius_m:
			return true
	return false


# M7-T59 (m6-094, m6-095): the console recipes the checklist gives.
func test_a_carriers_point_collapses_when_its_opener_is_destroyed() -> void:
	main.ships.prepare(ShipPool.DEFAULT_TYPE, 4)
	await _ticks(30)
	var result: ConsoleResult = _exec("transit carrier point fighter follow")
	assert_true(result.ok, "the recipe's carrier: %s" % result.text())
	await _ticks(10)
	assert_eq(int(_read("vortex.open")), 1, "its point is open")
	assert_true(_exec("vortex collapse").ok)
	await _ticks(2)
	assert_eq(int(_read("vortex.collapses")), 1)
	assert_eq(String(_read("vortex.last_collapse")), "opener_destroyed")


# M7-T75 (m6-094): free flight with encounters off builds no raiders, so the tool grows the pool and registers them for death.
func test_transit_carrier_grows_the_raider_pool_in_free_flight() -> void:
	assert_true(_exec("encounters off").ok)
	assert_eq(main.ships.pool_size(ShipPool.DEFAULT_TYPE), 0, "no raiders built")
	await _ticks(120)
	var result: ConsoleResult = _exec("transit carrier point fighter follow")
	assert_true(result.ok, "the recipe's carrier: %s" % result.text())
	assert_gte(main.ships.pool_size(ShipPool.DEFAULT_TYPE), 2, "the pool grew")
	# The raiders' carrier is the strike carrier (M12-T19, merged by M8-T07): it holds its arrival point for about a second,
	# then stands off instead of jumping straight back, so its point is collapsed while held and nobody is in its funnel.
	await _ticks(30)
	var alive: Array[Combatant] = main.ships.alive()
	assert_gt(alive.size(), 1, "the raiders it brought are alive")
	var before: int = alive.size()
	var victim: Combatant = alive[alive.size() - 1]
	assert_true(victim.damageable.kill(), "a pooled raider the tool built can be killed")
	await _ticks(10)
	assert_lt(main.ships.alive().size(), before, "killing one removes it")
	# The collapse destroys the carrier, whose reactor's blast (M10-T09) takes the fighters standing by it: checked after them.
	assert_true(_exec("vortex collapse").ok)
	await _ticks(30)
	assert_eq(int(_read("vortex.collapses")), 1)
	assert_eq(int(_read("vortex.collapse_kills")), 0, "its fighters are already out of the funnel")
	assert_eq(String(_read("vortex.last_collapse")), "opener_destroyed")


func test_a_capital_caught_in_its_own_funnel_dies_by_the_collapse() -> void:
	await _ticks(30)
	var result: ConsoleResult = _exec("transit arrive point capital")
	assert_true(result.ok, "the recipe's capital: %s" % result.text())
	await _ticks(5)
	assert_true(_exec("vortex collapse").ok)
	await _ticks(2)
	assert_eq(int(_read("vortex.collapse_kills")), 1, "the ship in the funnel counts as a collapse kill")
	assert_eq(String(_read("vortex.last_collapse")), "opener_destroyed")
