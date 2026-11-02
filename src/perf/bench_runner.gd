class_name BenchRunner
extends Node
## Runs one many-ships benchmark on the live main scene (M4-T01, architecture §17.1): `bench <layout> <n> [seconds]
## [warmup=<s>] [seed=<k>] [label=<name>] [probe=paired] [rebase_m=<m>] [sleep=keep]`. Sets the scene up from the pools, warms
## up, records ticks with the `PerfProbe`, writes the report and puts back what it changed; the ships stay in play.

## The report is written; the run's summary.
signal finished(summary: Dictionary)

const DEFAULT_SECONDS: float = 30.0
const DEFAULT_WARMUP_S: float = 5.0
const REBASE_THRESHOLD_M: float = 180.0
## The player's cruise along its nose (RebaseFight's default), m/s.
const CRUISE_MPS: float = 60.0
## Ticks per block of a paired probe run.
const BLOCK_TICKS: int = 30
## A run whose wall time passes this many times its sim time is cut short.
const MAX_SLOWDOWN: float = 10.0
## The console waits this many frames at most; the run releases the wait when it ends.
const HOLD_FRAMES: int = 1_000_000
const DEFAULT_ROOT: String = "res://reports/perf"
const OPTION_KEYS: Array[String] = ["warmup", "seed", "label", "probe", "rebase_m", "sleep"]

var main: Main = null
var probe: PerfProbe = null
## Where reports go; a label is a path below it.
var report_root: String = DEFAULT_ROOT
var running: bool = false

var _layout: StringName = &""
var _n: int = 0
var _options: Dictionary = {}
var _tick: int = 0
var _warmup_ticks: int = 0
var _measure_ticks: int = 0
var _started_us: int = 0
var _wall_start_us: int = 0
var _load_ms: float = 0.0
var _engine_worst := PackedFloat64Array()
var _placed: Dictionary = {}
var _restore: Dictionary = {}


func _init() -> void:
	process_physics_priority = -2_000_000  # first in the tick, so a window starts and ends on tick boundaries


func _ready() -> void:
	DebugConsole.registry.register_command(ConsoleCommand.new(&"bench",
			"Fly a benchmark layout (%s) with n ships from the pools, measure [seconds] (30) after warmup=<s> (5), and write reports/perf/<label>/ (seed=<k> label=<name> probe=paired rebase_m=<m>)"
			% ", ".join(PackedStringArray(BenchLayout.NAMES)),
			[ConsoleArg.enum_required(&"layout", BenchLayout.NAMES), ConsoleArg.int_required(&"n", 1, 2000),
			ConsoleArg.string_rest(&"options").make_optional("")]), _cmd_bench, self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)
	if running:
		running = false
		_put_back()


## Reads the words after `bench <layout> <n>`: an optional window in seconds first, then `key=value` options.
## `{"ok", "error", "seconds", "warmup", "seed", "label", "paired", "rebase_m", "keep_sleep"}`.
static func parse_options(words: PackedStringArray) -> Dictionary:
	var out: Dictionary = {"ok": true, "error": "", "seconds": DEFAULT_SECONDS, "warmup": DEFAULT_WARMUP_S, "seed": 1, "label": "",
			"paired": false, "rebase_m": REBASE_THRESHOLD_M, "keep_sleep": false}
	for i: int in words.size():
		var word: String = words[i]
		var pair: PackedStringArray = word.split("=", true, 1)
		if pair.size() == 1:
			if i == 0 and word.is_valid_float() and float(word) > 0.0:
				out["seconds"] = float(word)
				continue
			return _bad("expected the window in seconds (above 0) or key=value, got '%s'" % word)
		var key: String = pair[0]
		var text: String = pair[1]
		match key:
			"warmup":
				if not text.is_valid_float() or float(text) < 0.0:
					return _bad("warmup must be seconds, 0 or more")
				out["warmup"] = float(text)
			"seed":
				if not text.is_valid_int():
					return _bad("seed must be a whole number")
				out["seed"] = int(text)
			"label":
				if text.is_empty() or text.contains("..") or text.begins_with("/"):
					return _bad("label must be a relative path without '..'")
				out["label"] = text
			"probe":
				if text != "paired" and text != "on":
					return _bad("probe must be on or paired")
				out["paired"] = text == "paired"
			"rebase_m":
				if not text.is_valid_float() or float(text) <= 0.0:
					return _bad("rebase_m must be metres above 0")
				out["rebase_m"] = float(text)
			"sleep":
				# keep: the engine's own frame sleep stays (as the game idles), at the price of an untimed body sync.
				if text != "keep" and text != "0":
					return _bad("sleep must be keep or 0")
				out["keep_sleep"] = text == "keep"
			_:
				return _bad("unknown option '%s' (%s)" % [key, ", ".join(PackedStringArray(OPTION_KEYS))])
	return out


static func _bad(message: String) -> Dictionary:
	return {"ok": false, "error": message}


func _cmd_bench(args: Dictionary) -> ConsoleResult:
	var options: Dictionary = parse_options(String(args[&"options"]).split(" ", false))
	if not bool(options["ok"]):
		return ConsoleResult.failure("bench: %s" % options["error"])
	return start(StringName(args[&"layout"]), int(args[&"n"]), options)


## Sets the scene up for `layout` with `n` ships and starts the windows. The result holds the console queue until the end.
func start(layout: StringName, n: int, options: Dictionary) -> ConsoleResult:
	if running:
		return ConsoleResult.failure("bench: one is running already")
	if main == null or probe == null or main.ship == null:
		return ConsoleResult.failure("bench: needs the main scene")
	if not BenchLayout.is_layout(layout):
		return ConsoleResult.failure("bench: unknown layout '%s'" % layout)
	_layout = layout
	_n = n
	_options = options
	if String(_options["label"]).is_empty():
		_options["label"] = "%s_%d_%s" % [layout, n, Time.get_datetime_string_from_system(false, false).replace("-", "").replace(":", "").replace("T", "-")]
	var load_started: int = Time.get_ticks_usec()  # profiling only: the load time is recorded, never gameplay
	_set_up_scene()
	_load_ms = float(Time.get_ticks_usec() - load_started) * 1e-3
	var tps: float = float(Engine.physics_ticks_per_second)
	_warmup_ticks = roundi(float(_options["warmup"]) * tps)
	_measure_ticks = maxi(1, roundi(float(_options["seconds"]) * tps))
	_tick = 0
	_engine_worst = PackedFloat64Array()
	_started_us = Time.get_ticks_usec()
	running = true
	var result := ConsoleResult.line("bench %s %d: %d ships in play after %.1f s of load; warm-up %.1f s, measuring %.1f s -> %s" % [
			layout, n, main.ships.in_use_count(), _load_ms * 1e-3, float(_options["warmup"]), float(_options["seconds"]),
			report_root.path_join(String(_options["label"]))])
	result.wait_frames = HOLD_FRAMES
	return result


func _set_up_scene() -> void:
	_restore = {
		"threshold": main.world.auto_rebase_distance_m,
		"god": DebugConsole.flags.invulnerable,
		"probe": probe.enabled,
		"sleep": OS.low_processor_usage_mode_sleep_usec,
		"relation": Factions.relation(Factions.EARTH_ALLIANCE, Factions.RAIDERS),
	}
	main.waves.stop()
	DebugConsole.flags.invulnerable = true
	for c: Combatant in main.ships.alive():
		main.ships.release(c)
	var plan: Array[Dictionary] = BenchLayout.plan(_layout, _n, int(_options["seed"]))
	var wanted: Dictionary = {ShipPool.ALLY_TYPE: 0, ShipPool.DEFAULT_TYPE: 0}
	for e: Dictionary in plan:
		wanted[e["type"]] = int(wanted[e["type"]]) + 1
	for type: StringName in wanted:
		main.ensure_pool(type, int(wanted[type]))
	# The layout's frame: the player at its origin, nose along -Z, cruising so the world rebases as in play.
	var ship: Ship = main.ship
	main.debug_throttle = 0.0
	ship.reset_to(Transform3D(Basis.IDENTITY, ship.global_position))
	ship.linear_velocity = Vector3(0.0, 0.0, -CRUISE_MPS)
	main.world.auto_rebase_distance_m = float(_options["rebase_m"])
	if not BenchLayout.fights(_layout):
		Factions.table().set_relation(Factions.EARTH_ALLIANCE, Factions.RAIDERS, Factions.Relation.NEUTRAL)
	var anchor: UniversePos = main.world.to_universe(ship.global_position)
	var numbers: Dictionary = {ShipPool.ALLY_TYPE: ShipPool.ALLY_FIRST_NUMBER, ShipPool.DEFAULT_TYPE: 1}
	_placed = {ShipPool.ALLY_TYPE: 0, ShipPool.DEFAULT_TYPE: 0}
	for e: Dictionary in plan:
		var type: StringName = e["type"]
		var prefix: String = ShipPool.ALLY_NAME_PREFIX if type == ShipPool.ALLY_TYPE else ShipPool.NAME_PREFIX
		var ship_name: String = "%s %d" % [prefix, int(numbers[type])]
		numbers[type] = int(numbers[type]) + 1
		var made: Dictionary = BrainFactory.from_behaviour(e["behaviour"], anchor, int(e["seed"]))
		if not bool(made["ok"]):
			push_warning("bench: %s: %s" % [ship_name, made["error"]])
			continue
		var placed: Combatant = main.ships.acquire(ship_name, anchor.plus_local(e["offset"]), e["basis"], e["velocity"],
				made["brain"] as PilotBrain, type)
		if placed == null:
			continue
		placed.damageable.invulnerable = true
		_placed[type] = int(_placed[type]) + 1
		if not String(e["wing"]).is_empty():
			main.wings.join(String(e["wing"]), placed)
	if DisplayServer.get_name() == "headless" and not bool(_options["keep_sleep"]):
		OS.low_processor_usage_mode_sleep_usec = 0
		probe.time_sync = true
	probe.recording = false
	probe.clear_series()
	probe.stages_enabled = true
	probe.enabled = true


func _physics_process(_delta: float) -> void:
	if not running:
		return
	_tick += 1
	var now: int = Time.get_ticks_usec()
	var first: int = _warmup_ticks + 1
	var last: int = _warmup_ticks + _measure_ticks
	if _tick == first:
		probe.clear_series()
		probe.recording = true
		_wall_start_us = now
	elif _tick == last + 1:
		_finish(now, "")
		return
	if _tick >= first:
		var into: int = _tick - first
		if bool(_options["paired"]):
			probe.stages_enabled = (into / BLOCK_TICKS) % 2 == 0
		if into > 0 and into % int(Engine.physics_ticks_per_second) == 0:
			_engine_worst.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1e6)
	var budget_s: float = (float(_options["warmup"]) + float(_options["seconds"])) * MAX_SLOWDOWN
	if float(now - _started_us) * 1e-6 > maxf(budget_s, 30.0):
		_finish(now, "the simulation ran under 1/%d of real time" % int(MAX_SLOWDOWN))


func _finish(now: int, aborted: String) -> void:
	running = false
	probe.recording = false
	var series: Array[PackedInt64Array] = []
	for values: PackedInt64Array in probe.series:
		series.append(values.duplicate())
	var tps: float = float(Engine.physics_ticks_per_second)
	var recorded: int = series[PerfProbe.Field.TICK].size()
	var meta: Dictionary = {
		"layout": String(_layout),
		"n": _n,
		"n_includes_player": false,
		"seed": int(_options["seed"]),
		"label": String(_options["label"]),
		"date": Time.get_datetime_string_from_system(false, true),
		"warmup_s": float(_options["warmup"]),
		"seconds": float(_options["seconds"]),
		"ticks_per_second": int(tps),
		"sim_s": float(recorded) / tps,
		"wall_s": float(now - _wall_start_us) * 1e-6 if _wall_start_us > 0 and recorded > 0 else 0.0,
		"load_ms": _load_ms,
		"placed": {"allies": int(_placed.get(ShipPool.ALLY_TYPE, 0)), "raiders": int(_placed.get(ShipPool.DEFAULT_TYPE, 0))},
		"rebase_threshold_m": float(_options["rebase_m"]),
		"sync_timed": probe.time_sync,
		"sleep_usec_during_run": OS.low_processor_usage_mode_sleep_usec,
		"engine_check": _engine_check(series[PerfProbe.Field.TICK], int(tps)),
		"aborted": aborted,
		"machine": BenchReport.machine(),
	}
	if bool(_options["paired"]):
		meta["probe_cost"] = _probe_cost(series[PerfProbe.Field.TICK])
	var summary: Dictionary = BenchReport.run_summary(meta, series)
	var dir: String = report_root.path_join(String(_options["label"]))
	var problem: String = BenchReport.write(dir, summary, BenchReport.run_markdown(summary))
	var tick: Dictionary = (summary["stages"] as Dictionary)["tick"]
	print("[bench] %s %d seed %d: tick median %.2f ms, p99 %.2f ms, %.2f %% behind real time, %d rebases (worst tick holding one %.2f ms), %s -> %s" % [
			_layout, _n, int(_options["seed"]), float(tick["median_us"]) * 1e-3, float(tick["p99_us"]) * 1e-3, float(summary["lag"]) * 100.0,
			int((summary["rebase"] as Dictionary)["count"]), float((summary["rebase"] as Dictionary)["tick_max_us"]) * 1e-3,
			"pass" if bool((summary["verdict"] as Dictionary)["pass"]) else "fail: " + "; ".join(PackedStringArray((summary["verdict"] as Dictionary)["failures"])),
			ProjectSettings.globalize_path(dir) if problem.is_empty() else problem])
	_put_back()
	DebugConsole.release_wait()
	finished.emit(summary)


# Everything the run changed, back as it was (the ships stay in play).
func _put_back() -> void:
	if _restore.is_empty():
		return
	probe.recording = false
	probe.time_sync = false
	probe.stages_enabled = true
	probe.enabled = bool(_restore["probe"])
	OS.low_processor_usage_mode_sleep_usec = int(_restore["sleep"])
	DebugConsole.flags.invulnerable = bool(_restore["god"])
	if main != null and is_instance_valid(main.world):
		main.world.auto_rebase_distance_m = float(_restore["threshold"])
	Factions.table().set_relation(Factions.EARTH_ALLIANCE, Factions.RAIDERS, int(_restore["relation"]) as Factions.Relation)
	_restore = {}


# The engine's own worst tick of each second against the probe's, as a check that the probe's window misses nothing.
func _engine_check(ticks: PackedInt64Array, tps: int) -> Dictionary:
	var probe_worst := PackedFloat64Array()
	for start: int in range(0, ticks.size() - tps + 1, tps):
		var worst: int = 0
		for i: int in range(start, start + tps):
			worst = maxi(worst, ticks[i])
		probe_worst.append(float(worst))
	return {"engine_worst_us": PerfStats.median(_engine_worst), "probe_worst_us": PerfStats.median(probe_worst),
			"seconds": _engine_worst.size()}


# Tick medians of the blocks with the stage timers on and off, and the paired difference (on minus off).
func _probe_cost(ticks: PackedInt64Array) -> Dictionary:
	var on := PackedFloat64Array()
	var off := PackedFloat64Array()
	var blocks: int = ticks.size() / BLOCK_TICKS
	if blocks % 2 == 0:
		blocks -= 1  # end on an on block
	for b: int in blocks:
		var block := PackedFloat64Array()
		for i: int in range(b * BLOCK_TICKS, (b + 1) * BLOCK_TICKS):
			block.append(float(ticks[i]))
		(on if b % 2 == 0 else off).append(PerfStats.median(block))
	var all := PackedFloat64Array()
	for us: int in ticks:
		all.append(float(us))
	return {"on_blocks": on.size(), "off_blocks": off.size(), "paired_us": PerfStats.paired_difference(on, off),
			"on_median_us": PerfStats.median(on), "off_median_us": PerfStats.median(off), "tick_median_us": PerfStats.median(all)}
