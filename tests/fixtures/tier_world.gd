class_name TierWorld
extends RefCounted
## A small world for the low-attention tier's fire tests (M4-T22): its own physics space, the pool of raiders and allied
## Starfuries, the player at the origin, the stand-ins, the core, the tier director, the hit resolver and the destruction
## director, so a fight runs the same way near the player or far out in the tier. Build it under a test node with `build`.

const SETTINGS: Array[StringName] = [&"perf_native", &"perf_native_core", &"perf_native_brains", &"perf_native_flight",
		&"perf_native_commands", &"perf_native_driver_step", &"perf_native_weapons", &"perf_native_bolt_rows", &"sim_step",
		&"tier_radius_m", &"tier_hz", &"tier_brain_hz", &"ai_think_rate", &"perf_threads", &"friendly_fire"]
const NATIVE_SETTINGS: Array[StringName] = [&"perf_native", &"perf_native_core", &"perf_native_brains", &"perf_native_flight",
		&"perf_native_commands", &"perf_native_driver_step", &"perf_native_weapons", &"perf_native_bolt_rows", &"ai_think_rate"]

var space: SubViewport
var world: WorldFrame
var projectiles: Node3D
var pool: ShipPool
var player: Combatant
var standins: StandinDirector
var sim: SimCore
var tier: TierDirector
var resolver: HitResolver
var destruction: DestructionDirector
## Hits that reached a hull (`hit_taken`) by target body id, and every hit seen, as `[target, shooter, damage]`.
var hits_by_target: Dictionary[int, int] = {}
var hits: Array = []


## The settings the tests change, read now so `restore_settings` can put them back.
static func save_settings() -> Dictionary:
	var out: Dictionary = {}
	for key: StringName in SETTINGS:
		out[key] = Settings.get_value(key)
	return out


static func restore_settings(saved: Dictionary) -> void:
	for key: StringName in saved:
		Settings.set_value(key, saved[key])


## Every native path on, the tier at `radius_m` (0 = off).
static func use_native(radius_m: float) -> void:
	for key: StringName in NATIVE_SETTINGS:
		Settings.set_value(key, true)
	Settings.set_value(&"tier_radius_m", radius_m)


## The world under `parent`, with `raiders` raiders and `allies` allied Starfuries in the pool.
func build(parent: Node, raiders: int, allies: int) -> void:
	space = SubViewport.new()
	space.own_world_3d = true
	space.world_3d = World3D.new()
	parent.add_child(space)
	world = WorldFrame.new()
	world.name = "World"
	space.add_child(world)
	projectiles = Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	pool = ShipPool.new()
	pool.name = "Ships"
	world.add_child(pool)
	pool.world = world
	pool.projectiles = projectiles
	player = ShipAssembly.build(load("res://assets/ships/starfury_aurora.tres") as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE,
		ShipAssembly.OPT_DISPLAY_NAME: "PLAYER",
		ShipAssembly.OPT_CONSOLE_OWNER: true,
	})
	world.spawn(player.ship, world.to_universe(Vector3.ZERO))
	player.damageable.invulnerable = true
	pool.player = player.ship
	if raiders > 0:
		pool.prepare(ShipPool.DEFAULT_TYPE, raiders)
	if allies > 0:
		pool.prepare(ShipPool.ALLY_TYPE, allies)
	standins = StandinDirector.new()
	standins.name = "Standins"
	standins.world = world
	standins.projectiles = projectiles
	standins.ships = pool
	standins.player = player.ship
	world.add_child(standins)
	FlightBatch.attach(world)
	sim = SimCore.attach(world)
	tier = TierDirector.attach(world, pool, standins)
	resolver = HitResolver.new()
	resolver.name = "HitResolver"
	space.add_child(resolver)
	destruction = DestructionDirector.new()
	destruction.name = "Destruction"
	space.add_child(destruction)
	destruction.setup(world, pool, null, null, player)
	for c: Combatant in pool.all_ships():
		c.damageable.hit_taken.connect(_on_hit.bind(c))


## Tears the world down (call before building another in the same test).
func free_world() -> void:
	if space != null and is_instance_valid(space):
		space.get_parent().remove_child(space)
		space.free()
	space = null


## A pooled fighter of `type` at `at` (World-local, m) with an AI brain of `profile` seeded `seed_value`, its temperament
## (skill, aggression) as given or the profile's.
func fighter(type: StringName, display_name: String, at: Vector3, seed_value: int, basis: Basis = Basis.IDENTITY,
		velocity: Vector3 = Vector3.ZERO, profile: String = "", temperament: Dictionary = {}) -> Combatant:
	var chosen: String = profile if profile != "" else ("ally_starfury" if type == ShipPool.ALLY_TYPE else "raider")
	var spec: Dictionary = {"type": "ai", "profile": chosen}
	spec.merge(temperament, true)  # e.g. {"skill": "regular", "aggression": "balanced"}: the same on both sides
	var brain: PilotBrain = BrainFactory.from_behaviour(spec, world.to_universe(at), seed_value)["brain"] as PilotBrain
	return pool.acquire(display_name, world.to_universe(at), basis, velocity, brain, type)


## A cruiser of `faction` at `at`, cruising at `velocity`.
func cruiser(faction: StringName, display_name: String, at: Vector3, velocity: Vector3 = Vector3.ZERO) -> CapitalStandin:
	var cap: CapitalStandin = standins.add_capital(&"cruiser", faction, display_name, world.to_universe(at), Basis.IDENTITY,
			velocity)
	standins.active = true
	return cap


## Mean hull lost by `ships` (0 whole, 1 destroyed or released).
static func mean_hull_loss(ships: Array[Combatant]) -> float:
	if ships.is_empty():
		return 0.0
	var lost: float = 0.0
	for c: Combatant in ships:
		lost += 1.0 if c.damageable.hull.destroyed else 1.0 - c.damageable.hull.fraction()
	return lost / float(ships.size())


## The hull left on a side (destroyed ships count 0).
static func hull_left(ships: Array[Combatant]) -> float:
	var left: float = 0.0
	for c: Combatant in ships:
		left += 0.0 if c.damageable.hull.destroyed else c.damageable.hull.fraction()
	return left


func _on_hit(info: HitInfo, c: Combatant) -> void:
	if info.cause != HitInfo.CAUSE_BOLT:
		return
	var id: int = c.ship.get_instance_id()
	hits_by_target[id] = int(hits_by_target.get(id, 0)) + 1
	hits.append([id, info.shooter_id, info.damage])
