class_name ShipDocks
extends Node
## Docking at ships, seen from the game (M10-T53, Q84): finds every `ShipDock` in play, sends named craft to them (the console,
## `MissionApi.dock_at`), brings in a pooled shuttle to dock, and carries the player's own docking: the hold of X on a ship's
## collars or its shuttle bay, the autopilot's command for `Main`, the held controls while mated and the hold of X again to
## leave (`AutopilotAbort`: ABORT on the way in, UNDOCK once mated). A place is a collar or a berth by its name, or `bay`
## for the berth that takes the craft (stage 2: the Asimov's shuttle bay takes a crew shuttle and a Kestrel).
## Console: command `shipdock`, provider `ship_docks`.

const NODE_NAME: StringName = &"ShipDocks"
const GROUP: StringName = &"ship_docks_director"
const PROVIDER: StringName = &"ship_docks"
const COMMAND: StringName = &"shipdock"
const ACTIONS: Array[StringName] = [&"status", &"list", &"dock", &"undock", &"cancel", &"send", &"player", &"hold"]
## The craft `send` brings in when none is named, and how far off the collars it appears, m.
const SEND_TYPE: StringName = &"ea_shuttle"
const SEND_OUT_M: float = 700.0

var main: Main = null
## Craft `send` brought in so far.
var sent: int = 0

var _player_dock: ShipDock = null


func _init() -> void:
	name = NODE_NAME
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _ready() -> void:
	add_to_group(GROUP)
	_register_console()


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


## The scene's director, or null.
static func of(tree: SceneTree) -> ShipDocks:
	return tree.get_first_node_in_group(GROUP) as ShipDocks if tree != null else null


## Every ship's dock in play.
func docks() -> Array[ShipDock]:
	var out: Array[ShipDock] = []
	for node: Node in get_tree().get_nodes_in_group(ShipDock.GROUP) if is_inside_tree() else []:
		var dock := node as ShipDock
		if dock != null and is_instance_valid(dock.ship):
			out.append(dock)
	return out


## The dock of the ship called `ship_name` ("" or no match by name: the nearest to the player, else the first), or null.
func dock_named(ship_name: String) -> ShipDock:
	var all: Array[ShipDock] = docks()
	var wanted: String = ship_name.strip_edges().to_lower()
	for dock: ShipDock in all:
		if not wanted.is_empty() and (dock.ship.targetable.display_name.to_lower() == wanted or String(dock.ship.type_id) == wanted):
			return dock
	if not wanted.is_empty() or all.is_empty():
		return null
	var best: ShipDock = all[0]
	if main != null and is_instance_valid(main.ship):
		for dock: ShipDock in all:
			if dock.global_position.distance_squared_to(main.ship.global_position) \
					< best.global_position.distance_squared_to(main.ship.global_position):
				best = dock
	return best


## The dock `craft` is visiting, or null.
func dock_of(craft: Ship) -> ShipDock:
	for dock: ShipDock in docks():
		if dock.visit_of(craft) != null:
			return dock
	return null


## The small craft in play called `craft_name` ("player": the player's), or null.
func craft_named(craft_name: String) -> Ship:
	if main == null:
		return null
	if craft_name.to_lower() == "player":
		return main.ship if main.player_alive else null
	for c: Combatant in main.ships.alive():
		if c.display_name.to_lower() == craft_name.to_lower() and is_instance_valid(c.ship):
			return c.ship
	return null


# --- orders (the console, missions, stage 3's traffic) ---------------------------------------------------------------------


## Sends the AI craft `craft_name` to dock at the ship `ship_name` ("": the nearest), collar `port_name` ("": its nearest free
## one). Returns "" or why not.
func dock_ship(craft_name: String, ship_name: String = "", port_name: String = "") -> String:
	var craft: Ship = craft_named(craft_name)
	if craft == null:
		return "no craft '%s' in play" % craft_name
	if main != null and craft == main.ship:
		return "the player docks with a hold of X (shipdock player)"
	var dock: ShipDock = dock_named(ship_name)
	if dock == null:
		return "no ship with docking collars%s" % ("" if ship_name.is_empty() else " called '%s'" % ship_name)
	var port: int = dock.place_named(port_name, craft.spec.asset_id) if not port_name.is_empty() else -1
	if not port_name.is_empty() and port < 0:
		return "%s has no place '%s' for it (%s)" % [dock.ship.targetable.display_name, port_name, ", ".join(dock.ports.names)]
	return dock.start(craft, port)


## Sends the mated craft `craft_name` on its way again. Returns "" or why not.
func undock_ship(craft_name: String) -> String:
	var craft: Ship = craft_named(craft_name)
	var dock: ShipDock = dock_of(craft) if craft != null else null
	if dock == null:
		return "no craft '%s' at a ship's dock" % craft_name
	if main != null and craft == main.ship:
		return undock_player()
	return dock.undock(craft)


## Calls off the docking of `craft_name` while it is still on its way in. Returns "" or why not.
func cancel_ship(craft_name: String) -> String:
	var craft: Ship = craft_named(craft_name)
	var dock: ShipDock = dock_of(craft) if craft != null else null
	if dock == null:
		return "no craft '%s' on its way to a ship's dock" % craft_name
	return dock.cancel(craft)


## Brings a pooled craft of `type` into play off one of `dock`'s places and sends it in (the console's `send`; a test's
## visitor): `port` -1 for a free collar, or its berth when it has no lock. Returns the craft, or null with `why[0]` saying why not.
func send_craft(dock: ShipDock, type: StringName = SEND_TYPE, port: int = -1, why: Array[String] = []) -> Combatant:
	var pool: ShipPool = ShipPool.for_tree(get_tree())
	var world: WorldFrame = WorldFrame.of(dock.ship)
	var problem: String = dock.closed_reason()
	if problem.is_empty() and (pool == null or world == null or not ShipCatalog.data().has(type)):
		problem = "no pooled craft of type %s" % type
	var has_lock: bool = problem.is_empty() and _type_has_lock(type)
	if problem.is_empty():
		problem = dock.refusal_for(String(type), has_lock, port)
	if not problem.is_empty():
		why.append(problem)
		return null
	if pool.free_count(type) <= 0:
		pool.prepare(type, pool.pool_size(type) + 1)
	var index: int = port if port >= 0 else dock.place_for(String(type), has_lock, Vector3.ZERO)
	var hull: Transform3D = dock.ship.global_transform
	var out: Vector3 = dock.ports.outs[index]
	# Off the collar's lane, to one side, so its first leg is seen as an approach.
	var at: Vector3 = hull * (dock.ports.positions[index] + out * SEND_OUT_M + dock.ports.ups[index].cross(out) * 0.4 * SEND_OUT_M)
	var label: String = pool.next_name(ShipCatalog.entry_text(type, "callsign").capitalize() if not ShipCatalog.entry_text(type, "callsign").is_empty() else "Shuttle")
	var made: Dictionary = BrainFactory.from_behaviour({"type": "idle", "hold": false}, world.to_universe(at), hash([label, sent]))
	var combatant: Combatant = pool.acquire(label, world.to_universe(at), Basis.looking_at(hull.basis * -out, hull.basis.y),
			dock.ship.linear_velocity, made["brain"] as PilotBrain, type) if bool(made.get("ok", false)) else null
	if combatant == null:
		why.append("the pool gave no %s" % type)
		return null
	var refused: String = dock.start(combatant.ship, index)
	if not refused.is_empty():
		pool.release(combatant)
		why.append(refused)
		return null
	sent += 1
	return combatant


# --- the player ------------------------------------------------------------------------------------------------------------


## The player's visit under way, or null.
func player_visit() -> DockVisit:
	if _player_dock == null or not is_instance_valid(_player_dock) or main == null or not is_instance_valid(main.ship):
		return null
	return _player_dock.visit_of(main.ship)


## The docking holds the player's controls (`Main.controls_locked`): on the way in, mated and leaving.
func locks_controls() -> bool:
	return player_visit() != null


## The hold of X on `dock`'s collars: dock there, or leave when mated there. Returns "" or why not.
func toggle_player(dock: ShipDock) -> String:
	var visit: DockVisit = player_visit()
	if visit != null:
		return undock_player() if visit.state == DockVisit.State.INSIDE else "docking is under way (%s)" % visit.state_name()
	return start_player(dock)


## Starts the player's docking at `dock`: `place` a collar's or a berth's number or name, `bay` for the berth that takes the
## player's craft, -1 or "" for the nearest free collar. Returns "" or why not.
func start_player(dock: ShipDock, place: Variant = -1) -> String:
	if main == null or not main.player_alive:
		return "the player's ship is lost"
	if dock == null:
		return "no ship with docking collars"
	if main.controls_locked():
		return "the controls are held"
	var port: int = int(place) if place is int else -1
	if place is String and not (place as String).is_empty():
		port = dock.place_named(place, main.ship.spec.asset_id)
		if port < 0:
			return "%s has no place '%s' for a %s" % [dock.ship.targetable.display_name, place, main.ship.spec.asset_id]
	var refused: String = dock.start(main.ship, port, true, DockVisit.WHY_HOLD)
	if refused.is_empty():
		_player_dock = dock
	return refused


## Whether a hold of X calls the player's docking off now: on its way in, until it is mated.
func abort_offered() -> bool:
	var visit: DockVisit = player_visit()
	return visit != null and visit.can_cancel()


## Calls the player's docking off (`AutopilotAbort`). Returns "" or why not.
func abort() -> String:
	if not abort_offered():
		return "no docking to abort"
	return _player_dock.cancel(main.ship, "aborted")


## Whether a hold of X sends the player's mated craft on its way (`AutopilotAbort.UNDOCK`).
func undock_offered() -> bool:
	var visit: DockVisit = player_visit()
	return visit != null and visit.state == DockVisit.State.INSIDE


## Sends the player's mated craft out along its collar's lane. Returns "" or why not.
func undock_player() -> String:
	return _player_dock.undock(main.ship) if player_visit() != null else "the player is not docked"


## Ends the player's visit whatever its state (a respawn).
func cancel_player(reason: String) -> void:
	if player_visit() != null:
		_player_dock._end(_player_dock._entry_of(main.ship), reason)
	_player_dock = null


## The docking autopilot's command for the player's ship this tick, null when it is not docking.
func step_player(_delta: float) -> FlightCommand:
	if player_visit() == null:
		return null
	return _player_dock.command_for(main.ship)


# --- console ---------------------------------------------------------------------------------------------------------------


func _register_console() -> void:
	DebugConsole.registry.register_provider(PROVIDER, ConsoleVars.new({
		&"ships": {"get": func() -> int: return docks().size(), "type": TYPE_INT, "doc": "Ships in play with docking collars"},
		&"collars": {"get": func() -> int: return _sum(func(d: ShipDock) -> int: return d.ports.collar_count()), "type": TYPE_INT,
				"doc": "Their collars together"},
		&"berths": {"get": func() -> int: return _sum(func(d: ShipDock) -> int: return d.ports.bay_count()), "type": TYPE_INT,
				"doc": "Their shuttle bays' berths together"},
		&"visiting": {"get": func() -> int: return _sum(func(d: ShipDock) -> int: return d.visits().size()), "type": TYPE_INT,
				"doc": "Craft on their way in, mated or leaving"},
		&"docked": {"get": func() -> int: return _sum(func(d: ShipDock) -> int: return d.docked_count()), "type": TYPE_INT,
				"doc": "Craft mated on a collar or resting in a berth now"},
		&"dockings": {"get": func() -> int: return _sum(func(d: ShipDock) -> int: return d.dockings), "type": TYPE_INT,
				"doc": "Craft mated so far"},
		&"undockings": {"get": func() -> int: return _sum(func(d: ShipDock) -> int: return d.undockings), "type": TYPE_INT,
				"doc": "Craft that left their collar so far"},
		&"given_up": {"get": func() -> int: return _sum(func(d: ShipDock) -> int: return d.given_up), "type": TYPE_INT,
				"doc": "Dockings called off before the craft mated (cancelled, timed out, the ship under way or dark)"},
		&"player": {"get": func() -> String: return player_visit().state_name() if player_visit() != null else "none",
				"doc": "The player's docking at a ship: approach, lane, inside (mated), launching, or none"},
		&"tick_us": {"get": _mean_tick_us, "unit": "us", "doc": "A dock's own cost a tick while craft visit it, the mean so far"},
		&"list": {"get": func() -> String: return "; ".join(_describe_all()), "doc": "Every dock and its visitors"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(COMMAND,
			"Docking at ships (M10-T53): status, list, dock <craft> [ship] [place], undock <craft>, cancel <craft>, send [type] [place] (a pooled shuttle flies in and docks), player [place] (the player's hold of X: dock, or leave when mated), hold (the ship holds station); a place is a collar's or a berth's name, or bay (the shuttle bay's berth for that craft)",
			[ConsoleArg.enum_optional(&"action", ACTIONS, &"status"), ConsoleArg.string_optional(&"what"),
			ConsoleArg.string_optional(&"where"), ConsoleArg.string_optional(&"collar")] as Array[ConsoleArg]), _cmd, self)


func _cmd(args: Dictionary) -> ConsoleResult:
	var action: StringName = StringName(args[&"action"])
	var what: String = str(args[&"what"]) if args[&"what"] != null else ""
	var where: String = str(args[&"where"]) if args[&"where"] != null else ""
	var collar: String = str(args[&"collar"]) if args[&"collar"] != null else ""
	var why: String = ""
	match action:
		&"dock":
			why = dock_ship(what, where, collar) if not what.is_empty() else "shipdock dock <craft> [ship] [collar]"
			return ConsoleResult.failure(why) if not why.is_empty() else ConsoleResult.line("%s is cleared to dock" % what)
		&"undock":
			why = undock_ship(what) if not what.is_empty() else "shipdock undock <craft>"
			return ConsoleResult.failure(why) if not why.is_empty() else ConsoleResult.line("%s undocks" % what)
		&"cancel":
			why = cancel_ship(what) if not what.is_empty() else "shipdock cancel <craft>"
			return ConsoleResult.failure(why) if not why.is_empty() else ConsoleResult.line("%s breaks off" % what)
		&"send", &"player", &"hold":
			var dock: ShipDock = dock_named("")
			if dock == null:
				return ConsoleResult.failure("shipdock: no ship with docking collars (capital spawn ea_asimov)")
			var named: String = where if action == &"send" else what
			var flown: String = (what if not what.is_empty() else String(SEND_TYPE)) if action == &"send" else \
					(main.ship.spec.asset_id if main != null and is_instance_valid(main.ship) else "")
			var port: int = dock.place_named(named, flown) if not named.is_empty() else -1
			if not named.is_empty() and port < 0:
				return ConsoleResult.failure("places are %s, and bay" % ", ".join(dock.ports.names))
			var label: String = dock.ship.targetable.display_name
			if action == &"hold":
				dock.hold_station()
				return ConsoleResult.line("%s holds station" % label)
			if action == &"player":
				why = toggle_player(dock) if port < 0 or player_visit() != null else start_player(dock, port)
				return ConsoleResult.failure(why) if not why.is_empty() else ConsoleResult.line("the player %s %s" % [
						"leaves" if player_visit().state == DockVisit.State.LAUNCHING else "docks at", label])
			var reasons: Array[String] = []
			var made: Combatant = send_craft(dock, StringName(what) if not what.is_empty() else SEND_TYPE, port, reasons)
			return ConsoleResult.failure(reasons[0]) if made == null else ConsoleResult.line("%s flies in to dock at %s (%s)" % [
					made.display_name, label, dock.ports.names[dock.port_of(made.ship)]])
	return ConsoleResult.success(_describe_all())


# Whether craft of `type` have a docking lock of their own (their hull's `docking_ports`).
static func _type_has_lock(type: StringName) -> bool:
	var spec: ShipSpec = ShipCatalog.spec_for(type)
	var loaded: Hardpoints = Hardpoints.load_file(spec.hardpoints_path()) if spec != null else null
	return loaded != null and loaded.valid and not ShipDockPorts.craft_port(loaded.raw).is_empty()


func _sum(per: Callable) -> int:
	var n: int = 0
	for dock: ShipDock in docks():
		n += int(per.call(dock))
	return n


func _mean_tick_us() -> float:
	var us: float = 0.0
	var n: int = 0
	for dock: ShipDock in docks():
		us += dock.tick_us
		n += dock.ticks
	return us / float(maxi(n, 1))


func _describe_all() -> PackedStringArray:
	var lines := PackedStringArray()
	for dock: ShipDock in docks():
		var closed: String = dock.closed_reason()
		var bay: String = "" if dock.ports.bay_count() == 0 else ", %d berths, %d free" % [dock.ports.bay_count(), dock.free_berths()]
		lines.append("%s: %d collars, %d free%s, %d mated, %d dockings, %d undockings%s" % [dock.ship.targetable.display_name,
				dock.ports.collar_count(), dock.free_count(), bay, dock.docked_count(), dock.dockings, dock.undockings,
				"" if closed.is_empty() else " (closed: %s)" % closed])
		for line: String in dock.describe_visits():
			lines.append("  %s" % line)
	if lines.is_empty():
		lines.append("no ship with docking collars in play")
	return lines
