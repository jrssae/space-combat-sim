class_name HangarConsole
extends RefCounted
## The `hangars` provider and the `hangar` command (M10-T17): the capital carriers' hangars, on the `capital` command's focus.
## `hangar` shows its stock, wings, bays, doors and lifts; `stock` fills it from its loadout (and the pool with it), `launch
## [type] [n]` sends craft out (carriers spawn full; `empty` empties one) (no type: its next wing), `recall` calls them home, `jump` calls them home and leaves after its
## wait, `auto on|off` lets it launch on its own or not, `door <bay> open|shut` drives a door by hand, `fold <ship name>`
## folds or spreads a shuttle's wings.

const PROVIDER: StringName = &"hangars"
const COMMAND: StringName = &"hangar"
const ACTIONS: Array[StringName] = [&"info", &"list", &"stock", &"empty", &"launch", &"recall", &"jump", &"auto", &"door", &"fold"]

var brains: CapitalBrains = null


func _init(p_brains: CapitalBrains) -> void:
	brains = p_brains


func register() -> void:
	DebugConsole.registry.register_provider(PROVIDER, ConsoleVars.new({
		&"carriers": {"get": func() -> int: return _hangars().size(), "type": TYPE_INT, "doc": "Capital ships with a hangar"},
		&"aboard": {"get": func() -> int: return _sum(func(h: CapitalHangar) -> int: return _aboard(h)), "type": TYPE_INT,
				"doc": "Craft aboard every hangar"},
		&"out": {"get": func() -> int: return _sum(func(h: CapitalHangar) -> int: return h.out_count()), "type": TYPE_INT,
				"doc": "Craft out of their hangars"},
		&"wings": {"get": func() -> int: return _sum(func(h: CapitalHangar) -> int: return h.wings_sent), "type": TYPE_INT,
				"doc": "Wings launched so far"},
		&"sent": {"get": func() -> int: return _sum(func(h: CapitalHangar) -> int: return h.sent), "type": TYPE_INT,
				"doc": "Craft launched so far"},
		&"recovered": {"get": func() -> int: return _sum(func(h: CapitalHangar) -> int: return h.recoveries), "type": TYPE_INT,
				"doc": "Craft recovered into a bay so far"},
		&"left_behind": {"get": func() -> int: return _sum(func(h: CapitalHangar) -> int: return h.left_behind), "type": TYPE_INT,
				"doc": "Craft left behind when their carrier jumped"},
		&"refused": {"get": func() -> int: return _sum(func(h: CapitalHangar) -> int: return h.refused), "type": TYPE_INT,
				"doc": "Launches refused (no power, a lost bay, no pooled ship)"},
		&"tick_us": {"get": func() -> float: return _mean_tick_us(), "unit": "us",
				"doc": "A hangar's own cost a tick, the mean over every carrier so far (the dock's rows and the hangar's decisions)"},
		&"focus": {"get": func() -> String: return "; ".join(_describe(_focused())), "doc": "The focused carrier's hangar"},
	}), brains)
	DebugConsole.registry.register_command(ConsoleCommand.new(COMMAND,
			"Carrier hangars (M10-T17): info, list, stock, empty, launch [type|wing] [n], recall, jump, auto on|off, door <bay> open|shut, fold <ship name> (on the capital command's focus)",
			[ConsoleArg.enum_optional(&"action", ACTIONS, &"info"), ConsoleArg.string_optional(&"what"),
			ConsoleArg.string_optional(&"how")]), _cmd, brains)


func _cmd(args: Dictionary) -> ConsoleResult:
	var action: StringName = StringName(args[&"action"])
	var what: String = str(args[&"what"]) if args[&"what"] != null else ""
	var how: String = str(args[&"how"]) if args[&"how"] != null else ""
	if action == &"list":
		var lines := PackedStringArray()
		for h: CapitalHangar in _hangars():
			lines.append(_describe(h)[0])
		return ConsoleResult.success(lines)
	if action == &"fold":
		var craft := BeamConsole.target_named(brains.get_parent(), what) as Ship
		var fold: WingFoldNode = WingFoldNode.attach(craft)
		if fold == null:
			return ConsoleResult.failure("hangar fold <ship name>: no such shuttle, or its wings do not fold")
		fold.set_folded(fold.is_spread())
		return ConsoleResult.line("%s: wings %s" % [BeamConsole.name_of(craft), "folding" if fold.is_spread() else "spreading"])
	var h: CapitalHangar = _focused()
	if h == null:
		return ConsoleResult.failure("hangar: no carrier (capital spawn ea_nova)")
	var label: String = h.ship.targetable.display_name
	match action:
		&"stock":
			var n: int = h.stock_from_loadout()
			return ConsoleResult.line("%s: %d craft aboard (%d built into the pool)" % [label, n, h.prepare_pool()])
		&"empty":
			h.empty()
			return ConsoleResult.line("%s: hangar emptied" % label)
		&"launch":
			if what.is_empty() or what == "wing":
				return ConsoleResult.line("%s launches a wing of %d" % [label, h.launch_wing()])
			var count: int = int(how) if how.is_valid_int() else 1
			return ConsoleResult.line("%s launches %d %s" % [label, h.launch(StringName(what), count), what])
		&"recall":
			return ConsoleResult.line("%s calls its craft home (%d on their way)" % [label, h.recall_all()])
		&"jump":
			return ConsoleResult.line("%s: %s" % [label, "ready to jump" if h.ready_to_jump() else "waiting for its craft"])
		&"auto":
			h.auto = what != "off"
			return ConsoleResult.line("%s launches on its own: %s" % [label, "on" if h.auto else "off"])
		&"door":
			if not h.bay_names().has(what) or h.door_of(what) == null:
				return ConsoleResult.failure("hangar door <bay> open|shut: bays with doors are %s" % ", ".join(_door_bays(h)))
			var moved: bool = h.ship.set_bay_door(what, how != "shut")
			h.set_physics_process(true)  # an idle hangar shuts a door it did not open once its bay has been idle a while
			return ConsoleResult.line("%s %s: %s" % [label, what, ("opening" if how != "shut" else "shutting") if moved else "no power"])
	return ConsoleResult.success(_describe(h))


func _hangars() -> Array[CapitalHangar]:
	var out: Array[CapitalHangar] = []
	for ship: CapitalShip in brains.ships():
		if is_instance_valid(ship) and ship.hangar != null:
			out.append(ship.hangar)
	return out


func _focused() -> CapitalHangar:
	var flight: CapitalFlight = CapitalFlight.of(brains.get_parent())
	var ship: CapitalShip = flight.focused() if flight != null else null
	if ship != null and ship.hangar != null:
		return ship.hangar
	var all: Array[CapitalHangar] = _hangars()
	return all.back() if not all.is_empty() else null


func _sum(per: Callable) -> int:
	var n: int = 0
	for h: CapitalHangar in _hangars():
		n += int(per.call(h))
	return n


func _mean_tick_us() -> float:
	var us: float = 0.0
	var n: int = 0
	for h: CapitalHangar in _hangars():
		us += h.tick_us
		n += h.ticks
	return us / float(maxi(n, 1))


static func _aboard(h: CapitalHangar) -> int:
	var n: int = 0
	for type: Variant in h.stock:
		n += int(h.stock[type])
	return n


static func _door_bays(h: CapitalHangar) -> PackedStringArray:
	var out := PackedStringArray()
	for bay: String in h.bay_names():
		if h.door_of(bay) != null:
			out.append(bay)
	return out


func _describe(h: CapitalHangar) -> PackedStringArray:
	var lines := PackedStringArray()
	if h == null:
		return lines
	lines.append("%s: %d aboard %s, %d out, %d queued, wings %d (%d sent, %d lost), threat %d fighters %d warships%s%s%s" % [
			h.ship.targetable.display_name, _aboard(h), h.stock, h.out_count(), h.queued_count(), h.wings_out, h.wing_fighters,
			h.wing_losses, h.threat_fighters, h.threat_warships, ", launching" if h.is_launching() else "",
			", recalling" if h.recalling else "", ", jumping (%.0f s)" % h.waited_s if h.jumping else ""])
	for bay: String in h.bay_names():
		var door: BayDoorNode = h.door_of(bay)
		var lift: BayElevator = h.lift_of(bay)
		lines.append("  %s: %s%s" % [bay, "door %.0f %% open" % (door.amount * 100.0) if door != null else "no door",
				", lift %s" % lift.state_name() if lift != null else ""])
	return lines
