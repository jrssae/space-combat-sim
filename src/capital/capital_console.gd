class_name CapitalConsole
extends RefCounted
## The `capital` provider and command (M10-T07): the capital ships in play, one in focus (the newest by default), and ways to
## spawn one, set its helm, open its own jump point and hurt a section, so the capital path can be driven from a live build.

const PROVIDER: StringName = &"capital"
const ACTIONS: Array[StringName] = [&"info", &"list", &"spawn", &"helm", &"jump", &"focus"]
## How far ahead of the player `capital spawn` places a ship, m, unless told.
const SPAWN_AHEAD_M: float = 2000.0

var flight: CapitalFlight = null
## The ship the provider describes and the commands act on; null takes the newest.
var focus: CapitalShip = null
var _points: JumpPointPool = null
var _spawned: int = 0


func _init(p_flight: CapitalFlight) -> void:
	flight = p_flight


func register() -> void:
	DebugConsole.registry.register_provider(PROVIDER, ConsoleVars.new({
		&"count": {"get": func() -> int: return flight.ships().size(), "type": TYPE_INT, "doc": "Capital ships in play"},
		&"names": {"get": func() -> String: return ", ".join(_names()), "doc": "Their names, in the order they came"},
		&"focus": {"get": func() -> String: return _focus_name(), "doc": "The one the other fields describe (capital focus <name>)"},
		&"type": {"get": func() -> String: return String(_focused().type_id) if _focused() != null else "",
				"doc": "Its catalogue type and class"},
		&"propulsion": {"get": _propulsion_text, "doc": "Reaction or gravitic (Q51), with retros or flipping to brake"},
		&"speed_mps": {"get": func() -> float: return _focused().linear_velocity.length() if _focused() != null else 0.0,
				"type": TYPE_FLOAT, "doc": "Its speed in the World frame, m/s"},
		&"helm": {"get": _helm_text, "doc": "The helm: heading, the velocity it holds, flipping"},
		&"hull": {"get": func() -> float: return _focused().damageable.hull.fraction() if _focused() != null else 0.0,
				"type": TYPE_FLOAT, "doc": "Hull points left, 0 to 1"},
		&"last_section": {"get": func() -> String: return _focused().last_section if _focused() != null else "",
				"doc": "The section the last hit or ram landed on"},
		&"collision": {"get": _collision_text, "doc": "Hull shapes, rotors, sections, and whether the core holds the surfaces"},
		&"broadcast_km": {"get": func() -> float: return _focused().targetable.broadcast_range_m / 1000.0 if _focused() != null else 0.0,
				"type": TYPE_FLOAT, "doc": "How far it is heard, km (by class)"},
		&"jump": {"get": _jump_text, "doc": "Whether it opens its own points, its drive, and its held point"},
		&"tier": {"get": func() -> bool: return _focused() != null and _focused().is_tier_parked(), "type": TYPE_BOOL,
				"doc": "It is a low-attention tier row now"},
		&"flight_us": {"get": func() -> int: return flight.last_us, "type": TYPE_INT,
				"doc": "Wall-clock cost of the last tick's capital flight, us (a readout)"},
	}), flight)
	DebugConsole.registry.register_command(ConsoleCommand.new(PROVIDER,
			"Capital ships (M10-T07): info, list, spawn <type> [ahead_m], helm <speed_mps> [yaw_deg], jump, focus <name>",
			[ConsoleArg.enum_optional(&"action", ACTIONS, &"info"), ConsoleArg.string_optional(&"a"),
					ConsoleArg.float_optional(&"b", null)]), _cmd, flight)


func _cmd(args: Dictionary) -> ConsoleResult:
	var a: String = str(args[&"a"]) if args[&"a"] != null else ""
	match StringName(args[&"action"]):
		&"list":
			return ConsoleResult.line(", ".join(_names()) if not flight.ships().is_empty() else "no capital ships")
		&"spawn":
			return _spawn(StringName(a), float(args[&"b"]) if args[&"b"] != null else SPAWN_AHEAD_M)
		&"focus":
			for ship: CapitalShip in flight.ships():
				if ship.targetable.display_name == a or String(ship.name) == a:
					focus = ship
					return ConsoleResult.line("focus %s" % a)
			return ConsoleResult.failure("capital focus <%s>" % "|".join(_names()))
		&"helm":
			return _helm(a, args[&"b"])
		&"jump":
			return _jump()
	var ship: CapitalShip = _focused()
	if ship == null:
		return ConsoleResult.line("no capital ships")
	return ConsoleResult.line("%s (%s): %s; %s; hull %.2f; %s; %s" % [ship.targetable.display_name, ship.type_id,
			_propulsion_text(), _helm_text(), ship.damageable.hull.fraction(), _collision_text(), _jump_text()])


# A capital of `type` ahead of the player, at the player's velocity, flying on.
func _spawn(type: StringName, ahead_m: float) -> ConsoleResult:
	if ShipCatalog.entry_text(type, "role") != "capital":
		return ConsoleResult.failure("capital spawn <%s> [ahead_m]" % "|".join(PackedStringArray(ShipCatalog.data().ids_where("role", "capital"))))
	var world: WorldFrame = flight.get_parent() as WorldFrame
	var player: Combatant = AiPilotDriver.player
	if world == null or player == null or not is_instance_valid(player.ship):
		return ConsoleResult.failure("capital spawn: no player to place it by")
	_spawned += 1
	var label: String = "%s %d" % [String(type).to_upper().replace("_", " "), _spawned]
	var ship: CapitalShip = CapitalShip.create(type, ShipCatalog.faction_for(type), label, player.ship.linear_velocity)
	if ship == null:
		return ConsoleResult.failure("capital spawn: %s is not generated (scripts/gen_assets.sh, then import)" % type)
	var basis: Basis = player.ship.global_basis
	world.spawn(ship, world.to_universe(player.ship.global_position - basis.z * ahead_m), basis)
	ship.set_course(-basis.z, player.ship.linear_velocity)
	focus = ship
	return ConsoleResult.line("%s spawned %.0f m ahead" % [label, ahead_m])


# The focused ship holds `speed` along a heading turned `yaw_deg` from its bow (none: straight on).
func _helm(speed_text: String, yaw: Variant) -> ConsoleResult:
	var ship: CapitalShip = _focused()
	if ship == null or not speed_text.is_valid_float():
		return ConsoleResult.failure("capital helm <speed_mps> [yaw_deg]")
	var bow: Vector3 = -ship.global_basis.z
	var heading: Vector3 = bow.rotated(ship.global_basis.y, deg_to_rad(float(yaw))) if yaw != null else bow
	var rest: Vector3 = ship.world.rest_velocity() if ship.world != null else Vector3.ZERO
	ship.set_course(heading, rest + heading * float(speed_text))
	return ConsoleResult.line("%s: %s" % [ship.targetable.display_name, _helm_text()])


# The focused ship opens its own departure point at its anchor and holds it.
func _jump() -> ConsoleResult:
	var ship: CapitalShip = _focused()
	if ship == null:
		return ConsoleResult.failure("capital jump: no capital ship")
	var point: JumpVortex = ship.open_own_point(_pool())
	if point == null:
		return ConsoleResult.failure("capital jump: refused (%s)" % _jump_text())
	return ConsoleResult.line("%s holds its point %.0f m from it" % [ship.targetable.display_name, JumpPointPool.opener_distance_m(point)])


func _pool() -> JumpPointPool:
	if _points == null or not is_instance_valid(_points):
		_points = JumpPointPool.new()
		_points.name = "CapitalJumpPoints"
		_points.world = flight.get_parent() as WorldFrame
		flight.get_parent().add_child(_points)
		_points.prepare(2)
	return _points


func _focused() -> CapitalShip:
	if focus != null and is_instance_valid(focus) and flight.ships().has(focus):
		return focus
	return flight.ships().back() if not flight.ships().is_empty() else null


func _focus_name() -> String:
	return _focused().targetable.display_name if _focused() != null else ""


func _names() -> PackedStringArray:
	var out := PackedStringArray()
	for ship: CapitalShip in flight.ships():
		out.append(ship.targetable.display_name)
	return out


func _propulsion_text() -> String:
	var ship: CapitalShip = _focused()
	if ship == null:
		return ""
	if CapitalPropulsion.is_gravitic(ship.spec):
		return "gravitic %.0f %%" % (100.0 * ship.spec.gravitic_fraction)
	return "reaction, %s" % ("retros" if CapitalPropulsion.has_retros(ship.spec) else "flips to brake")


func _helm_text() -> String:
	var ship: CapitalShip = _focused()
	if ship == null:
		return ""
	return "heading %s, holding %.1f m/s%s" % [ship.helm.heading.snappedf(0.01), ship.cruise_velocity.length(),
			", flipping" if ship.helm.flipping else ""]


func _collision_text() -> String:
	var ship: CapitalShip = _focused()
	if ship == null:
		return ""
	return "%d hull shapes, %d rotors, %d sections, surfaces %s" % [ship.hull_shape_count(), ship.rotors.size(),
			ship.sections.pieces.size(), "in the core" if ship.surfaces_held() else "not in a core"]


func _jump_text() -> String:
	var ship: CapitalShip = _focused()
	if ship == null:
		return ""
	var held: String = ""
	if _points != null and is_instance_valid(_points):
		for point: JumpVortex in _points.points():
			if point.held and point.opener == ship:
				held = ", holds a point %.0f m off" % JumpPointPool.opener_distance_m(point)
	return "%s, drive %.0f s%s" % ["opens its own points" if ship.can_open_jump_point() else "uses gates",
			JumpCapability.recharge_left_s(ship, SimClock.now()), held]
