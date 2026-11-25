class_name GunConsole
extends RefCounted
## The `capital_guns` provider and the `gun` command (M10-T14): the capital guns and launchers on the native rows, the focused
## capital's mounts (the `capital` command's focus) and a test shot: `gun fire [player|selection|<capital name>]` orders the
## focused ship's heavy guns onto a target and readies every mount, so a shot can be seen and measured from a live build.

const PROVIDER: StringName = &"capital_guns"
const COMMAND: StringName = &"gun"
const ACTIONS: Array[StringName] = [&"info", &"fire", &"clear", &"hold", &"free"]

var guns: CapitalGuns = null


func _init(p_guns: CapitalGuns) -> void:
	guns = p_guns


func register() -> void:
	DebugConsole.registry.register_provider(PROVIDER, ConsoleVars.new({
		&"ships": {"get": func() -> int: return guns.ships().size(), "type": TYPE_INT,
				"doc": "Capital ships with guns or launchers"},
		&"mounts": {"get": func() -> int: return guns.mount_count() - guns.battery_count(), "type": TYPE_INT,
				"doc": "Gun turrets, fixed guns and launchers on the native rows (interceptors: `interceptors.batteries`)"},
		&"shots": {"get": func() -> int: return guns.shots, "type": TYPE_INT,
				"doc": "Bolts and missiles the capitals fired since the last reset"},
		&"missiles": {"get": func() -> int: return guns.missiles_launched, "type": TYPE_INT,
				"doc": "Missiles and torpedoes launched since the last reset"},
		&"in_flight": {"get": func() -> int: return guns.missiles_in_flight(), "type": TYPE_INT,
				"doc": "Missiles and torpedoes in flight now"},
		&"blocked": {"get": func() -> int: return int(guns.readouts()[2]), "type": TYPE_INT,
				"doc": "Shots a capital's own hull blocked, since the rows were made"},
		&"picks": {"get": func() -> int: return int(guns.readouts()[3]), "type": TYPE_INT,
				"doc": "Target picks that found one, since the rows were made"},
		&"hidden": {"get": func() -> int: return int(guns.readouts()[4]), "type": TYPE_INT,
				"doc": "Candidates a pick passed over because the ship's own hull hid them, since the rows were made"},
		&"step_us": {"get": func() -> float: return guns.step_us, "type": TYPE_FLOAT,
				"doc": "Wall-clock cost of the last tick's native gun step, us (a readout)"},
		&"kernel_us": {"get": func() -> float: return guns.kernel_us, "type": TYPE_FLOAT,
				"doc": "Wall-clock cost of the last tick's gun kernels alone, us (a readout)"},
		&"focus": {"get": func() -> String: return "; ".join(_describe(_focused())),
				"doc": "The focused capital's mounts: weapon, target, shots, working"},
	}), guns)
	DebugConsole.registry.register_command(ConsoleCommand.new(COMMAND,
			"Capital guns and launchers (M10-T14): info, fire [player|selection|<capital name>] (a test shot from the focused "
			+ "capital), clear, hold, free",
			[ConsoleArg.enum_optional(&"action", ACTIONS, &"info"), ConsoleArg.string_optional(&"target")]), _cmd, guns)


func _cmd(args: Dictionary) -> ConsoleResult:
	var ship: CapitalShip = _focused()
	if ship == null:
		return ConsoleResult.failure("gun: no capital ship with guns (capital spawn ea_omega)")
	var label: String = ship.targetable.display_name
	match StringName(args[&"action"]):
		&"fire":
			var target: Node3D = BeamConsole.target_named(guns.get_parent(), str(args[&"target"]) if args[&"target"] != null else "selection")
			if target == null:
				return ConsoleResult.failure("gun fire [player|selection|<capital name>]: no such target")
			guns.set_order(ship, target)
			var n: int = guns.ready_now(ship)
			return ConsoleResult.line("%s: %d mounts ready, heavy guns ordered onto %s (they fire when it is hostile, in range and in arc)"
					% [label, n, BeamConsole.name_of(target)])
		&"clear":
			guns.set_order(ship, null)
			return ConsoleResult.line("%s: its guns pick their own targets" % label)
		&"hold":
			guns.hold(ship, true)
			return ConsoleResult.line("%s: its guns and launchers hold their fire" % label)
		&"free":
			guns.hold(ship, false)
			return ConsoleResult.line("%s: its guns and launchers are free to fire" % label)
	return ConsoleResult.success(_describe(ship))


# The focused capital, when it has guns.
func _focused() -> CapitalShip:
	var flight: CapitalFlight = CapitalFlight.of(guns.get_parent())
	var ship: CapitalShip = flight.focused() if flight != null else null
	return ship if ship != null and guns.ships().has(ship) else (guns.ships().back() if not guns.ships().is_empty() else null)


func _describe(ship: CapitalShip) -> PackedStringArray:
	var lines := PackedStringArray()
	if ship == null:
		return lines
	if guns.is_held(ship):
		lines.append("%s holds its fire" % ship.targetable.display_name)
	for k: int in guns.mounts_of(ship):
		var s: Dictionary = guns.state(k)
		var m: Dictionary = s["mount"]
		var id: int = int(s["target"])
		var target: Node = instance_from_id(id) as Node if id > 0 and is_instance_id_valid(id) else null
		lines.append("%s %s: target %s, %d shots%s" % [m["name"], m["weapon"], BeamConsole.name_of(target), int(s["shots"]),
				"" if bool(s["works"]) else ", lost"])
	return lines
