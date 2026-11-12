class_name FlightBatch
extends Node
## Flies every batched ship's tick in one native call (M4-T10, N4; architecture §17.9). A child of `World` at physics
## priority -1: after the AI drivers (-10) have set this tick's commands and before the ships (0), it gathers each batched
## ship's command into packed arrays, hands them to `ScsFlightStep` (the flight model, the governor and the force
## application, by body RID), and keeps the outputs for the ships to read lazily: the applied force (the ram resolver), the
## levels and RCS shares (the thruster glow and the engine audio) and the reaction-mass flow (drawn here).
##
## A ship joins (`Ship.batched`) when it is built and leaves when it exits the tree; the player's ship never joins. A
## joined ship that cannot process (parked in the pool) is skipped. Ships' types and nozzles are registered once; a rebuilt
## ship registers again. M4-T37 removed the switch that flew every ship on its own GDScript model instead.
##
## The step reads each ship's basis and velocities from the native core's rows (M4-T15, `SimCore`; synced at -11, nothing
## moves a body between); a ship the core has no row for (back from the pool this tick) is read from the physics server.
## Every world has a core (M4-T42); with none (it was freed as its world left) the batch flies nothing that tick.
##
## Commands from rows (M4-T33): a native pilot's ship flies the command its row holds (the step reads it there, whatever was
## gathered). Row flight (M5-T31): such a ship is not gathered at all; the step finds it among its slots and reads its pose,
## its selected target and the gravity from the core. GDScript gathers only the ships without a row command, a row ship
## with fresh commands (once), and a row ship whose row lost its command.
##
## The batch owns its ships' ticks (M4-T35): a ship the batch flew has nothing left to do at 0 (its combat edges are taken
## in the gather), so its `_physics_process` is switched off and given back when the ship leaves the batch.

## The native class that flies the batch.
const NATIVE_CLASS: StringName = &"ScsFlightStep"
const NODE_NAME: StringName = &"FlightBatch"
const PRIORITY: int = -1

## Per ship in a step: command scalars (the four nozzle groups' levels, `main_right, main_left, retro_right, retro_left`),
## vectors (strafe, rot, track_dir_b, track_rate_b, face_dir_b, env_accel world) and flags (brake, autotrack, assist_on,
## has_propellant).
const CMD_SCALARS: int = 4
const CMD_VECTORS: int = 6
const CMD_FLAGS: int = 4
## Per ship when the caller supplies the state: basis rows 0 to 2, linear velocity, angular velocity (world).
const STATE_VECTORS: int = 5
## Per ship out: vectors by `Out`, scalars by `OutScalar`.
const OUT_VECTORS: int = 10
const OUT_SCALARS: int = 12
enum Out { FORCE, TORQUE, POD_FORCE, POD_TORQUE, RCS_FORCE, RCS_TORQUE, RCS_FORCE_LEVEL, RCS_TORQUE_LEVEL, RATE_TARGET, VELOCITY }
enum OutScalar { R_MAIN, L_MAIN, R_RETRO, L_RETRO, TRIM, POD_YAW_CMD, MASS_FLOW, FACE_ERROR, BRAKING, FACING, TRACKING,
		PROPELLANT_EMPTY }

## The physics frame of the last step (-1 before the first).
var tick: int = -1
## The last tick's outputs, `OUT_VECTORS` and `OUT_SCALARS` per row.
var out_vectors: PackedVector3Array = PackedVector3Array()
var out_scalars: PackedFloat64Array = PackedFloat64Array()
## Wall-clock microseconds of the last tick's gather (GDScript) and native step (readouts only, never gameplay).
var gather_us: int = 0
var step_us: int = 0
## Ships the last tick gathered in GDScript (the rest of `stepped_count` flew from their rows, M5-T31).
var gathered_count: int = 0

var _ships: Array[Ship] = []
var _slots: Dictionary[Ship, int] = {}  # the native slot of every registered ship
var _by_slot: Array[Ship] = []  # the ship of each slot (null for a free slot)
var _row_ships: Dictionary[Ship, bool] = {}  # ships the step flies from their rows without a gather (M5-T31)
var _plain: Dictionary[Ship, bool] = {}  # every other joined ship, in join order: the ones the tick gathers
var _marked: Array[Ship] = []  # row ships to gather once (fresh commands)
var _out_slots: PackedInt32Array = PackedInt32Array()  # the slot of each output row of the last step
var _slot_rows: PackedInt32Array = PackedInt32Array()  # the output row of each slot (-1: not flown)
var _gathered: Dictionary[Ship, int] = {}  # this tick's gathered ships, against gathering one twice
var _step: Object = null
var _slot_ids: PackedInt32Array = PackedInt32Array()
var _body_ids: PackedInt64Array = PackedInt64Array()
var _source: StringName = &"none"
## Ships the last core step had to read from the physics server (no row: back from the pool this tick); a readout.
var fallback_reads: int = 0
var _scalars: PackedFloat64Array = PackedFloat64Array()
var _vectors: PackedVector3Array = PackedVector3Array()
var _flags: PackedByteArray = PackedByteArray()
var _fuel_unlimited: bool = true


func _init() -> void:
	name = NODE_NAME
	process_physics_priority = PRIORITY


func _ready() -> void:
	_register_console()


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)
	_give_back_all()


# Every ship ticks itself again (the batch leaves the tree).
func _give_back_all() -> void:
	for ship: Ship in _ships:
		if is_instance_valid(ship) and ship.is_batch_owned():
			ship.set_batch_owned(false)


## The batch under `world`, made on first ask; null without a world.
static func attach(world: Node) -> FlightBatch:
	if world == null or not is_instance_valid(world):
		return null
	var found := world.get_node_or_null(NodePath(NODE_NAME)) as FlightBatch
	if found != null:
		return found
	var made := FlightBatch.new()
	world.add_child(made)
	SimCore.attach(world)
	return made


## Takes a ship into the batch (registering it with the native step when there is one). Joining again re-registers it,
## for a ship rebuilt with another type.
func join(ship: Ship) -> void:
	if ship == null:
		return
	if _ships.has(ship):
		_unregister(ship)
	else:
		_ships.append(ship)
	_plain[ship] = true
	if _native() != null:
		_register(ship)


## Drops a ship from the batch; it flies its own model from the next tick.
func leave(ship: Ship) -> void:
	_unregister(ship)
	_ships.erase(ship)
	_plain.erase(ship)


## Whether the batch flew `ship` in the latest step.
func stepped(ship: Ship) -> bool:
	return _slots.has(ship) and row_of(_slots[ship]) >= 0


## The output row the latest step gave slot `slot`, or -1.
func row_of(slot: int) -> int:
	return _slot_rows[slot] if slot >= 0 and slot < _slot_rows.size() else -1


## How many ships the latest step flew.
func stepped_count() -> int:
	return _out_slots.size()


## The ships the latest step flew, in row order (tests and the console; built on each call).
func stepped_ships() -> Array[Ship]:
	var out: Array[Ship] = []
	for slot: int in _out_slots:
		if slot < _by_slot.size() and _by_slot[slot] != null:
			out.append(_by_slot[slot])
	return out


## Row flight (M5-T31): `ship` flies its native pilot's row command from now on (`on`), with no gather, or is gathered
## again. The ship calls it when its row flag changes.
func set_row_flight(ship: Ship, on: bool) -> void:
	if not _ships.has(ship):
		return
	if on:
		_row_ships[ship] = true
		_plain.erase(ship)
	else:
		_row_ships.erase(ship)
		_plain[ship] = true
	_push_row_flight(ship)


## The assist, hulk or propellant of a row ship changed: the step's copy follows.
func flags_changed(ship: Ship) -> void:
	if _row_ships.has(ship):
		_push_row_flight(ship)


## A row ship took fresh commands (combat edges): it is gathered once, so they land as a gathered ship's do.
func mark_gather(ship: Ship) -> void:
	if _row_ships.has(ship) and not _marked.has(ship):
		_marked.append(ship)


## The assist's smoothed pod-yaw command as the native step holds it for `ship` (0 when the ship has no slot).
func assist_state(ship: Ship) -> float:
	if _step == null or not _slots.has(ship):
		return 0.0
	return float(_step.assist_state(_slots[ship]))


## Hands the native step the assist state a ship's GDScript model carried, when the ship changes path.
func set_assist_state(ship: Ship, value: float) -> void:
	if _step != null and _slots.has(ship):
		_step.set_assist_state(_slots[ship], value)


## Clears a ship's native assist state (an assist toggle or a reset).
func reset_assist(ship: Ship) -> void:
	if _step != null and _slots.has(ship):
		_step.reset_assist(_slots[ship])


## Where the last step read the ships' poses and motion: &"core" (the native core's rows, M4-T15) or &"none" (nothing
## stepped).
func source() -> StringName:
	return _source if not _out_slots.is_empty() else &"none"


## Which path flew the last tick: `native` when the batch stepped any ship, else `gdscript`.
func path() -> StringName:
	return &"native" if not _out_slots.is_empty() else &"gdscript"


## Registers `spec` and `layout` with a native step for the body `rid` and returns the slot, or -1.
static func register_slot(step: Object, rid: RID, spec: ShipSpec, layout: ThrusterLayout) -> int:
	if step == null or spec == null or layout == null or not layout.valid:
		return -1
	var a: Array = type_arrays(spec, layout)
	return int(step.register(rid, a[0], a[1], a[2], a[3], a[4], a[5]))


## A ship type as the native step and the tier (M4-T21) take it: `[scalars, vectors, nozzle groups, nozzle positions,
## nozzle exhausts, torque axes]`.
static func type_arrays(spec: ShipSpec, layout: ThrusterLayout) -> Array:
	var scalars := PackedFloat64Array([spec.mass, spec.pod_main_thrust, spec.pod_retro_thrust, spec.assist_gain_k,
			spec.pod_yaw_gain, spec.pod_yaw_deadzone, spec.pod_yaw_smoothing_s, spec.brake_gain_k, spec.exhaust_velocity,
			spec.speed_limit_mps, spec.assist_speed_max_mps])
	var vectors := PackedVector3Array([spec.inertia, spec.rcs_force_max, spec.rcs_torque_max, spec.rate_max_rad()])
	var axes := PackedVector3Array()
	for group: int in ThrusterLayout.GROUP_COUNT:
		axes.append(layout.torque_axis(group))
	return [scalars, vectors, layout.nozzle_groups, layout.nozzle_positions, layout.nozzle_exhausts, axes]


## Packs one ship's command for a step at `row` of the command arrays (sized by the caller).
static func pack_command(cmd: FlightCommand, env_accel: Vector3, assist_on: bool, has_propellant: bool,
		scalars: PackedFloat64Array, vectors: PackedVector3Array, flags: PackedByteArray, row: int) -> void:
	var s: int = row * CMD_SCALARS
	scalars[s] = cmd.main_right
	scalars[s + 1] = cmd.main_left
	scalars[s + 2] = cmd.retro_right
	scalars[s + 3] = cmd.retro_left
	var v: int = row * CMD_VECTORS
	vectors[v] = Vector3(cmd.strafe.x, cmd.strafe.y, 0.0)
	vectors[v + 1] = cmd.rot
	vectors[v + 2] = cmd.track_dir_b
	vectors[v + 3] = cmd.track_rate_b
	vectors[v + 4] = cmd.face_dir_b
	vectors[v + 5] = env_accel
	var f: int = row * CMD_FLAGS
	flags[f] = 1 if cmd.brake else 0
	flags[f + 1] = 1 if cmd.autotrack else 0
	flags[f + 2] = 1 if assist_on else 0
	flags[f + 3] = 1 if has_propellant else 0


func _physics_process(delta: float) -> void:
	var step: Object = _native()
	var started: int = Time.get_ticks_usec()  # readout only
	var frame: int = Engine.get_physics_frames()
	var unlimited: bool = bool(Settings.get_value(&"fuel_unlimited"))
	if unlimited != _fuel_unlimited:
		_fuel_unlimited = unlimited
		for ship: Ship in _row_ships:
			_push_row_flight(ship)  # an empty tank counts again, or no longer
	var sim: SimCore = SimCore.for_tree(get_tree())
	var synced: bool = sim != null and sim.ensure_synced()
	_gathered.clear()
	var row: int = 0
	for ship: Ship in _plain:
		row = _gather(ship, row, frame, delta)
	for ship: Ship in _marked:
		row = _gather(ship, row, frame, delta)
	_marked.clear()
	if synced and not _row_ships.is_empty():
		for slot: int in (step.row_strays(sim.core) as PackedInt32Array):
			row = _gather(_by_slot[slot], row, frame, delta)
	gathered_count = row
	var gathered: int = Time.get_ticks_usec()
	gather_us = gathered - started
	_source = &"none"
	fallback_reads = 0
	var stepped: bool = false
	if synced:
		_source = &"core"
		stepped = step.step_core(sim.core, _slot_ids.slice(0, row), _body_ids.slice(0, row), _scalars.slice(0, row * CMD_SCALARS),
				_vectors.slice(0, row * CMD_VECTORS), _flags.slice(0, row * CMD_FLAGS), delta)
		fallback_reads = int(step.fallback_reads())
	if not stepped:
		# No core (its world is leaving), or the step refused the arrays (it logged why): nothing flies this tick.
		_out_slots = PackedInt32Array()
		_slot_rows = PackedInt32Array()
		step_us = 0
		return
	out_vectors = step.out_vectors()
	out_scalars = step.out_scalars()
	_out_slots = step.out_slots()
	_slot_rows = step.slot_rows()
	tick = frame
	if not _fuel_unlimited:
		for i: int in _out_slots.size():
			var ship: Ship = _by_slot[_out_slots[i]]
			if ship != null and ship.batch_draw_fuel(out_scalars[i * OUT_SCALARS + OutScalar.MASS_FLOW], delta):
				flags_changed(ship)
	step_us = Time.get_ticks_usec() - gathered


# Packs `ship`'s command at `row` of the command arrays when it can fly this tick; returns the next free row.
func _gather(ship: Ship, row: int, frame: int, delta: float) -> int:
	if ship == null or _gathered.has(ship):
		return row
	if not _slots.has(ship):
		_register(ship)
		if not _slots.has(ship):
			return row
	if not ship.can_process() or not ship.is_inside_tree():
		return row
	if _slot_ids.size() <= row:
		var n: int = maxi(row + 1, _ships.size())
		_slot_ids.resize(n)
		_body_ids.resize(n)
		_scalars.resize(n * CMD_SCALARS)
		_vectors.resize(n * CMD_VECTORS)
		_flags.resize(n * CMD_FLAGS)
	ship.batch_gather(self, row, frame, delta, _fuel_unlimited, _scalars, _vectors, _flags)
	ship.set_batch_owned(true)
	_slot_ids[row] = _slots[ship]
	_body_ids[row] = ship.get_instance_id()
	_gathered[ship] = row
	return row + 1


# The step's copy of a row ship's flight flags (or its row flight switched off).
func _push_row_flight(ship: Ship) -> void:
	if _step == null or not _slots.has(ship):
		return
	var on: bool = _row_ships.has(ship)
	_step.set_row_flight(_slots[ship], ship.get_instance_id(), on, ship.batch_assist_flag(),
			_fuel_unlimited or ship.batch_has_propellant())
	if on:
		ship.batch_row_flight_started(self)


# The native step, made on first use with every joined ship registered.
func _native() -> Object:
	if _step == null:
		_step = NativeLib.instantiate(NATIVE_CLASS)
		_slots.clear()
		for ship: Ship in _ships:
			_register(ship)
	return _step


func _register(ship: Ship) -> void:
	if _step == null or _slots.has(ship):
		return
	var slot: int = register_slot(_step, ship.get_rid(), ship.spec, ship.get_layout())
	if slot >= 0:
		_slots[ship] = slot
		if _by_slot.size() <= slot:
			_by_slot.resize(slot + 1)
		_by_slot[slot] = ship
		ship.batch_slot = slot
		if ship.is_row_commanded():
			_row_ships[ship] = true
			_plain.erase(ship)
		if _row_ships.has(ship):
			_push_row_flight(ship)


func _unregister(ship: Ship) -> void:
	if _row_ships.has(ship) and _ships.has(ship):
		_plain[ship] = true  # gathered again until it registers back into row flight
	_row_ships.erase(ship)
	_marked.erase(ship)
	if _slots.has(ship):
		var slot: int = _slots[ship]
		if _step != null:
			_step.unregister(slot)
		if slot < _by_slot.size():
			_by_slot[slot] = null
		if slot < _slot_rows.size():
			_slot_rows[slot] = -1  # a reused slot must not read this ship's row
		_slots.erase(ship)
		ship.batch_slot = -1


func _register_console() -> void:
	DebugConsole.registry.register_provider(&"flight", ConsoleVars.new({
		&"path": {"get": path, "doc": "native when the batch flew ships in the last tick, else gdscript (every ship its own model)"},
		&"ships": {"get": func() -> int: return _ships.size(), "doc": "Ships that may fly in the batch (every ship but the player's)"},
		&"stepped": {"get": stepped_count, "doc": "Ships the batch flew in the last tick"},
		&"gathered": {"get": func() -> int: return gathered_count, "doc": "Ships the last tick gathered in GDScript (M5-T31)"},
		&"row_flown": {"get": func() -> int: return _row_ships.size(), "doc": "Ships flown from their row commands with no gather (M5-T31)"},
		&"gather_us": {"get": func() -> int: return gather_us, "unit": "us", "doc": "The last tick's GDScript gather; wall clock"},
		&"step_us": {"get": func() -> int: return step_us, "unit": "us", "doc": "The last tick's native step and its outputs; wall clock"},
		&"source": {"get": func() -> String: return String(source()), "doc": "Where the last step read the ships' poses: core (the native core's rows, M4-T15) or none"},
		&"fallback_reads": {"get": func() -> int: return fallback_reads, "doc": "Ships the last core step read from the physics server because the core had no row for them (back from the pool this tick)"},
		&"positions": {"get": _console_positions, "doc": "Every batchable ship's name and World position, for comparing seeded runs"},
	}), self)


func _console_positions() -> PackedStringArray:
	var out := PackedStringArray()
	for ship: Ship in _ships:
		if not is_instance_valid(ship) or not ship.is_inside_tree() or not ship.can_process():
			continue
		var p: Vector3 = ship.global_position
		out.append("%s %.2f %.2f %.2f" % [ship.display_name(), p.x, p.y, p.z])
	return out
