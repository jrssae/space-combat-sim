class_name BrainBatch
extends Node
## Every native think of a tick in one call (M4-T18, architecture §17.13). An internal child of `SimCore` at physics
## priority -9: the AI drivers (-10) hand their native pilots' inputs here instead of calling the host one ship at a time,
## and this node asks the brain host once (`ScsBrains.think_batch`, which runs the thinks across the core's worker threads)
## and gives each driver its result in the order they came, so every command, selection and counter lands as before, one
## priority later. Nothing between -10 and -9 reads a command. A driver stepped by hand (tests) thinks alone, as before.
##
## Rows batches (M4-T33, `perf_native_commands`): the drivers hand in only what the rows do not hold, the host writes each
## think's command into the core (the flight batch flies it at -1) and names the few ships whose drivers have something to
## do (a first command from the row, a changed trigger, a target to select). Every other driver and pilot reads its place
## in the tick's `BrainAnswer` when it next needs it, so no driver finishes its think ship by ship.

const NODE_NAME: StringName = &"BrainBatch"
const PRIORITY: int = -9
## Per ship in the host's answer: 1 when it thought, then the think's `AiPilot.NATIVE_OUT_LEN` numbers.
const STRIDE: int = AiPilot.NATIVE_OUT_LEN + 1
## A rows batch's events per ship (`ScsBrains.rows_events`, M4-T33): its first command from the row, a changed trigger, a
## target to select; and the events' head (thinks near, thinks far, declined, the most contacts seen).
const EVENT_ENTER: int = 1
const EVENT_FIRE: int = 2
const EVENT_SELECT: int = 4
const EVENT_SETTLE: int = 8
const EVENTS_HEAD: int = 4
const NO_RELATION := Vector2i(-1, -1)

# The batch of the latest core.
static var _current: BrainBatch = null

## Wall-clock microseconds of the last batch's native call, and how many ships it carried (readouts, never gameplay).
var call_us: int = 0
var ships: int = 0
## Drivers that finished a think one by one, and drivers a rows batch handed an event, in the last flush (readouts).
var finishes: int = 0
var events: int = 0

var _frame: int = -1
var _host: Object = null
var _rows_version: int = -1
var _now_s: float = 0.0
var _friendly_fire: bool = false
var _origin_x: float = 0.0
var _origin_y: float = 0.0
var _origin_z: float = 0.0
var _drivers: Array[AiPilotDriver] = []
var _dts := PackedFloat64Array()
var _ints := PackedInt64Array()
var _floats := PackedFloat64Array()
var _relations := PackedByteArray()
var _relation_at: Dictionary[StringName, Vector2i] = {}
# This tick's batch is a rows batch (M4-T33), its answer, and `perf_native_commands` as last read (-1: read again).
var _rows: bool = false
var _answer: BrainAnswer = null
static var _rows_setting: int = -1


func _init() -> void:
	name = NODE_NAME
	process_physics_priority = PRIORITY


func _enter_tree() -> void:
	_current = self


func _exit_tree() -> void:
	if _current == self:
		_current = null


func _physics_process(_delta: float) -> void:
	flush()


## The batch the drivers of `tree` hand their thinks to now, or null (none, or another tree's).
static func for_tree(tree: SceneTree) -> BrainBatch:
	if _current == null or not is_instance_valid(_current) or not _current.is_inside_tree() or _current.get_tree() != tree:
		return null
	return _current


## Takes `driver`'s native think for this tick: `p` is its lite perception on `host`, `slot` its pilot's ready slot and
## `rows_version` the core's rows version its scan was taken at. False when it cannot join this tick's batch (another
## host, rows version, clock, frame origin or friendly-fire setting than the ships already in it); the driver then
## thinks alone.
func add(driver: AiPilotDriver, host: Object, p: Perception, slot: int, dt: float, rows_version: int) -> bool:
	var frame: int = Engine.get_physics_frames()
	var o: UniversePos = p.frame_origin
	if frame != _frame:
		_begin(frame, host, p.now_s, p.friendly_fire, o, rows_version, false)
	if _rows or host != _host or rows_version != _rows_version or p.now_s != _now_s or o.x != _origin_x or o.y != _origin_y \
			or o.z != _origin_z or p.friendly_fire != _friendly_fire:
		return false
	var at: Vector2i
	if _relation_at.has(p.faction):
		at = _relation_at[p.faction]
	else:
		at = Vector2i(_relations.size(), p.relation_row.size())
		_relations.append_array(p.relation_row)
		_relation_at[p.faction] = at
	_ints.append(slot)
	_ints.append(at.x)
	_ints.append(at.y)
	_ints.append(p.selected_id)
	_ints.append(p.last_attacker_id)
	_floats.append(dt)
	_floats.append(p.hull_fraction)
	_floats.append(p.last_hit_s)
	_floats.append(p.last_bolt_hit_s)
	_dts.append(dt)
	_drivers.append(driver)
	return true


## Whether this tick's native thinks go into the core's rows (`perf_native_commands`, M4-T33).
static func rows_mode() -> bool:
	if _rows_setting < 0:
		_rows_setting = 1 if bool(Settings.get_value(&"perf_native_commands")) else 0
		if not Settings.changed.is_connected(_on_setting_changed):
			Settings.changed.connect(_on_setting_changed)
	return _rows_setting == 1


## Takes `driver`'s native think into this tick's rows batch (M4-T33): its pilot's ready `slot` on `host`, the time since
## its last think, its faction's relation row from `scan`, whether it is near the player and its latest hits; the clock,
## the friendly-fire setting, the frame origin and the scan's rows version as the whole batch shares them. Returns the
## ship's place in the tick's `answer()`, or -1 when it cannot join (the driver then thinks alone).
func add_rows(driver: AiPilotDriver, host: Object, slot: int, dt: float, faction: StringName, scan: ContactScan,
		near: bool, attacker_id: int, hit_s: float, bolt_hit_s: float, rows_version: int, now_s: float, friendly_fire: bool,
		origin: UniversePos) -> int:
	var frame: int = Engine.get_physics_frames()
	if frame != _frame:
		_begin(frame, host, now_s, friendly_fire, origin, rows_version, true)
	if not _rows or host != _host or rows_version != _rows_version or now_s != _now_s or origin.x != _origin_x \
			or origin.y != _origin_y or origin.z != _origin_z or friendly_fire != _friendly_fire:
		return -1
	var at: Vector2i = _relation_at.get(faction, NO_RELATION)
	if at.x < 0:
		var row: PackedByteArray = scan.relation_row(faction)
		at = Vector2i(_relations.size(), row.size())
		_relations.append_array(row)
		_relation_at[faction] = at
	_ints.append(slot)
	_ints.append(at.x)
	_ints.append(at.y)
	_ints.append(attacker_id)
	_ints.append(1 if near else 0)
	_floats.append(dt)
	_floats.append(hit_s)
	_floats.append(bolt_hit_s)
	_drivers.append(driver)
	return _drivers.size() - 1


## This tick's answer for a rows batch (null outside one): the drivers that joined keep it.
func answer() -> BrainAnswer:
	return _answer if _rows and _frame == Engine.get_physics_frames() else null


## Ships taken into this tick's batch so far.
func queued() -> int:
	return _drivers.size() if _frame == Engine.get_physics_frames() else 0


## Thinks every ship taken this tick in one native call and hands each driver its result, in the order they came. When
## the rows moved since the drivers took them, the host declines every ship and each holds its last command.
func flush() -> void:
	finishes = 0
	events = 0
	if _drivers.is_empty():
		return
	if _rows:
		_flush_rows()
		return
	var started_us: int = Time.get_ticks_usec()  # profiling readout only, never gameplay time
	var out := PackedFloat64Array()
	if is_instance_valid(_host):
		out = _host.think_batch(_ints, _floats, _relations, _now_s, _friendly_fire, _origin_x, _origin_y, _origin_z,
				_rows_version)
	call_us = Time.get_ticks_usec() - started_us
	ships = _drivers.size()
	var drivers: Array[AiPilotDriver] = _drivers
	var dts: PackedFloat64Array = _dts
	_drivers = []
	_dts = PackedFloat64Array()
	_frame = -1
	AiPilotDriver.add_think_time(call_us)
	for i: int in drivers.size():
		var driver: AiPilotDriver = drivers[i]
		if is_instance_valid(driver):
			var base: int = i * STRIDE
			var thought: bool = out.size() >= base + STRIDE and out[base] != 0.0
			driver.finish_native(out, base + 1 if thought else -1, dts[i])
			finishes += 1


# A rows batch's flush (M4-T33): one native call that thinks every ship and writes the commands into the core, the
# answer handed to everyone who joined, the tick's counts, and the few drivers with an event told in the order they came.
func _flush_rows() -> void:
	var started_us: int = Time.get_ticks_usec()  # profiling readout only, never gameplay time
	var out := PackedFloat64Array()
	var head := PackedInt64Array()
	if is_instance_valid(_host):
		out = _host.think_batch_rows(_ints, _floats, _relations, _now_s, _friendly_fire, _origin_x, _origin_y, _origin_z,
				_rows_version)
		head = _host.rows_events()
	call_us = Time.get_ticks_usec() - started_us
	ships = _drivers.size()
	var drivers: Array[AiPilotDriver] = _drivers
	var answered: BrainAnswer = _answer
	_drivers = []
	_dts = PackedFloat64Array()
	_frame = -1
	_answer = null
	answered.out = out
	answered.ready = true
	var named: int = maxi(head.size() - EVENTS_HEAD, 0) / 2
	if head.size() >= EVENTS_HEAD:
		AiPilotDriver.add_rows_counts(head[0], head[1], head[2], head[3], named)
	else:
		AiPilotDriver.add_rows_counts(0, 0, drivers.size(), 0, 0)
	var k: int = EVENTS_HEAD
	while k + 1 < head.size():
		var i: int = head[k]
		var driver: AiPilotDriver = drivers[i]
		if is_instance_valid(driver):
			driver.rows_event(int(head[k + 1]), out, i * STRIDE + 1)
			events += 1
		k += 2
	AiPilotDriver.add_think_time(Time.get_ticks_usec() - started_us)


# A new tick's batch: what every ship in it shares.
func _begin(frame: int, host: Object, now_s: float, friendly_fire: bool, origin: UniversePos, rows_version: int,
		rows: bool) -> void:
	_frame = frame
	_host = host
	_rows_version = rows_version
	_now_s = now_s
	_friendly_fire = friendly_fire
	_origin_x = origin.x
	_origin_y = origin.y
	_origin_z = origin.z
	_rows = rows
	_answer = BrainAnswer.new() if rows else null
	_drivers.clear()
	_dts.clear()
	_ints.clear()
	_floats.clear()
	_relations.clear()
	_relation_at.clear()


static func _on_setting_changed(key: StringName, _value: Variant) -> void:
	if key == &"perf_native_commands":
		_rows_setting = -1
