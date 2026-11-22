class_name CapitalConsole
extends RefCounted
## The `capital` provider and command (M10-T07): the capital ships in play, one in focus (the newest by default), and ways to
## spawn one, set its helm, open its own jump point, list its sections and hurt a section or a mount (M10-T08), so the capital
## path can be driven from a live build; disable or scuttle one and list the hulks (M10-T10).

const PROVIDER: StringName = &"capital"
const ACTIONS: Array[StringName] = [&"info", &"list", &"spawn", &"helm", &"jump", &"focus", &"sections", &"damage",
		&"disable", &"scuttle", &"hulks"]
## How far ahead of the player `capital spawn` places a ship, m, unless told.
const SPAWN_AHEAD_M: float = 2000.0

var flight: CapitalFlight = null
## The ship the provider describes and the commands act on; null takes the newest.
var focus: CapitalShip = null
var _points: JumpPointPool = null
var _spawned: int = 0
var _named: Dictionary = {}  # type -> how many of its names `spawn` has given


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
		&"state": {"get": _state_text, "doc": "fighting, disabled or destroyed (and the section that blew), M10-T08"},
		&"sections": {"get": func() -> String: return "; ".join(_focused().damage.describe()) if _focused() != null else "",
				"doc": "Each section: kind, state (intact, damaged, disabled, destroyed), points left, a reactor's overload"},
		&"power": {"get": func() -> float: return _focused().damage.power() if _focused() != null else 0.0, "type": TYPE_FLOAT,
				"doc": "Its reactors' power, 0 to 1 (a stage down below half a reactor's points)"},
		&"thrust": {"get": func() -> float: return _focused().damage.thrust_fraction() if _focused() != null else 0.0,
				"type": TYPE_FLOAT, "doc": "The thrust it can give, 0 to 1: the live engines' share at the power left"},
		&"fire_rate": {"get": func() -> float: return _focused().damage.fire_rate() if _focused() != null else 0.0,
				"type": TYPE_FLOAT, "doc": "Its weapons' rate of fire, 0 to 1 (half on last orders with the bridge lost)"},
		&"mounts": {"get": func() -> String: return _live_text(_focused().damage.live_mounts().size(), _focused().damage.mounts.size()) if _focused() != null else "",
				"doc": "Weapon mounts that work, of all"},
		&"bays": {"get": func() -> String: return _live_text(_focused().damage.live_bays().size(), _focused().damage.bay_sections.size()) if _focused() != null else "",
				"doc": "Launch bays that work, of all"},
		&"hulk": {"get": _hulk_text, "doc": "A disabled hull's wind-down (M10-T10): its stage (live, power lost, control lost, cold), its lights and drive left"},
		&"hulks": {"get": func() -> String: return "%d" % _live_hulks(),
				"doc": "Disabled hulks in play (no cap, M10-T10)"},
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
			"Capital ships (M10-T07): info, list, spawn <type> [ahead_m], helm <speed_mps> [yaw_deg], jump, focus <name>, sections, damage <section|mount> <amount>, disable, scuttle, hulks",
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
		&"sections":
			return _sections()
		&"damage":
			return _damage(a, args[&"b"])
		&"disable":
			return _disable()
		&"scuttle":
			return _scuttle()
		&"hulks":
			return _hulks()
	var ship: CapitalShip = _focused()
	if ship == null:
		return ConsoleResult.line("no capital ships")
	return ConsoleResult.line("%s (%s): %s; %s; %s; hull %.2f; %s; %s" % [ship.targetable.display_name, ship.type_id,
			_state_text(), _propulsion_text(), _helm_text(), ship.damageable.hull.fraction(), _collision_text(), _jump_text()])


# The focused ship's sections, one a line, and what still works.
func _sections() -> ConsoleResult:
	var ship: CapitalShip = _focused()
	if ship == null:
		return ConsoleResult.failure("capital sections: no capital ship")
	var lines: PackedStringArray = ship.damage.describe()
	lines.append("%s; power %.2f, thrust %.2f, fire rate %.2f; mounts %s, bays %s" % [_state_text(), ship.damage.power(),
			ship.damage.thrust_fraction(), ship.damage.fire_rate(), _live_text(ship.damage.live_mounts().size(), ship.damage.mounts.size()),
			_live_text(ship.damage.live_bays().size(), ship.damage.bay_sections.size())])
	return ConsoleResult.success(lines)


# A hit of `amount` with no shooter on the focused ship's section or mount `target`, through its Damageable (god mode aside),
# landing at the section's centre or on the mount.
func _damage(target: String, amount: Variant) -> ConsoleResult:
	var ship: CapitalShip = _focused()
	var usage: String = "capital damage <section|mount> <amount>"
	if ship == null or amount == null or float(amount) <= 0.0:
		return ConsoleResult.failure(usage)
	var rest: Vector3
	var section: String = target
	if ship.damage.mounts.has(target):
		rest = ship.damage.mounts[target].position
		section = ship.damage.mounts[target].section
	elif ship.damage.sections.has(target):
		rest = ship.damage.sections[target].box.get_center()
	else:
		return ConsoleResult.failure("%s; sections %s" % [usage, ", ".join(PackedStringArray(ship.damage.sections.keys()))])
	var info := HitInfo.new(ship.get_instance_id(), 0, &"", float(amount), ship.global_transform * rest, Vector3.ZERO, 0.0,
			HitInfo.CAUSE_CONSOLE)
	info.set_meta(CapitalShip.SECTION_META, section)
	info.set_meta(CapitalShip.REST_POINT_META, rest)
	ship.damageable.apply_hit(info)
	var s: CapitalSection = ship.damage.sections[section]
	return ConsoleResult.line("%s: %.0f on %s, now %s %.0f/%.0f; %s" % [ship.targetable.display_name, info.applied, target,
			CapitalSection.state_name(s.state), s.hp, s.max_hp, _state_text()])


# Disables the focused ship as a lost reactor does: each reactor takes a console hit of its points left (god mode aside).
func _disable() -> ConsoleResult:
	var ship: CapitalShip = _focused()
	if ship == null:
		return ConsoleResult.failure("capital disable: no capital ship")
	if ship.is_hulk():
		return ConsoleResult.line("%s is already disabled (%s)" % [ship.targetable.display_name, _hulk_text()])
	for s: CapitalSection in ship.damage.sections.values():
		if s.kind == CapitalSection.REACTOR and not s.lost():
			var info := HitInfo.new(ship.get_instance_id(), 0, &"", s.hp, ship.global_transform * s.box.get_center(), Vector3.ZERO,
					0.0, HitInfo.CAUSE_CONSOLE)
			info.set_meta(CapitalShip.SECTION_META, s.name)
			info.set_meta(CapitalShip.REST_POINT_META, s.box.get_center())
			ship.damageable.apply_hit(info)
	if not ship.is_hulk():
		return ConsoleResult.failure("capital disable: %s has no reactor to shut down (%s)" % [ship.targetable.display_name, _state_text()])
	return ConsoleResult.line("%s disabled: %s" % [ship.targetable.display_name, _hulk_text()])


# The crew scuttles the focused ship: silent, it winds down into a hulk (a Vorlon or Shadow ship blows instead).
func _scuttle() -> ConsoleResult:
	var ship: CapitalShip = _focused()
	if ship == null:
		return ConsoleResult.failure("capital scuttle: no capital ship")
	var who: String = ship.targetable.display_name
	if not ship.scuttle():
		return ConsoleResult.failure("capital scuttle: %s is already disabled or destroyed" % who)
	return ConsoleResult.line("%s scuttled" % who)


# Lists the hulks, oldest first.
func _hulks() -> ConsoleResult:
	var lines := PackedStringArray()
	for key: int in flight.hulks.keys():
		var ship: CapitalShip = CapitalShip.of_body(key)
		if ship != null and ship.is_hulk():
			lines.append("%s: %s%s" % [ship.targetable.display_name, ship.hulk_stages.stage_name(), ", in the tier" if ship.is_tier_parked() else ""])
	lines.append("%d hulks" % _live_hulks())
	return ConsoleResult.success(lines)


func _live_hulks() -> int:
	var count: int = 0
	for key: int in flight.hulks.keys():
		var ship: CapitalShip = CapitalShip.of_body(key)
		if ship != null and ship.is_hulk():
			count += 1
	return count


func _hulk_text() -> String:
	var ship: CapitalShip = _focused()
	if ship == null:
		return ""
	return "%s, lights %.2f, drive %.2f" % [ship.hulk_stages.stage_name(), ship.hulk_stages.lights_level(), ship.hulk_stages.thrust_level()]


# A capital of `type` ahead of the player, at the player's velocity, flying on.
func _spawn(type: StringName, ahead_m: float) -> ConsoleResult:
	if ShipCatalog.entry_text(type, "role") != "capital":
		return ConsoleResult.failure("capital spawn <%s> [ahead_m]" % "|".join(PackedStringArray(ShipCatalog.data().ids_where("role", "capital"))))
	var world: WorldFrame = flight.get_parent() as WorldFrame
	var player: Combatant = AiPilotDriver.player
	if world == null or player == null or not is_instance_valid(player.ship):
		return ConsoleResult.failure("capital spawn: no player to place it by")
	_spawned += 1
	var faction: StringName = ShipCatalog.data().faction(type)
	# A class with a name list gives its ships their names (the Omegas' Greek ones); the rest are numbered by type.
	var label: String = ShipNames.pick(type, faction, _named.get(type, 0))
	if label.is_empty():
		label = "%s %d" % [String(type).to_upper().replace("_", " "), _spawned]
	else:
		_named[type] = int(_named.get(type, 0)) + 1
	var ship: CapitalShip = CapitalShip.create(type, faction, label, player.ship.linear_velocity)
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


func _state_text() -> String:
	var ship: CapitalShip = _focused()
	if ship == null:
		return ""
	if ship.damage.is_destroyed:
		return "destroyed (%s blew)" % ship.damage.blown
	return "disabled" if ship.damage.is_disabled else "fighting"


static func _live_text(live: int, total: int) -> String:
	return "%d/%d" % [live, total]


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
