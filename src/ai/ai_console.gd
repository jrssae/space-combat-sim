class_name AiConsole
extends RefCounted
## The console side of the AI drivers (architecture §16.4, M3-T06): provider `ai` (`ships`, `by_behaviour`, `think_us`;
## M4-T04 adds `mean_speed_mps`, `thinks_near`, `thinks_far`, `held`, `contacts_max`)
## and the command `ai <name>`, which prints that ship's brain `describe()` with a `*` on the behaviour in control.
## `ai <name> objective <target|none>` (M3-T17) sets an `AiPilot`'s objective; `ai <name> skill <rank|0-1>` and
## `ai <name> aggression <level|0-1>` (M3-T13) change its temperament live.
## Drivers come and go with the pool, so each registers these as owner when it enters the tree and hands them to another
## live driver when it leaves (`register`).


## Registers (or re-registers, replacing the entries) the provider and the command on `registry`, owned by `owner`.
static func register(registry: ConsoleRegistry, owner: Object) -> void:
	registry.register_provider(&"ai", provider(), owner)
	registry.register_command(command(), run, owner)


static func provider() -> ConsoleVars:
	return ConsoleVars.new({
		&"ships": {"get": ships, "doc": "AI ships in play: name, behaviour (state)"},
		&"by_behaviour": {"get": by_behaviour, "doc": "How many AI ships run each behaviour"},
		&"think_us": {"get": AiPilotDriver.think_us, "unit": "us",
				"doc": "Wall-clock time of every AI driver in the last physics tick (profiling only)"},
		&"mean_speed_mps": {"get": mean_speed_mps, "unit": "m/s", "doc": "Mean speed of the AI ships in play (M4-T04)"},
		&"thinks_near": {"get": AiPilotDriver.thinks_near,
				"doc": "AI ships within ai_think_near_m of the player that thought in the last tick (M4-T04)"},
		&"thinks_far": {"get": AiPilotDriver.thinks_far,
				"doc": "AI ships farther out (or with no player alive) that thought in the last tick, at ai_think_far_hz"},
		&"held": {"get": AiPilotDriver.held, "doc": "AI ships that held their last command in the last tick"},
		&"contacts_max": {"get": AiPilotDriver.contacts_max,
				"doc": "The most contacts one AI ship scored and avoided in the last tick (ai_nearest_k plus what it keeps)"},
	})


static func command() -> ConsoleCommand:
	return ConsoleCommand.new(&"ai", "Show an AI ship's behaviour, its state and every behaviour's last score; "
			+ "ai <name> objective <target|none> sends it at a target from any broadcast range; "
			+ "ai <name> skill <rookie|regular|veteran|ace|0-1>, ai <name> aggression <passive|cautious|balanced|aggressive|reckless|0-1>",
			[ConsoleArg.string_rest(&"name").with_suggestions(names)])


static func ships() -> PackedStringArray:
	var out := PackedStringArray()
	for driver: AiPilotDriver in AiPilotDriver.flying():
		var d: Dictionary = driver.brain.describe()
		out.append("%s %s (%s)" % [driver.combatant.display_name, d.get("behaviour", "none"), d.get("state", "none")])
	return out


static func mean_speed_mps() -> float:
	var flying: Array[AiPilotDriver] = AiPilotDriver.flying()
	var total: float = 0.0
	for driver: AiPilotDriver in flying:
		total += driver.combatant.ship.linear_velocity.length()
	return snappedf(total / flying.size(), 0.01) if not flying.is_empty() else 0.0


static func by_behaviour() -> Dictionary:
	var out: Dictionary = {}
	for driver: AiPilotDriver in AiPilotDriver.flying():
		var behaviour: String = str(driver.brain.describe().get("behaviour", "none"))
		out[behaviour] = int(out.get(behaviour, 0)) + 1
	return out


static func names() -> PackedStringArray:
	var out := PackedStringArray()
	for driver: AiPilotDriver in AiPilotDriver.flying():
		out.append(driver.combatant.display_name)
	return out


## Handler of `ai <name>` and `ai <name> objective <target|none>` (names case-insensitive).
static func run(args: Dictionary) -> ConsoleResult:
	var wanted: String = String(args[&"name"]).strip_edges()
	# `<name> <verb> <value>`: ship names hold spaces, never the verbs, and the last verb found wins.
	var verb: String = ""
	var value: String = ""
	var at: int = -1
	for word: String in VERBS:
		var found: int = (wanted + " ").to_lower().rfind(" %s " % word)
		if found > at:
			at = found
			verb = word
	if at >= 0:
		value = wanted.substr(at + verb.length() + 2).strip_edges()
		wanted = wanted.substr(0, at).strip_edges()
	for driver: AiPilotDriver in AiPilotDriver.flying():
		if driver.combatant.display_name.to_lower() == wanted.to_lower():
			match verb:
				"objective":
					return _set_objective(driver, value)
				"skill", "aggression":
					return _set_temperament(driver, verb, value)
			return ConsoleResult.success(describe_lines(driver.combatant.display_name, driver.brain.describe()))
	var known: PackedStringArray = names()
	return ConsoleResult.failure("no AI ship named '%s' (AI ships: %s)%s" % [wanted,
			", ".join(known) if not known.is_empty() else "none", ConsoleFormat.did_you_mean(wanted, known)])


const VERBS: Array[String] = ["objective", "skill", "aggression"]
const OBJECTIVE_NONE: String = "none"


static func _set_temperament(driver: AiPilotDriver, verb: String, value: String) -> ConsoleResult:
	var pilot := driver.brain as AiPilot
	var ship_name: String = driver.combatant.display_name
	if pilot == null:
		return ConsoleResult.failure("%s flies an M2 brain, which has no %s" % [ship_name, verb])
	var t := AiTemperament.new(pilot.temperament.skill, pilot.temperament.aggression)
	if verb == "skill":
		var v: float = AiTemperament.parse_skill(value)
		if v < 0.0:
			return ConsoleResult.failure("skill must be one of %s or a number 0-1, got '%s'" % [
					", ".join(PackedStringArray(AiTemperament.SKILL_RANKS.keys())), value])
		t.skill = v
	else:
		var v: float = AiTemperament.parse_aggression(value)
		if v < 0.0:
			return ConsoleResult.failure("aggression must be one of %s or a number 0-1, got '%s'" % [
					", ".join(PackedStringArray(AiTemperament.AGGRESSION_LEVELS.keys())), value])
		t.aggression = v
	pilot.set_temperament(t)
	return ConsoleResult.line("%s: skill %s, aggression %s" % [ship_name, AiTemperament.skill_name(t.skill),
			AiTemperament.aggression_name(t.aggression)])


static func _set_objective(driver: AiPilotDriver, target_name: String) -> ConsoleResult:
	var pilot := driver.brain as AiPilot
	var ship_name: String = driver.combatant.display_name
	if pilot == null:
		return ConsoleResult.failure("%s flies an M2 brain, which takes no objective" % ship_name)
	if target_name.is_empty():
		return ConsoleResult.failure("usage: ai <name> objective <target|none>")
	if target_name.to_lower() == OBJECTIVE_NONE:
		pilot.context.objective_name = ""
		return ConsoleResult.line("%s: no objective" % ship_name)
	var known := PackedStringArray()
	for node: Node in driver.get_tree().get_nodes_in_group(Targetable.GROUP):
		var targetable := node as Targetable
		if targetable == null or targetable.display_name.is_empty() or targetable.get_parent() == driver.combatant.ship:
			continue
		if targetable.display_name.to_lower() == target_name.to_lower():
			pilot.context.objective_name = targetable.display_name
			return ConsoleResult.line("%s: objective %s" % [ship_name, targetable.display_name])
		known.append(targetable.display_name)
	return ConsoleResult.failure("no target named '%s'%s" % [target_name, ConsoleFormat.did_you_mean(target_name, known)])


## The `ai <name>` lines for a brain's `describe()`: `NAME: behaviour (state)`, then its other fields, then the scores.
static func describe_lines(ship_name: String, d: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	out.append("%s: %s (%s)" % [ship_name, d.get("behaviour", "none"), d.get("state", "none")])
	var fields := PackedStringArray()
	for key: Variant in d:
		if key != "behaviour" and key != "state" and key != "scores":
			fields.append("%s %s" % [key, ConsoleFormat.value(d[key])])
	if not fields.is_empty():
		out.append("  " + ", ".join(fields))
	if d.has("scores"):
		var scores: Dictionary = d["scores"]
		var parts := PackedStringArray()
		for id: Variant in scores:
			parts.append("%s %.2f%s" % [id, float(scores[id]), " *" if str(id) == str(d.get("behaviour", "")) else ""])
		out.append("  scores: " + ", ".join(parts))
	return out
