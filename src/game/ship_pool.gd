class_name ShipPool
extends Node3D
## Pooled AI ships (architecture §15.6, D22). GDGS re-merges the splat data of every node in the scene each time a
## `GaussianSplatNode` enters or leaves the tree, so a spawn mid-fight would hitch. Raiders and allied Starfuries are built
## once at scenario load (`prepare`) and only switched afterwards: parked ships are hidden, not processing, not targetable
## and not hittable. `acquire` brings one back at a universe position, `release` parks it again. The splat node count never
## changes.
##
## Each type is built with its `ShipCatalog` faction (`raiders`, `earth_alliance`). Whoever acquires a ship names it;
## `next_name(prefix, first)` finds the next free callsign.
##
## This node is `World/Ships`, with an identity transform so a ship's local position is its World position. Set `world`,
## `projectiles` and (for the console's `spawn`) `player` before `prepare`.
##
## Console (§15.13, D27, §16.4): providers `raiders` and `allies`, and commands `despawn [target|all]` and
## `spawn <raider|ally> [behaviour] [distance_m] [yaw_deg] [pitch_deg] [lights=on|off]` (an ally takes only `idle` or `ai`). Raiders are
## named `RAIDER <n>`, allies `ALPHA <n>` from 2 (the player is ALPHA 1). A pooled ship has an `AiPilotDriver`; `acquire`
## gives it the brain and `release` takes it away.

## A pooled ship is back in play. It is somebody new, so per-ship records start over (M3-T16).
signal acquired(combatant: Combatant)

const DEFAULT_TYPE: StringName = &"raider_fighter"
const ALLY_TYPE: StringName = &"starfury_ally"
const NAME_PREFIX: String = "RAIDER"
const ALLY_NAME_PREFIX: String = "ALPHA"
## The wing leader (the player) is ALPHA 1.
const ALLY_FIRST_NUMBER: int = 2
const SPAWN_CHOICES: Array[StringName] = [&"raider", &"ally"]
## The pool type each `spawn` word takes a ship from.
const SPAWN_TYPES: Dictionary[StringName, StringName] = {&"raider": DEFAULT_TYPE, &"ally": ALLY_TYPE}
## The behaviours a console `spawn ally` accepts (a raider takes every `BrainFactory` behaviour).
const ALLY_SPAWN_BEHAVIOURS: Array[StringName] = [&"idle", &"ai"]
## The `AiProfile` an `ai` console spawn flies, by spawn word.
const SPAWN_PROFILES: Dictionary[StringName, String] = {&"raider": "raider", &"ally": "ally_starfury"}
const DESPAWN_CHOICES: Array[StringName] = [&"target", &"all"]
## Allied ships broadcast their position this far (M3-T17, Q21): 100 km. Raiders do not broadcast.
const ALLY_BROADCAST_RANGE_M: float = 1.0e5
## Where parked ships wait: far below the play area (universe metres).
const PARK_Y_M: float = -1.0e6

var world: WorldFrame = null
var projectiles: Node3D = null
## The player's ship: the console's `spawn` places ships relative to it and `despawn target` uses its selection.
var player: Ship = null

var _all: Array[Combatant] = []
var _free: Array[Combatant] = []
var _types: Dictionary[Combatant, StringName] = {}
var _in_use: Array[Combatant] = []


func _ready() -> void:
	_register_provider(&"raiders", DEFAULT_TYPE, "Raiders")
	_register_provider(&"allies", ALLY_TYPE, "Allied ships")
	DebugConsole.registry.register_command(ConsoleCommand.new(&"spawn",
			"Take a raider or an allied Starfury from the pool ahead of the player, nose toward the player, turned by yaw then pitch",
			[ConsoleArg.enum_required(&"type", SPAWN_CHOICES), ConsoleArg.string_rest(&"options").make_optional("")]),
			_cmd_spawn, self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"despawn",
			"Return the selected pooled ship, or every one (raiders and allies), to the pool without effects",
			[ConsoleArg.enum_optional(&"which", DESPAWN_CHOICES, &"target")]), _cmd_despawn, self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


## Builds `count` more ships of `type` (with the faction `ShipCatalog` gives it) and parks them. Returns how many were built.
func prepare(type: StringName, count: int) -> int:
	assert(world != null and projectiles != null, "ShipPool.prepare: set world and projectiles first")
	var spec: ShipSpec = ShipCatalog.spec_for(type)
	if spec == null:
		return 0
	var faction: StringName = ShipCatalog.faction_for(type)
	var built: int = 0
	for i: int in count:
		var combatant: Combatant = ShipAssembly.build(spec, world, projectiles, {
			ShipAssembly.OPT_FACTION: faction,
			ShipAssembly.OPT_DISPLAY_NAME: "",
			ShipAssembly.OPT_FORCE_ASSIST: true,
			ShipAssembly.OPT_AI: true,
		})
		world.spawn(combatant.ship, _park_position(), Basis.IDENTITY, self)
		if type == ALLY_TYPE:
			combatant.targetable.broadcast_range_m = ALLY_BROADCAST_RANGE_M
		_park(combatant)
		_all.append(combatant)
		_free.append(combatant)
		_types[combatant] = type
		built += 1
	return built


## Takes a ship of `type` out of the pool, restored and called `display_name`, at `at` (universe) with World-frame `velocity`.
## Returns null, with one warning, when none is free. Interpolation is reset so the move from the park does not smear.
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
	# Nothing of the last pilot shows: no plume or flash fading out, no level the console forced.
	combatant.cannon.reset_flashes()
	if combatant.thrusters != null:
		combatant.thrusters.reset()
	var switcher := ship.get_node_or_null(^"LodSwitcher") as LodSwitcher
	if switcher != null:
		switcher.forced = LodSwitcherMath.NONE
	combatant.damageable.restore()
	combatant.damageable.invulnerable = false  # per spawn (M3-T09); the caller sets it
	combatant.display_name = display_name
	combatant.targetable.display_name = display_name
	_set_brain(combatant, brain)
	_in_use.append(combatant)
	acquired.emit(combatant)
	return combatant


## Parks a ship again (no effects; destruction effects are `DestructionDirector`'s). Ignores ships not in use.
func release(combatant: Combatant) -> void:
	if combatant == null or not _in_use.has(combatant):
		return
	_in_use.erase(combatant)
	_park(combatant)
	_free.append(combatant)


## Ships currently in the world: every type, or only those of `type`.
func alive(type: StringName = &"") -> Array[Combatant]:
	if type == &"":
		return _in_use.duplicate()
	var out: Array[Combatant] = []
	for combatant: Combatant in _in_use:
		if _types.get(combatant) == type:
			out.append(combatant)
	return out


## How many ships are in the world, without building a list (`PerfProbe` reads it every tick).
func in_use_count() -> int:
	return _in_use.size()


## Every pooled ship, parked or not.
func all_ships() -> Array[Combatant]:
	return _all.duplicate()


## Ships built: every type, or only those of `type`.
func pool_size(type: StringName = &"") -> int:
	return _all.size() if type == &"" else _count_of(type)


## Ships parked and ready: every type, or only those of `type`.
func free_count(type: StringName = &"") -> int:
	if type == &"":
		return _free.size()
	var n: int = 0
	for combatant: Combatant in _free:
		n += 1 if _types.get(combatant) == type else 0
	return n


## The type a pooled ship was built as (`&""` for a ship that is not from this pool).
func type_of(combatant: Combatant) -> StringName:
	return _types.get(combatant, &"")


## The in-use ship whose `Targetable` has this instance id, or null.
func find_by_target_id(target_id: int) -> Combatant:
	for combatant: Combatant in _in_use:
		if combatant.targetable.get_instance_id() == target_id:
			return combatant
	return null


## `<prefix> <n>` with the smallest n from `first` up that no ship in the world carries: `RAIDER 1` by default, `ALPHA 2` for
## `next_name("ALPHA", 2)` (the player is ALPHA 1).
func next_name(prefix: String = NAME_PREFIX, first: int = 1) -> String:
	var taken: Dictionary = {}
	for combatant: Combatant in _in_use:
		taken[combatant.display_name] = true
	var n: int = first
	while taken.has("%s %d" % [prefix, n]):
		n += 1
	return "%s %d" % [prefix, n]


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


# One provider per ship type: `raiders` and `allies` read the same way, each about its own ships.
func _register_provider(provider_name: StringName, type: StringName, noun: String) -> void:
	DebugConsole.registry.register_provider(provider_name, ConsoleVars.new({
		&"pool_size": {"get": func() -> int: return pool_size(type), "doc": "%s built at scenario load" % noun},
		&"free": {"get": func() -> int: return free_count(type), "doc": "%s parked and ready" % noun},
		&"alive": {"get": func() -> int: return alive(type).size(), "doc": "%s in the world" % noun},
		&"list": {"get": func() -> PackedStringArray: return _console_list(type), "doc": "%s in the world: name, hull %%, range from the player" % noun},
		&"selected_brain": {"get": func() -> Variant: return _console_selected_brain(type),
				"doc": "The player's selected ship's behaviour and state, when it is one of these"},
	}), self)


func _console_list(type: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	for combatant: Combatant in alive(type):
		var range_text: String = ""
		if player != null and is_instance_valid(player):
			range_text = " %.0f m" % player.global_position.distance_to(combatant.ship.global_position)
		var dark_text: String = "" if combatant.ship.running_lights else " dark"
		out.append("%s hull %.0f%%%s%s" % [combatant.display_name, 100.0 * combatant.damageable.hull.fraction(), range_text, dark_text])
	return out


func _cmd_spawn(args: Dictionary) -> ConsoleResult:
	var kind: StringName = StringName(args[&"type"])
	var type: StringName = SPAWN_TYPES[kind]
	var usage: String = ("spawn raider [idle|patrol|attack|aggro|ai] [distance_m] [yaw_deg] [pitch_deg]" if kind == &"raider" \
			else "spawn ally [idle|ai] [distance_m] [yaw_deg] [pitch_deg]") + " [skill=<rank|0-1>] [aggression=<level|0-1>] [lights=on|off]"
	if player == null or not is_instance_valid(player) or world == null:
		return ConsoleResult.failure("no player ship to place the %s relative to" % kind)
	# `[behaviour] [distance_m] [yaw_deg] [pitch_deg]`: the behaviour word is optional (idle), the numbers too (30 0 0).
	var words: PackedStringArray = String(args[&"options"]).split(" ", false)
	# `skill=` and `aggression=` (M3-T13) anywhere among the words, for an `ai` spawn.
	var temper: Dictionary = {}
	var lights: Variant = null  # `lights=` (M3-T27), on any spawn
	for i: int in range(words.size() - 1, -1, -1):
		var pair: PackedStringArray = words[i].split("=", true, 1)
		if pair.size() == 2 and (pair[0] == "skill" or pair[0] == "aggression"):
			temper[pair[0]] = pair[1]
			words.remove_at(i)
		elif pair.size() == 2 and pair[0] == "lights":
			lights = pair[1]
			words.remove_at(i)
	var behaviour: StringName = &"idle"
	if not words.is_empty() and BrainFactory.BEHAVIOURS.has(StringName(words[0])):
		behaviour = StringName(words[0])
		words.remove_at(0)
	if kind == &"ally" and not ALLY_SPAWN_BEHAVIOURS.has(behaviour):
		return ConsoleResult.failure("an ally takes idle or ai, not %s (%s)" % [behaviour, usage])
	var numbers: Array[float] = [30.0, 0.0, 0.0]
	if words.size() > 3:
		return ConsoleResult.failure(usage)
	for i: int in words.size():
		if not words[i].is_valid_float():
			return ConsoleResult.failure("'%s' is not a number (%s)" % [words[i], usage])
		numbers[i] = words[i].to_float()
	var distance: float = clampf(numbers[0], 1.0, 20000.0)
	var forward: Vector3 = -player.global_basis.z
	var up: Vector3 = Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	# The nose points back at the player; yaw turns it about its own up axis, then pitch about its own right axis.
	var facing: Basis = Basis.looking_at(-forward, up)
	var basis: Basis = facing * Basis(Vector3.UP, deg_to_rad(numbers[1])) * Basis(Vector3.RIGHT, deg_to_rad(numbers[2]))
	var local: Vector3 = player.global_position + forward * distance
	var at: UniversePos = world.to_universe(local)
	var ship_name: String = next_name() if kind == &"raider" else next_name(ALLY_NAME_PREFIX, ALLY_FIRST_NUMBER)
	var spec: Dictionary = _console_behaviour(kind, behaviour, basis)
	if not temper.is_empty():
		if behaviour != &"ai":
			return ConsoleResult.failure("skill= and aggression= take an ai spawn (%s)" % usage)
		spec.merge(temper, true)
	if lights != null:
		spec["running_lights"] = lights
	var made: Dictionary = BrainFactory.from_behaviour(spec, at, hash([ship_name, 0]))
	if not bool(made["ok"]):
		return ConsoleResult.failure(String(made["error"]))
	var combatant: Combatant = acquire(ship_name, at, basis, player.linear_velocity, made["brain"] as PilotBrain, type)
	if combatant == null:
		return ConsoleResult.failure("the %s pool is empty (%d of %d in use)" % [kind, alive(type).size(), pool_size(type)])
	player.targeting.refresh()  # selectable by name in the very next console statement
	return ConsoleResult.line("%s (%s) at %.0f m" % [ship_name, behaviour, distance])


# The scenario-style behaviour dictionary for a console spawn: patrol and aggro fly a triangle of 800 m legs around the
# spawn point in the ship's own frame; `ai` is an `AiPilot` with the profile of the kind (`SPAWN_PROFILES`).
func _console_behaviour(kind: StringName, behaviour: StringName, basis: Basis) -> Dictionary:
	var spec: Dictionary = {"type": String(behaviour)}
	if behaviour == &"ai":
		spec["profile"] = SPAWN_PROFILES[kind]
	if behaviour == &"patrol" or behaviour == &"aggro":
		var legs: Array = []
		for v: Vector3 in [Vector3(0.0, 0.0, -800.0), Vector3(700.0, 0.0, -300.0), Vector3(-700.0, 0.0, -300.0)]:
			var w: Vector3 = basis * v
			legs.append([w.x, w.y, w.z])
		spec["waypoints"] = legs
	return spec


func _console_selected_brain(type: StringName) -> Variant:
	if player == null or not is_instance_valid(player) or not player.targeting.system.has_selection():
		return null
	var combatant: Combatant = find_by_target_id(player.targeting.selected_id())
	if combatant == null or _types.get(combatant) != type or combatant.driver == null or combatant.driver.brain == null:
		return null
	return combatant.driver.brain.describe()


func _cmd_despawn(args: Dictionary) -> ConsoleResult:
	var which: StringName = StringName(args[&"which"])
	if which == &"all":
		var count: int = _in_use.size()
		for combatant: Combatant in alive():
			release(combatant)
		return ConsoleResult.line("returned %d ship(s) to the pool" % count)
	if player == null or not is_instance_valid(player) or not player.targeting.system.has_selection():
		return ConsoleResult.failure("no target selected")
	var target: Combatant = find_by_target_id(player.targeting.selected_id())
	if target == null:
		return ConsoleResult.failure("the selected target is not a pooled ship")
	var released_name: String = target.display_name
	release(target)
	return ConsoleResult.line("returned %s to the pool" % released_name)
