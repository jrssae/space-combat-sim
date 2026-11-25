class_name CapitalBrainConsole
extends RefCounted
## The `capital_brain` provider and the `capbrain` command (M10-T16): the capital ships' native brains, on the `capital`
## command's focus. `capbrain` shows the focused ship's state, target, aim and helm; `hold` gives its helm orders to keep its
## course (its brain still names targets), `free` hands the helm back to its brain, `withdraw` sends it home (its hull is not
## touched: the exit is searched now), `charge <capital name>` makes it screen another ship (`none` stops).

const PROVIDER: StringName = &"capital_brain"
const COMMAND: StringName = &"capbrain"
const ACTIONS: Array[StringName] = [&"info", &"list", &"hold", &"free", &"withdraw", &"charge"]

var brains: CapitalBrains = null


func _init(p_brains: CapitalBrains) -> void:
	brains = p_brains


func register() -> void:
	DebugConsole.registry.register_provider(PROVIDER, ConsoleVars.new({
		&"ships": {"get": func() -> int: return brains.ships().size(), "type": TYPE_INT,
				"doc": "Capital ships with a native helm and brain"},
		&"states": {"get": func() -> String: return _states(), "doc": "How many capitals are in each brain state"},
		&"applied": {"get": func() -> int: return int(_readouts()[0]), "type": TYPE_INT,
				"doc": "Brain answers applied at the AI job's join so far"},
		&"stale": {"get": func() -> int: return int(_readouts()[1]), "type": TYPE_INT,
				"doc": "Brain answers dropped because their ship left or rejoined meanwhile"},
		&"withdrawals": {"get": func() -> int: return brains.withdraw_asks, "type": TYPE_INT,
				"doc": "Times a brain asked for a way out"},
		&"gone": {"get": func() -> int: return brains.gone, "type": TYPE_INT,
				"doc": "Capitals that withdrew through their exit and left play"},
		&"focus": {"get": func() -> String: return "; ".join(_describe(_focused())),
				"doc": "The focused capital's brain: state, target, aim, attitude, helm"},
	}), brains)
	DebugConsole.registry.register_command(ConsoleCommand.new(COMMAND,
			"Capital brains (M10-T16): info, list, hold, free, withdraw, charge <capital name|none> (on the capital command's focus)",
			[ConsoleArg.enum_optional(&"action", ACTIONS, &"info"), ConsoleArg.string_optional(&"name")]), _cmd, brains)


func _cmd(args: Dictionary) -> ConsoleResult:
	var action: StringName = StringName(args[&"action"])
	if action == &"list":
		var lines := PackedStringArray()
		for ship: CapitalShip in brains.ships():
			lines.append(" ".join(_describe(ship)))
		return ConsoleResult.success(lines)
	var ship: CapitalShip = _focused()
	if ship == null:
		return ConsoleResult.failure("capbrain: no capital ship (capital spawn ea_omega)")
	var label: String = ship.targetable.display_name
	match action:
		&"hold":
			ship.set_course(-ship.global_basis.z, ship.linear_velocity)
			return ConsoleResult.line("%s holds its course on orders" % label)
		&"free":
			ship.release_helm()
			return ConsoleResult.line("%s: its brain steers" % label)
		&"withdraw":
			var sim: SimCore = SimCore.for_tree(brains.get_tree())
			if sim == null:
				return ConsoleResult.failure("capbrain withdraw: no core")
			ship.release_helm()
			sim.core.capital_set_exit(ship.get_instance_id(), 0, 0.0, 0.0, 0.0)
			brains.withdraw(ship, sim.core)
			return ConsoleResult.line("%s withdraws via %s" % [label, brains.withdrawing_via(ship) if not brains.withdrawing_via(ship).is_empty() else "nothing (it fights on)"])
		&"charge":
			var wanted: String = str(args[&"name"]) if args[&"name"] != null else "none"
			if wanted == "none":
				ship.remove_meta(&"capital_charge")
			else:
				var charge: Node3D = BeamConsole.target_named(brains.get_parent(), wanted)
				if charge == null:
					return ConsoleResult.failure("capbrain charge <capital name|none>: no such ship")
				ship.set_meta(&"capital_charge", charge.get_instance_id())
			brains.refresh(ship)
			return ConsoleResult.line("%s screens %s" % [label, wanted])
	return ConsoleResult.success(_describe(ship))


func _focused() -> CapitalShip:
	var flight: CapitalFlight = CapitalFlight.of(brains.get_parent())
	var ship: CapitalShip = flight.focused() if flight != null else null
	return ship if ship != null and brains.ships().has(ship) else (brains.ships().back() if not brains.ships().is_empty() else null)


func _readouts() -> PackedInt64Array:
	var sim: SimCore = SimCore.for_tree(brains.get_tree())
	return sim.core.capital_readouts() if sim != null else PackedInt64Array([0, 0])


func _states() -> String:
	var counts: Dictionary = {}
	for ship: CapitalShip in brains.ships():
		var state: StringName = brains.brain_state(ship).get("state", &"none")
		counts[state] = int(counts.get(state, 0)) + 1
	var parts := PackedStringArray()
	for key: Variant in counts:
		parts.append("%s %d" % [key, counts[key]])
	return ", ".join(parts)


func _describe(ship: CapitalShip) -> PackedStringArray:
	var lines := PackedStringArray()
	if ship == null:
		return lines
	var s: Dictionary = brains.brain_state(ship)
	if s.is_empty():
		return lines
	var target: Node = instance_from_id(int(s["target"])) as Node if int(s["target"]) > 0 and is_instance_id_valid(int(s["target"])) else null
	var aim: Variant = s["aim"]
	var helm: Dictionary = ship.helm_state()
	lines.append("%s: %s%s, target %s%s, attitude %d, %d thinks" % [ship.targetable.display_name, s["state"],
			" (held)" if bool(s["held"]) else "", BeamConsole.name_of(target), " at %s" % (aim as Vector3).snappedf(1.0) if aim != null else "",
			int(s["attitude"]), int(s["thinks"])])
	lines.append("helm: heading %s, %.1f m/s%s" % [(helm.get("heading", Vector3.ZERO) as Vector3).snappedf(0.01),
			(helm.get("velocity", Vector3.ZERO) as Vector3).length(), ", flipping" if bool(helm.get("flipping", false)) else ""])
	var via: StringName = brains.withdrawing_via(ship)
	if not via.is_empty():
		lines.append("withdrawing via %s" % via)
	return lines
