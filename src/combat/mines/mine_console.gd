class_name MineConsole
extends RefCounted
## The `mines` provider and command (M10-T15, `info.md`): what is in play in every field, what set the mines off, the nearest one
## to the player, and the commands to look at one, set it off, list the fields, lay a test field in front of the player and clear
## them all. `Main` registers it at start (the commands work with no field in play), owned by `Main`.

const PROVIDER: StringName = &"mines"
const COMMAND: StringName = &"mines"
const ACTIONS: Array[StringName] = [&"view", &"set_off", &"list", &"spawn", &"clear"]
## How far `mines view` puts the player from the nearest mine, m.
const VIEW_M: float = 800.0
## A `mines spawn` field: its radius, m, and how far ahead of the player its centre lies by default, m.
const SPAWN_RADIUS_M: float = 400.0
const SPAWN_AHEAD_M: float = 1500.0
const SPAWN_COUNT: int = 40


func register(owner: Object) -> void:
	DebugConsole.registry.register_provider(PROVIDER, ConsoleVars.new({
		&"fields": {"get": func() -> int: return MineField.fields.size(), "doc": "Minefields in the tree"},
		&"laid": {"get": func() -> int: return _sum(func(f: MineField) -> int: return f.capacity), "doc": "Mine slots in every field, in play or not"},
		&"in_play": {"get": func() -> int: return MineField.total_in_play(), "doc": "Mines in play"},
		&"set_off": {"get": func() -> int: return _sum(func(f: MineField) -> int: return _total(f.by_cause)), "doc": "Mines set off so far"},
		&"by_trigger": {"get": func() -> int: return _cause(0), "doc": "Set off by a hull hostile to their layer inside the trigger"},
		&"by_touch": {"get": func() -> int: return _cause(1), "doc": "Set off by a hull of any side touching them"},
		&"by_shot": {"get": func() -> int: return _cause(2), "doc": "Set off by a bolt, beam or missile of any side"},
		&"by_blast": {"get": func() -> int: return _cause(3), "doc": "Set off by a blast (another mine's, a death's, a warhead)"},
		&"by_fuse": {"get": func() -> int: return _cause(4), "doc": "Energy mines whose fuse ran out"},
		&"by_flight": {"get": func() -> int: return _cause(5), "doc": "Mines in flight that struck something or ran out of time"},
		&"shot_down": {"get": func() -> int: return _sum(func(f: MineField) -> int: return f.shot_down_count),
				"doc": "Mines in flight an interceptor shot down"},
		&"shots_on_flight": {"get": func() -> int: return _sum(func(f: MineField) -> int: return f.shots_on_flight()),
				"doc": "Hostile bolts and missiles that met a mine in flight (the guns' and fighters' shots take its toughness as pulses do)"},
		&"laid_in_battle": {"get": func() -> int: return _sum(func(f: MineField) -> int: return f.mines_laid), "doc": "Mines the layers or `lay` put in play"},
		&"step_us": {"get": func() -> float: return _sum_f(func(f: MineField) -> float: return f.step_us), "unit": "us",
				"doc": "Wall-clock cost of the last tick's mine step, every field (a readout)"},
		&"relays": {"get": func() -> bool: return MineField.fields.any(func(f: MineField) -> bool: return f.relays),
				"doc": "Whether a spent mine is laid again (only during a bench run)"},
		&"nearest_m": {"get": func() -> float: return _nearest_to_player()[2], "unit": "m",
				"doc": "The nearest mine in play to the player, centre to centre (-1 with none)"},
		&"nearest_side": {"get": func() -> String: return _nearest_to_player()[3], "doc": "That mine's side"},
		&"nearest_hostile": {"get": func() -> bool: return _nearest_to_player()[4],
				"doc": "Whether that mine's side is hostile to the player (only then does its trigger go off on the player)"},
	}), owner)
	DebugConsole.registry.register_command(ConsoleCommand.new(COMMAND,
			"Mines (M10-T15): view [metres] (look at the nearest), set_off (as a shot would), list, spawn [metres] [kind] [count] "
			+ "(a hostile test field that far ahead of the player), clear",
			[ConsoleArg.enum_optional(&"action", ACTIONS, &"view"), ConsoleArg.float_optional(&"metres", VIEW_M, 50.0),
			ConsoleArg.string_optional(&"kind", "mine_prox"), ConsoleArg.int_optional(&"count", SPAWN_COUNT, 1, 2000)]), _cmd, owner)


func _cmd(args: Dictionary) -> ConsoleResult:
	match StringName(args[&"action"]):
		&"list":
			return _list()
		&"spawn":
			return _spawn(StringName(args[&"kind"]), int(args[&"count"]), float(args[&"metres"]))
		&"clear":
			return ConsoleResult.line("%d mines cleared" % _clear())
	var nearest: Array = _nearest_to_player()
	var field: MineField = nearest[0]
	if field == null:
		return ConsoleResult.failure("mines: no player or no mine in play")
	var slot: int = nearest[1]
	if StringName(args[&"action"]) == &"set_off":
		field.strike_any(slot)
		return ConsoleResult.line("mine %d of %s (%s, %.0f m off) set off" % [slot, field.name, nearest[3], nearest[2]])
	var ship := _player().body() as Ship
	if ship == null:
		return ConsoleResult.failure("mines: no player ship to move")
	var frame: WorldFrame = WorldFrame.of(field)
	if frame != null:
		frame.return_home()  # the frame back on the home rail first (M7-T71)
	var metres: float = float(args[&"metres"])
	var info: Array = field.rows.info(slot)
	var look: Vector3 = field.global_position + (info[4] as Vector3)
	var at: Vector3 = look + Vector3(0.6, 0.35, 0.72).normalized() * metres
	ship.reset_to(Transform3D(Basis.looking_at((look - at).normalized(), Vector3.UP), at))
	ship.linear_velocity = frame.rest_velocity() if frame != null else Vector3.ZERO
	ship.angular_velocity = Vector3.ZERO
	return ConsoleResult.line("%.0f m from mine %d of %s (%s)" % [metres, slot, field.name, nearest[3]])


func _list() -> ConsoleResult:
	var lines := PackedStringArray()
	for f: MineField in MineField.fields:
		lines.append("%s %s slots=%d in_play=%d set_off=%d shot_down=%d" % [f.name, "placed" if f.placed else "battle", f.capacity,
				f.alive_count(), _total(f.by_cause), f.shot_down_count])
	return ConsoleResult.line("no minefields" if lines.is_empty() else "\n".join(lines))


# A sphere field of `count` mines of `kind_name` `metres` ahead of the player, of the first faction hostile to the player.
func _spawn(kind_name: StringName, count: int, metres: float) -> ConsoleResult:
	var player: Damageable = _player()
	if player == null or player.body() == null:
		return ConsoleResult.failure("mines: no player to lay ahead of")
	if not MineKinds.is_kind(kind_name):
		return ConsoleResult.failure("mines: kind must be one of %s" % [MineKinds.NAMES])
	var frame: WorldFrame = WorldFrame.of(player.body())
	if frame == null:
		return ConsoleResult.failure("mines: no world")
	var side: StringName = &""
	for id: StringName in Factions.table().ids():
		if Factions.is_hostile(id, player.faction):
			side = id
			break
	if side == &"":
		return ConsoleResult.failure("mines: no faction is hostile to the player's")
	var body: Node3D = player.body()
	var centre: Vector3 = body.global_position - body.global_basis.z * metres
	var plan: MineFieldPlan = MineFieldPlan.place({"id": "console", "faction": String(side), "kind": String(kind_name),
			"pattern": "sphere", "radius_m": SPAWN_RADIUS_M, "count": count, "seed": Engine.get_physics_frames(), "min_gap_m": 20.0})
	var field: MineField = MineField.spawn_in(frame, frame.to_universe(centre), true)
	var made: int = field.build(plan.rows)
	return ConsoleResult.line("%d %s mines of %s laid %.0f m ahead (%s)" % [made, kind_name, side, metres, field.name])


# Takes every mine in every field out of play; how many there were.
func _clear() -> int:
	var n: int = 0
	for f: MineField in MineField.fields:
		n += f.clear()
	return n


func _total(counts: PackedInt32Array) -> int:
	var n: int = 0
	for c: int in counts:
		n += c
	return n


func _cause(index: int) -> int:
	return _sum(func(f: MineField) -> int: return f.by_cause[index])


func _sum(of: Callable) -> int:
	var n: int = 0
	for f: MineField in MineField.fields:
		if is_instance_valid(f):
			n += int(of.call(f))
	return n


func _sum_f(of: Callable) -> float:
	var n: float = 0.0
	for f: MineField in MineField.fields:
		if is_instance_valid(f):
			n += float(of.call(f))
	return n


# The player's hull, or null.
func _player() -> Damageable:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	for node: Node in tree.get_nodes_in_group(Damageable.GROUP):
		var d := node as Damageable
		if d != null and d.respects_god_mode and d.body() != null:
			return d
	return null


# The nearest mine in play to the player: `[field, slot, distance, side, hostile to the player]`, a null field for none.
func _nearest_to_player() -> Array:
	var player: Damageable = _player()
	if player == null:
		return [null, -1, -1.0, "", false]
	var from: Vector3 = player.body().global_position
	var best_field: MineField = null
	var best: int = -1
	var best_sq: float = INF
	for f: MineField in MineField.fields:
		if not is_instance_valid(f) or f.rows == null:
			continue
		var slot: int = f.nearest_to(from)
		if slot < 0:
			continue
		var info: Array = f.rows.info(slot)
		var d_sq: float = from.distance_squared_to(f.global_position + (info[4] as Vector3))
		if d_sq < best_sq:
			best_sq = d_sq
			best = slot
			best_field = f
	if best_field == null:
		return [null, -1, -1.0, "", false]
	var side: StringName = best_field.side_of(best)
	return [best_field, best, sqrt(best_sq), String(side), Factions.is_hostile(side, player.faction)]
