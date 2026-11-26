class_name ShipDock
extends Node3D
## A capital ship's docking collars (M10-T53, Q84): small craft with a lock of their own (the crew shuttle's stern hatch) fly
## to a collar, back onto it, ride mated with the ship and leave again. A child of every `CapitalShip` whose hull has
## `docking_ports`; M8-T06's docking autopilot and keep-out fly the craft, in the hull's frame instead of the station's.
##
## A visit (`DockVisit`): **approach** round the hull's keep-out boxes to the start of the collar's lane, **lane** (the craft
## turns as it will lie mated, nose out, and backs down the collar's axis), **inside** (mated: held on the collar, moving with
## the ship), **launching** (out along the lane until it is let go). An AI craft's pilot is held for the whole visit and the
## dock commands its ship; the player's command comes from `command_for` through `ShipDocks.step_player`.
##
## The ship holds station while craft dock (Q84): no visit starts while it is under way, without power or lost.
## Console: `shipdock`, provider `ship_docks` (`ShipDocks`).

## `craft` is mated on collar `port`.
signal docked(craft: Ship, port: int)
## `craft` left collar `port` and flies on its own again.
signal undocked(craft: Ship, port: int)
## `craft`'s visit ended before it mated (cancelled, timed out, lost).
signal gave_up(craft: Ship, reason: String)

const NODE_NAME: StringName = &"ShipDock"
const GROUP: StringName = &"ship_docks"
const LABEL_DOCK: String = "DOCK"

var ship: CapitalShip = null
var ports: ShipDockPorts = ShipDockPorts.new()
var options: Dictionary = {}
## The place the player targets to dock (HOLD X), ahead of the collars.
var nav: NavPoint = null
## Counts so far, for tests and the console.
var dockings: int = 0
var undockings: int = 0
var given_up: int = 0
## Its own cost so far: ticks with a visit and their time, us (a readout).
var ticks: int = 0
var tick_us: float = 0.0

var _entries: Array[Dictionary] = []  # each {visit, craft, port, lock, mate, capability, cautious, way, driver, tier_exempt, assist, excepted}


## A dock for `capital` from its hull's collars; null when it has none. Call before it enters the tree.
static func make(capital: CapitalShip) -> ShipDock:
	var found: ShipDockPorts = ShipDockPorts.of(capital.hardpoints())
	if found.count() == 0:
		return null
	var dock := ShipDock.new()
	dock.name = NODE_NAME
	dock.ship = capital
	dock.ports = found
	dock.options = ShipDockRules.options(capital.type_id)
	return dock


## The dock of `capital`, or null.
static func of(capital: Node) -> ShipDock:
	return capital.get_node_or_null(NodePath(NODE_NAME)) as ShipDock if capital != null else null


## A craft's own lock (`ShipDockPorts.craft_port` of its hardpoints), empty when its hull has none.
static func lock_of(craft: Ship) -> Dictionary:
	if craft == null or craft.spec == null:
		return {}
	var loaded: Hardpoints = Hardpoints.load_file(craft.spec.hardpoints_path())
	return ShipDockPorts.craft_port(loaded.raw) if loaded != null and loaded.valid else {}


func _ready() -> void:
	add_to_group(GROUP)
	set_physics_process(false)
	var hull: Damageable = Damageable.of(ship)
	if hull != null:
		hull.destroyed.connect(_on_hull_destroyed)
	var middle := Vector3.ZERO
	for i: int in ports.count():
		middle += (ports.positions[i] + ports.outs[i] * 20.0) / float(ports.count())
	var act := TargetInteraction.new(NavPoint.KIND_DOCK, LABEL_DOCK, _player_action, Callable(), float(options["range_m"]))
	nav = NavPoint.make("%s DOCKING COLLARS" % ship.targetable.display_name, act, CapitalData.broadcast_range_m(ship.capital_class))
	nav.class_text = "Docking collars"
	nav.home_id = StringName(ship.targetable.display_name)
	nav.position = middle
	add_child(nav)


# --- asking --------------------------------------------------------------------------------------------------------------


## Whether collar `port` is kept for a craft (on its way, mated or leaving).
func is_taken(port: int) -> bool:
	for entry: Dictionary in _entries:
		if int(entry["port"]) == port:
			return true
	return false


func free_count() -> int:
	var n: int = 0
	for i: int in ports.count():
		n += 0 if is_taken(i) else 1
	return n


## Craft mated now.
func docked_count() -> int:
	var n: int = 0
	for entry: Dictionary in _entries:
		n += 1 if (entry["visit"] as DockVisit).state == DockVisit.State.INSIDE else 0
	return n


## Whether any craft is on its way in, mated or leaving: a ship with visitors stays where it is (stage 3's traffic asks).
func is_busy() -> bool:
	return not _entries.is_empty()


## The visit of `craft`, or null.
func visit_of(craft: Ship) -> DockVisit:
	var entry: Dictionary = _entry_of(craft)
	return entry["visit"] if not entry.is_empty() else null


## The collar `craft` is bound for or mated on, -1 when it is not visiting.
func port_of(craft: Ship) -> int:
	var entry: Dictionary = _entry_of(craft)
	return int(entry["port"]) if not entry.is_empty() else -1


## How far `craft` is from its mated place, m (INF when it is not visiting).
func distance_left(craft: Ship) -> float:
	var entry: Dictionary = _entry_of(craft)
	if entry.is_empty() or not is_instance_valid(craft):
		return INF
	return craft.global_position.distance_to(ship.global_transform * (entry["mate"] as Transform3D).origin)


## Every visit as a line: the craft, its collar, its state and how far it has to go.
func describe_visits() -> PackedStringArray:
	var lines := PackedStringArray()
	for entry: Dictionary in _entries:
		var visit: DockVisit = entry["visit"]
		lines.append("%s -> %s, %.0f m, %.0f s" % [visit.describe(), ports.names[int(entry["port"])],
				distance_left(entry["craft"]), visit.total_s])
	return lines


func visits() -> Array[DockVisit]:
	var out: Array[DockVisit] = []
	for entry: Dictionary in _entries:
		out.append(entry["visit"])
	return out


## Why nobody can dock here now, or "": the ship holds station with its power on (Q84, Q78).
func closed_reason() -> String:
	if ship == null or not is_instance_valid(ship) or JumpCapability.is_destroyed(ship):
		return "the ship is lost"
	if ship.is_hulk():
		return "%s has no power" % ship.targetable.display_name
	var world: WorldFrame = WorldFrame.of(ship)
	var rest: Vector3 = world.rest_velocity() if world != null else Vector3.ZERO
	if ShipDockRules.under_way((ship.linear_velocity - rest).length(), options):
		return "%s is under way" % ship.targetable.display_name
	return ""


## Why `craft` cannot dock at collar `port` (-1: any free one), or "".
func refusal(craft: Ship, port: int = -1) -> String:
	if craft == null or not is_instance_valid(craft) or not craft.is_visible_in_tree():
		return "no such craft in play"
	if not _entry_of(craft).is_empty():
		return "it is docking here already"
	if lock_of(craft).is_empty():
		return "a %s has no docking lock (it lands in bays)" % (craft.spec.asset_id if craft.spec != null else "craft")
	var closed: String = closed_reason()
	if not closed.is_empty():
		return closed
	if port >= ports.count():
		return "no such collar"
	if port >= 0 and is_taken(port):
		return "%s is taken" % ports.names[port]
	if port < 0 and free_count() == 0:
		return "every collar is taken"
	return ""


## Has the ship hold where it is, at rest against the place (the console and missions call it before a docking).
func hold_station() -> void:
	var world: WorldFrame = WorldFrame.of(ship)
	if world != null:
		ship.set_course(Vector3.ZERO, world.rest_velocity())


# --- visits --------------------------------------------------------------------------------------------------------------


## Sends `craft` to collar `port` (-1: the free one nearest to it). An AI craft's pilot is held and the dock flies it; with
## `is_player` the caller flies `command_for`. Returns "" or why not.
func start(craft: Ship, port: int = -1, is_player: bool = false, why: StringName = DockVisit.WHY_ORDER) -> String:
	var refused: String = refusal(craft, port)
	if not refused.is_empty():
		return refused
	var local: Vector3 = ship.global_transform.affine_inverse() * craft.global_position
	var index: int = port if port >= 0 else ports.nearest_free(local, _taken())
	var lock: Dictionary = lock_of(craft)
	var gap: float = float(options["gap_m"])
	var entry: Dictionary = {
		"visit": DockVisit.new(_label(craft), is_player, why), "craft": craft, "port": index, "lock": lock,
		"mate": ports.mate(index, lock, gap), "capability": ShipCapability.from_spec(craft.spec, craft.get_layout()),
		"cautious": ShipDockRules.cautious(ShipCapability.from_spec(craft.spec, craft.get_layout()), options),
		"way": ShipDockRules.keep_out(options, ports.lane_point(index, lock, gap, float(options["join_out_m"]))),
		"driver": _driver_of(craft), "tier_exempt": craft.tier_exempt, "assist": craft.assist_on, "excepted": false,
	}
	var driver: AiPilotDriver = entry["driver"]
	if driver != null and not is_player:
		driver.in_passage = true
	craft.tier_exempt = true
	if is_player:
		craft.assist_on = true
	_entries.append(entry)
	set_physics_process(true)
	return ""


## Sends the craft mated here on its way: out along its collar's lane, then its pilot has it again. Returns "" or why not.
func undock(craft: Ship) -> String:
	var entry: Dictionary = _entry_of(craft)
	if entry.is_empty():
		return "it is not docked here"
	var visit: DockVisit = entry["visit"]
	if visit.state != DockVisit.State.INSIDE:
		return "it is not mated (%s)" % visit.state_name()
	visit.enter(DockVisit.State.LAUNCHING)
	return ""


## Calls off the visit of a craft still on its way in. Returns "" or why not.
func cancel(craft: Ship, reason: String = "cancelled") -> String:
	var entry: Dictionary = _entry_of(craft)
	if entry.is_empty():
		return "it is not docking here"
	if not (entry["visit"] as DockVisit).can_cancel():
		return "it is mated: undock it"
	_end(entry, reason)
	return ""


## Lets go of every craft at once, mated or not (the ship is lost, a respawn, a scene's end).
func release_all(reason: String) -> void:
	for entry: Dictionary in _entries.duplicate():
		_end(entry, reason)


## This tick's autopilot command for a visiting `craft` (the player's goes through `Main`); null when it is not visiting.
func command_for(craft: Ship) -> FlightCommand:
	var entry: Dictionary = _entry_of(craft)
	return _command(entry) if not entry.is_empty() else null


func _physics_process(delta: float) -> void:
	var t0: int = Time.get_ticks_usec()
	var closed: String = closed_reason()
	for entry: Dictionary in _entries.duplicate():
		_step(entry, delta, closed)
	ticks += 1
	tick_us += float(Time.get_ticks_usec() - t0)
	set_physics_process(not _entries.is_empty())


# One visit's tick: its state moves on from what the craft does, and an AI craft gets its command.
func _step(entry: Dictionary, delta: float, closed: String) -> void:
	var visit: DockVisit = entry["visit"]
	var craft: Ship = entry["craft"]
	if not is_instance_valid(craft) or not craft.is_inside_tree() or not craft.is_visible_in_tree() or JumpCapability.is_destroyed(craft):
		_end(entry, "the craft is lost")
		return
	visit.advance(delta)
	var mated: Transform3D = ship.global_transform * (entry["mate"] as Transform3D)
	var velocity: Vector3 = craft.linear_velocity - ship.linear_velocity
	match visit.state:
		DockVisit.State.APPROACH, DockVisit.State.LANE:
			if not closed.is_empty():
				_end(entry, closed)  # the ship got under way or went dark: the docking is off (Q84, Q78)
				return
			if visit.total_s > float(options["timeout_s"]):
				_end(entry, "it took too long")
				return
			if visit.state == DockVisit.State.APPROACH:
				var start_at: Vector3 = ship.global_transform * (entry["way"] as DockKeepOut).goal
				if ShipDockRules.joins(craft.global_position.distance_to(start_at), velocity.length(), options):
					visit.enter(DockVisit.State.LANE)
			elif ShipDockRules.captured(craft.global_position - mated.origin, velocity.length(), options):
				_mate(entry)
				return
			if _along(craft.global_position, mated, int(entry["port"])) <= float(options["final_m"]):
				_except(entry, true)  # the locks meet within centimetres
		DockVisit.State.INSIDE:
			_hold(craft, mated)
		DockVisit.State.LAUNCHING:
			if _along(craft.global_position, mated, int(entry["port"])) >= float(options["release_m"]):
				undockings += 1
				var port: int = int(entry["port"])
				visit.enter(DockVisit.State.DONE)
				_drop(entry)
				undocked.emit(craft, port)
				return
	if not visit.is_player:
		craft.set_flight_command(_command(entry))


# The craft's command for its visit's state.
func _command(entry: Dictionary) -> FlightCommand:
	var visit: DockVisit = entry["visit"]
	var craft: Ship = entry["craft"]
	var capability: ShipCapability = entry["capability"]
	var port: int = int(entry["port"])
	var hull: Transform3D = ship.global_transform
	var mated: Transform3D = hull * (entry["mate"] as Transform3D)
	var velocity: Vector3 = craft.linear_velocity - ship.linear_velocity
	var out: Vector3 = hull.basis * ports.outs[port]
	var nose: Vector3 = -mated.basis.z
	match visit.state:
		DockVisit.State.APPROACH:
			var way: DockKeepOut = entry["way"]
			var target: Vector3 = way.next_target(hull.affine_inverse() * craft.global_position)
			var arrive: float = 0.0 if target.is_equal_approx(way.goal) else float(options["via_mps"])
			return DockAutopilot.approach(craft.global_position, velocity, craft.global_basis, hull * target,
					float(options["approach_mps"]), arrive, entry["cautious"])
		DockVisit.State.LANE:
			var lined_up: bool = ShipDockRules.aligned(craft.global_basis, nose, mated.basis.y, options)
			var speed: float = ShipDockRules.lane_speed(_along(craft.global_position, mated, port), lined_up,
					ShipDockRules.brake_mps2(nose.dot(-out), capability), options)
			return DockAutopilot.lane(craft.global_position, velocity, craft.global_basis, mated.origin, -out, speed, capability,
					PilotSteering.align_roll(craft.global_basis, mated.basis.y, capability.rate_max_rad), nose, true)
		DockVisit.State.LAUNCHING:
			return DockAutopilot.lane(craft.global_position, velocity, craft.global_basis, mated.origin, out,
					float(options["lane_mps"]), capability,
					PilotSteering.align_roll(craft.global_basis, mated.basis.y, capability.rate_max_rad), nose)
	return FlightCommand.new()


# How far out of its mated place the craft stands along the collar's axis, m.
func _along(at: Vector3, mated: Transform3D, port: int) -> float:
	return (at - mated.origin).dot(ship.global_basis * ports.outs[port])


# The craft is on the collar from now on: held there, moving with the ship.
func _mate(entry: Dictionary) -> void:
	var visit: DockVisit = entry["visit"]
	var craft: Ship = entry["craft"]
	visit.enter(DockVisit.State.INSIDE)
	_except(entry, true)
	dockings += 1
	craft.set_flight_command(FlightCommand.new())
	_hold(craft, ship.global_transform * (entry["mate"] as Transform3D))
	docked.emit(craft, int(entry["port"]))


# A mated craft rides with the ship: placed on its collar every tick.
func _hold(craft: Ship, mated: Transform3D) -> void:
	craft.global_transform = Transform3D(mated.basis.orthonormalized(), mated.origin)
	craft.linear_velocity = ship.linear_velocity + ship.angular_velocity.cross(mated.origin - ship.global_position)
	craft.angular_velocity = ship.angular_velocity


# Ends a visit that did not run its course: the craft is let go where it is.
func _end(entry: Dictionary, reason: String) -> void:
	var visit: DockVisit = entry["visit"]
	var craft: Ship = entry["craft"]
	var was_mated: bool = visit.state == DockVisit.State.INSIDE or visit.state == DockVisit.State.LAUNCHING
	visit.cancel(reason)
	_drop(entry)
	if not was_mated:
		given_up += 1
		gave_up.emit(craft, reason)


# The dock's hold on the craft ends: its pilot, its own tier rule and its collisions with the ship are as before.
func _drop(entry: Dictionary) -> void:
	_entries.erase(entry)
	var craft: Ship = entry["craft"]
	if is_instance_valid(craft):
		_except(entry, false)
		craft.tier_exempt = bool(entry["tier_exempt"])
		var visit: DockVisit = entry["visit"]
		if visit.is_player:
			craft.assist_on = bool(entry["assist"])
		var driver: AiPilotDriver = entry["driver"]
		if driver != null and is_instance_valid(driver) and not visit.is_player:
			driver.in_passage = false


# Whether the craft and the ship pass through each other (the last metres and while mated).
func _except(entry: Dictionary, on: bool) -> void:
	if bool(entry["excepted"]) == on:
		return
	entry["excepted"] = on
	var craft: Ship = entry["craft"]
	if not is_instance_valid(craft) or not is_instance_valid(ship):
		return
	if on:
		craft.add_collision_exception_with(ship)
	else:
		craft.remove_collision_exception_with(ship)


func _taken() -> Array[bool]:
	var out: Array[bool] = []
	for i: int in ports.count():
		out.append(is_taken(i))
	return out


func _entry_of(craft: Ship) -> Dictionary:
	for entry: Dictionary in _entries:
		if entry["craft"] == craft:
			return entry
	return {}


# The player's hold of X on the collars: dock at the nearest free one.
func _player_action() -> String:
	var docks: ShipDocks = ShipDocks.of(get_tree()) if is_inside_tree() else null
	return docks.start_player(self) if docks != null else TargetInteraction.NOT_AVAILABLE


func _on_hull_destroyed(_info: HitInfo) -> void:
	release_all("the ship is lost")


static func _label(craft: Ship) -> String:
	var marker: Targetable = Targetable.of(craft)
	return marker.display_name if marker != null else String(craft.name)


static func _driver_of(craft: Node) -> AiPilotDriver:
	for child: Node in craft.get_children():
		if child is AiPilotDriver:
			return child as AiPilotDriver
	return null
