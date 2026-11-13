class_name BenchRunner
extends Node
## Runs one many-ships benchmark on the live main scene (M4-T01, architecture §17.1): `bench <layout> <n> [seconds]
## [warmup=<s>] [seed=<k>] [label=<name>] [probe=paired] [rebase_m=<m>] [sleep=keep] [rocks=<count>] [capitals=<share>] [boost=<m/s>]
## [arrive=jump|placed]`. Sets the scene up from
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
## freely (the anchor-tied things drift every tick) with the same relative motion as a run that rides the anchor. The
## automatic velocity rebase is held off for the run (M6-T21), or it would boost the frame straight back.
##
## Arrivals (M6-T20, AC13): in `battle` and `typical` every ship comes in out of a jump point (`BattleArrivals`, the bench's own
## `JumpPointPool` of 100): the first wave at the start, the rest in later waves during the warm-up, which is stretched until the
## last wave is in, so the measured window holds the whole battle. The report's `arrivals` gives the points and the waves,
## `engine_ticks` the engine's tick time in the warm-up against the window, `render` what the GPU drew (with a window).
## `arrive=placed` puts every ship in place at the start instead (the comparison).

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
const OPTION_KEYS: Array[String] = ["warmup", "seed", "label", "probe", "rebase_m", "sleep", "rocks", "capitals", "boost", "arrive"]
const ARRIVE_JUMP: StringName = &"jump"
const ARRIVE_PLACED: StringName = &"placed"
## With arrivals, the measured window starts at least this long after the last point opened: its ships fly out of the funnel
## first (M6-T22, at most `VortexTransit.MAX_TRANSIT_S`), and the gate's groups wait for its vortex to open (M6-T23).
const ARRIVAL_SETTLE_S: float = 1.0 + VortexTransit.MAX_TRANSIT_S + GateActivation.DURATION_S + VortexTiming.FLASH_S \
		+ VortexTiming.GROW_S
## The battle's jumpgate (M6-T23), for the fighter groups with no capital to bring them: this far below the first fight, facing
## up into the battle. Past the low-attention tier's reach from the player (10 km and its 10 % hysteresis, with 3 km to spare)
## and below the battle's lowest layer of fights, so its arrivals come in as far ships, not beside the player.
const GATE_BELOW_M: float = 14000.0
## Ships a tick the gate brings out of its vortex, so a wave's gate groups come in over a few ticks, not in one.
const GATE_ARRIVALS_PER_TICK: int = 4
## Riders a tick brings out of their capitals' points once the battle runs, only in ticks no capital comes in (a capital's
## arrival is the costly part); they wait in their point's opening flash meanwhile, so nothing shows the delay.
const RIDERS_PER_TICK: int = 8
## Ships of one wave come out of the gate on a spiral this far apart, m, at most `GATE_SLOTS` before it starts over.
const GATE_SPACING_M: float = 35.0
const GATE_SLOTS: int = 300
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
## The battle's jump points (M6-T20), made at the first battle that arrives through them and kept.
var jumps: JumpPointPool = null
## This run's arrivals, or null when its ships are placed.
var arrivals: BattleArrivals = null
## The battle's jumpgate while a run that needs one is set up (M6-T23), else null.
var gate: Jumpgate = null
var _gate_slot: int = 0  # the next spiral spot at the gate
var _riders: Dictionary = {}  # capital unit -> ships brought through its point so far
var _rider_queue: Array[Vector2i] = []  # (plan entry, its capital's unit) still to come out of that point, oldest first
## The most points a wave opens: the pool's hundred; a test asks for fewer to see several waves in a small battle.
var wave_points: int = JumpPointPool.MAX_POINTS
var _plan: Array[Dictionary] = []
var _names := PackedStringArray()
var _anchor: UniversePos = null
var _next_point: int = 0  # the next point of `arrivals` to open
var _radii := PackedFloat32Array()  # by plan entry: the ship's radius once it is in play
var _warmup_engine := PackedFloat64Array()  # the engine's physics time of each warm-up tick after the load's, us
var _window_engine := PackedFloat64Array()  # and of each measured tick
var _bodies: Array[RigidBody3D] = []  # each plan entry's body once in play (null before), for its passage out of its point
var _arrival_spawn_us: int = 0  # the worst tick's own cost of bringing ships in, us
var _render_frames: Array[PackedFloat64Array] = []  # with a window: what each frame drew (`render_phases`)


func _init() -> void:
	process_physics_priority = -2_000_000  # first in the tick, so a window starts and ends on tick boundaries


func _ready() -> void:
	DebugConsole.registry.register_command(ConsoleCommand.new(&"bench",
			"Fly a benchmark layout (%s) with n ships from the pools, measure [seconds] (30) after warmup=<s> (5), and write reports/perf/<label>/ (seed=<k> label=<name> probe=paired rebase_m=<m> rocks=<count> capitals=<share> boost=<m/s> arrive=jump|placed: battle and typical ships come in through jump points, in waves, or are placed)"
			% ", ".join(PackedStringArray(BenchLayout.NAMES)),
			[ConsoleArg.enum_required(&"layout", BenchLayout.NAMES), ConsoleArg.int_required(&"n", 1, 2000),
			ConsoleArg.string_rest(&"options").make_optional("")]), _cmd_bench, self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)
	if running:
		running = false
		_put_back()


## Reads the words after `bench <layout> <n>`: an optional window in seconds first, then `key=value` options.
## `{"ok", "error", "seconds", "warmup", "seed", "label", "paired", "rebase_m", "keep_sleep", "rocks", "capitals", "boost", "arrive"}`
## (`rocks` and `capitals`, the capital share, -1: the mix's; `boost`, m/s, 0 for none; `arrive`, jump or placed).
static func parse_options(words: PackedStringArray) -> Dictionary:
	var out: Dictionary = {"ok": true, "error": "", "seconds": DEFAULT_SECONDS, "warmup": DEFAULT_WARMUP_S, "seed": 1, "label": "",
			"paired": false, "rebase_m": REBASE_THRESHOLD_M, "keep_sleep": false, "rocks": -1,
			"capitals": -1.0, "boost": 0.0, "arrive": ARRIVE_JUMP}
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
			"arrive":
				if text != String(ARRIVE_JUMP) and text != String(ARRIVE_PLACED):
					return _bad("arrive must be jump or placed")
				out["arrive"] = StringName(text)
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
	if arrivals != null and (arrivals.waves > 1 or arrivals.count_via(BattleArrivals.VIA_GATE) > 0):  # the gate's open later
		_warmup_ticks = maxi(_warmup_ticks, ceili((arrivals.last_at_s() + ARRIVAL_SETTLE_S) * tps))
	_tick = 0
	_engine_worst = PackedFloat64Array()
	_started_us = Time.get_ticks_usec()
	running = true
	var result := ConsoleResult.line("bench %s %d: %d ships in play after %.1f s of load; warm-up %.1f s, measuring %.1f s -> %s" % [
			layout, n, main.ships.in_use_count(), _load_ms * 1e-3, float(_warmup_ticks) / tps, float(_options["seconds"]),
			report_root.path_join(String(_options["label"]))])
	if arrivals != null:
		result.lines.append("bench %s %d arrivals: %d jump points in %d waves (%d open at most), the last at %.1f s" % [layout, n,
				arrivals.points.size(), arrivals.waves, arrivals.max_open(), arrivals.last_at_s()])
		print("[bench] %s" % result.lines[-1])
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
		"boost_speed": main.world.auto_boost_speed_mps,
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
	_plan = plan
	_anchor = anchor
	_names = _ship_names(plan)
	_radii = PackedFloat32Array()
	_radii.resize(plan.size())
	_bodies.clear()
	_bodies.resize(plan.size())
	_warmup_engine = PackedFloat64Array()
	_window_engine = PackedFloat64Array()
	_arrival_spawn_us = 0
	_render_frames.clear()
	_next_point = 0
	arrivals = null
	if BenchLayout.has_mix(_layout) and StringName(_options.get("arrive", ARRIVE_JUMP)) == ARRIVE_JUMP:
		_ensure_jumps()
		arrivals = BattleArrivals.plan(plan, mini(wave_points, jumps.size()))
	_placed = {ShipPool.ALLY_TYPE: 0, ShipPool.DEFAULT_TYPE: 0}
	_riders.clear()
	_rider_queue.clear()
	_gate_slot = 0
	if arrivals != null and arrivals.count_via(BattleArrivals.VIA_GATE) > 0:
		_ensure_gate()
	for i: int in plan.size():
		if StringName(plan[i]["kind"]) == BenchLayout.KIND_FIGHTER and arrivals == null:
			_place_fighter(i, Vector3.ZERO)  # with arrivals, every fighter comes in with its unit (M6-T23)
	_mix = BenchLayout.mix(_layout, _n)
	_rocks_placed = 0
	if not _mix.is_empty() and standins != null:
		_set_up_standins(plan, anchor)
	if arrivals != null:
		_open_due(0.0)
	if DisplayServer.get_name() == "headless" and not bool(_options["keep_sleep"]):
		OS.low_processor_usage_mode_sleep_usec = 0
		probe.time_sync = true
	if float(_options.get("boost", 0.0)) > 0.0:
		main.world.auto_boost_speed_mps = 0.0
		main.world.boost(Vector3(float(_options["boost"]), 0.0, 0.0))
	probe.recording = false
	probe.clear_series()
	probe.stages_enabled = true
	probe.enabled = true


# The capitals, the rocks, the orbit and the launch cycle of a battle or typical run (M4-T07).
func _set_up_standins(plan: Array[Dictionary], anchor: UniversePos) -> void:
	standins.clear()
	standins.sides = int(_mix["sides"])
	for i: int in plan.size():
		if StringName(plan[i]["kind"]) == BenchLayout.KIND_CAPITAL and _arrives_at_start(i):
			_place_capital(i, Vector3.ZERO)
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


# Every plan entry's name: fighters numbered per pool type, capitals per class, in plan order.
static func _ship_names(plan: Array[Dictionary]) -> PackedStringArray:
	var out := PackedStringArray()
	var numbers: Dictionary = {ShipPool.ALLY_TYPE: ShipPool.ALLY_FIRST_NUMBER, ShipPool.DEFAULT_TYPE: 1}
	for e: Dictionary in plan:
		if StringName(e["kind"]) == BenchLayout.KIND_CAPITAL:
			var cls: String = String(e["class"])
			numbers[cls] = int(numbers.get(cls, 0)) + 1
			out.append("%s %d" % [cls.to_upper(), int(numbers[cls])])
			continue
		var type: StringName = e["type"]
		var prefix: String = ShipPool.ALLY_NAME_PREFIX if type == ShipPool.ALLY_TYPE else ShipPool.NAME_PREFIX
		out.append("%s %d" % [prefix, int(numbers[type])])
		numbers[type] = int(numbers[type]) + 1
	return out


# Whether plan entry `i` is in play from the start: every ship when they are placed, else the first wave's.
func _arrives_at_start(i: int) -> bool:
	return arrivals == null or int(arrivals.points[arrivals.entry_point[i]]["wave"]) == 0


# Plan entry `i`, a fighter, into play from its pool; `rest` is the frame's rest velocity for a ship arriving mid-run. `xform`
# (World-local) and `velocity` (World) place it elsewhere than its plan's place: at a capital's point or the gate (M6-T23).
func _place_fighter(i: int, rest: Vector3, xform: Variant = null, velocity: Variant = null) -> Combatant:
	var e: Dictionary = _plan[i]
	var type: StringName = e["type"]
	var made: Dictionary = BrainFactory.from_behaviour(e["behaviour"], _anchor, int(e["seed"]))
	if not bool(made["ok"]):
		push_warning("bench: %s: %s" % [_names[i], made["error"]])
		return null
	var at: UniversePos = _anchor.plus_local(e["offset"]) if xform == null \
			else main.world.to_universe((xform as Transform3D).origin)
	var basis: Basis = e["basis"] if xform == null else (xform as Transform3D).basis
	var v: Vector3 = (e["velocity"] as Vector3) + rest if velocity == null else velocity as Vector3
	var placed: Combatant = main.ships.acquire(_names[i], at, basis, v, made["brain"] as PilotBrain, type)
	if placed == null:
		return null
	placed.damageable.invulnerable = true
	if placed.faction != StringName(e["faction"]):
		set_faction(placed, StringName(e["faction"]))
	_placed[type] = int(_placed[type]) + 1
	_radii[i] = placed.ship.bounding_radius()
	_bodies[i] = placed.ship
	if not String(e["wing"]).is_empty():
		main.wings.join(String(e["wing"]), placed)
	return placed


# Plan entry `i`, a capital, into play as a stand-in.
func _place_capital(i: int, rest: Vector3) -> void:
	var e: Dictionary = _plan[i]
	var cap: CapitalStandin = standins.add_capital(StringName(e["class"]), StringName(e["faction"]), _names[i],
			_anchor.plus_local(e["offset"]), e["basis"], (e["velocity"] as Vector3) + rest)
	cap.damageable.invulnerable = true
	# It comes out nose first, so its point fits its cross-section, not its length.
	var spec: Dictionary = CapitalStandin.CLASSES.get(StringName(e["class"]), CapitalStandin.CLASSES[&"cruiser"])
	_radii[i] = 0.5 * Vector2(float(spec["width"]), float(spec["height"])).length()
	_bodies[i] = cap


# The bench's pool of jump points, made once with room for the largest wave.
func _ensure_jumps() -> void:
	if jumps == null or not is_instance_valid(jumps):
		jumps = JumpPointPool.new()
		jumps.name = "BenchJumpPoints"
		main.effects.add_child(jumps)
	jumps.world = main.world
	jumps.prepare(JumpPointPool.MAX_POINTS)


# Brings in every unit of `arrivals` due by `now_s` (M6-T23): each capital first (the first wave's are in play already; a later
# one is placed), out of the point it opens; then the fighter groups riding a capital's point come out of it round its axis (once
# the battle runs, queued for `_bring_riders`), and the rest come through the gate once its vortex is open. Each ship comes out of
# its black ring and flies out (M6-T22). Returns how many capitals came in.
func _open_due(now_s: float) -> int:
	var rest: Vector3 = main.world.rest_velocity()
	var due: int = _next_point
	while due < arrivals.points.size() and float(arrivals.points[due]["at_s"]) <= now_s:
		due += 1
	var transits: VortexTransits = VortexTransits.attach(main.world)
	var capitals: int = 0
	for p: int in range(_next_point, due):
		var unit: Dictionary = arrivals.points[p]
		if StringName(unit["via"]) != BattleArrivals.VIA_OWN:
			continue
		capitals += 1
		var i: int = (unit["members"] as PackedInt32Array)[0]
		if int(unit["wave"]) > 0:
			_place_capital(i, rest)
		var cap := _bodies[i] as CapitalStandin
		if cap == null or not is_instance_valid(cap):
			continue
		var e: Dictionary = _plan[i]
		var opened: JumpVortex = jumps.open_for(_anchor.plus_local(e["offset"]), -(e["basis"] as Basis).z, _radii[i],
				JumpVortex.Direction.ARRIVAL, false, cap)
		unit["point"] = opened
		if opened != null and transits != null and cap.is_inside_tree():
			transits.begin_arrival(cap, opened, cap.global_position, cap.linear_velocity)
	for p: int in range(_next_point, due):
		var unit: Dictionary = arrivals.points[p]
		match StringName(unit["via"]):
			BattleArrivals.VIA_CAPITAL:
				_ride_in(unit, rest, transits)
			BattleArrivals.VIA_GATE:
				for i: int in unit["members"] as PackedInt32Array:
					_through_gate(i, rest)
	_next_point = due
	return capitals


# A fighter group comes out of its capital's point with it: at once while the scene is set up, else queued for `_bring_riders`.
func _ride_in(unit: Dictionary, rest: Vector3, transits: VortexTransits) -> void:
	for i: int in unit["members"] as PackedInt32Array:
		if running:
			_rider_queue.append(Vector2i(i, int(unit["rides"])))
		else:
			_ride_out(i, int(unit["rides"]), rest, transits)


# Brings up to `budget` queued riders out of their capitals' points, oldest first.
func _bring_riders(budget: int) -> void:
	var take: int = mini(budget, _rider_queue.size())
	if take == 0:
		return
	var rest: Vector3 = main.world.rest_velocity()
	var transits: VortexTransits = VortexTransits.attach(main.world)
	for k: int in take:
		_ride_out(_rider_queue[k].x, _rider_queue[k].y, rest, transits)
	_rider_queue = _rider_queue.slice(take)


# Plan entry `i` comes out of the point of capital unit `rides`, round its axis, moving as the capital does; with the capital's
# point gone (refused or taken back) it takes its plan place instead.
func _ride_out(i: int, rides: int, rest: Vector3, transits: VortexTransits) -> void:
	var capital_unit: Dictionary = arrivals.points[rides]
	var point := capital_unit.get("point") as JumpVortex
	if point == null or not point.is_active():
		_place_fighter(i, rest)
		return
	var cap_entry: Dictionary = _plan[(capital_unit["members"] as PackedInt32Array)[0]]
	var velocity: Vector3 = (cap_entry["velocity"] as Vector3) + rest
	var k: int = int(_riders.get(rides, 0))
	_riders[rides] = k + 1
	var placed: Combatant = _place_fighter(i, rest, CarrierJumps.ride_transform(point, k, null), velocity)
	if placed == null:
		return
	var xform: Transform3D = CarrierJumps.ride_transform(point, k, placed.ship)  # clear of the mouth by its own size
	placed.ship.reset_to(xform)
	placed.ship.linear_velocity = velocity
	if transits != null:
		transits.begin_arrival(placed.ship, point, xform.origin, velocity)


# Plan entry `i`, a fighter with no capital to bring it, comes through the battle's gate once its vortex is open: side by side on a
# spiral across the mouth, flying out at the gate's arrival speed.
func _through_gate(i: int, rest: Vector3) -> void:
	if gate == null or not is_instance_valid(gate):
		_place_fighter(i, rest)
		return
	var k: int = _gate_slot % GATE_SLOTS
	_gate_slot += 1
	var r: float = GATE_SPACING_M * sqrt(float(k))
	var angle: float = float(k) * 2.39996323
	var offset := Vector3(cos(angle) * r * Jumpgate.DEFAULT_SIDE_RADIUS_M / Jumpgate.DEFAULT_ARM_RADIUS_M, sin(angle) * r, 0.0)
	var g: Jumpgate = gate
	gate.request_arrival(func() -> void:
		if not running or g != gate:
			return
		var placed: Combatant = _place_fighter(i, Vector3.ZERO, g.arrival_transform(offset),
				g.arrival_velocity() + main.world.rest_velocity())
		if placed != null:
			g.bring_through(placed.ship))


# The battle's gate far below its first fight, facing up into it; made for a run that needs it, freed when it ends.
func _ensure_gate() -> void:
	if gate != null and is_instance_valid(gate):
		return
	var centres: Array[Vector3] = BenchLayout.fight_centres(_layout, _n)
	var below: Vector3 = (centres[0] if not centres.is_empty() else Vector3.ZERO) + Vector3.DOWN * GATE_BELOW_M
	gate = Jumpgate.create("BENCH GATE")
	gate.arrivals_per_tick = GATE_ARRIVALS_PER_TICK
	main.world.spawn(gate, _anchor.plus_local(below), Basis.looking_at(Vector3.UP, Vector3.BACK), main.targets)


func _free_gate() -> void:
	if gate != null and is_instance_valid(gate):
		gate.get_parent().remove_child(gate)
		gate.queue_free()
	gate = null


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


# With a window, what the GPU drew this frame, for the report's `render` (M6-T20).
func _process(delta: float) -> void:
	if not running or DisplayServer.get_name() == "headless":
		return
	var viewport: RID = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	_render_frames.append(PackedFloat64Array([float(_tick) / float(Engine.physics_ticks_per_second),
			RenderingServer.viewport_get_measured_render_time_gpu(viewport), delta * 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1e6,
			float(jumps.open_count()) if jumps != null and is_instance_valid(jumps) else 0.0]))


func _physics_process(_delta: float) -> void:
	if not running:
		return
	_tick += 1
	var now: int = Time.get_ticks_usec()
	var first: int = _warmup_ticks + 1
	var last: int = _warmup_ticks + _measure_ticks
	if _tick > 2:  # the first ticks' engine time holds the load
		var engine_us: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1e6
		(_warmup_engine if _tick <= _warmup_ticks + 1 else _window_engine).append(engine_us)
	if arrivals != null and (_next_point < arrivals.points.size() or not _rider_queue.is_empty()):
		var spawn_started: int = Time.get_ticks_usec()  # profiling only
		if _open_due(float(_tick) / float(Engine.physics_ticks_per_second)) == 0:
			_bring_riders(RIDERS_PER_TICK)
		_arrival_spawn_us = maxi(_arrival_spawn_us, Time.get_ticks_usec() - spawn_started)
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
	var budget_s: float = (float(_warmup_ticks + _measure_ticks) / float(Engine.physics_ticks_per_second)) * MAX_SLOWDOWN
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
		"arrivals": _arrivals_summary(),
		"engine_ticks": _engine_ticks(),
		"render": render_phases(_render_frames, float(_warmup_ticks) / tps),
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
		main.world.auto_boost_speed_mps = float(_restore["boost_speed"])
		if float(_options.get("boost", 0.0)) > 0.0:
			main.world.boost_to_anchor()
	if jumps != null and is_instance_valid(jumps):
		jumps.stop_all()  # before their capitals go: a point losing its opener would collapse on whatever is in it
	if standins != null and is_instance_valid(standins):
		standins.clear()
	_free_gate()
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
	arrivals = null
	_plan = []


# How the ships came in (M6-T20): the points, the waves and the ticks while they arrived.
func _arrivals_summary() -> Dictionary:
	if arrivals == null:
		return {"mode": String(ARRIVE_PLACED)}
	return {"mode": String(ARRIVE_JUMP), "points": arrivals.points.size(), "waves": arrivals.waves,
			"max_open": arrivals.max_open(), "last_at_s": arrivals.last_at_s(), "pool": jumps.size() if jumps != null else 0,
			"opened": _next_point, "warmup_s": float(_warmup_ticks) / float(Engine.physics_ticks_per_second),
			"spawn_worst_us": _arrival_spawn_us,
			"capital_points": arrivals.count_via(BattleArrivals.VIA_OWN),
			"groups_via_capital": arrivals.count_via(BattleArrivals.VIA_CAPITAL),
			"groups_via_gate": arrivals.count_via(BattleArrivals.VIA_GATE),
			"fighters_via_capital": arrivals.ships_via(BattleArrivals.VIA_CAPITAL),
			"fighters_via_gate": arrivals.ships_via(BattleArrivals.VIA_GATE),
			"gate_arrived": gate.arrived if gate != null and is_instance_valid(gate) else 0,
			"collapses": jumps.collapses if jumps != null else 0}


# The engine's own physics time a tick, us, in the warm-up (with arrivals, while the ships come in) and in the measured window:
# the same measure for a run that arrives and one that is placed (M6-T20).
func _engine_ticks() -> Dictionary:
	return {"warmup_ticks": _warmup_engine.size(), "warmup_median_us": PerfStats.median(_warmup_engine),
			"warmup_p99_us": PerfStats.percentile(_warmup_engine, 0.99), "warmup_max_us": PerfStats.max_value(_warmup_engine),
			"window_ticks": _window_engine.size(), "window_median_us": PerfStats.median(_window_engine),
			"window_p99_us": PerfStats.percentile(_window_engine, 0.99)}


## What the GPU drew in each part of a run with a window (M6-T20's fps test): `frames` holds one row a frame, (sim s, GPU ms, frame
## ms, draw calls, VRAM MB, points open). The parts: the first wave's points forming (flash and growth), the points open, the
## measured window from `window_s`. Empty without frames.
static func render_phases(frames: Array[PackedFloat64Array], window_s: float) -> Dictionary:
	if frames.is_empty():
		return {}
	var forming_s: float = VortexTiming.FLASH_S + VortexTiming.GROW_S
	var open_s: float = VortexTiming.new().close_from_s
	var bounds: Dictionary = {"forming": Vector2(0.0, forming_s), "open": Vector2(forming_s, open_s), "window": Vector2(window_s, INF)}
	var out: Dictionary = {}
	for part: String in bounds:
		var span: Vector2 = bounds[part]
		var gpu := PackedFloat64Array()
		var frame := PackedFloat64Array()
		var calls := PackedFloat64Array()
		var vram: float = 0.0
		var points: float = 0.0
		for row: PackedFloat64Array in frames:
			if row[0] < span.x or row[0] >= span.y:
				continue
			gpu.append(row[1])
			frame.append(row[2])
			calls.append(row[3])
			vram = maxf(vram, row[4])
			points = maxf(points, row[5])
		if gpu.is_empty():
			continue
		out[part] = {"frames": gpu.size(), "gpu_ms_median": PerfStats.median(gpu), "gpu_ms_p95": PerfStats.percentile(gpu, 0.95),
				"gpu_ms_max": PerfStats.max_value(gpu), "frame_ms_median": PerfStats.median(frame),
				"fps": 1000.0 / maxf(PerfStats.mean(frame), 1e-3), "draw_calls_median": PerfStats.median(calls),
				"draw_calls_max": PerfStats.max_value(calls), "vram_mb_max": vram, "points_open_max": int(points)}
	return out


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
