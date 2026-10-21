class_name DestructionDirector
extends Node
## What happens when a ship's hull reaches zero (architecture §15.7). It listens to every watched `Damageable.destroyed`:
##
## - a **raider**: its pose and velocity are read, then it is released to the `ShipPool` in the same tick (hidden, not
##   processing, `Targetable` and `Damageable` inactive, so nothing targets or hits it afterwards); an `Explosion` (radius =
##   its bounding radius) appears under `effects` at its position, drifting with its velocity, and `DebrisPool.burst`
##   breaks it into its chunks (generic shards for an asset without any);
## - the **player**: the same effects, then the ship is hidden and disabled and `player_destroyed` is emitted (Main ignores
##   input while the player is dead); after `RESPAWN_DELAY_S` of sim time `respawn_due` is emitted and Main puts the ship
##   back at the scenario start with a full hull.
##
## Console: `kill [target|all|player]` destroys now, bypassing god mode.

## A raider was destroyed (it is already back in the pool).
signal raider_destroyed(combatant: Combatant, info: HitInfo)
## A nav buoy was destroyed (it is already hidden and out of play).
signal buoy_destroyed(buoy: NavBuoy, info: HitInfo)
## The player's hull reached zero.
signal player_destroyed(info: HitInfo)
## `RESPAWN_DELAY_S` of sim time passed since the player died.
signal respawn_due

const RESPAWN_DELAY_S: float = 3.0
const KILL_CHOICES: Array[StringName] = [&"target", &"all", &"player"]

var world: WorldFrame = null
var pool: ShipPool = null
var debris: DebrisPool = null
## Where explosions are added (`World/Effects`).
var effects: Node3D = null
var player: Combatant = null

var _watched: Array[Combatant] = []
var _respawn_at_s: float = INF


func _ready() -> void:
	DebugConsole.registry.register_command(ConsoleCommand.new(&"kill",
			"Destroy the selected target, every raider or the player now (bypasses god mode)",
			[ConsoleArg.enum_optional(&"who", KILL_CHOICES, &"target")]), _cmd_kill, self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


func _physics_process(_delta: float) -> void:
	if SimClock.now() >= _respawn_at_s:
		_respawn_at_s = INF
		respawn_due.emit()


## Connects to every ship in `pool` and to `player`. Call it after the pool is prepared and the player is spawned.
func setup(p_world: WorldFrame, p_pool: ShipPool, p_debris: DebrisPool, p_effects: Node3D, p_player: Combatant) -> void:
	world = p_world
	pool = p_pool
	debris = p_debris
	effects = p_effects
	player = p_player
	for combatant: Combatant in pool._all:
		watch(combatant)
	watch(player)


## Reacts to this ship's `destroyed` from now on. Watching a ship twice is harmless.
func watch(combatant: Combatant) -> void:
	if combatant == null or combatant.damageable == null or _watched.has(combatant):
		return
	_watched.append(combatant)
	combatant.damageable.destroyed.connect(_on_destroyed.bind(combatant))


## Reacts to this buoy's `destroyed` from now on: an explosion and shards at its position, then it leaves play (hidden, not freed).
func watch_buoy(buoy: NavBuoy) -> void:
	if buoy == null or buoy.damageable == null:
		return
	buoy.damageable.destroyed.connect(_on_buoy_destroyed.bind(buoy))


## True while a respawn of the player is pending.
func respawn_pending() -> bool:
	return _respawn_at_s < INF


func _on_destroyed(info: HitInfo, combatant: Combatant) -> void:
	var ship: Ship = combatant.ship
	var xform: Transform3D = ship.global_transform
	var velocity: Vector3 = ship.linear_velocity
	var spin: Vector3 = ship.angular_velocity
	var radius: float = combatant.damageable.bounding_radius
	var hardpoints: Hardpoints = ship.get_hardpoints()
	# The ship leaves play in this very tick, before anything else in it looks at it.
	if combatant == player:
		ship.visible = false
		ship.process_mode = Node.PROCESS_MODE_DISABLED
		_respawn_at_s = SimClock.now() + RESPAWN_DELAY_S
	else:
		pool.release(combatant)
	_spawn_effects(ship, xform, velocity, spin, radius, hardpoints)
	if combatant == player:
		player_destroyed.emit(info)
	else:
		raider_destroyed.emit(combatant, info)


func _on_buoy_destroyed(info: HitInfo, buoy: NavBuoy) -> void:
	var xform: Transform3D = buoy.global_transform
	var radius: float = maxf(buoy.damageable.bounding_radius, 1.5)
	var velocity: Vector3 = buoy.velocity
	var spin: Vector3 = xform.basis.y.normalized() * deg_to_rad(buoy.spin_dps)
	buoy.set_destroyed(true)
	# Building the explosion and the shards is the costly part: done right after the hit resolver's tick, not inside it.
	_spawn_buoy_effects.call_deferred(xform, radius, velocity, spin, buoy.get_instance_id())
	buoy_destroyed.emit(buoy, info)


func _spawn_buoy_effects(xform: Transform3D, radius: float, velocity: Vector3, spin: Vector3, buoy_id: int) -> void:
	if effects != null and is_instance_valid(effects):
		var explosion: Explosion = Explosion.create(radius, velocity)
		explosion.position = xform.origin
		effects.add_child(explosion)
		explosion.reset_physics_interpolation()
	if debris != null and is_instance_valid(debris):
		debris.burst(&"nav_buoy", [] as Array[Dictionary], xform, velocity, spin, hash([buoy_id, Engine.get_physics_frames()]))


func _spawn_effects(ship: Ship, xform: Transform3D, velocity: Vector3, spin: Vector3, radius: float, hardpoints: Hardpoints) -> void:
	if effects != null and is_instance_valid(effects):
		var explosion: Explosion = Explosion.create(radius, velocity)
		explosion.position = xform.origin
		effects.add_child(explosion)
		explosion.reset_physics_interpolation()
	if debris != null and is_instance_valid(debris):
		var chunks: Array[Dictionary] = hardpoints.chunks if hardpoints.valid else ([] as Array[Dictionary])
		debris.burst(StringName(ship.spec.asset_id), chunks, xform, velocity, spin, hash([ship.get_instance_id(), Engine.get_physics_frames()]))


# --- console -----------------------------------------------------------------------------------------------------


func _cmd_kill(args: Dictionary) -> ConsoleResult:
	var who: StringName = StringName(args[&"who"])
	match who:
		&"player":
			if player == null or not player.damageable.kill():
				return ConsoleResult.failure("the player is not alive")
			return ConsoleResult.line("the player's ship destroyed")
		&"all":
			var killed: int = 0
			for combatant: Combatant in pool.alive():
				killed += 1 if combatant.damageable.kill() else 0
			return ConsoleResult.line("destroyed %d raider(s)" % killed)
	var ship: Ship = player.ship if player != null else null
	if ship == null or not ship.targeting.system.has_selection():
		return ConsoleResult.failure("no target selected")
	var target: Combatant = pool.find_by_target_id(ship.targeting.selected_id())
	if target == null:
		return ConsoleResult.failure("the selected target is not a raider")
	var target_name: String = target.display_name
	return ConsoleResult.line("%s destroyed" % target_name) if target.damageable.kill() else ConsoleResult.failure("%s is already destroyed" % target_name)
