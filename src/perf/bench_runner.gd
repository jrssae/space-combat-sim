class_name BenchRunner
extends Node
## Runs one many-ships benchmark on the live main scene (M4-T01, architecture §17.1): `bench <layout> <n> [seconds]
## [warmup=<s>] [seed=<k>] [label=<name>] [probe=paired] [rebase_m=<m>] [sleep=keep] [rocks=<count>] [capitals=<share>] [boost=<m/s>]`. Sets the scene up from
## the pools, warms up, records ticks with the `PerfProbe`, writes the report and puts back what it changed; the ships stay in
## play.
##
## `battle` and `typical` (M4-T07, §17.6) also bring the battle's stand-ins through `standins` (`World/Standins`): the
## capitals with their turrets and beam lasers, the asteroid field (`rocks=` overrides the mix's count; 0 for none), the mine
## belts and the missiles the mix holds in flight (M4-T12), a low orbit of a body of the star system's data for its gravity
## (M6-T07; the frame's anchor is put back after), the carriers' launch cycle, and for four sides a session
## faction table and the bench factions on the fighters of sides three and four.
## All of it goes when the run ends.
##
## `boost=` (M6-T06) boosts the frame off its anchor once the scene is placed, so the run measures the frame falling
## freely (the anchor-tied things drift every tick) with the same relative motion as a run that rides the anchor.

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
const OPTION_KEYS: Array[String] = ["warmup", "seed", "label", "probe", "rebase_m", "sleep", "rocks", "capitals", "boost"]
## A carrier's launch leaves its bay this much faster than the carrier, along its nose, m/s.
const LAUNCH_MPS: float = 80.0

var main: Main = null
var probe: PerfProbe = null
## The battle's stand-ins (M4-T07); Main makes it.
var standins: StandinDirector = null
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
var _mix: Dictionary = {}
var _rocks_placed: int = 0
var _launch_turn: Dictionary = {}  # carrier -> how many it launched, to take its side's fighters in turn


func _init() -> void:
	process_physics_priority = -2_000_000  # first in the tick, so a window starts and ends on tick boundaries


func _ready() -> void:
	DebugConsole.registry.register_command(ConsoleCommand.new(&"bench",
			"Fly a benchmark layout (%s) with n ships from the pools, measure [seconds] (30) after warmup=<s> (5), and write reports/perf/<label>/ (seed=<k> label=<name> probe=paired rebase_m=<m> rocks=<count> capitals=<share> boost=<m/s>)"
			% ", ".join(PackedStringArray(BenchLayout.NAMES)),
			[ConsoleArg.enum_required(&"layout", BenchLayout.NAMES), ConsoleArg.int_required(&"n", 1, 2000),
			ConsoleArg.string_rest(&"options").make_optional("")]), _cmd_bench, self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)
	if running:
		running = false
		_put_back()


## Reads the words after `bench <layout> <n>`: an optional window in seconds first, then `key=value` options.
## `{"ok", "error", "seconds", "warmup", "seed", "label", "paired", "rebase_m", "keep_sleep", "rocks", "capitals", "boost"}` (`rocks`
## and `capitals`, the capital share, -1: the mix's; `boost`, m/s, 0 for none).
static func parse_options(words: PackedStringArray) -> Dictionary:
	var out: Dictionary = {"ok": true, "error": "", "seconds": DEFAULT_SECONDS, "warmup": DEFAULT_WARMUP_S, "seed": 1, "label": "",
			"paired": false, "rebase_m": REBASE_THRESHOLD_M, "keep_sleep": false, "rocks": -1,
			"capitals": -1.0, "boost": 0.0}
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
			"rocks":
				if not text.is_valid_int() or int(text) < 0:
					return _bad("rocks must be a count, 0 or more")
				out["rocks"] = int(text)
			"capitals":
				if not text.is_valid_float() or float(text) < 0.0 or float(text) > 1.0:
					return _bad("capitals must be a share from 0 to 1")
				out["capitals"] = float(text)
			"boost":
				if not text.is_valid_float() or float(text) < 0.0:
					return _bad("boost must be m/s, 0 or more")
				out["boost"] = float(text)
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
	if not _mix.is_empty():
		result.lines.append("bench %s %d mix: %s; %d rocks placed, %d fights among them" % [layout, n, BattleMix.describe(_mix),
				_rocks_placed, BenchLayout.fights_in_slab(layout, n)])
		print("[bench] %s" % result.lines[-1])
	result.wait_frames = HOLD_FRAMES
	return result


func _set_up_scene() -> void:
	_restore = {
		"table": Factions.table(),
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
	BenchLayout.capital_share = float(_options.get("capitals", -1.0))
	var plan: Array[Dictionary] = BenchLayout.plan(_layout, _n, int(_options["seed"]))
	if TierDirector.current() != null:
		TierDirector.current().seed_value = int(_options["seed"])  # the tier's rolls follow the bench's seed (M4-T22)
	var wanted: Dictionary = {ShipPool.ALLY_TYPE: 0, ShipPool.DEFAULT_TYPE: 0}
	for e: Dictionary in plan:
		if StringName(e["kind"]) == BenchLayout.KIND_FIGHTER:
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
	var session_table: FactionTable = BenchLayout.faction_table(_layout)
	if session_table != null:
		Factions.use_table(session_table)
	var anchor: UniversePos = main.world.to_universe(ship.global_position)
	var numbers: Dictionary = {ShipPool.ALLY_TYPE: ShipPool.ALLY_FIRST_NUMBER, ShipPool.DEFAULT_TYPE: 1}
	_placed = {ShipPool.ALLY_TYPE: 0, ShipPool.DEFAULT_TYPE: 0}
	for e: Dictionary in plan:
		if StringName(e["kind"]) != BenchLayout.KIND_FIGHTER:
			continue
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
		if placed.faction != StringName(e["faction"]):
			set_faction(placed, StringName(e["faction"]))
		_placed[type] = int(_placed[type]) + 1
		if not String(e["wing"]).is_empty():
			main.wings.join(String(e["wing"]), placed)
	_mix = BenchLayout.mix(_layout, _n)
	_rocks_placed = 0
	if not _mix.is_empty() and standins != null:
		_set_up_standins(plan, anchor)
	if DisplayServer.get_name() == "headless" and not bool(_options["keep_sleep"]):
		OS.low_processor_usage_mode_sleep_usec = 0
		probe.time_sync = true
	if float(_options.get("boost", 0.0)) > 0.0:
		main.world.boost(Vector3(float(_options["boost"]), 0.0, 0.0))
	probe.recording = false
	probe.clear_series()
	probe.stages_enabled = true
	probe.enabled = true


# The capitals, the rocks, the orbit and the launch cycle of a battle or typical run (M4-T07).
func _set_up_standins(plan: Array[Dictionary], anchor: UniversePos) -> void:
	standins.clear()
	standins.sides = int(_mix["sides"])
	var numbers: Dictionary = {}
	for e: Dictionary in plan:
		if StringName(e["kind"]) != BenchLayout.KIND_CAPITAL:
			continue
		var cls: String = String(e["class"])
		numbers[cls] = int(numbers.get(cls, 0)) + 1
		var cap: CapitalStandin = standins.add_capital(StringName(cls), StringName(e["faction"]),
				"%s %d" % [cls.to_upper(), int(numbers[cls])], anchor.plus_local(e["offset"]), e["basis"], e["velocity"])
		cap.damageable.invulnerable = true
	var rocks: Array[Dictionary] = BenchLayout.rocks(_layout, _n, int(_options["seed"]), int(_options.get("rocks", -1)))
	if not rocks.is_empty():
		standins.add_asteroids(rocks, anchor)
	_rocks_placed = rocks.size()
	var belts: Array[Dictionary] = BenchLayout.mines(_layout, _n, int(_options["seed"]))
	if not belts.is_empty():
		standins.add_mines(belts, anchor)
	standins.missile_target = int(_mix.get("missiles", 0))
	MissileStandin.steers = 0
	MissileStandin.steer_us = 0
	MissileStandin.native_steers = 0
	var orbit: Dictionary = BenchLayout.gravity_orbit(_layout)
	if not orbit.is_empty():
		_fly_in_orbit(orbit, anchor)
	_launch_turn.clear()
	standins.launcher = _launch_from
	standins.active = true


# The battle's gravity (M6-T07): the frame falls on the circular orbit `orbit` names, placed so that the battle's centre
# `centre` is on it, and the frame's anchor before is kept to put back.
func _fly_in_orbit(orbit: Dictionary, centre: UniversePos) -> void:
	var world: WorldFrame = main.world
	var system: StarSystem = world.star_system if world.star_system != null else StarSystem.load_system(StarSystemHost.DEFAULT_SYSTEM)
	var info: Dictionary = system.info(orbit["body"]) if system.is_valid() else {}
	if info.is_empty():
		push_warning("bench: no body %s to orbit; the battle runs with no gravity" % orbit["body"])
		return
	_restore["frame"] = {"kind": world.anchor_text().get_slice(" ", 0), "system": world.star_system, "name": world.anchor_name,
			"state": world.anchor_state()}
	var radius: float = float(info["radius_m"]) + float(orbit["altitude_m"])
	var speed: float = sqrt(float(info["gm"]) / radius)
	world.anchor_in_orbit(system, orbit["body"], PackedFloat64Array([radius - centre.x, -centre.y, -centre.z, 0.0, 0.0, -speed]))


# Puts back the frame's anchor the battle's orbit replaced.
func _restore_frame() -> void:
	var was: Dictionary = _restore.get("frame", {})
	if was.is_empty() or main == null or not is_instance_valid(main.world):
		return
	match String(was["kind"]):
		"rail":
			main.world.anchor_on_rail(was["system"], was["name"])
		"orbit":
			main.world.anchor_in_orbit(was["system"], was["name"], was["state"])
		_:
			main.world.clear_anchor()


# A carrier's launch: one fighter of its side goes back to the pool and comes out again at the carrier's bay, so N holds.
func _launch_from(carrier: CapitalStandin) -> bool:
	var side: Array[Combatant] = []
	for c: Combatant in main.ships.alive():
		if c.faction == carrier.faction:
			side.append(c)
	if side.is_empty():
		return false
	var turn: int = int(_launch_turn.get(carrier, 0))
	_launch_turn[carrier] = turn + 1
	var leaving: Combatant = side[turn % side.size()]
	var type: StringName = main.ships.type_of(leaving)
	var ship_name: String = leaving.display_name
	var side_index: int = maxi(0, BenchLayout.sides(_layout).find(carrier.faction))
	main.ships.release(leaving)
	var at: UniversePos = main.world.to_universe(carrier.bay_position())
	var made: Dictionary = BrainFactory.from_behaviour({"type": "ai", "profile": BenchLayout.SIDE_PROFILES[side_index]}, at,
			hash([ship_name, standins.launches, int(_options["seed"])]))
	if not bool(made["ok"]):
		return false
	var nose: Vector3 = -carrier.global_basis.z
	var placed: Combatant = main.ships.acquire(ship_name, at, carrier.global_basis, carrier.linear_velocity + nose * LAUNCH_MPS,
			made["brain"] as PilotBrain, type)
	if placed == null:
		return false
	placed.damageable.invulnerable = true
	if placed.faction != carrier.faction:
		set_faction(placed, carrier.faction)
	return true


## Gives a pooled ship another faction: its hull, marker, guns, targeting and pilot all read it (the bench's sides 3 and 4).
static func set_faction(c: Combatant, faction: StringName) -> void:
	c.faction = faction
	c.targetable.faction = faction
	c.damageable.faction = faction
	c.cannon.faction = faction
	c.ship.targeting.system.own_faction = faction


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
		if standins != null:
			standins.restart_weapon_counters()
		if SimCore.current() != null:
			SimCore.current().reset_window()
		MissileStandin.steers = 0
		MissileStandin.steer_us = 0
		MissileStandin.native_steers = 0
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
		"mix": _json_mix(_mix),
		"mix_line": BattleMix.describe(_mix),
		"rocks_placed": _rocks_placed,
		"fights_in_slab": BenchLayout.fights_in_slab(_layout, _n),
		"intercepts": standins.intercepts if standins != null else 0,
		"weapons": _weapons(),
		"core": SimCore.current().window_summary() if SimCore.current() != null else {},
		"rebase_threshold_m": float(_options["rebase_m"]),
		"boost_mps": float(_options.get("boost", 0.0)),
		"sync_timed": probe.time_sync,
		"sleep_usec_during_run": OS.low_processor_usage_mode_sleep_usec,
		"engine_check": _engine_check(series[PerfProbe.Field.TICK], int(tps)),
		"aborted": aborted,
		"machine": BenchReport.machine(),
	}
	if bool(_options["paired"]):
		meta["probe_cost"] = _probe_cost(series[PerfProbe.Field.TICK])
	if _mix.is_empty():
		for key: String in ["mix", "mix_line", "rocks_placed", "fights_in_slab", "intercepts", "weapons"]:
			meta.erase(key)
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
	BenchLayout.capital_share = -1.0
	DebugConsole.flags.invulnerable = bool(_restore["god"])
	if main != null and is_instance_valid(main.world):
		main.world.auto_rebase_distance_m = float(_restore["threshold"])
		if float(_options.get("boost", 0.0)) > 0.0:
			main.world.boost_to_anchor()
	if standins != null and is_instance_valid(standins):
		standins.clear()
	_restore_frame()
	if main != null and is_instance_valid(main.ships):
		for c: Combatant in main.ships.all_ships():
			var own: StringName = ShipCatalog.faction_for(main.ships.type_of(c))
			if c.faction != own:
				set_faction(c, own)
	Factions.use_table(_restore["table"] as FactionTable)
	Factions.table().set_relation(Factions.EARTH_ALLIANCE, Factions.RAIDERS, int(_restore["relation"]) as Factions.Relation)
	_mix = {}
	_restore = {}


# What the battle's weapons did over the measured window (M4-T12) and what each stand-in part cost per tick, us.
func _weapons() -> Dictionary:
	if standins == null:
		return {}
	var ticks: int = maxi(standins.ticks, 1)
	return {"missile_launches": standins.missile_launches, "missile_intercepts": standins.missile_intercepts,
			"beam_shots": standins.beam_shots, "detonations": standins.detonations, "ticks": standins.ticks,
			"parts_us": standins.part_means_us(), "missile_steer_us": float(MissileStandin.steer_us) / float(ticks),
			"missile_steers_per_tick": float(MissileStandin.steers) / float(ticks),
			"path": String(standins.weapons_path()), "missile_native_steers_per_tick": float(MissileStandin.native_steers) / float(ticks),
			"tier": TierDirector.current().window_summary() if TierDirector.current() != null else {},
			"tier_capital_hits": standins.tier_hits_landed}


# The mix for summary.json: the area as a plain list.
static func _json_mix(m: Dictionary) -> Dictionary:
	var out: Dictionary = m.duplicate()
	if out.has("area_m"):
		var area: Vector3 = out["area_m"]
		out["area_m"] = [area.x, area.y, area.z]
	return out


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
