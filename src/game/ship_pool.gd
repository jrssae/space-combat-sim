class_name ShipPool
extends Node3D
## Pooled AI ships (architecture §15.6, D22). GDGS re-merges the splat data of every node in the scene each time a
## `GaussianSplatNode` enters or leaves the tree, so a spawn mid-fight would hitch. Raiders are therefore built once, at
## scenario load (`prepare`), and only switched afterwards: parked ships are hidden, not processing (their bodies leave
## the physics space), not targetable and not hittable; `acquire` brings one back at a universe position, `release`
## parks it again. The number of splat nodes in the tree never changes.
##
## This node is `World/Ships`: the parent of the pooled ships, spawned through `World.spawn` like everything else
## (it has an identity transform, so a ship's local position is its World position). Set `world`, `projectiles` and
## (for the console's `spawn`) `player` before `prepare`.
##
## Console (§15.13, D27): provider `raiders` (`pool_size`, `free`, `alive`, `list`, `selected_brain`) and commands
## `despawn [target|all]` and `spawn raider [idle|patrol|attack|aggro] [distance_m] [yaw_deg] [pitch_deg]` (M2-T09 moves
## the command to the `WaveDirector`). Raiders are named `RAIDER <n>`, the next free number. A pooled ship has an
## `AiPilotDriver`; `acquire` gives it the brain and `release` takes it away.

const DEFAULT_TYPE: StringName = &"raider_fighter"
const NAME_PREFIX: String = "RAIDER"
const SPAWN_CHOICES: Array[StringName] = [&"raider"]
const DESPAWN_CHOICES: Array[StringName] = [&"target", &"all"]
## Where parked ships wait: far below the play area (universe metres).
const PARK_Y_M: float = -1.0e6

var world: WorldFrame = null
var projectiles: Node3D = null
## The player's ship: the console's `spawn` places raiders relative to it and `despawn target` uses its selection.
var player: Ship = null

var _all: Array[Combatant] = []
var _free: Array[Combatant] = []
var _types: Dictionary[Combatant, StringName] = {}
var _in_use: Array[Combatant] = []


func _ready() -> void:
	DebugConsole.registry.register_provider(&"raiders", ConsoleVars.new({
		&"pool_size": {"get": func() -> int: return _all.size(), "doc": "Raiders built at scenario load"},
		&"free": {"get": func() -> int: return _free.size(), "doc": "Raiders parked and ready"},
		&"alive": {"get": func() -> int: return _in_use.size(), "doc": "Raiders in the world"},
		&"list": {"get": _console_list, "doc": "Raiders in the world: name, hull %, range from the player"},
		&"selected_brain": {"get": _console_selected_brain, "doc": "The player's selected raider's behaviour and state"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"spawn",
			"Take a raider from the pool ahead of the player, nose toward the player, turned by yaw then pitch",
			[ConsoleArg.enum_required(&"type", SPAWN_CHOICES), ConsoleArg.string_rest(&"options").make_optional("")]),
			_cmd_spawn, self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"despawn",
			"Return the selected raider, or every raider, to the pool without effects",
			[ConsoleArg.enum_optional(&"which", DESPAWN_CHOICES, &"target")]), _cmd_despawn, self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


## Builds `count` more ships of `type` and parks them. Returns how many were built.
func prepare(type: StringName, count: int) -> int:
	assert(world != null and projectiles != null, "ShipPool.prepare: set world and projectiles first")
	var spec: ShipSpec = ShipCatalog.spec_for(type)
	if spec == null:
		return 0
	var built: int = 0
	for i: int in count:
		var combatant: Combatant = ShipAssembly.build(spec, world, projectiles, {
			ShipAssembly.OPT_FACTION: Factions.RAIDERS,
			ShipAssembly.OPT_DISPLAY_NAME: "",
			ShipAssembly.OPT_FORCE_ASSIST: true,
			ShipAssembly.OPT_AI: true,
		})
		world.spawn(combatant.ship, _park_position(), Basis.IDENTITY, self)
		_park(combatant)
		_all.append(combatant)
		_free.append(combatant)
		_types[combatant] = type
		built += 1
	return built


## Takes a ship out of the pool and puts it at `at` (universe) with orientation `basis` and World-frame `velocity`, at
## full hull, fuel and charge. `brain` is kept for the AI (M2-T07). Returns null, with one warning, when the pool is
## empty. The ship is enabled first, then placed, then its physics interpolation is reset (no smear from the park).
func acquire(display_name: String, at: UniversePos, basis: Basis = Basis.IDENTITY, velocity: Vector3 = Vector3.ZERO,
		brain: PilotBrain = null, type: StringName = DEFAULT_TYPE) -> Combatant:
	var combatant: Combatant = _take(type)
	if combatant == null:
		push_warning("ShipPool: no free %s (pool of %d, all in use)" % [type, _count_of(type)])
		return null
	var ship: Ship = combatant.ship
	ship.process_mode = Node.PROCESS_MODE_INHERIT
	ship.visible = true
	ship.reset_to(Transform3D(basis, world.universe_to_local(at)))
	ship.linear_velocity = velocity
	ship.set_flight_command(FlightCommand.new())
	ship.set_combat_command(CombatCommand.new())
	ship.targeting.clear_selection()
	combatant.cannon.gate.reset()
	combatant.damageable.restore()
	combatant.display_name = display_name
	combatant.targetable.display_name = display_name
	_set_brain(combatant, brain)
	_in_use.append(combatant)
	return combatant


## Parks a ship again (no effects; destruction effects are `DestructionDirector`'s). Ignores ships not in use.
func release(combatant: Combatant) -> void:
	if combatant == null or not _in_use.has(combatant):
		return
	_in_use.erase(combatant)
	_park(combatant)
	_free.append(combatant)


## Ships currently in the world.
func alive() -> Array[Combatant]:
	return _in_use.duplicate()


## Every pooled ship, parked or not.
func all_ships() -> Array[Combatant]:
	return _all.duplicate()


func pool_size() -> int:
	return _all.size()


func free_count() -> int:
	return _free.size()


## The in-use ship whose `Targetable` has this instance id, or null.
func find_by_target_id(target_id: int) -> Combatant:
	for combatant: Combatant in _in_use:
		if combatant.targetable.get_instance_id() == target_id:
			return combatant
	return null


## `RAIDER <n>` with the smallest n not used by a ship in the world.
func next_name() -> String:
	var taken: Dictionary = {}
	for combatant: Combatant in _in_use:
		taken[combatant.display_name] = true
	var n: int = 1
	while taken.has("%s %d" % [NAME_PREFIX, n]):
		n += 1
	return "%s %d" % [NAME_PREFIX, n]


# --- internals ---------------------------------------------------------------------------------------------------


func _park_position() -> UniversePos:
	return UniversePos.new(0.0, PARK_Y_M, 0.0)


func _park(combatant: Combatant) -> void:
	var ship: Ship = combatant.ship
	ship.visible = false
	ship.process_mode = Node.PROCESS_MODE_DISABLED
	ship.linear_velocity = Vector3.ZERO
	ship.angular_velocity = Vector3.ZERO
	combatant.targetable.display_name = ""
	_set_brain(combatant, null)


func _set_brain(combatant: Combatant, brain: PilotBrain) -> void:
	if combatant.driver != null:
		combatant.driver.brain = brain


func _take(type: StringName) -> Combatant:
	for i: int in _free.size():
		if _types.get(_free[i]) == type:
			var combatant: Combatant = _free[i]
			_free.remove_at(i)
			return combatant
	return null


func _count_of(type: StringName) -> int:
	var n: int = 0
	for combatant: Combatant in _all:
		n += 1 if _types.get(combatant) == type else 0
	return n


# --- console -----------------------------------------------------------------------------------------------------


func _console_list() -> PackedStringArray:
	var out := PackedStringArray()
	for combatant: Combatant in _in_use:
		var range_text: String = ""
		if player != null and is_instance_valid(player):
			range_text = " %.0f m" % player.global_position.distance_to(combatant.ship.global_position)
		out.append("%s hull %.0f%%%s" % [combatant.display_name, 100.0 * combatant.damageable.hull.fraction(), range_text])
	return out


func _cmd_spawn(args: Dictionary) -> ConsoleResult:
	if player == null or not is_instance_valid(player) or world == null:
		return ConsoleResult.failure("no player ship to place the raider relative to")
	# `[behaviour] [distance_m] [yaw_deg] [pitch_deg]`: the behaviour word is optional (idle), the numbers too (30 0 0).
	var words: PackedStringArray = String(args[&"options"]).split(" ", false)
	var behaviour: StringName = &"idle"
	if not words.is_empty() and BrainFactory.BEHAVIOURS.has(StringName(words[0])):
		behaviour = StringName(words[0])
		words.remove_at(0)
	var numbers: Array[float] = [30.0, 0.0, 0.0]
	if words.size() > 3:
		return ConsoleResult.failure("spawn raider [idle|patrol|attack|aggro] [distance_m] [yaw_deg] [pitch_deg]")
	for i: int in words.size():
		if not words[i].is_valid_float():
			return ConsoleResult.failure("'%s' is not a number (spawn raider [behaviour] [distance_m] [yaw_deg] [pitch_deg])" % words[i])
		numbers[i] = words[i].to_float()
	var distance: float = clampf(numbers[0], 1.0, 20000.0)
	var forward: Vector3 = -player.global_basis.z
	var up: Vector3 = Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	# The nose points back at the player; yaw turns it about its own up axis, then pitch about its own right axis.
	var facing: Basis = Basis.looking_at(-forward, up)
	var basis: Basis = facing * Basis(Vector3.UP, deg_to_rad(numbers[1])) * Basis(Vector3.RIGHT, deg_to_rad(numbers[2]))
	var local: Vector3 = player.global_position + forward * distance
	var at: UniversePos = world.to_universe(local)
	var raider_name: String = next_name()
	var made: Dictionary = BrainFactory.from_behaviour(_console_behaviour(behaviour, basis), at, hash([raider_name, 0]))
	if not bool(made["ok"]):
		return ConsoleResult.failure(String(made["error"]))
	var combatant: Combatant = acquire(raider_name, at, basis, player.linear_velocity, made["brain"] as PilotBrain)
	if combatant == null:
		return ConsoleResult.failure("the raider pool is empty (%d of %d in use)" % [_in_use.size(), _all.size()])
	player.targeting.refresh()  # selectable by name in the very next console statement
	return ConsoleResult.line("%s (%s) at %.0f m" % [raider_name, behaviour, distance])


# The scenario-style behaviour dictionary for a console spawn: patrol and aggro fly a triangle of 800 m legs around the
# spawn point in the raider's own frame.
func _console_behaviour(behaviour: StringName, basis: Basis) -> Dictionary:
	var spec: Dictionary = {"type": String(behaviour)}
	if behaviour == &"patrol" or behaviour == &"aggro":
		var legs: Array = []
		for v: Vector3 in [Vector3(0.0, 0.0, -800.0), Vector3(700.0, 0.0, -300.0), Vector3(-700.0, 0.0, -300.0)]:
			var w: Vector3 = basis * v
			legs.append([w.x, w.y, w.z])
		spec["waypoints"] = legs
	return spec


func _console_selected_brain() -> Variant:
	if player == null or not is_instance_valid(player) or not player.targeting.system.has_selection():
		return null
	var combatant: Combatant = find_by_target_id(player.targeting.selected_id())
	if combatant == null or combatant.driver == null or combatant.driver.brain == null:
		return null
	return combatant.driver.brain.describe()


func _cmd_despawn(args: Dictionary) -> ConsoleResult:
	var which: StringName = StringName(args[&"which"])
	if which == &"all":
		var count: int = _in_use.size()
		for combatant: Combatant in alive():
			release(combatant)
		return ConsoleResult.line("returned %d raider(s) to the pool" % count)
	if player == null or not is_instance_valid(player) or not player.targeting.system.has_selection():
		return ConsoleResult.failure("no target selected")
	var target: Combatant = find_by_target_id(player.targeting.selected_id())
	if target == null:
		return ConsoleResult.failure("the selected target is not a pooled raider")
	var released_name: String = target.display_name
	release(target)
	return ConsoleResult.line("returned %s to the pool" % released_name)
