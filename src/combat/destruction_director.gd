class_name DestructionDirector
extends Node
## What happens when a ship's hull reaches zero (architecture §15.7, §16 D35). It listens to every watched `Damageable.destroyed`:
##
## - a **pooled ship**, raider or ally alike: its pose and velocity are read, then it is released to the `ShipPool` in the same
##   tick (hidden, not processing, `Targetable` and `Damageable` inactive, so nothing targets or hits it afterwards); an
##   `Explosion` (radius = its bounding radius) appears under `effects` at its position, drifting with its velocity, and
##   `DebrisPool.burst` breaks it into its asset's chunks (the raider's wings and hump; generic shards for an asset without
##   any). A **Starfury** (an ally or the player) dies where it was hit (M3-T28): the killing hit's point picks the cabin or arm
##   that leaves first, the explosion starts at that chunk's joint and `DebrisPool.stage_wreck` frees the rest one by one over
##   the next second. A console `kill` or a hit without a point blasts from the centre, in a seeded order;
## - the **player**: the same effects, then the ship is hidden and disabled and `player_destroyed` is
##   emitted (Main ignores input while the player is dead); after `RESPAWN_DELAY_S` of sim time `respawn_due` is emitted and Main
##   puts the ship back at the scenario start with a full hull. A respawn before then (Back) cancels it (`cancel_respawn`).
##
## Signals: `ship_destroyed` for every pooled ship; `raider_destroyed` as well when it is a raider (a kill, which is what the
## waves count). An ally's death is a `ship_destroyed` only. Which is which is the pool type (`ShipPool.DEFAULT_TYPE` raiders,
## `ShipPool.ALLY_TYPE` allies), never the faction relation, so a `relation` change on the console cannot turn kills into losses.
##
## The level of detail (M4-T23, `ExplosionLod`): how a death is drawn depends on its distance from the camera, set by the
## hull's size: the full effects above near, a reduced explosion (no light, the gas shell only, no debris) between, and a point
## flash in the world's `FarFlashes` far, with no node and no particle. A death in the low-attention tier is drawn where its row
## flew. A **capital** stand-in's death (`watch_capital`) is drawn the same way; the capital then leaves play (and the tier)
## and `capital_destroyed` is emitted. Every death's killing hit carries its blast's energy, radius and point (`set_blast`),
## the data M12's blast damage and hulks start from.
##
## Console: `kill [target|all|allies|player]` destroys now, bypassing god mode: the selected pooled ship or capital, every
## raider, every ally, or the player.

## A pooled ship was destroyed (it is already back in the pool): a raider or an allied Starfury.
signal ship_destroyed(combatant: Combatant, info: HitInfo)
## A raider was destroyed (it is already back in the pool). Follows `ship_destroyed`.
signal raider_destroyed(combatant: Combatant, info: HitInfo)
## A nav buoy was destroyed (it is already hidden and out of play).
signal buoy_destroyed(buoy: NavBuoy, info: HitInfo)
## The player's hull reached zero.
signal player_destroyed(info: HitInfo)
## `RESPAWN_DELAY_S` of sim time passed since the player died.
signal respawn_due
## A capital stand-in was destroyed (it has left play) (M4-T23).
signal capital_destroyed(capital: CapitalStandin, info: HitInfo)

const RESPAWN_DELAY_S: float = 3.0
## A death's blast (M4-T22): energy per kilogram of the dead hull, J/kg, and its reach in bounding radii (the explosion's
## light reaches four). Placeholders until M12 sizes a blast by the ship's class and what it carries.
const BLAST_J_PER_KG: float = 1.0e5
const BLAST_RADIUS_FACTOR: float = 4.0
## DamageZones' X-fighter zones -> the Starfury chunk each one is.
const ZONE_CHUNKS: Dictionary[int, StringName] = {
	DamageZones.CABIN: &"cabin", DamageZones.UPPER_LEFT: &"arm_ul", DamageZones.UPPER_RIGHT: &"arm_ur",
	DamageZones.LOWER_LEFT: &"arm_ll", DamageZones.LOWER_RIGHT: &"arm_lr",
}
const KILL_CHOICES: Array[StringName] = [&"target", &"all", &"allies", &"player"]

var world: WorldFrame = null
var pool: ShipPool = null
var debris: DebrisPool = null
## Where explosions get their sparks (`Main` sets it).
var fx: FxPool = null
## Where explosions are added (`World/Effects`).
var effects: Node3D = null
var player: Combatant = null

## Where the last ship's explosion started (World-local); sounds follow it.
var last_blast_position: Vector3 = Vector3.ZERO

var _watched: Array[Combatant] = []
var _watched_capitals: Array[CapitalStandin] = []
var _respawn_at_s: float = INF

static var _current: DestructionDirector = null


func _ready() -> void:
	DebugConsole.registry.register_command(ConsoleCommand.new(&"kill",
			"Destroy the selected target, every raider, every allied ship or the player now (bypasses god mode)",
			[ConsoleArg.enum_optional(&"who", KILL_CHOICES, &"target")]), _cmd_kill, self)


func _enter_tree() -> void:
	_current = self


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)
	if _current == self:
		_current = null


## The latest director in a tree, or null.
static func current() -> DestructionDirector:
	return _current if _current != null and is_instance_valid(_current) else null


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
	for combatant: Combatant in pool.all_ships():
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


## Reacts to this capital's `destroyed` from now on (M4-T23): its blast at its level of detail, then it leaves play.
func watch_capital(cap: CapitalStandin) -> void:
	if cap == null or cap.damageable == null or _watched_capitals.has(cap):
		return
	_watched_capitals.append(cap)
	cap.damageable.destroyed.connect(_on_capital_destroyed.bind(cap))


## True while a respawn of the player is pending.
func respawn_pending() -> bool:
	return _respawn_at_s < INF


## Drops a pending respawn: the player was put back another way (Back, the console's `respawn`).
func cancel_respawn() -> void:
	_respawn_at_s = INF


func _on_destroyed(info: HitInfo, combatant: Combatant) -> void:
	var ship: Ship = combatant.ship
	var xform: Transform3D = ship.global_transform
	var velocity: Vector3 = ship.linear_velocity
	var spin: Vector3 = ship.angular_velocity
	# A ship in the low-attention tier (M4-T22) died where its row flew, not where its node was parked.
	var tiered: bool = ship.is_tier_parked()
	if tiered:
		var pose: Array = TierDirector.row_pose(ship)
		if not pose.is_empty():
			xform = pose[0]
			velocity = pose[1]
			spin = pose[2]
	var radius: float = combatant.damageable.bounding_radius
	var hardpoints: Hardpoints = ship.get_hardpoints()
	var staged: bool = combatant.damageable.zones.layout == DamageZones.Layout.X_FIGHTER and hardpoints.valid and not hardpoints.chunks.is_empty()
	var first: int = first_chunk(hardpoints.chunks, info, xform) if staged else -1
	# The ship leaves play in this very tick, before anything else in it looks at it.
	if combatant == player:
		ship.visible = false
		ship.process_mode = Node.PROCESS_MODE_DISABLED
		_respawn_at_s = SimClock.now() + RESPAWN_DELAY_S
	else:
		pool.release(combatant)
	var level: ExplosionLod.Level = _level_at(radius, xform.origin)
	if level == ExplosionLod.Level.FULL:
		_spawn_effects(ship, xform, velocity, spin, radius, hardpoints, staged, first)
	else:
		last_blast_position = xform.origin
		_spawn_far(level, xform.origin, velocity, radius, blast_energy_j(ship.mass))
	set_blast(info, ship.mass, radius, last_blast_position)
	if combatant == player:
		player_destroyed.emit(info)
	else:
		ship_destroyed.emit(combatant, info)
		if pool.type_of(combatant) == ShipPool.DEFAULT_TYPE:
			raider_destroyed.emit(combatant, info)


func _on_capital_destroyed(info: HitInfo, cap: CapitalStandin) -> void:
	var xform: Transform3D = cap.global_transform
	var velocity: Vector3 = cap.linear_velocity
	if cap.is_tier_parked():
		var pose: Array = TierDirector.row_pose(cap)
		if not pose.is_empty():
			xform = pose[0]
			velocity = pose[1]
		var tier: TierDirector = TierDirector.current()
		if tier != null:
			tier.forget_capital(cap)
	cap.leave_play()
	var radius: float = cap.damageable.bounding_radius
	last_blast_position = xform.origin
	var level: ExplosionLod.Level = _level_at(radius, xform.origin)
	if level == ExplosionLod.Level.FULL:
		_add_explosion(radius, velocity, xform.origin, false)
	else:
		_spawn_far(level, xform.origin, velocity, radius, blast_energy_j(cap.mass))
	set_blast(info, cap.mass, radius, xform.origin)
	capital_destroyed.emit(cap, info)


# How a death of a hull of `radius` at `at` is drawn, from the camera's distance (the full effect with no camera).
func _level_at(radius: float, at: Vector3) -> ExplosionLod.Level:
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return ExplosionLod.Level.FULL
	return ExplosionLod.level(radius, camera.global_position.distance_to(at))


# A death past the full effect's distance: a reduced explosion, or a far flash with no node and no particle.
func _spawn_far(level: ExplosionLod.Level, at: Vector3, velocity: Vector3, radius: float, energy_j: float) -> void:
	if level == ExplosionLod.Level.REDUCED:
		_add_explosion(radius, velocity, at, true)
		return
	var flashes: FarFlashes = FarFlashes.attach(world)
	if flashes != null:
		flashes.add(at, velocity, energy_j)


func _add_explosion(radius: float, velocity: Vector3, at: Vector3, reduced: bool) -> void:
	if effects == null or not is_instance_valid(effects):
		return
	var explosion: Explosion = Explosion.create(radius, velocity, reduced)
	explosion.fx = fx
	explosion.position = at
	effects.add_child(explosion)
	explosion.reset_physics_interpolation()


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
		explosion.fx = fx
		explosion.position = xform.origin
		effects.add_child(explosion)
		explosion.reset_physics_interpolation()
	if debris != null and is_instance_valid(debris):
		debris.burst(&"nav_buoy", [] as Array[Dictionary], xform, velocity, spin, hash([buoy_id, Engine.get_physics_frames()]))


func _spawn_effects(ship: Ship, xform: Transform3D, velocity: Vector3, spin: Vector3, radius: float, hardpoints: Hardpoints,
		staged: bool, first: int) -> void:
	var chunks: Array[Dictionary] = hardpoints.chunks if hardpoints.valid else ([] as Array[Dictionary])
	var seed_value: int = hash([ship.get_instance_id(), Engine.get_physics_frames()])
	# A Starfury's blast starts at the joint of the part that leaves first.
	last_blast_position = xform * (chunks[first]["joint"] as Vector3) if first >= 0 else xform.origin
	_add_explosion(radius, velocity, last_blast_position, false)
	if debris != null and is_instance_valid(debris):
		if staged:
			debris.stage_wreck(StringName(ship.spec.asset_id), chunks, xform, velocity, spin, seed_value, first, ship.livery)
		else:
			debris.burst(StringName(ship.spec.asset_id), chunks, xform, velocity, spin, seed_value, ship.livery)


## A death's blast energy from the hull's mass, J.
static func blast_energy_j(mass_kg: float) -> float:
	return maxf(mass_kg, 0.0) * BLAST_J_PER_KG


## Writes a death's blast onto its killing hit (M4-T22): energy from the hull's mass, reach from its size, at `at`.
static func set_blast(info: HitInfo, mass_kg: float, bounding_radius_m: float, at: Vector3) -> void:
	if info == null:
		return
	info.blast_energy_j = blast_energy_j(mass_kg)
	info.blast_radius_m = maxf(bounding_radius_m, 0.5) * BLAST_RADIUS_FACTOR
	info.blast_point = at


## The index in `chunks` of the part the killing hit landed on (`info.point` is World-local, put into the ship's frame by
## `xform`), or -1 when there is no point (a console kill) or no chunk by that name.
static func first_chunk(chunks: Array[Dictionary], info: HitInfo, xform: Transform3D) -> int:
	if info == null or info.cause == HitInfo.CAUSE_CONSOLE:
		return -1
	var zone: int = DamageZones.zone_for(DamageZones.Layout.X_FIGHTER, xform.affine_inverse() * info.point)
	var wanted: StringName = ZONE_CHUNKS.get(zone, &"")
	for i: int in chunks.size():
		if StringName(chunks[i]["name"]) == wanted:
			return i
	return -1


# --- console -----------------------------------------------------------------------------------------------------


# A selected target that is not a pooled ship (a capital, M4-T23): destroyed through its owner's hull.
func _kill_other(target_id: int) -> ConsoleResult:
	var marker := instance_from_id(target_id) as Targetable if is_instance_id_valid(target_id) else null
	var hull: Damageable = Damageable.of(marker.get_parent()) if marker != null else null
	if hull == null:
		return ConsoleResult.failure("the selected target has no hull")
	if not hull.kill():
		return ConsoleResult.failure("%s is already destroyed" % marker.display_name)
	return ConsoleResult.line("%s destroyed" % marker.display_name)


func _cmd_kill(args: Dictionary) -> ConsoleResult:
	var who: StringName = StringName(args[&"who"])
	match who:
		&"player":
			if player == null or not player.damageable.kill():
				return ConsoleResult.failure("the player is not alive")
			return ConsoleResult.line("the player's ship destroyed")
		&"all":
			var killed: int = 0
			for combatant: Combatant in pool.alive(ShipPool.DEFAULT_TYPE):
				killed += 1 if combatant.damageable.kill() else 0
			return ConsoleResult.line("destroyed %d raider(s)" % killed)
		&"allies":
			var lost: int = 0
			for combatant: Combatant in pool.alive(ShipPool.ALLY_TYPE):
				lost += 1 if combatant.damageable.kill() else 0
			if lost == 0:
				return ConsoleResult.failure("no allied ships in play")
			return ConsoleResult.line("destroyed %d allied ship(s)" % lost)
	var ship: Ship = player.ship if player != null else null
	if ship == null or not ship.targeting.system.has_selection():
		return ConsoleResult.failure("no target selected")
	var target: Combatant = pool.find_by_target_id(ship.targeting.selected_id())
	if target == null:
		return _kill_other(ship.targeting.selected_id())
	var target_name: String = target.display_name
	return ConsoleResult.line("%s destroyed" % target_name) if target.damageable.kill() else ConsoleResult.failure("%s is already destroyed" % target_name)
