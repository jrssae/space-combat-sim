class_name CarrierDock
extends Node3D
## A carrier's docking (M12-T19, Q27, Q29): the fighters on its cradles, the ones it is launching and the ones it has called
## back. A child of the carrier, built from the hull's cradles (`CarrierCradles`).
##
## A docked fighter is a pooled ship kept out of play (hidden, out of Jolt, its pilot held) and drawn on its cradle as one
## instance of the dock's multimesh, so it rides with the carrier for nothing and dies with it. A launch brings the ship back at
## its cradle and pushes it straight out before its pilot is let go. A fighter called back is flown to its cradle's approach
## point and then drawn in onto the pad. The paths are the native kernel's (`ScsDockRows`, `native/src/dock_kernels.rs`); this
## node only moves the ships it is told to.
##
## While a ship is launched or drawn in it does not collide with the carrier (it passes within centimetres of its pad).

## A fighter left its cradle and flies on its own again.
signal launched(ship: Ship)
## A fighter called back sits on its cradle.
signal docked(ship: Ship)
## A fighter called back will not make it: destroyed, gone from play, or let go (`abandon`).
signal gave_up(ship: Ship)

const FIGHTER_ASSET: String = "raider_fighter"
const DOCKED_META: StringName = &"_scs_docked"
## The gap kept between a docked fighter's belly and its pad, m.
const DOCK_GAP_M: float = 0.05
## Launches of `launch_all` leave this far apart, s.
const LAUNCH_GAP_S: float = 0.35
## A returning fighter keeps this far outside the carrier's hull while it flies round to its cradle's side, m.
const SHELL_MARGIN_M: float = 40.0
## A returning fighter turns its nose onto its velocity error while that is larger than this, else onto its docked heading.
const FACE_DV_MPS: float = 30.0

const PHASE_LAUNCH: int = 0
const PHASE_RETURN: int = 1
const EVENT_RELEASED: int = 1
const EVENT_AT_APPROACH: int = 2
const EVENT_DOCKED: int = 3

var cradles: CarrierCradles = CarrierCradles.new()
## Counts so far, for tests and the console.
var launches: int = 0
var dockings: int = 0
var lost_docked: int = 0

var _rows: ScsDockRows = ScsDockRows.new()
var _held: Dictionary = {}  # the ship's instance id -> {ship, cradle, driver, capability, tier_exempt}
var _on_cradle: Array[Ship] = []  # per cradle, the ship docked on it (null: none)
var _queue: Array[int] = []  # cradles waiting their turn to launch
var _since_launch_s: float = INF
var _rest: Vector3 = Vector3.ZERO  # the point of a fighter that meets the pad
var _multimesh: MultiMesh = null


## Takes the hull's cradles. Call before the node enters the tree.
func setup(p_cradles: CarrierCradles) -> void:
	cradles = p_cradles
	_on_cradle.resize(cradles.count())
	_on_cradle.fill(null)


func _ready() -> void:
	var mesh: Mesh = MeshAssets.for_asset(FIGHTER_ASSET)
	var bounds: AABB = mesh.get_aabb() if mesh != null else AABB(Vector3(-8.5, -0.8, -4.3), Vector3(17.0, 2.0, 7.2))
	_rest = CarrierCradles.rest_point(bounds, DOCK_GAP_M)
	if mesh != null:
		_multimesh = MultiMesh.new()
		_multimesh.transform_format = MultiMesh.TRANSFORM_3D
		_multimesh.mesh = mesh
		_multimesh.instance_count = cradles.count()
		var shown := MultiMeshInstance3D.new()
		shown.name = "Docked"
		shown.multimesh = _multimesh
		add_child(shown)
		for i: int in cradles.count():
			_show(i, false)
	var hull: Damageable = Damageable.of(get_parent())
	if hull != null:
		hull.destroyed.connect(_on_carrier_destroyed)
	set_physics_process(false)


func carrier() -> RigidBody3D:
	return get_parent() as RigidBody3D


## Fighters sitting on cradles, cradles free, and fighters being launched or on their way back.
func docked_count() -> int:
	return cradles.count_in(CarrierCradles.State.DOCKED)


func free_count() -> int:
	return cradles.count_in(CarrierCradles.State.FREE)


func busy_count() -> int:
	return _held.size()


## Fighters called back and not yet docked.
func returning_count() -> int:
	var n: int = 0
	for entry: Dictionary in _held.values():
		n += 1 if bool(entry["returning"]) else 0
	return n


## Whether `ship` sits on a cradle, or is under the dock's control (launching or coming back).
func is_docked(ship: Ship) -> bool:
	return ship != null and _on_cradle.has(ship)


func is_handling(ship: Ship) -> bool:
	return ship != null and _held.has(ship.get_instance_id())


## Puts `ship` (a pooled fighter in play) on a free cradle at once: how a raid's fighters come in docked (Q29). False when
## no cradle is free.
func dock_now(ship: Ship) -> bool:
	var index: int = cradles.first_in(CarrierCradles.State.FREE)
	if ship == null or index < 0 or is_docked(ship) or is_handling(ship):
		return false
	_hold(ship, index, false)
	_settle(ship, index)
	return true


## Launches every docked fighter, one after another. Returns how many this call sent on their way.
func launch_all() -> int:
	var added: int = 0
	for i: int in cradles.count():
		if cradles.states[i] == CarrierCradles.State.DOCKED and not _queue.has(i):
			_queue.append(i)
			added += 1
	set_physics_process(not _queue.is_empty() or not _held.is_empty())
	return added


## Calls `ship` back to a free cradle (the one nearest to it): its pilot is held and the dock flies it in. False when it
## cannot (no free cradle, or the ship is already here).
func recall(ship: Ship) -> bool:
	if ship == null or not is_instance_valid(ship) or is_docked(ship) or is_handling(ship) or not ship.is_visible_in_tree():
		return false
	var body: RigidBody3D = carrier()
	var index: int = cradles.nearest_free(body.global_transform.affine_inverse() * ship.global_position)
	if index < 0:
		return false
	_hold(ship, index, true)
	_rows.add(ship.get_instance_id(), PHASE_RETURN, cradles.positions[index], cradles.bases[index], cradles.approach_m[index], _rest)
	set_physics_process(true)
	return true


## Lets go of every fighter still on its way back (the carrier will not wait): each flies on its own again. Returns them.
func abandon() -> Array[Ship]:
	var out: Array[Ship] = []
	for key: int in _held.keys():
		var entry: Dictionary = _held[key]
		if bool(entry["returning"]):
			out.append(entry["ship"] as Ship)
			_let_go(key, true)
	return out


## Takes every docked fighter off its cradle and returns them, still out of play: the carrier has left, and their pool takes
## them back.
func take_docked() -> Array[Ship]:
	var out: Array[Ship] = []
	_queue.clear()
	for i: int in cradles.count():
		var ship: Ship = _on_cradle[i]
		if ship != null:
			if is_instance_valid(ship) and ship.has_meta(DOCKED_META):
				ship.remove_meta(DOCKED_META)
				_release_pilot(ship)
				out.append(ship)
			_on_cradle[i] = null
			cradles.set_state(i, CarrierCradles.State.FREE)
			_show(i, false)
	return out


## Empties the dock: every hold let go, every cradle free. Docked ships are returned as `take_docked` does.
func reset() -> Array[Ship]:
	for key: int in _held.keys():
		_let_go(key, false)
	_rows.clear()
	return take_docked()


func _physics_process(delta: float) -> void:
	_since_launch_s += delta
	if not _queue.is_empty() and _since_launch_s >= LAUNCH_GAP_S:
		_launch(_queue.pop_front())
	_step_rows(delta)
	set_physics_process(not _queue.is_empty() or not _held.is_empty())


# One tick of the ships under the dock's control: the kernel says where each goes, this applies it.
func _step_rows(delta: float) -> void:
	var keys: PackedInt64Array = _rows.keys()
	for key: int in keys:  # a ship that died or left play on the way is dropped first
		var entry: Dictionary = _held.get(key, {})
		var gone: Ship = entry.get("ship") as Ship
		if entry.is_empty() or not is_instance_valid(gone) or not gone.is_inside_tree() or not gone.is_visible_in_tree() \
				or JumpCapability.is_destroyed(gone):
			_let_go(key, true)
	keys = _rows.keys()
	if keys.is_empty():
		return
	var body: RigidBody3D = carrier()
	var positions := PackedVector3Array()
	var velocities := PackedVector3Array()
	var brakes := PackedFloat32Array()
	for key: int in keys:
		var ship: Ship = _held[key]["ship"]
		positions.append(ship.global_position)
		velocities.append(ship.linear_velocity)
		brakes.append((_held[key]["capability"] as ShipCapability).a_main)
	var hull: Damageable = Damageable.of(body)
	var shell_m: float = (hull.bounding_radius if hull != null else 0.0) + SHELL_MARGIN_M
	var out: Array = _rows.step(delta, body.global_position, body.global_basis.orthonormalized(), body.linear_velocity,
			body.angular_velocity, shell_m, positions, velocities, brakes)
	if out.size() < 6:
		return
	var events: PackedInt32Array = out[0]
	var at: PackedVector3Array = out[1]
	var vel: PackedVector3Array = out[2]
	for i: int in keys.size():
		var key: int = keys[i]
		var entry: Dictionary = _held[key]
		var ship: Ship = entry["ship"]
		var basis := Basis(out[3][i], out[4][i], out[5][i])
		if bool(entry["flying"]):
			_steer(ship, entry["capability"], vel[i], -basis.z)
			if events[i] == EVENT_AT_APPROACH:
				entry["flying"] = false
				ship.add_collision_exception_with(body)
				var inverse: Transform3D = body.global_transform.affine_inverse()
				_rows.begin_capture(key, inverse * ship.global_position, (inverse.basis * ship.global_basis).orthonormalized())
			continue
		ship.global_transform = Transform3D(basis, at[i])
		ship.linear_velocity = vel[i]
		ship.angular_velocity = body.angular_velocity
		if events[i] == EVENT_RELEASED:
			launches += 1
			cradles.set_state(int(entry["cradle"]), CarrierCradles.State.FREE)
			_let_go(key, false)
			launched.emit(ship)
		elif events[i] == EVENT_DOCKED:
			dockings += 1
			_held.erase(key)
			ship.remove_collision_exception_with(body)
			_settle(ship, int(entry["cradle"]))
			docked.emit(ship)


# The command that brings a returning ship's velocity to `wanted` (World), its nose on the change or, near it, on `course`.
func _steer(ship: Ship, capability: ShipCapability, wanted: Vector3, course: Vector3) -> void:
	var cmd := FlightCommand.new()
	var change: Vector3 = wanted - ship.linear_velocity
	var nose: Vector3 = change if change.length() > FACE_DV_MPS else course
	if nose.length() > 1e-6:
		cmd.rot = PilotSteering.face(ship.global_basis, nose, capability.rate_max_rad)
	PilotSteering.apply_seek(cmd, PilotSteering.seek(ship.linear_velocity, wanted, ship.global_basis, capability))
	ship.set_flight_command(cmd)


# Brings the fighter on cradle `index` back into play there and starts its launch.
func _launch(index: int) -> void:
	_since_launch_s = 0.0
	var ship: Ship = _on_cradle[index]
	_on_cradle[index] = null
	_show(index, false)
	if ship == null or not is_instance_valid(ship) or not ship.has_meta(DOCKED_META):
		cradles.set_state(index, CarrierCradles.State.FREE)  # its pool took it back meanwhile
		return
	var body: RigidBody3D = carrier()
	ship.remove_meta(DOCKED_META)
	ShiftableRegistry.set_out(ship, WorldFrame.PARKED_META, false)
	ship.process_mode = Node.PROCESS_MODE_INHERIT
	ship.visible = true
	ship.reset_to(body.global_transform * cradles.docked_transform(index, _rest))
	ship.linear_velocity = body.linear_velocity
	ship.add_collision_exception_with(body)
	cradles.set_state(index, CarrierCradles.State.BUSY)
	_held[ship.get_instance_id()] = {"ship": ship, "cradle": index, "returning": false, "flying": false,
			"capability": ShipCapability.from_spec(ship.spec, ship.get_layout()), "tier_exempt": false}
	_rows.add(ship.get_instance_id(), PHASE_LAUNCH, cradles.positions[index], cradles.bases[index], cradles.approach_m[index], _rest)


# Takes `ship`'s pilot out of the loop and keeps cradle `index` for it.
func _hold(ship: Ship, index: int, returning: bool) -> void:
	cradles.set_state(index, CarrierCradles.State.BUSY)
	var driver: AiPilotDriver = _driver_of(ship)
	if driver != null:
		driver.in_passage = true
		if driver.combatant != null:
			driver.combatant.apply_commands(FlightCommand.new(), CombatCommand.new())
	_held[ship.get_instance_id()] = {"ship": ship, "cradle": index, "returning": returning, "flying": returning,
			"capability": ShipCapability.from_spec(ship.spec, ship.get_layout()), "tier_exempt": ship.tier_exempt}
	ship.tier_exempt = true


# `ship` sits on cradle `index` from now on: out of play, drawn by the dock.
func _settle(ship: Ship, index: int) -> void:
	_held.erase(ship.get_instance_id())
	_rows.remove(ship.get_instance_id())
	_on_cradle[index] = ship
	cradles.set_state(index, CarrierCradles.State.DOCKED)
	ship.set_meta(DOCKED_META, true)
	ship.visible = false
	ship.process_mode = Node.PROCESS_MODE_DISABLED
	ShiftableRegistry.set_out(ship, WorldFrame.PARKED_META, true)
	ship.linear_velocity = Vector3.ZERO
	ship.angular_velocity = Vector3.ZERO
	_show(index, true)


# Ends the dock's control of the ship `key`: its pilot flies it again, its cradle is free. With `failed` it never docked.
func _let_go(key: int, failed: bool) -> void:
	var entry: Dictionary = _held.get(key, {})
	_held.erase(key)
	_rows.remove(key)
	if entry.is_empty():
		return
	cradles.set_state(int(entry["cradle"]), CarrierCradles.State.FREE)
	var ship: Ship = entry["ship"] as Ship
	if not is_instance_valid(ship):
		return
	var body: RigidBody3D = carrier()
	if body != null:
		ship.remove_collision_exception_with(body)
	ship.tier_exempt = bool(entry["tier_exempt"])
	_release_pilot(ship)
	if failed:
		gave_up.emit(ship)


func _release_pilot(ship: Ship) -> void:
	var driver: AiPilotDriver = _driver_of(ship)
	if driver != null:
		driver.in_passage = false


static func _driver_of(ship: Node) -> AiPilotDriver:
	for child: Node in ship.get_children():
		if child is AiPilotDriver:
			return child as AiPilotDriver
	return null


# Draws or hides the docked fighter on cradle `index`.
func _show(index: int, shown: bool) -> void:
	if _multimesh == null:
		return
	var xform: Transform3D = cradles.docked_transform(index, _rest)
	_multimesh.set_instance_transform(index, xform if shown else Transform3D(Basis.from_scale(Vector3.ZERO), xform.origin))


# The carrier died: its docked fighters die with it, each where it sat (Q28); the others are let go.
func _on_carrier_destroyed(_info: HitInfo) -> void:
	var body: RigidBody3D = carrier()
	_queue.clear()
	for key: int in _held.keys():
		_let_go(key, true)
	for i: int in cradles.count():
		var ship: Ship = _on_cradle[i]
		_on_cradle[i] = null
		cradles.set_state(i, CarrierCradles.State.FREE)
		_show(i, false)
		if ship == null or not is_instance_valid(ship) or not ship.has_meta(DOCKED_META):
			continue
		ship.remove_meta(DOCKED_META)
		ShiftableRegistry.set_out(ship, WorldFrame.PARKED_META, false)
		ship.process_mode = Node.PROCESS_MODE_INHERIT
		ship.visible = true
		ship.reset_to(body.global_transform * cradles.docked_transform(i, _rest))
		ship.linear_velocity = body.linear_velocity
		_release_pilot(ship)
		lost_docked += 1
		var hull: Damageable = Damageable.of(ship)
		if hull != null:
			hull.kill(HitInfo.CAUSE_CARRIER_LOST)
