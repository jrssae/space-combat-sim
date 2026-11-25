class_name InterceptConsole
extends RefCounted
## The `interceptors` provider and the `intercept` command (M10-T13): the capitals' interceptor batteries on the native rows,
## what they shot down by kind, and the focused capital's share of the hostile shots headed for it; `intercept hold|free`
## stops or frees the focused capital's batteries.

const PROVIDER: StringName = &"interceptors"
const COMMAND: StringName = &"intercept"
const ACTIONS: Array[StringName] = [&"info", &"hold", &"free"]

var guns: CapitalGuns = null


func _init(p_guns: CapitalGuns) -> void:
	guns = p_guns


func register() -> void:
	var vars: Dictionary = {
		&"batteries": {"get": func() -> int: return guns.battery_count(), "type": TYPE_INT,
				"doc": "Capital interceptor batteries on the native rows"},
		&"pulses": {"get": func() -> int: return guns.pulses, "type": TYPE_INT,
				"doc": "Pulses the batteries fired since the last reset"},
		&"in_flight": {"get": func() -> int: return int(guns.intercept_readouts()[6]), "type": TYPE_INT,
				"doc": "Pulses in flight now"},
		&"met": {"get": func() -> int: return int(guns.intercept_readouts()[1]), "type": TYPE_INT,
				"doc": "Pulses that met a shot, since the rows were made"},
		&"share": {"get": func() -> String: return _share_text(_focused()),
				"doc": "The focused capital's hostile shots seen headed for its hull, and the share shot down"},
	}
	for k: int in CapitalGuns.SHOT_KINDS.size():
		var kind: String = CapitalGuns.SHOT_KINDS[k]
		vars[StringName("down_" + kind)] = {"get": func() -> int: return int(guns.downed[k]), "type": TYPE_INT,
				"doc": "%ss shot down since the last reset" % kind.capitalize()}
	DebugConsole.registry.register_provider(PROVIDER, ConsoleVars.new(vars), guns)
	DebugConsole.registry.register_command(ConsoleCommand.new(COMMAND,
			"Capital interceptors (M10-T13): info, hold (the focused capital's batteries stop), free",
			[ConsoleArg.enum_optional(&"action", ACTIONS, &"info")]), _cmd, guns)


func _cmd(args: Dictionary) -> ConsoleResult:
	var ship: CapitalShip = _focused()
	if ship == null:
		return ConsoleResult.failure("intercept: no capital ship with interceptors (capital spawn ea_omega)")
	var label: String = ship.targetable.display_name
	match StringName(args[&"action"]):
		&"hold":
			guns.hold_interceptors(ship, true)
			return ConsoleResult.line("%s: its interceptors hold" % label)
		&"free":
			guns.hold_interceptors(ship, false)
			return ConsoleResult.line("%s: its interceptors are free" % label)
	return ConsoleResult.success(_describe(ship))


# The focused capital, when it has interceptors.
func _focused() -> CapitalShip:
	var flight: CapitalFlight = CapitalFlight.of(guns.get_parent())
	var ship: CapitalShip = flight.focused() if flight != null else null
	if ship != null and _has_batteries(ship):
		return ship
	for other: CapitalShip in guns.ships():
		if _has_batteries(other):
			ship = other
	return ship if ship != null and _has_batteries(ship) else null


func _has_batteries(ship: CapitalShip) -> bool:
	return not guns.interceptors_of(ship).is_empty()


func _share_text(ship: CapitalShip) -> String:
	if ship == null:
		return "none"
	var share: PackedInt64Array = guns.intercept_share(ship)
	var pct: float = 100.0 * float(share[1]) / float(share[0]) if share[0] > 0 else 0.0
	return "%s: %d of %d shot down (%.0f %%)" % [ship.targetable.display_name, share[1], share[0], pct]


func _describe(ship: CapitalShip) -> PackedStringArray:
	var lines := PackedStringArray()
	var r: PackedInt64Array = guns.intercept_readouts()
	lines.append("pulses %d (in flight %d), met %d; down: bolts %d, heavy %d, missiles %d, torpedoes %d" % [guns.pulses, r[6], r[1],
			guns.downed[0], guns.downed[1], guns.downed[2], guns.downed[3]])
	lines.append(_share_text(ship) + (", held" if guns.interceptors_held(ship) else ""))
	for k: int in guns.interceptors_of(ship):
		var s: Dictionary = guns.state(k)
		var m: Dictionary = s["mount"]
		lines.append("%s %s: %d pulses%s" % [m["name"], m["weapon"], int(s["shots"]), "" if bool(s["works"]) else ", silent"])
	return lines
