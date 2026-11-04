class_name FlightBatch
extends Node
## Flies every batched ship's tick in one native call (M4-T10, N4; architecture §17.9). A child of `World` at physics
## priority -1: after the AI drivers (-10) have set this tick's commands and before the ships (0), it gathers each batched
## ship's command into packed arrays, hands them to `ScsFlightStep` (the flight model, the governor and the force
## application, by body RID), and keeps the outputs for the ships to read lazily: the applied force (the ram resolver), the
## levels and RCS shares (the thruster glow and the engine audio) and the reaction-mass flow (drawn here).
##
## A ship joins (`Ship.batched`) when it is built and leaves when it exits the tree; the player's ship never joins. A
## joined ship that cannot process (parked in the pool) is skipped. When the library lacks the class or `perf_native` or
## `perf_native_flight` is off, no row is stepped and every ship flies its own GDScript model that tick, so the setting can
## flip live and a bench can pair the two paths in one process. Ships' types and nozzles are registered once; a rebuilt ship
## registers again.
##
## With the native core on (M4-T15, `SimCore`), the step reads each ship's basis and velocities from the core's rows (synced
## at -11; nothing moves a body between) instead of the physics server; a ship the core has no row for (back from the
## pool this tick) is read from the server as before. The batch attaches the core to the world when it attaches itself.

## The native class that flies the batch when the library is loaded and the settings are on.
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

## Rows stepped in the last tick, in row order (empty when the batch did not run).
var rows: Array[Ship] = []
## The physics frame of the last step (-1 before the first).
var tick: int = -1
## The last tick's outputs, `OUT_VECTORS` and `OUT_SCALARS` per row.
var out_vectors: PackedVector3Array = PackedVector3Array()
var out_scalars: PackedFloat64Array = PackedFloat64Array()
## Wall-clock microseconds of the last tick's gather (GDScript) and native step (readouts only, never gameplay).
var gather_us: int = 0
var step_us: int = 0

var _ships: Array[Ship] = []
var _slots: Dictionary[Ship, int] = {}  # the native slot of every registered ship
var _step: Object = null
var _native_class_known: int = -1  # -1 until first asked; classes never change while the game runs
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
	if _native() != null:
		_register(ship)


## Drops a ship from the batch; it flies its own model from the next tick.
func leave(ship: Ship) -> void:
	_unregister(ship)
	_ships.erase(ship)
	rows.erase(ship)


## Whether the batch flew `ship` in the latest step.
func stepped(ship: Ship) -> bool:
	return rows.has(ship)


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


## Where the last step read the ships' poses and motion: &"server" (the physics server by RID, M4-T10), &"core" (the
## native core's rows, M4-T15) or &"none" (nothing stepped).
func source() -> StringName:
	return _source if not rows.is_empty() else &"none"


## Which path flew the last tick: `native` when the batch stepped any ship, else `gdscript`.
func path() -> StringName:
	return &"native" if not rows.is_empty() else &"gdscript"


## Registers `spec` and `layout` with a native step for the body `rid` and returns the slot, or -1.
static func register_slot(step: Object, rid: RID, spec: ShipSpec, layout: ThrusterLayout) -> int:
	if step == null or spec == null or layout == null or not layout.valid:
		return -1
	var scalars := PackedFloat64Array([spec.mass, spec.pod_main_thrust, spec.pod_retro_thrust, spec.assist_gain_k,
			spec.pod_yaw_gain, spec.pod_yaw_deadzone, spec.pod_yaw_smoothing_s, spec.brake_gain_k, spec.exhaust_velocity,
			spec.speed_limit_mps, spec.assist_speed_max_mps])
	var vectors := PackedVector3Array([spec.inertia, spec.rcs_force_max, spec.rcs_torque_max, spec.rate_max_rad()])
	var axes := PackedVector3Array()
	for group: int in ThrusterLayout.GROUP_COUNT:
		axes.append(layout.torque_axis(group))
	return int(step.register(rid, scalars, vectors, layout.nozzle_groups, layout.nozzle_positions, layout.nozzle_exhausts,
			axes))


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
	rows.clear()
	var step: Object = _native()
	if step == null:
		return
	var started: int = Time.get_ticks_usec()  # readout only
	var frame: int = Engine.get_physics_frames()
	_fuel_unlimited = bool(Settings.get_value(&"fuel_unlimited"))
	var n: int = _ships.size()
	if _slot_ids.size() < n:
		_slot_ids.resize(n)
		_body_ids.resize(n)
		_scalars.resize(n * CMD_SCALARS)
		_vectors.resize(n * CMD_VECTORS)
		_flags.resize(n * CMD_FLAGS)
	var row: int = 0
	for ship: Ship in _ships:
		if not _slots.has(ship):
			_register(ship)
			if not _slots.has(ship):
				continue
		if not ship.can_process() or not ship.is_inside_tree():
			continue
		ship.batch_gather(self, row, frame, delta, _fuel_unlimited, _scalars, _vectors, _flags)
		_slot_ids[row] = _slots[ship]
		_body_ids[row] = ship.get_instance_id()
		rows.append(ship)
		row += 1
	var slots: PackedInt32Array = _slot_ids.slice(0, row)
	var scalars: PackedFloat64Array = _scalars.slice(0, row * CMD_SCALARS)
	var vectors: PackedVector3Array = _vectors.slice(0, row * CMD_VECTORS)
	var flags: PackedByteArray = _flags.slice(0, row * CMD_FLAGS)
	var gathered: int = Time.get_ticks_usec()
	gather_us = gathered - started
	if row == 0:
		step_us = 0
		return
	var sim: SimCore = SimCore.for_tree(get_tree())
	var stepped: bool
	if sim != null and sim.ensure_synced():
		_source = &"core"
		stepped = step.step_core(sim.core, slots, _body_ids.slice(0, row), scalars, vectors, flags, delta)
		fallback_reads = int(step.fallback_reads())
	else:
		_source = &"server"
		stepped = step.step(slots, scalars, vectors, flags, PackedVector3Array(), delta)
		fallback_reads = 0
	if not stepped:
		# The step refused the arrays (it logged why): every ship flies its own model this tick.
		for ship: Ship in rows:
			ship.batch_refused()
		rows.clear()
		step_us = 0
		return
	out_vectors = step.out_vectors()
	out_scalars = step.out_scalars()
	tick = frame
	if not _fuel_unlimited:
		for i: int in rows.size():
			rows[i].batch_draw_fuel(out_scalars[i * OUT_SCALARS + OutScalar.MASS_FLOW], delta)
	step_us = Time.get_ticks_usec() - gathered


# The native step, or null when the library lacks it or a setting is off (then nothing is stepped this tick).
func _native() -> Object:
	if not NativeLib.enabled() or not bool(Settings.get_value(&"perf_native_flight")):
		return null
	if _native_class_known < 0:
		_native_class_known = 1 if NativeLib.has_class(NATIVE_CLASS) else 0
	if _native_class_known == 0:
		return null
	if _step == null:
		_step = NativeLib.instantiate(NATIVE_CLASS)
		if _step == null:
			return null
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


func _unregister(ship: Ship) -> void:
	if _slots.has(ship):
		if _step != null:
			_step.unregister(_slots[ship])
		_slots.erase(ship)


func _register_console() -> void:
	DebugConsole.registry.register_provider(&"flight", ConsoleVars.new({
		&"path": {"get": path, "doc": "native when the batch flew ships in the last tick, else gdscript (every ship its own model)"},
		&"ships": {"get": func() -> int: return _ships.size(), "doc": "Ships that may fly in the batch (every ship but the player's)"},
		&"stepped": {"get": func() -> int: return rows.size(), "doc": "Ships the batch flew in the last tick"},
		&"gather_us": {"get": func() -> int: return gather_us, "unit": "us", "doc": "The last tick's GDScript gather; wall clock"},
		&"step_us": {"get": func() -> int: return step_us, "unit": "us", "doc": "The last tick's native step and its outputs; wall clock"},
		&"source": {"get": func() -> String: return String(source()), "doc": "Where the last step read the ships' poses: core (the native core's rows, M4-T15), server (the physics server by RID) or none"},
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
