class_name EncounterConsole
extends RefCounted
## The encounters' console (architecture §18 D58, §6.4): command `encounters [on|off|status|next|force|clear] [kind]` and
## provider `encounters`, registered by the `EncounterDirector` that owns them.

const ACTIONS: Array[StringName] = [&"status", &"on", &"off", &"next", &"force", &"clear"]


static func register(director: EncounterDirector) -> void:
	var registry: ConsoleRegistry = DebugConsole.registry
	registry.register_command(ConsoleCommand.new(&"encounters",
			"Free-flight encounters: status, on (builds the pools), off, next (start the next one now), force <raid|patrol|traffic>, clear (every encounter ship back to its pool)",
			[ConsoleArg.enum_optional(&"action", ACTIONS, &"status"),
			ConsoleArg.enum_optional(&"kind", EncounterPlan.KINDS, null)] as Array[ConsoleArg]),
			func(args: Dictionary) -> ConsoleResult: return _run(director, args), director)
	registry.register_provider(&"encounters", ConsoleVars.new({
		&"on": {"get": func() -> bool: return director.on, "doc": "Whether encounters are on"},
		&"pools_built": {"get": func() -> bool: return director.pools_built, "doc": "Whether the encounter pools are built"},
		&"seed": {"get": func() -> int: return director.seed_value, "doc": "The session seed the plan draws from"},
		&"interval_s": {"get": func() -> float: return director.plan.interval_s if director.plan != null else -1.0,
				"unit": "s", "doc": "Mean time between encounters (-1 before they first turn on)"},
		&"max_ships": {"get": director.cap, "doc": "Most encounter ships in play at once (settings.encounter_max_ships)"},
		&"alive": {"get": director.alive_count, "doc": "Encounter ships in play"},
		&"raiders": {"get": func() -> int: return director.alive_of(&"raid"), "doc": "Of them, raiders"},
		&"patrol": {"get": func() -> int: return director.alive_of(&"patrol"), "doc": "Of them, patrolling Starfuries"},
		&"traffic": {"get": func() -> int: return director.alive_of(&"traffic"), "doc": "Of them, civilian traffic"},
		&"next_index": {"get": func() -> int: return director.next_index, "doc": "The next event the plan hands out"},
		&"next_in_s": {"get": director.next_in_s, "unit": "s",
				"doc": "Encounter time to the next event (0 while one waits, -1 before they first turn on)"},
		&"waiting": {"get": func() -> String: return director.waiting.summary() if director.waiting != null else "none",
				"doc": "An event held by the cap or the pools"},
		&"started": {"get": func() -> int: return director.events_started, "doc": "Events started so far"},
		&"released": {"get": func() -> int: return director.ships_released, "doc": "Ships returned to their pools so far"},
		&"last_event": {"get": func() -> String: return director.last_event.summary() if director.last_event != null else "none",
				"doc": "The last event started"},
		&"check_work": {"get": func() -> int: return director.check_work,
				"doc": "Ships the last release check looked at (its own, never every ship in play)"},
		&"build_ms": {"get": func() -> int: return director.build_ms, "unit": "ms", "doc": "Time the pools took to build"},
		&"gate_events": {"get": func() -> int: return director.gate_events,
				"doc": "Events that came out of or left through the jumpgate (M6-T14)"},
		&"gate_in_transit": {"get": func() -> int: return director.in_transit,
				"doc": "Ships waiting for the jumpgate's arrival vortex to open"},
	}), director)


static func _run(director: EncounterDirector, args: Dictionary) -> ConsoleResult:
	var action: StringName = StringName(args[&"action"])
	match action:
		&"on":
			return ConsoleResult.line(director.enable())
		&"off":
			director.disable()
			return ConsoleResult.line("encounters off; %d ship(s) in play fly on until released" % director.alive_count())
		&"clear":
			return ConsoleResult.line("returned %d encounter ship(s) to their pools" % director.release_all())
		&"next", &"force":
			if not director.on:
				return ConsoleResult.failure("encounters are off (encounters on first)")
			var kind: Variant = args.get(&"kind")
			if action == &"force" and kind == null:
				return ConsoleResult.failure("encounters force <%s>" % "|".join(PackedStringArray(EncounterPlan.KINDS)))
			if action == &"next" and director.waiting != null:
				var held: EncounterEvent = director.waiting
				if not director.start(held):
					return ConsoleResult.failure("%s still waits (%d of %d ships in play)" % [held.summary(),
							director.alive_count(), director.cap()])
				director.waiting = null
				return ConsoleResult.line("started %s" % held.summary())
			var e: EncounterEvent = director.take_forced(StringName(kind)) if action == &"force" else director.take_next()
			if not director.start(e):
				if action == &"next":
					director.waiting = e  # a scheduled event is not lost: it waits like one that came on time
					return ConsoleResult.line("%s waits: %d of %d ships in play, or its pools are spent" % [e.summary(),
							director.alive_count(), director.cap()])
				return ConsoleResult.failure("%s does not fit: %d of %d ships in play, or its pools are spent" % [e.summary(),
						director.alive_count(), director.cap()])
			return ConsoleResult.line("started %s" % e.summary())
	return ConsoleResult.line(_status(director))


static func _status(director: EncounterDirector) -> String:
	var parts := PackedStringArray(["encounters %s" % ("on" if director.on else "off")])
	parts.append("%d of %d ships in play (%d raiders, %d patrol, %d traffic)" % [director.alive_count(), director.cap(),
			director.alive_of(&"raid"), director.alive_of(&"patrol"), director.alive_of(&"traffic")])
	if director.plan != null:
		parts.append("next #%d in %.0f s" % [director.next_index, director.next_in_s()])
	if director.waiting != null:
		parts.append("waiting: %s" % director.waiting.summary())
	return "; ".join(parts)
