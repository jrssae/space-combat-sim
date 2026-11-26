class_name BeamConsole
extends RefCounted
## The `beams` provider and the `beam` command (M10-T12): the capital beams on the native rows, the focused capital's emitters
## (the `capital` command's focus) and a test shot: `beam fire [player|selection|<capital name>]` orders the focused ship's
## beams onto a target and readies its cooling emitters, so a beam can be seen and measured from a live build.

const PROVIDER: StringName = &"beams"
const COMMAND: StringName = &"beam"
const ACTIONS: Array[StringName] = [&"info", &"fire", &"clear"]
const PHASES: Array[String] = ["ready", "charging", "firing", "cooling"]

var beams: CapitalBeams = null


func _init(p_beams: CapitalBeams) -> void:
	beams = p_beams


func register() -> void:
	DebugConsole.registry.register_provider(PROVIDER, ConsoleVars.new({
		&"ships": {"get": func() -> int: return beams.ships().size(), "type": TYPE_INT, "doc": "Capital ships with beam emitters"},
		&"emitters": {"get": func() -> int: return beams.emitter_count(), "type": TYPE_INT,
				"doc": "Beam emitters on the native rows"},
		&"lines": {"get": func() -> int: return beams.lines_last, "type": TYPE_INT,
				"doc": "Beams drawn on the last tick (sustained beams on, pulses fired)"},
		&"hits": {"get": func() -> int: return beams.hits, "type": TYPE_INT, "doc": "Beam hits landed since the last reset"},
		&"damage": {"get": func() -> float: return beams.damage_landed, "type": TYPE_FLOAT,
				"doc": "Hull points the beams carried onto hulls since the last reset"},
		&"step_us": {"get": func() -> float: return beams.step_us, "type": TYPE_FLOAT,
				"doc": "Wall-clock cost of the last tick's native beam step, us (a readout)"},
		&"land_us": {"get": func() -> int: return beams.land_us, "type": TYPE_INT,
				"doc": "Wall-clock cost of landing and handing over the last tick's beams, us (a readout)"},
		&"land_native_us": {"get": func() -> float: return beams.land_native_us, "type": TYPE_FLOAT,
				"doc": "Of land_us, the native batches' own cost, us (M10-T75; a readout)"},
		&"batches": {"get": func() -> int: return beams.batches_last, "type": TYPE_INT,
				"doc": "Native landing batches on the last tick (one, plus one a hit that raised an event)"},
		&"deferred": {"get": func() -> int: return beams.deferred, "type": TYPE_INT,
				"doc": "Hits the batch left to GDScript since the last reset (a hull with no landing; should stay 0)"},
		&"focus": {"get": func() -> String: return "; ".join(_describe(_focused())),
				"doc": "The focused capital's emitters: mount, phase, seconds left, target, working"},
	}), beams)
	DebugConsole.registry.register_command(ConsoleCommand.new(COMMAND,
			"Capital beams (M10-T12): info, fire [player|selection|<capital name>] (a test shot from the focused capital), clear",
			[ConsoleArg.enum_optional(&"action", ACTIONS, &"info"), ConsoleArg.string_optional(&"target")]), _cmd, beams)


func _cmd(args: Dictionary) -> ConsoleResult:
	var ship: CapitalShip = _focused()
	if ship == null:
		return ConsoleResult.failure("beam: no capital ship with beams (capital spawn ea_omega)")
	match StringName(args[&"action"]):
		&"fire":
			var target: Node3D = target_named(beams.get_parent(), str(args[&"target"]) if args[&"target"] != null else "selection")
			if target == null:
				return ConsoleResult.failure("beam fire [player|selection|<capital name>]: no such target")
			beams.set_order(ship, target)
			var n: int = beams.ready_now(ship)
			return ConsoleResult.line("%s: %d emitters ordered onto %s (they fire when it is hostile, in range and in arc)" % [
					ship.targetable.display_name, n, name_of(target)])
		&"clear":
			beams.set_order(ship, null)
			return ConsoleResult.line("%s: its beams pick their own targets" % ship.targetable.display_name)
	return ConsoleResult.success(_describe(ship))


# The focused capital, when it has beams.
func _focused() -> CapitalShip:
	var flight: CapitalFlight = CapitalFlight.of(beams.get_parent())
	var ship: CapitalShip = flight.focused() if flight != null else null
	return ship if ship != null and beams.ships().has(ship) else (beams.ships().back() if not beams.ships().is_empty() else null)


## The body `name` names in `world`: the player's ship, its selection, or a capital by its name (the `gun` command's too).
static func target_named(world: Node, name: String) -> Node3D:
	var player: Combatant = AiPilotDriver.player
	var own: Ship = player.ship if player != null and is_instance_valid(player.ship) else null
	if name == "player":
		return own
	if name == "selection":
		var id: int = own.targeting.selected_id() if own != null else 0
		var picked := instance_from_id(id) as Node if id > 0 and is_instance_id_valid(id) else null
		var targetable := picked as Targetable
		return (targetable.get_parent() if targetable != null else picked) as Node3D
	var flight: CapitalFlight = CapitalFlight.of(world)
	for ship: CapitalShip in flight.ships() if flight != null else []:
		if ship.targetable.display_name == name or String(ship.name) == name:
			return ship
	return null


func _describe(ship: CapitalShip) -> PackedStringArray:
	var lines := PackedStringArray()
	if ship == null:
		return lines
	for k: int in beams.beams_of(ship):
		var s: Dictionary = beams.state(k)
		var m: Dictionary = s["mount"]
		var target: Object = instance_from_id(int(s["target"])) if int(s["target"]) > 0 and is_instance_id_valid(int(s["target"])) else null
		lines.append("%s %s: %s %.1f s, target %s%s" % [m["name"], m["weapon"], PHASES[clampi(int(s["phase"]), 0, 3)],
				float(s["timer"]), name_of(target as Node), "" if bool(s["works"]) else ", lost"])
	return lines


## A body's display name (its `Targetable`'s, else its node name), "none" for null.
static func name_of(node: Node) -> String:
	if node == null:
		return "none"
	var targetable: Targetable = Targetable.of(node)
	return targetable.display_name if targetable != null else String(node.name)
