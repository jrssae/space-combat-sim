class_name PerfProbe
extends Node
## Times every physics tick by stage for the many-ships benchmark and the `perf` provider (M4-T01, architecture §17.1).
## Marker nodes between the systems' priorities split the tick; the engine's part (Jolt, the body sync) is timed around the
## scripts. The stages add up to the tick. Off by default (`perf on`, or a `bench` run); wall clock only, never gameplay.

const AI_BEGIN_PRIORITY: int = -11
const AI_END_PRIORITY: int = -9
const TARGETING_BEGIN_PRIORITY: int = TargetingController.LATE_PRIORITY - 1
const TARGETING_END_PRIORITY: int = TargetingController.LATE_PRIORITY + 1
const RESOLVERS_END_PRIORITY: int = RamResolver.LATE_PRIORITY + 1
## The probe's own sampler: last in the tick, after the rebase's interpolation reset.
const END_PRIORITY: int = 2_000_000

## What one tick records, in this order (`last`, `series`).
enum Field { TICK, AI, SCAN, THINK, FLIGHT, REBASE, TARGETING, RESOLVERS, HIT, RAM, LATE, PHYSICS, SYNC, OTHER, SHIPS, BOLTS,
		PAIRS, STAGES_ON, SYNC_ON }
const FIELD_NAMES: Array[StringName] = [&"tick", &"ai", &"scan", &"think", &"flight", &"rebase", &"targeting", &"resolvers",
		&"hit", &"ram", &"late", &"physics", &"sync", &"other", &"ships", &"bolts", &"pairs", &"stages_on", &"sync_on"]

enum State { IDLE, SCRIPT, POST }

## Where the rebase cost, the resolvers' own timers and the bolt counts come from, and how many ships are in play (Main sets them).
var world: WorldFrame = null
var hits: HitResolver = null
var rams: RamResolver = null
var ships_in_play: Callable = Callable()
## Nothing runs between frames (headless, frame sleep off), so the body sync before the scripts can be timed; else it is 0.
var time_sync: bool = false
var enabled: bool = false:
	set = set_enabled
var stages_enabled: bool = true:
	set = set_stages_enabled
## The last complete tick, by `Field` (all 0 while off).
var last: PackedInt64Array = PackedInt64Array()
## While true every complete tick is appended to `series`, one array per `Field`.
var recording: bool = false
var series: Array[PackedInt64Array] = []

var _markers: Array[Marker] = []
var _end: Marker = null
var _marks: PackedInt64Array = PackedInt64Array()
var _mark_frames: PackedInt64Array = PackedInt64Array()
var _state: State = State.IDLE
var _tick_frame: int = -1
var _t0: int = 0
var _t_end: int = 0
var _pre_us: int = 0
var _idle_end_us: int = 0
var _idle_end_valid: bool = false
var _rebases_seen: int = 0
var _sync_timed: bool = false
var _captured: PackedInt64Array = PackedInt64Array()  # rebase, scan, think, ships, bolts, pairs, hit, ram at the end of the scripts


## One clock read at a fixed place in the tick.
class Marker extends Node:
	var probe: PerfProbe = null
	var index: int = -1  # -1: the end of the tick's scripts

	func _init(p_probe: PerfProbe, p_index: int, priority: int) -> void:
		probe = p_probe
		index = p_index
		name = "PerfMark%d" % p_index if p_index >= 0 else "PerfEnd"
		process_physics_priority = priority
		set_physics_process(false)

	func _physics_process(_delta: float) -> void:
		if index >= 0:
			probe._mark(index)
		else:
			probe._end_script()


func _init() -> void:
	last.resize(FIELD_NAMES.size())
	_marks.resize(5)
	_mark_frames.resize(5)
	_captured.resize(8)
	clear_series()


func _ready() -> void:
	var priorities: Array[int] = [AI_BEGIN_PRIORITY, AI_END_PRIORITY, TARGETING_BEGIN_PRIORITY, TARGETING_END_PRIORITY,
			RESOLVERS_END_PRIORITY]
	for i: int in priorities.size():
		var marker := Marker.new(self, i, priorities[i])
		_markers.append(marker)
		add_child(marker)
	_end = Marker.new(self, -1, END_PRIORITY)
	add_child(_end)
	_register_console()
	_apply()


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)
	ContactScan.timing = false
	_disconnect()


func set_enabled(value: bool) -> void:
	enabled = value
	_state = State.IDLE
	_idle_end_valid = false
	if not value:
		last.fill(0)
	if world != null:
		_rebases_seen = world.rebases
	_apply()


func set_stages_enabled(value: bool) -> void:
	stages_enabled = value
	_apply()


## Empties `series` (one empty array per `Field`).
func clear_series() -> void:
	series.clear()
	for i: int in FIELD_NAMES.size():
		series.append(PackedInt64Array())


## The last tick's value of a field by name (the console provider).
func value(field: StringName) -> int:
	var i: int = FIELD_NAMES.find(field)
	return last[i] if i >= 0 else 0


func _apply() -> void:
	ContactScan.timing = enabled and stages_enabled
	if not is_inside_tree():
		return
	for marker: Marker in _markers:
		marker.set_physics_process(enabled and stages_enabled)
	if _end != null:
		_end.set_physics_process(enabled)
	if enabled:
		_connect()
	else:
		_disconnect()


func _connect() -> void:
	var tree: SceneTree = get_tree()
	if not tree.physics_frame.is_connected(_on_physics_frame):
		tree.physics_frame.connect(_on_physics_frame)
	if not tree.process_frame.is_connected(_on_process_frame):
		tree.process_frame.connect(_on_process_frame)


func _disconnect() -> void:
	var tree: SceneTree = get_tree() if is_inside_tree() else null
	if tree == null:
		return
	if tree.physics_frame.is_connected(_on_physics_frame):
		tree.physics_frame.disconnect(_on_physics_frame)
	if tree.process_frame.is_connected(_on_process_frame):
		tree.process_frame.disconnect(_on_process_frame)


# The start of a tick's scripts: closes the last tick if it ran back to back with this one, and opens this one.
func _on_physics_frame() -> void:
	var now: int = Time.get_ticks_usec()
	var timed: bool = false
	if _state == State.POST:
		_finish(now)
		_pre_us = 0  # back to back: this tick's sync went into the last tick's engine window
	elif _state == State.IDLE and time_sync and _idle_end_valid:
		_pre_us = now - _idle_end_us
		timed = true
	else:
		_pre_us = 0
	_sync_timed = timed  # only after the last tick is closed, which keeps its own flag
	_idle_end_valid = false
	_t0 = now
	_tick_frame = Engine.get_physics_frames()
	_state = State.SCRIPT


func _mark(index: int) -> void:
	_marks[index] = Time.get_ticks_usec()
	_mark_frames[index] = Engine.get_physics_frames()


# The end of the tick's scripts: what the systems' own timers said about this tick.
func _end_script() -> void:
	if _state != State.SCRIPT:
		return
	_t_end = Time.get_ticks_usec()
	var rebase: int = 0
	if world != null and world.rebases != _rebases_seen:
		_rebases_seen = world.rebases
		rebase = world.last_rebase_us
	_captured[0] = rebase
	_captured[1] = ContactScan.time_this_tick_us()
	_captured[2] = AiPilotDriver.think_us_this_tick()
	_captured[3] = int(ships_in_play.call()) if ships_in_play.is_valid() else 0
	_captured[4] = hits.projectiles_last_tick if hits != null else 0
	_captured[5] = hits.pairs_tested if hits != null else 0
	_captured[6] = hits.resolve_us if hits != null else 0
	_captured[7] = rams.resolve_us if rams != null else 0
	_state = State.POST


# An idle frame begins: the last tick's engine work is over. With the sync timed, the end of this frame is marked too.
func _on_process_frame() -> void:
	if _state == State.POST:
		_finish(Time.get_ticks_usec())
		_state = State.IDLE
	if time_sync:
		# A timer of zero fires after the frame's scripts, transform updates and deletes: the frame's real end.
		get_tree().create_timer(0.0, false, false, true).timeout.connect(_on_idle_end)


func _on_idle_end() -> void:
	_idle_end_us = Time.get_ticks_usec()
	_idle_end_valid = true


func _finish(now: int) -> void:
	var post: int = now - _t_end
	var script: int = _t_end - _t0
	last[Field.TICK] = _pre_us + script + post
	last[Field.PHYSICS] = _pre_us + post
	last[Field.SYNC] = _pre_us
	last[Field.REBASE] = _captured[0]
	last[Field.SCAN] = _captured[1]
	last[Field.THINK] = _captured[2]
	last[Field.SHIPS] = _captured[3]
	last[Field.BOLTS] = _captured[4]
	last[Field.PAIRS] = _captured[5]
	last[Field.HIT] = _captured[6]
	last[Field.RAM] = _captured[7]
	last[Field.SYNC_ON] = 1 if _sync_timed else 0
	var staged: bool = stages_enabled
	for f: int in _mark_frames:
		staged = staged and f == _tick_frame
	last[Field.STAGES_ON] = 1 if staged else 0
	if staged:
		last[Field.OTHER] = _marks[0] - _t0
		last[Field.AI] = _marks[1] - _marks[0]
		last[Field.FLIGHT] = _marks[2] - _marks[1]
		last[Field.TARGETING] = _marks[3] - _marks[2]
		last[Field.RESOLVERS] = _marks[4] - _marks[3]
		last[Field.LATE] = _t_end - _marks[4]
	else:
		for f: int in [Field.AI, Field.FLIGHT, Field.TARGETING, Field.RESOLVERS, Field.LATE]:
			last[f] = 0
		last[Field.OTHER] = script
	if recording:
		for i: int in last.size():
			series[i].append(last[i])


func _register_console() -> void:
	var entries: Dictionary = {
		&"enabled": {"get": func() -> bool: return enabled, "doc": "Whether ticks are timed (`perf on|off`, or a bench run)"},
	}
	var docs: Dictionary = {
		&"tick": "The whole tick: the body sync, every script and Jolt's step",
		&"ai": "The AI drivers (-10)",
		&"scan": "The part of ai spent building and querying the contact scans",
		&"think": "The AI drivers' own timer (ai.think_us for this tick)",
		&"flight": "Priority 0: the console, Main, the rebase's shift, ships' flight model, bolts and props",
		&"rebase": "The rebase in this tick (shift, handlers and reset), 0 without one",
		&"targeting": "Every TargetingController (100)",
		&"resolvers": "The hit and ram resolvers (200, 210)",
		&"hit": "The hit resolver's own timer (combat.resolve_us), inside resolvers",
		&"ram": "The ram resolver's own timer (ram.resolve_us), inside resolvers",
		&"late": "Wings, waves, the rebase's reset and the rest after the resolvers",
		&"physics": "Jolt's step and the body sync, with the engine's flushes around them",
		&"sync": "The body sync before the scripts; 0 unless headless with the frame sleep off (bench), and 0 when ticks ran back to back",
		&"other": "The tick's remainder outside every named stage (before the AI drivers)",
	}
	for key: StringName in docs:
		var field: StringName = key
		entries[StringName(String(key) + "_us")] = {"get": func() -> int: return value(field), "unit": "us",
				"doc": String(docs[key]) + "; last tick, wall clock"}
	entries[&"ships"] = {"get": func() -> int: return value(&"ships"), "doc": "Ships in play in the last tick (pool ships and the player)"}
	entries[&"bolts"] = {"get": func() -> int: return value(&"bolts"), "doc": "Bolts swept in the last tick"}
	entries[&"native_loaded"] = {"get": func() -> bool: return NativeLib.has_class(NativeProbe.NATIVE_CLASS),
			"doc": "Whether the native library is loaded (scripts/build_native.sh; M4-T05)"}
	entries[&"native_version"] = {"get": func() -> String: return NativeLib.version(NativeProbe.NATIVE_CLASS),
			"doc": "The loaded native library's version, empty when it is not loaded"}
	DebugConsole.registry.register_provider(&"perf", ConsoleVars.new(entries), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"perf",
			"Time every tick's stages (the perf provider); toggles with no argument",
			[ConsoleArg.bool_optional(&"state")] as Array[ConsoleArg]), _cmd_perf, self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"native",
			"Show whether the native library is loaded and used; 'bench' times a call into it from GDScript",
			[ConsoleArg.enum_optional(&"action", [&"bench"])] as Array[ConsoleArg]), _cmd_native, self)


func _cmd_perf(args: Dictionary) -> String:
	var wanted: Variant = args.get(&"state")
	enabled = not enabled if wanted == null else bool(wanted)
	return "perf %s" % ("on" if enabled else "off")


func _cmd_native(args: Dictionary) -> PackedStringArray:
	var loaded: bool = NativeLib.has_class(NativeProbe.NATIVE_CLASS)
	var out := PackedStringArray(["native library %s, perf_native %s, probe path %s" % [
			"loaded (%s)" % NativeLib.version(NativeProbe.NATIVE_CLASS) if loaded else "not loaded",
			"on" if NativeLib.enabled() else "off", NativeProbe.new().path()]])
	if args.get(&"action") == &"bench":
		out.append_array(NativeBoundaryBench.format(NativeBoundaryBench.run()))
	return out
