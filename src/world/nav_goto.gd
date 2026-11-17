class_name NavGoto
extends Node
## The `goto <nav point>` console command (M7-T67): puts the player, at rest, a stand-off clear of a place the target menu names,
## facing it, with the frame on that place's rail so every world object keeps its universe position (M7-T66). Places are
## Babylon 5, its bays, the jumpgate, the scenario's NAV buoys and the star system's bodies. A wing that flies with the player
## comes along in formation. Console only; refused in a mission, and held back until a running launch has let the player go.

const KIND_STATION: StringName = &"station"
const KIND_BAY: StringName = &"bay"
const KIND_GATE: StringName = &"gate"
const KIND_NAV: StringName = &"nav"
const KIND_BODY: StringName = &"body"

const STATION_OFF_BOW_M: float = 4000.0
const BAY_OFF_MOUTH_M: float = 2000.0
const GATE_OFF_M: float = 6000.0
const NAV_OFF_M: float = 1000.0
## A body's orbit clears its atmosphere by at least this, or a tenth of its radius for a big one (the star).
const ORBIT_CLEAR_MIN_M: float = 300000.0
const ORBIT_CLEAR_FRACTION: float = 0.1
const COMMAND: StringName = &"goto"

var main: Main = null

var _after_launch: String = ""  # the place a goto during a launch waits to take the player to


func _ready() -> void:
	DebugConsole.registry.register_command(ConsoleCommand.new(COMMAND,
			"Move the player to a nav point (M7-T67): no argument lists them; a name (or a unique prefix) puts the player clear of it, "
			+ "at rest against it and facing it (a body: a circular orbit over its atmosphere, on its day side)",
			[ConsoleArg.string_rest(&"place").make_optional("").with_suggestions(_names)]), _cmd_goto, self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


## The entry whose name `typed` picks among `names`: an exact match (any case) wins, else every name it is a prefix of. Pure.
static func match_names(names: PackedStringArray, typed: String) -> PackedStringArray:
	var wanted: String = typed.strip_edges().to_lower()
	var found := PackedStringArray()
	if wanted.is_empty():
		return found
	for entry: String in names:
		if entry.to_lower() == wanted:
			return PackedStringArray([entry])
		if entry.to_lower().begins_with(wanted):
			found.append(entry)
	return found


## The nav points in play: dictionaries `name`, `kind` and, by kind, the node or body id behind them.
func places() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var station: Station = main.far_props.station if main.far_props != null else null
	if station != null and station.is_inside_tree():
		out.append({"name": Station.DISPLAY_NAME, "kind": KIND_STATION, "node": station})
		for bay: NavPoint in [station.docking_bay, station.cargo_bay]:
			if bay != null and bay.targetable != null:
				out.append({"name": bay.targetable.display_name, "kind": KIND_BAY, "node": bay})
	for gate: Jumpgate in main.gates.gates:
		out.append({"name": gate.display_name, "kind": KIND_GATE, "node": gate})
	for buoy: NavBuoy in main.buoys:
		if is_instance_valid(buoy) and buoy.is_inside_tree():
			out.append({"name": buoy.display_name, "kind": KIND_NAV, "node": buoy})
	var system: StarSystem = _system()
	if system != null:
		for id: StringName in system.body_ids:
			out.append({"name": system.display_name(id), "kind": KIND_BODY, "body": id})
	return out


func _names() -> PackedStringArray:
	var names := PackedStringArray()
	for place: Dictionary in places():
		names.append(String(place["name"]))
	return names


func _system() -> StarSystem:
	var host: StarSystemHost = main.star_system
	return host.system if host != null and host.system != null and host.system.is_valid() else null


func _cmd_goto(args: Dictionary) -> ConsoleResult:
	var typed: String = str(args[&"place"]).strip_edges() if args[&"place"] != null else ""
	var list: Array[Dictionary] = places()
	var names := PackedStringArray()
	for place: Dictionary in list:
		names.append(String(place["name"]))
	if typed.is_empty():
		return ConsoleResult.line("\n".join(names) if not names.is_empty() else "no nav points")
	var matches: PackedStringArray = match_names(names, typed)
	if matches.is_empty():
		return ConsoleResult.failure("goto: no nav point '%s'; they are: %s" % [typed, ", ".join(names)])
	if matches.size() > 1:
		return ConsoleResult.failure("goto: '%s' could be %s" % [typed, ", ".join(matches)])
	if main.mission != null:
		return ConsoleResult.failure("goto: not in a mission")
	if not main.player_alive:
		return ConsoleResult.failure("goto: no player to move")
	# A launch in progress still carries the player: end it first and go once the player is away (the last goto asked wins).
	if main.launches != null and main.launches.locks_controls():
		main.launches.skip()
		_after_launch = matches[0]
		if not main.launches.player_released.is_connected(_place_after_launch):
			main.launches.player_released.connect(_place_after_launch)
			main.player_died.connect(_forget)
		return ConsoleResult.line("launch skipped; to %s once the player is away" % matches[0])
	var refused: String = go(matches[0])
	return ConsoleResult.failure("goto: " + refused) if not refused.is_empty() else ConsoleResult.line("at %s" % matches[0])


func _place_after_launch() -> void:
	var place_name: String = _after_launch
	_forget()
	if main.player_alive and not place_name.is_empty():
		var refused: String = go(place_name)
		if not refused.is_empty():
			push_warning("goto %s: %s" % [place_name, refused])


# A goto waiting on a launch is dropped once done, or when the player dies first.
func _forget() -> void:
	_after_launch = ""
	if main.launches.player_released.is_connected(_place_after_launch):
		main.launches.player_released.disconnect(_place_after_launch)
	if main.player_died.is_connected(_forget):
		main.player_died.disconnect(_forget)


## Puts the player (and its wing) at place `place_name`. Returns "" or why it was refused.
func go(place_name: String) -> String:
	var place: Dictionary = {}
	for entry: Dictionary in places():
		if String(entry["name"]) == place_name:
			place = entry
	if place.is_empty():
		return "no nav point %s" % place_name
	var world: WorldFrame = main.world
	var system: StarSystem = _system()
	if place["kind"] == KIND_BODY:
		var id: StringName = place["body"]
		var info: Dictionary = system.info(id)
		var radius_m: float = float(info["radius_m"])
		var clear_m: float = maxf(ORBIT_CLEAR_MIN_M, ORBIT_CLEAR_FRACTION * radius_m)
		var refused: String = world.orbit_focus(system, id, float(info["atmosphere_top_m"]) + clear_m)
		if not refused.is_empty():
			return refused
		var centre := Vector3.ZERO
		var state: PackedFloat64Array = world.body_state(id)
		if state.size() >= 3:
			centre = Vector3(state[0], state[1], state[2])
		_put(main.ship.global_position, centre, Vector3.ZERO)
		return ""
	# A place on the station's rail: the frame goes back onto it first when the console has moved it, then the nodes stand
	# where the universe puts them.
	if not world.on_home_rail():
		var refused: String = world.rail_focus(system, world.home_id)
		if not refused.is_empty():
			return refused
	var pose: Array = _stand_off(place)
	_put(pose[0], pose[1], pose[2])
	return ""


# The stand-off point, the point to face and the place's velocity in the local frame, for a place on the station's rail.
func _stand_off(place: Dictionary) -> Array:
	var node: Node3D = place["node"]
	match place["kind"]:
		KIND_STATION:
			var station: Station = node
			var bow: Dictionary = station.hardpoints.tour("bow")
			var at: Vector3 = station.to_world(bow["position"], String(bow["body"]))
			var outward: Vector3 = (at - station.global_position).normalized()
			return [at + outward * STATION_OFF_BOW_M, station.global_position, main.world.anchored_velocity()]
		KIND_BAY:
			var station: Station = node.get_parent() as Station
			var is_dock: bool = node == station.docking_bay
			var mouth: Vector3 = node.global_position
			var path: Array[Vector3] = []
			path.assign(station.hardpoints.main_docking_bay["main_docking_bay_approach"] if is_dock
					else station.hardpoints.cargo_bay["cargo_bay_approach"])
			var local_mouth: Vector3 = station.to_local(mouth)
			var far: Vector3 = path[0] + (station.drum_origin if is_dock else Vector3.ZERO)
			var outward: Vector3 = (station.global_transform.basis * (far - local_mouth)).normalized()
			return [mouth + outward * BAY_OFF_MOUTH_M, mouth, main.world.anchored_velocity()]
		KIND_GATE:
			return [node.global_transform * Vector3(0.0, 0.0, -GATE_OFF_M), node.global_position, main.world.anchored_velocity()]
	var buoy: NavBuoy = node as NavBuoy
	return [buoy.global_position + buoy.global_basis.z * NAV_OFF_M, buoy.global_position, buoy.targetable.get_target_velocity()]


# Puts the player at `at` facing `look`, riding with `velocity`, and the wing around it in formation.
func _put(at: Vector3, look: Vector3, velocity: Vector3) -> void:
	var forward: Vector3 = (look - at).normalized()
	var up: Vector3 = Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.98 else Vector3.BACK
	var basis: Basis = Basis.looking_at(forward, up)
	main.ship.reset_to(Transform3D(basis, at))
	main.ship.linear_velocity = velocity
	var wing: Wing = main.wings.player_wing() if main.wings != null else null
	if wing != null:
		for member: Combatant in wing.members():
			if member.is_player or member.ship == null or not is_instance_valid(member.ship):
				continue
			member.ship.reset_to(Transform3D(basis, at + basis * wing.slot_offset(wing.slot_of(member))))
			member.ship.linear_velocity = velocity
	main.camera_rig.snap_chase()
