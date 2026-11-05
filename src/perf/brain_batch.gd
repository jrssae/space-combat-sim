class_name BrainBatch
extends Node
## Every native think of a tick in one call (M4-T18, architecture §17.13). An internal child of `SimCore` at physics
## priority -9: the AI drivers (-10) hand their native pilots' inputs here instead of calling the host one ship at a time,
## and this node asks the brain host once (`ScsBrains.think_batch`, which runs the thinks across the core's worker threads)
## and gives each driver its result in the order they came, so every command, selection and counter lands as before, one
## priority later. Nothing between -10 and -9 reads a command. A driver stepped by hand (tests) thinks alone, as before.

const NODE_NAME: StringName = &"BrainBatch"
const PRIORITY: int = -9
## Per ship in the host's answer: 1 when it thought, then the think's `AiPilot.NATIVE_OUT_LEN` numbers.
const STRIDE: int = AiPilot.NATIVE_OUT_LEN + 1

# The batch of the latest core.
static var _current: BrainBatch = null

## Wall-clock microseconds of the last batch's native call, and how many ships it carried (readouts, never gameplay).
var call_us: int = 0
var ships: int = 0

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
	if frame != _frame:
		_begin(frame, host, p, rows_version)
	var o: UniversePos = p.frame_origin
	if host != _host or rows_version != _rows_version or p.now_s != _now_s or o.x != _origin_x or o.y != _origin_y \
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


## Ships taken into this tick's batch so far.
func queued() -> int:
	return _drivers.size() if _frame == Engine.get_physics_frames() else 0


## Thinks every ship taken this tick in one native call and hands each driver its result, in the order they came. When
## the rows moved since the drivers took them, the host declines every ship and each holds its last command.
func flush() -> void:
	if _drivers.is_empty():
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


# A new tick's batch: what every ship in it shares.
func _begin(frame: int, host: Object, p: Perception, rows_version: int) -> void:
	_frame = frame
	_host = host
	_rows_version = rows_version
	_now_s = p.now_s
	_friendly_fire = p.friendly_fire
	_origin_x = p.frame_origin.x
	_origin_y = p.frame_origin.y
	_origin_z = p.frame_origin.z
	_drivers.clear()
	_dts.clear()
	_ints.clear()
	_floats.clear()
	_relations.clear()
	_relation_at.clear()
