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
## A carrier with no power (a hulk, M10-T65, Q78) takes nobody in: a recall is refused and a fighter on its way back is let go.
##
## M10-T17: a capital carrier's bays are flown the same way (`CapitalHangar` extends this node; its cradles are `BayBerths`):
## a launch runs out of the mouth (from a lift first, in the Nova), a recall is drawn in through it once `capture_gate` lets it
## (its door open, its wings folded), and a craft drawn into a bay with a lift waits on the floor until `begin_lower`. Bay craft
## are not drawn by the dock: once docked they go back to their pool (`take_from`).

## A fighter left its cradle and flies on its own again.
signal launched(ship: Ship)
## A fighter called back sits on its cradle.
signal docked(ship: Ship)
## A fighter called back will not make it: destroyed, gone from play, or let go (`abandon`).
signal gave_up(ship: Ship)
## A bay's lift brought `ship` up to the floor: its run out begins (M10-T17).
signal lifted(ship: Ship, cradle: int)
## `ship` was drawn into a bay with a lift and waits on its floor for `begin_lower` (M10-T17).
signal in_bay(ship: Ship, cradle: int)

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

## A returning fighter follows the carrier's turning only within this of it, m; by twice this it flies the straight way.
const TURN_FRAME_M: float = 400.0

const PHASE_LAUNCH: int = 0
const PHASE_RETURN: int = 1
const PHASE_CAPTURE: int = 2
const PHASE_LIFT: int = 3
const PHASE_LOWER: int = 4
const PHASE_HOLD: int = 5
const EVENT_RELEASED: int = 1
const EVENT_AT_APPROACH: int = 2
const EVENT_DOCKED: int = 3
const EVENT_LIFTED: int = 4
const EVENT_IN_BAY: int = 5

var cradles: CarrierCradles = CarrierCradles.new()
## Counts so far, for tests and the console.
var launches: int = 0
var dockings: int = 0
var lost_docked: int = 0
## Launches of `launch_all` leave this far apart, s.
var launch_gap_s: float = LAUNCH_GAP_S
## `func(ship: Ship, cradle: int) -> bool`: whether a returning craft at its approach point may be drawn in now (none: always).
var capture_gate: Callable = Callable()

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
	var hull: Damageable = Damageable.of(get_parent())
	if hull != null:
		hull.destroyed.connect(_on_carrier_destroyed)
	set_physics_process(false)
	if cradles.is_bays():
		return  # bay craft are pooled ships, not drawn on a pad
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


## Whether the carrier can take fighters in: not a hulk (Q78). The bench's boxes always can.
func has_power() -> bool:
	var body := get_parent() as CapitalBody
	return body == null or not body.is_hulk()


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


## Launches every docked fighter in the same tick, none waiting its turn (M8-T08: a carrier under attack that cannot jump
## away). Returns how many left their cradles.
func scramble() -> int:
	var sent: int = 0
	_queue.clear()
	for i: int in cradles.count():
		if cradles.states[i] != CarrierCradles.State.DOCKED:
			continue
		_launch(i)
		sent += 1 if cradles.states[i] == CarrierCradles.State.BUSY else 0
	set_physics_process(not _held.is_empty())
	return sent


## Calls `ship` back to a free cradle (the one nearest to it): its pilot is held and the dock flies it in. False when it
## cannot (no free cradle, no power, or the ship is already here). Bays: only a cradle that takes its craft `type` and that
## `usable` allows (a bay that works).
func recall(ship: Ship, type: StringName = &"", usable: Callable = Callable()) -> bool:
	if ship == null or not is_instance_valid(ship) or is_docked(ship) or is_handling(ship) or not ship.is_visible_in_tree() \
			or not has_power():
		return false
	var local: Vector3 = carrier().global_transform.affine_inverse() * ship.global_position
	var index: int = cradles.nearest_taking(local, type, usable) if cradles.is_bays() else cradles.nearest_free(local, type, usable)
	return recall_to(ship, index)


## Calls `ship` back to cradle `index`. A pad must be free; a bay's lane need not be, since the craft wait their turn at its
## approach point and the lane is only kept while one is drawn in.
func recall_to(ship: Ship, index: int) -> bool:
	if ship == null or not is_instance_valid(ship) or is_docked(ship) or is_handling(ship) or not ship.is_visible_in_tree() \
			or not has_power() or index < 0 or index >= cradles.count():
		return false
	if not cradles.is_bays() and cradles.states[index] != CarrierCradles.State.FREE:
		return false
	_hold(ship, index, true)
	_add_row(ship, PHASE_RETURN, index)
	set_physics_process(true)
	return true


## Sends `ship`, a craft just brought into play, out of cradle `index` at once (M10-T17: a bay's launch; from its lift first
## when it has one). False when the cradle is not free.
func launch_ship(ship: Ship, index: int) -> bool:
	if ship == null or index < 0 or index >= cradles.count() or cradles.states[index] != CarrierCradles.State.FREE \
			or is_handling(ship):
		return false
	_since_launch_s = 0.0
	var body: RigidBody3D = carrier()
	var start: Transform3D = cradles.docked_transform(index, rest_of(ship))
	if cradles.is_bays() and cradles.lift_m[index] > 0.0:
		start.origin -= cradles.bases[index].y * cradles.lift_m[index]
	ship.reset_to(body.global_transform * start)
	ship.linear_velocity = body.linear_velocity
	ship.add_collision_exception_with(body)
	_hold(ship, index, false)
	_add_row(ship, PHASE_LAUNCH, index)
	set_physics_process(true)
	return true


## The lift takes `ship`, waiting on a bay's floor, down to the hangar deck; it docks at the bottom.
func begin_lower(ship: Ship) -> void:
	if ship != null and is_handling(ship):
		_rows.begin_lower(ship.get_instance_id())


## Takes the craft docked on cradle `index` off it, still out of play, and frees the cradle: its pool takes it back. Null when
## none sits there.
func take_from(index: int) -> Ship:
	var ship: Ship = _on_cradle[index] if index >= 0 and index < _on_cradle.size() else null
	if ship == null:
		return null
	_on_cradle[index] = null
	cradles.set_state(index, CarrierCradles.State.FREE)
	_show(index, false)
	if is_instance_valid(ship) and ship.has_meta(DOCKED_META):
		ship.remove_meta(DOCKED_META)
		_release_pilot(ship)
	return ship if is_instance_valid(ship) else null


## The cradle `ship` is launching from or coming back to, -1 when the dock does not hold it.
func cradle_of(ship: Ship) -> int:
	var entry: Dictionary = _held.get(ship.get_instance_id(), {}) if ship != null else {}
	return int(entry.get("cradle", -1))


## The ships the dock holds now, launching or coming back.
func held_ships() -> Array[Ship]:
	var out: Array[Ship] = []
	for entry: Dictionary in _held.values():
		if is_instance_valid(entry["ship"]):
			out.append(entry["ship"] as Ship)
	return out


## The point of `ship` that meets the floor or pad: a pad's fighter is the carrier's one kind; a bay's craft its own hull's.
func rest_of(ship: Ship) -> Vector3:
	if not cradles.is_bays() or ship == null:
		return _rest
	var mesh: Mesh = ship.hull_mesh()
	return CarrierCradles.rest_point(mesh.get_aabb(), DOCK_GAP_M) if mesh != null else Vector3.ZERO


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
	if not _queue.is_empty() and _since_launch_s >= launch_gap_s:
		_launch(_queue.pop_front())
	if not _held.is_empty():  # every row is a held ship's
		_step_rows(delta)
	set_physics_process(not _queue.is_empty() or not _held.is_empty())


# One tick of the ships under the dock's control: the kernel says where each goes, this applies it.
func _step_rows(delta: float) -> void:
	if not has_power():
		abandon()  # the carrier went dark: a docking under way aborts at once (Q78)
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
			# The kernel flies it in the carrier's turning frame, which is right beside the hull only: kilometres out a
			# slow turn of the carrier asked for hundreds of m/s sideways, and the fighter flew off for good.
			var offset: Vector3 = ship.global_position - body.global_position
			var far: float = clampf((offset.length() - TURN_FRAME_M) / TURN_FRAME_M, 0.0, 1.0)
			_steer(ship, entry["capability"], vel[i] - body.angular_velocity.cross(offset) * far, -basis.z)
			if events[i] == EVENT_AT_APPROACH and _may_capture(ship, entry):
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
			ship.remove_collision_exception_with(body)
			_settle(ship, int(entry["cradle"]))  # reads the hold's tier exemption before it lets the hold go
			docked.emit(ship)
		elif events[i] == EVENT_LIFTED:
			lifted.emit(ship, int(entry["cradle"]))
		elif events[i] == EVENT_IN_BAY:
			in_bay.emit(ship, int(entry["cradle"]))


# Whether a returning ship at its approach point is drawn in now: a bay's lane must be free and is kept from then on, and the
# gate (doors, folds, lifts) must agree.
func _may_capture(ship: Ship, entry: Dictionary) -> bool:
	var index: int = int(entry["cradle"])
	if cradles.is_bays() and cradles.states[index] != CarrierCradles.State.FREE:
		return false
	if capture_gate.is_valid() and not bool(capture_gate.call(ship, index)):
		return false
	cradles.set_state(index, CarrierCradles.State.BUSY)
	entry["owns"] = true
	return true


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
	var tier_exempt: bool = bool(ship.get_meta(DOCKED_META))  # as it was before it docked (a mission's ship stays exempt)
	ship.remove_meta(DOCKED_META)
	ShiftableRegistry.set_out(ship, WorldFrame.PARKED_META, false)
	ship.process_mode = Node.PROCESS_MODE_INHERIT
	ship.visible = true
	ship.reset_to(body.global_transform * cradles.docked_transform(index, _rest))
	ship.linear_velocity = body.linear_velocity
	ship.add_collision_exception_with(body)
	cradles.set_state(index, CarrierCradles.State.BUSY)
	_held[ship.get_instance_id()] = {"ship": ship, "cradle": index, "returning": false, "flying": false,
			"capability": ShipCapability.from_spec(ship.spec, ship.get_layout()), "tier_exempt": tier_exempt}
	_add_row(ship, PHASE_LAUNCH, index)


# Puts `ship` on the rows in `phase` for cradle `index`: a pad's row, or a bay's with its way out, run and lift.
func _add_row(ship: Ship, phase: int, index: int) -> void:
	var key: int = ship.get_instance_id()
	if not cradles.is_bays():
		_rows.add(key, phase, cradles.positions[index], cradles.bases[index], cradles.approach_m[index], _rest)
		return
	_rows.add_bay(key, phase, cradles.positions[index], cradles.bases[index], cradles.out_axes[index], cradles.approach_m[index],
			cradles.launch_m[index], cradles.lift_m[index], rest_of(ship))


# Takes `ship`'s pilot out of the loop and keeps cradle `index` for it (a bay's lane only once it is drawn in).
func _hold(ship: Ship, index: int, returning: bool) -> void:
	var owns: bool = not (returning and cradles.is_bays())
	if owns:
		cradles.set_state(index, CarrierCradles.State.BUSY)
	var driver: AiPilotDriver = _driver_of(ship)
	if driver != null:
		driver.in_passage = true
		if driver.combatant != null:
			driver.combatant.apply_commands(FlightCommand.new(), CombatCommand.new())
	_held[ship.get_instance_id()] = {"ship": ship, "cradle": index, "returning": returning, "flying": returning, "owns": owns,
			"capability": ShipCapability.from_spec(ship.spec, ship.get_layout()), "tier_exempt": ship.tier_exempt}
	ship.tier_exempt = true


# `ship` sits on cradle `index` from now on: out of play, drawn by the dock.
func _settle(ship: Ship, index: int) -> void:
	var tier_exempt: bool = bool((_held.get(ship.get_instance_id(), {}) as Dictionary).get("tier_exempt", false))
	_held.erase(ship.get_instance_id())
	_rows.remove(ship.get_instance_id())
	_on_cradle[index] = ship
	cradles.set_state(index, CarrierCradles.State.DOCKED)
	ship.set_meta(DOCKED_META, tier_exempt)  # what its tier exemption was, for its next launch
	ship.visible = false
	ship.process_mode = Node.PROCESS_MODE_DISABLED
	ShiftableRegistry.set_out(ship, WorldFrame.PARKED_META, true)
	ship.global_position = carrier().global_position  # where it is, for whoever asks how far away it is
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
	if bool(entry.get("owns", true)):
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
	MultiMeshUpload.set_instance_transform(_multimesh, index,
			xform if shown else Transform3D(Basis.from_scale(Vector3.ZERO), xform.origin))


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
