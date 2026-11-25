class_name CapitalFlight
extends Node
## Flies every capital ship in play through the native flight step (M10-T07, D12.4): one `ScsFlightStep.step_core` call a tick
## for all of them, as `FlightBatch` does for the AI fighters (§17.9), from each ship's helm command, all of them worked out
## natively in one call (`ScsSimCore.capital_helm_commands`, M10-T16, Q70). A child of `World` at the
## fighters' batch priority, after the core's sync and before Jolt's step; it also turns the ships' rotating sections. Its own
## step instance keeps the fighters' slots and their parity recordings untouched.
##
## A ship joins in its `_ready` and leaves when it exits the tree; a parked one (the tier, the pool) is skipped. Each ship's
## type is registered once with its flight spec (`CapitalPropulsion.flight_spec`); a ship whose spec changes joins again.
##
## Disabled hulks (M10-T10, D12.7, Q19): each tick a disabled ship's wind-down moves on before its command, and its assist goes
## with its control. The hulks are listed oldest first (`hulks`); there is no cap on them.
##
## Console: it hosts the `capital` provider and command (`CapitalConsole`).

const NODE_NAME: StringName = &"CapitalFlight"
const PRIORITY: int = FlightBatch.PRIORITY

## The last tick's outputs (`FlightBatch.OUT_VECTORS` and `OUT_SCALARS` per flown ship) and which ship each row was.
var out_vectors: PackedVector3Array = PackedVector3Array()
var out_scalars: PackedFloat64Array = PackedFloat64Array()
var flown: Array[CapitalShip] = []
## Wall-clock microseconds of the last tick (a readout, never gameplay).
var last_us: int = 0
## The disabled hulks, oldest first.
var hulks: HulkRoster = HulkRoster.new()

var _ships: Array[CapitalShip] = []
var _step: Object = null
var _out_slots := PackedInt32Array()  # the slot of each output row of the last step
var _commands: Array = []  # the last tick's command arrays (scalars, vectors, flags), by flown row
var _console: CapitalConsole = null


func _init() -> void:
	name = NODE_NAME
	process_physics_priority = PRIORITY


static func attach(world: Node) -> CapitalFlight:
	var found: CapitalFlight = of(world)
	if found != null:
		return found
	var made := CapitalFlight.new()
	world.add_child(made)
	SimCore.attach(world)
	return made


static func of(world: Node) -> CapitalFlight:
	if world == null or not is_instance_valid(world):
		return null
	return world.get_node_or_null(NodePath(NODE_NAME)) as CapitalFlight


func _ready() -> void:
	_console = CapitalConsole.new(self)
	_console.register()


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


## Takes `ship` into the flight (again, after its spec changed).
func join(ship: CapitalShip) -> void:
	if ship == null:
		return
	if _ships.has(ship):
		_unregister(ship)
	else:
		_ships.append(ship)
		ship.ship_disabled.connect(_on_ship_disabled.bind(ship))
	_register(ship)


func leave(ship: CapitalShip) -> void:
	_unregister(ship)
	_ships.erase(ship)
	hulks.remove(ship.get_instance_id())
	var callback: Callable = _on_ship_disabled.bind(ship)
	if ship.ship_disabled.is_connected(callback):
		ship.ship_disabled.disconnect(callback)


## The capital ships it flies, in join order.
func ships() -> Array[CapitalShip]:
	return _ships


## The ship the `capital` console has in focus, or null.
func focused() -> CapitalShip:
	return _console.focused() if _console != null else null


## The command `ship` flew on the last tick (its helm's, shaped by a wind-down), or an empty one (a readout).
func last_command(ship: CapitalShip) -> FlightCommand:
	var row: int = flown.find(ship)
	if row < 0 or _commands.size() < 3:
		return FlightCommand.new()
	return _unpack(_commands[0], _commands[1], _commands[2], row)


## The flight step's output row of `ship` in the last tick, or -1.
func row_of(ship: CapitalShip) -> int:
	return _out_slots.find(ship.flight_slot) if flown.has(ship) else -1


func _physics_process(delta: float) -> void:
	var started: int = Time.get_ticks_usec()  # readout only
	var sim: SimCore = SimCore.for_tree(get_tree())
	flown.clear()
	if sim == null or not sim.ensure_synced() or _native() == null:
		last_us = Time.get_ticks_usec() - started
		return
	var slots := PackedInt32Array()
	var bodies := PackedInt64Array()
	var states := PackedVector3Array()
	for ship: CapitalShip in _ships:
		if not is_instance_valid(ship) or not ship.is_inside_tree() or not ship.can_process() or ship.flight_slot < 0:
			continue
		ship.step_rotors(delta)
		ship.advance_hulk(delta)
		var b: Basis = ship.global_basis
		states.append_array([b.x, b.y, b.z, ship.linear_velocity])
		slots.append(ship.flight_slot)
		bodies.append(ship.get_instance_id())
		flown.append(ship)
	if flown.is_empty():
		last_us = Time.get_ticks_usec() - started
		return
	# Every helm at once; a disabled hull's command is then shaped by its wind-down. The core adds the frame's pull itself.
	var helm: Array = sim.core.capital_helm_commands(bodies, states)
	var scalars: PackedFloat64Array = helm[0]
	var vectors: PackedVector3Array = helm[1]
	var flags: PackedByteArray = helm[2]
	var velocities: PackedVector3Array = helm[3]
	for row: int in flown.size():
		var ship: CapitalShip = flown[row]
		ship.cruise_velocity = velocities[row]
		if ship.needs_hulk_command():
			var shaped: FlightCommand = ship.hulk_command(_unpack(scalars, vectors, flags, row))
			FlightBatch.pack_command(shaped, Vector3.ZERO, ship.flight_assist(), true, scalars, vectors, flags, row)
	_commands = [scalars, vectors, flags]
	if bool(_step.step_core(sim.core, slots, bodies, scalars, vectors, flags, delta)):
		out_vectors = _step.out_vectors()
		out_scalars = _step.out_scalars()
		_out_slots = _step.out_slots()
	else:
		flown.clear()
	last_us = Time.get_ticks_usec() - started


# A ship was disabled: it joins the hulks, and the ones that are no longer hulks (destroyed, whole again) leave.
func _on_ship_disabled(ship: CapitalShip) -> void:
	for key: int in hulks.keys():
		var other: CapitalShip = CapitalShip.of_body(key)
		if other == null or not other.is_hulk():
			hulks.remove(key)
	hulks.add(ship.get_instance_id())


# Row `row`'s helm command as a `FlightCommand` (the few disabled hulls that shape it).
static func _unpack(scalars: PackedFloat64Array, vectors: PackedVector3Array, flags: PackedByteArray, row: int) -> FlightCommand:
	var cmd := FlightCommand.new()
	var s: int = row * FlightBatch.CMD_SCALARS
	cmd.main_right = scalars[s]
	cmd.main_left = scalars[s + 1]
	cmd.retro_right = scalars[s + 2]
	cmd.retro_left = scalars[s + 3]
	var v: int = row * FlightBatch.CMD_VECTORS
	cmd.strafe = Vector2(vectors[v].x, vectors[v].y)
	cmd.rot = vectors[v + 1]
	cmd.brake = flags[row * FlightBatch.CMD_FLAGS] != 0
	return cmd


func _native() -> Object:
	if _step == null:
		_step = NativeLib.instantiate(FlightBatch.NATIVE_CLASS)
		for ship: CapitalShip in _ships:
			_register(ship)
	return _step


func _register(ship: CapitalShip) -> void:
	if _step == null or ship.flight_slot >= 0:
		return
	ship.flight_slot = FlightBatch.register_slot(_step, ship.get_rid(), ship.flight_spec, ship.layout)


func _unregister(ship: CapitalShip) -> void:
	if ship.flight_slot >= 0 and _step != null:
		_step.unregister(ship.flight_slot)
	ship.flight_slot = -1
