class_name BrainBatch
extends Node
## Every native think of a tick in one call (M4-T18, architecture §17.13). An internal child of `SimCore` at physics
## priority -9: the AI drivers (-10) hand their native pilots' inputs here instead of calling the host one ship at a time,
## and this node asks the brain host once (`ScsBrains.launch_rows`, which runs the thinks across the core's worker threads)
## and gives each driver its result in the order they came. Nothing between -10 and -9 reads a command. A driver stepped by
## hand (tests) thinks alone.
##
## Rows batches (M4-T33): the drivers hand in only what the rows do not hold, the host writes each
## think's command into the core (the flight batch flies it at -1) and names the few ships whose drivers have something to
## do (a first command from the row, a changed trigger, a target to select). Every other driver and pilot reads its place
## in the tick's `BrainAnswer` when it next needs it, so no driver finishes its think ship by ship.
##
## Hosted drivers (M4-T35): a driver whose pilot's slot is bound hands its step to the host
## (`host_driver`): the think rate's stagger, the wake, the time since the last think and the hold of a declined think are
## decided there, in the same call as the thinks, so no driver runs per ship per tick. The batch gives the host the tick's
## frame first (the tick length, the player, the think rate's settings), pushes the contexts that changed since the last
## tick (`AiContext.take_changed`) and the relation matrix over the core's factions when the factions or the table change,
## and hands the hosted drivers their events as it hands the queued ones theirs.
##
## The step as a job (M4-T24, `sim_step`): the batch is launched at -9 (`ScsBrains.launch_rows`, a snapshot of the rows, on
## the step's worker thread when `threaded`, on the main thread when `delayed`) and joined at the next tick's -9, when its
## commands reach the core (the flight batch flies them at -1) and its events the drivers that joined the tick before, so
## every command lands one tick after its think (Q53; M4-T37 removed the same-tick inline step). A join that finds the job
## still running waits for it (a counted miss); nothing is skipped.

const NODE_NAME: StringName = &"BrainBatch"
const PRIORITY: int = -9
## Per ship in the host's answer: 1 when it thought, then the think's `AiPilot.NATIVE_OUT_LEN` numbers.
const STRIDE: int = AiPilot.NATIVE_OUT_LEN + 1
## A rows batch's events per ship (`ScsBrains.rows_events`, M4-T33): its first command from the row, a changed trigger, a
## target to select; and the events' head (thinks near, thinks far, declined, the most contacts seen, hosted held, hosted tiered).
const EVENT_ENTER: int = 1
const EVENT_FIRE: int = 2
const EVENT_SELECT: int = 4
const EVENT_SETTLE: int = 8
const EVENTS_HEAD: int = 6
const NO_RELATION := Vector2i(-1, -1)
## The step's schedules (`sim_step`, M4-T24): the one-tick handover on the main thread, and with the job on the step's
## worker thread.
const STEP_DELAYED: int = 1
const STEP_THREADED: int = 2

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
var _ints := PackedInt64Array()
var _floats := PackedFloat64Array()
var _relations := PackedByteArray()
var _relation_at: Dictionary[StringName, Vector2i] = {}
# This tick's answer (M4-T33).
var _answer: BrainAnswer = null
# The drivers the host steps (M4-T35), by their pilots' slots; the relation matrix as last built (the core's faction count,
# the table and its revision).
var _hosted: Dictionary[int, AiPilotDriver] = {}
var _matrix_count: int = -1
var _matrix_table: FactionTable = null
var _matrix_revision: int = -1
## Hosted drivers the last flush stepped (a readout).
var hosted_stepped: int = 0
## Wall-clock microseconds the last flush spent joining the previous tick's job (M4-T24; a readout).
var join_us: int = 0
## Results dropped because the ship was parked or re-piloted between the launch and the join (fix round 1, I3): the last
## flush's and the total.
var stale: int = 0
var stale_total: int = 0
# The hosted drivers' pilots as they were hosted (slot to brain), for the identity check at the join.
var _hosted_brains: Dictionary[int, PilotBrain] = {}
# The two above as the launched ticks read them: copied only after a host or unhost, never changed in place, so a tick in
# flight keeps the set it was launched with.
var _hosted_launch: Dictionary[int, AiPilotDriver] = {}
var _hosted_brains_launch: Dictionary[int, PilotBrain] = {}
var _hosted_changed: bool = false
# `perf_step_threads` as last given to the host (-1: give it again).
var _step_threads_given: int = -1
static var _step_threads_setting: int = -1
# The tick launched and not yet joined (M4-T24), and `sim_step` as last read (-1: read again).
var _launched: Launched = null
static var _step_setting: int = -1


## A tick's batch launched as a job and waiting for its results (M4-T24): who joined it, the answer they keep, and who each
## of them was (the pilot flying the ship at the launch; fix round 1, I3): a result for a ship parked or re-piloted since is
## stale and is dropped.
class Launched extends RefCounted:
	var host: Object = null
	var drivers: Array[AiPilotDriver] = []
	var brains: Array[PilotBrain] = []
	var answer: BrainAnswer = null
	var hosted_drivers: Dictionary[int, AiPilotDriver] = {}
	var hosted_brains: Dictionary[int, PilotBrain] = {}


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


## Hands `driver`'s step to the host (M4-T35): its pilot's slot, its ship's body, its place in the stagger and the think
## rate's state and hits as it kept them.
func host_driver(driver: AiPilotDriver, host: Object, slot: int, body_id: int, ordinal: int, steps: int, since_think_s: float,
		woken: bool, attacker_id: int, hit_s: float, bolt_hit_s: float) -> void:
	_host = host if _host == null or not is_instance_valid(_host) else _host
	host.host_driver(slot, body_id, ordinal, steps, since_think_s, woken, attacker_id, hit_s, bolt_hit_s)
	_hosted[slot] = driver
	_hosted_brains[slot] = driver.brain
	_hosted_changed = true


## Takes the step back from the host: `[steps, since_think_s, woken]` as the host left them (empty when it was not hosted).
func unhost_driver(host: Object, slot: int) -> PackedFloat64Array:
	_hosted.erase(slot)
	_hosted_brains.erase(slot)
	_hosted_changed = true
	if host != null and is_instance_valid(host):
		return host.unhost_driver(slot)
	return PackedFloat64Array()


## Drivers the host steps now.
func hosted_count() -> int:
	return _hosted.size()


## Every hosted driver steps itself again (no core or host is left to step them).
func unhost_all() -> void:
	for slot: int in _hosted.keys():
		var driver: AiPilotDriver = _hosted[slot]
		if is_instance_valid(driver):
			driver.unhost()
	_hosted.clear()
	_hosted_brains.clear()
	_hosted_changed = true


## The step's schedule now (`sim_step`): `STEP_DELAYED` or `STEP_THREADED`.
static func step_mode() -> int:
	if _step_setting < 0:
		_step_setting = step_mode_of(StringName(Settings.get_value(&"sim_step")))
		if not Settings.changed.is_connected(_on_setting_changed):
			Settings.changed.connect(_on_setting_changed)
	return _step_setting


static func step_mode_of(name: StringName) -> int:
	match name:
		&"delayed":
			return STEP_DELAYED
		_:
			return STEP_THREADED


## Whether a launched tick waits for its join.
func step_launched() -> bool:
	return _launched != null


## The brain host of the launched tick, or of this one (the console's readouts).
func host() -> Object:
	if _launched != null and is_instance_valid(_launched.host):
		return _launched.host
	return _host if _host != null and is_instance_valid(_host) else null


## Takes `driver`'s native think into this tick's rows batch (M4-T33): its pilot's ready `slot` on `host`, the time since
## its last think, its faction's relation row from `scan`, whether it is near the player and its latest hits; the clock,
## the friendly-fire setting, the frame origin and the scan's rows version as the whole batch shares them. Returns the
## ship's place in the tick's `answer()`, or -1 when it cannot join (the driver then thinks alone).
func add_rows(driver: AiPilotDriver, host: Object, slot: int, dt: float, faction: StringName, scan: ContactScan,
		near: bool, attacker_id: int, hit_s: float, bolt_hit_s: float, rows_version: int, now_s: float, friendly_fire: bool,
		origin: UniversePos) -> int:
	var frame: int = Engine.get_physics_frames()
	if frame != _frame:
		_begin(frame, host, now_s, friendly_fire, origin, rows_version)
	if host != _host or rows_version != _rows_version or now_s != _now_s or origin.x != _origin_x \
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
	return _answer if _frame == Engine.get_physics_frames() else null


## Ships taken into this tick's batch so far.
func queued() -> int:
	return _drivers.size() if _frame == Engine.get_physics_frames() else 0


## Thinks every ship taken this tick in one native call and hands each driver its result, in the order they came. When
## the rows moved since the drivers took them, the host declines every ship and each holds its last command. With the
## step delayed or threaded (M4-T24) the previous tick's job is joined and applied first, and this tick's is launched.
func flush() -> void:
	finishes = 0
	events = 0
	hosted_stepped = 0
	join_us = 0
	stale = 0
	AiPilotDriver.roll_counts()  # a tick with no think lands reads zero (the counts come at the join, M4-T24)
	if _launched != null:
		_join_launched()
	if _drivers.is_empty():
		if _hosted.is_empty():
			return
		if not _begin_hosted_tick():
			unhost_all()  # no core or host to step them: the drivers step themselves
			return
	_flush_rows()


# A rows batch's flush (M4-T33): one native job that thinks every ship and writes the commands into the core, the answer
# handed to everyone who joined, the tick's counts, and the few drivers with an event told in the order they came. The
# hosted drivers (M4-T35) are stepped in the same job, after the queued ships. The job is launched now and all of that
# happens at the next tick's join (M4-T24).
func _flush_rows() -> void:
	var started_us: int = Time.get_ticks_usec()  # profiling readout only, never gameplay time
	var mode: int = step_mode()
	var drivers: Array[AiPilotDriver] = _drivers
	var answered: BrainAnswer = _answer
	var host: Object = _host
	_drivers = []
	_frame = -1
	_answer = null
	var launched := Launched.new()
	launched.host = host
	launched.drivers = drivers
	launched.brains = _brains_of(drivers)
	launched.answer = answered
	if _hosted_changed:
		_hosted_launch = _hosted.duplicate()
		_hosted_brains_launch = _hosted_brains.duplicate()
		_hosted_changed = false
	launched.hosted_drivers = _hosted_launch
	launched.hosted_brains = _hosted_brains_launch
	if not is_instance_valid(host):
		_apply_rows(launched, PackedFloat64Array(), PackedInt64Array(), PackedInt64Array())
		return
	if not _hosted.is_empty():
		_prepare_hosted()
	_apply_step_threads(host)
	if host.launch_rows(_ints, _floats, _relations, _now_s, _friendly_fire, _origin_x, _origin_y, _origin_z, _rows_version,
			mode == STEP_THREADED):
		_launched = launched
	else:
		_apply_rows(launched, PackedFloat64Array(), PackedInt64Array(), PackedInt64Array())
	call_us = Time.get_ticks_usec() - started_us
	AiPilotDriver.add_think_time(call_us)


# A rows batch's results: the answer filled for everyone who joined, the tick's counts, and the drivers with an event
# told in the order they came (`out` empty: every think declined). A driver whose pilot changed since the launch (parked,
# re-piloted; a hosted slot taken by another pilot) gets no event: the result is stale.
func _apply_rows(launched: Launched, out: PackedFloat64Array, head: PackedInt64Array, hosted_slots: PackedInt64Array) -> void:
	var drivers: Array[AiPilotDriver] = launched.drivers
	ships = drivers.size() + hosted_slots.size()
	hosted_stepped = hosted_slots.size()
	if launched.answer != null:
		launched.answer.out = out
		launched.answer.ready = true
	var named: int = maxi(head.size() - EVENTS_HEAD, 0) / 2
	if head.size() >= EVENTS_HEAD:
		AiPilotDriver.add_rows_counts(head[0], head[1], head[2], head[3], named, head[4], head[5])
	else:
		AiPilotDriver.add_rows_counts(0, 0, drivers.size(), 0, 0, 0)
	var k: int = EVENTS_HEAD
	var queued: int = drivers.size()
	while k + 1 < head.size():
		var i: int = head[k]
		var driver: AiPilotDriver = null
		var brain: PilotBrain = null
		if i < queued:
			driver = drivers[i]
			brain = launched.brains[i]
		elif i - queued < hosted_slots.size():
			var slot: int = int(hosted_slots[i - queued])
			driver = launched.hosted_drivers.get(slot)
			brain = launched.hosted_brains.get(slot)
		k += 2
		if driver == null or not is_instance_valid(driver):
			continue
		if brain == null or driver.brain != brain or not driver.is_inside_tree():
			_count_stale()
			continue
		if i >= queued and _hosted.get(int(hosted_slots[i - queued])) != driver:
			_count_stale()  # unhosted since the launch (a setting flip, a hand-driven step): the slot is no longer its
			continue
		driver.rows_event(int(head[k - 1]), out, i * STRIDE + 1)
		events += 1


# The previous tick's job joined (waited for when it still runs) and its results applied (M4-T24).
func _join_launched() -> void:
	var started_us: int = Time.get_ticks_usec()  # profiling readout only, never gameplay time
	var launched: Launched = _launched
	_launched = null
	var out := PackedFloat64Array()
	var head := PackedInt64Array()
	var hosted_slots := PackedInt64Array()
	if is_instance_valid(launched.host):
		out = launched.host.join_step()
		head = launched.host.rows_events()
		hosted_slots = launched.host.hosted_item_slots()
	_apply_rows(launched, out, head, hosted_slots)
	join_us = Time.get_ticks_usec() - started_us
	AiPilotDriver.add_think_time(join_us)


# Who flies each queued driver's ship at the launch.
func _brains_of(drivers: Array[AiPilotDriver]) -> Array[PilotBrain]:
	var out: Array[PilotBrain] = []
	out.resize(drivers.size())
	for i: int in drivers.size():
		out[i] = drivers[i].brain if is_instance_valid(drivers[i]) else null
	return out


func _count_stale() -> void:
	stale += 1
	stale_total += 1


# Gives the host the job's thread count (`perf_step_threads`) when it changed.
func _apply_step_threads(host: Object) -> void:
	if _step_threads_setting < 0:
		_step_threads_setting = int(Settings.get_value(&"perf_step_threads"))
	if _step_threads_given != _step_threads_setting or host != _host:
		_step_threads_given = _step_threads_setting
		host.set_step_threads(_step_threads_setting)


# A tick no driver queued a think in: the hosted drivers still step, so the batch opens the tick itself from the core.
# False when there is no core or host to step them.
func _begin_hosted_tick() -> bool:
	var sim: SimCore = SimCore.for_tree(get_tree())
	var host: Object = NativeBrains.host(get_tree())
	if sim == null or host == null:
		return false
	var origin: UniversePos = sim.world.origin if sim.world != null else UniversePos.new()
	_begin(Engine.get_physics_frames(), host, SimClock.now(), bool(Settings.get_value(&"friendly_fire")), origin,
			int(sim.core.rows_version()))
	return true


# What the hosted drivers' step reads this tick (M4-T35): the frame, the contexts that changed, the relation matrix.
func _prepare_hosted() -> void:
	var frame: Array = AiPilotDriver.driver_frame()
	_host.set_driver_frame(get_physics_process_delta_time(), frame[0], frame[1], frame[2], frame[3], frame[4],
			TierDirector.brain_period_ticks())
	for ctx: AiContext in AiContext.take_changed():
		if ctx.native_pilot != null and ctx.native_pilot.is_hosted():
			ctx.native_pilot.sync_rows(_host)
	var sim: SimCore = SimCore.for_tree(get_tree())
	if sim == null:
		return
	var names: Array = sim.core.factions()
	var table: FactionTable = Factions.table()
	if names.size() == _matrix_count and table == _matrix_table and table.revision == _matrix_revision:
		return
	_matrix_count = names.size()
	_matrix_table = table
	_matrix_revision = table.revision
	var matrix := PackedByteArray()
	matrix.resize(names.size() * names.size())
	for a: int in names.size():
		for b: int in names.size():
			matrix[a * names.size() + b] = Factions.relation(names[a], names[b])
	_host.set_relation_matrix(matrix, names.size())


# A new tick's batch: what every ship in it shares.
func _begin(frame: int, host: Object, now_s: float, friendly_fire: bool, origin: UniversePos, rows_version: int) -> void:
	_frame = frame
	_host = host
	_rows_version = rows_version
	_now_s = now_s
	_friendly_fire = friendly_fire
	_origin_x = origin.x
	_origin_y = origin.y
	_origin_z = origin.z
	_answer = BrainAnswer.new()
	_drivers.clear()
	_ints.clear()
	_floats.clear()
	_relations.clear()
	_relation_at.clear()


static func _on_setting_changed(key: StringName, _value: Variant) -> void:
	if key == &"sim_step":
		_step_setting = -1  # a launched tick is still joined at the next flush, whatever the new schedule
	elif key == &"perf_step_threads":
		_step_threads_setting = -1
		if _current != null and is_instance_valid(_current):
			_current._step_threads_given = -1

