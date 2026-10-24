class_name AiConsole
extends RefCounted
## The console side of the AI drivers (architecture §16.4, M3-T06): provider `ai` (`ships`, `by_behaviour`, `think_us`)
## and the command `ai <name>`, which prints that ship's brain `describe()`: `NAME: behaviour (state)`, the behaviour's
## other fields, then every behaviour's score with `*` on the one in control (M2 brains print their `describe()`).
## The drivers are many nodes and come and go with the pool, so each `AiPilotDriver` entering the tree registers these with
## itself as owner and hands them to another live driver when it leaves (`register`); the entries read
## `AiPilotDriver.flying()` every time, so they always show the ships in play.


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
	})


static func command() -> ConsoleCommand:
	return ConsoleCommand.new(&"ai", "Show an AI ship's behaviour, its state and every behaviour's last score",
			[ConsoleArg.string_rest(&"name").with_suggestions(names)])


static func ships() -> PackedStringArray:
	var out := PackedStringArray()
	for driver: AiPilotDriver in AiPilotDriver.flying():
		var d: Dictionary = driver.brain.describe()
		out.append("%s %s (%s)" % [driver.combatant.display_name, d.get("behaviour", "none"), d.get("state", "none")])
	return out


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


## Handler of `ai <name>` (case-insensitive).
static func run(args: Dictionary) -> ConsoleResult:
	var wanted: String = String(args[&"name"]).strip_edges()
	for driver: AiPilotDriver in AiPilotDriver.flying():
		if driver.combatant.display_name.to_lower() == wanted.to_lower():
			return ConsoleResult.success(describe_lines(driver.combatant.display_name, driver.brain.describe()))
	var known: PackedStringArray = names()
	return ConsoleResult.failure("no AI ship named '%s' (AI ships: %s)%s" % [wanted,
			", ".join(known) if not known.is_empty() else "none", ConsoleFormat.did_you_mean(wanted, known)])


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
