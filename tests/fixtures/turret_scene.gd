class_name TurretScene
extends RefCounted
## A small scene for the defensive turrets' tests (M5-T21): a space of its own with a World, its projectiles, a hit resolver
## and the native core, ships built by `ShipAssembly` and turrets mounted on them by hand (or from their hardpoints), the
## step's schedule and thread count set, and the settings put back when it is freed.

const SETTINGS: Array[StringName] = [&"perf_threads", &"perf_step_threads", &"sim_step", &"ai_think_rate"]
const WEAPON_PATH: String = ShipAssembly.DEFAULT_TURRET_WEAPON
## The hand-mounted turrets fire the light turret at this interval, so a few seconds of a mechanics test carry several shots
## whatever the balance fight tunes the real gun to (`test_turret_defence` fires the real one from the hardpoints).
const MECHANICS_INTERVAL_S: float = 1.2

var space: SubViewport = null
var world: WorldFrame = null
var bolts: Node3D = null
var resolver: HitResolver = null
var sim: SimCore = null
var ships: Array[Combatant] = []
## Every hit the resolver landed, in order: `[target id, shooter id, applied]`.
var hits: Array = []

var _saved: Dictionary = {}


## A new scene under `parent` with the step `mode` (`threaded` or `delayed`) and `threads` worker threads.
static func build(parent: Node, mode: StringName = &"threaded", threads: int = 1) -> TurretScene:
	var scene := TurretScene.new()
	for key: StringName in SETTINGS:
		scene._saved[key] = Settings.get_value(key)
	Settings.set_value(&"ai_think_rate", true)
	Settings.set_value(&"sim_step", mode)
	Settings.set_value(&"perf_threads", threads)
	Settings.set_value(&"perf_step_threads", 0 if threads > 1 else 1)
	Factions.reset()
	ContactScan.invalidate()
	SimClock.reset()
	scene.space = SubViewport.new()
	scene.space.own_world_3d = true
	scene.space.world_3d = World3D.new()
	parent.add_child(scene.space)
	scene.world = WorldFrame.new()
	scene.world.name = "World"
	scene.space.add_child(scene.world)
	scene.bolts = Node3D.new()
	scene.bolts.name = "Projectiles"
	scene.world.add_child(scene.bolts)
	scene.resolver = HitResolver.new()
	scene.resolver.name = "HitResolver"
	scene.space.add_child(scene.resolver)
	scene.resolver.hit_resolved.connect(func(info: HitInfo) -> void:
		scene.hits.append([info.target_id, info.shooter_id, info.applied]))
	return scene


## A lean ship of `type` for `faction` at `at` (World frame), flown by `behaviour` when one is given.
func ship(type: StringName, faction: StringName, display_name: String, at: Vector3, behaviour: Dictionary = {},
		seed_value: int = 1, civilian: bool = false, basis: Basis = Basis.IDENTITY) -> Combatant:
	var ai: bool = not behaviour.is_empty()
	var c: Combatant = ShipAssembly.build(ShipCatalog.spec_for(type), world, bolts, {
		ShipAssembly.OPT_FACTION: faction, ShipAssembly.OPT_DISPLAY_NAME: display_name, ShipAssembly.OPT_LEAN: true,
		ShipAssembly.OPT_AI: ai, ShipAssembly.OPT_FORCE_ASSIST: true, ShipAssembly.OPT_CIVILIAN: civilian})
	world.spawn(c.ship, world.to_universe(at), basis)
	if ai:
		var made: Dictionary = BrainFactory.from_behaviour(behaviour, world.to_universe(at), seed_value)
		c.driver.brain = made["brain"] as PilotBrain
	ships.append(c)
	return c


## Takes `c` out of play when its hull is destroyed, as `ShipPool` parks a dead ship (hidden, not processing, no pilot), so a
## dead raider stops firing in a fight with no pool.
func park_on_death(c: Combatant) -> void:
	c.damageable.destroyed.connect(func(_info: HitInfo) -> void:
		c.ship.visible = false
		c.ship.process_mode = Node.PROCESS_MODE_DISABLED
		c.ship.linear_velocity = Vector3.ZERO
		c.ship.angular_velocity = Vector3.ZERO
		if c.driver != null:
			c.driver.brain = null)


## A turret on `c` at `position` (its frame) with its base facing `up` and a cone of `arc_deg`.
func mount(c: Combatant, position: Vector3 = Vector3(0.0, 3.0, 0.0), up: Vector3 = Vector3.UP, arc_deg: float = 200.0,
		mount_name: String = "dorsal") -> TurretMount:
	var gun: WeaponSpec = (load(WEAPON_PATH) as WeaponSpec).duplicate()
	gun.shot_interval_s = MECHANICS_INTERVAL_S
	var m := TurretMount.create({"name": mount_name, "position": position, "up": up, "arc_deg": arc_deg, "barrel_m": 2.0},
			gun, c.faction)
	c.ship.add_child(m)
	c.turrets.append(m)
	return m


## The core under the world (made on the first ask); the mounts bind to it as it comes.
func attach() -> SimCore:
	sim = SimCore.attach(world)
	sim.core.set_parallel_min(2)
	sim.core.set_flight_parallel_min(2)
	return sim


## A turret's state in the core.
func state(m: TurretMount) -> Dictionary:
	return sim.core.turret_state(m.slot())


func shots_total() -> int:
	return int(sim.core.turret_readouts()[0])


## The hits a ship took from a shooter so far.
func hits_on(target: Combatant, shooter: Combatant = null) -> int:
	var n: int = 0
	for h: Array in hits:
		if int(h[0]) == target.ship.get_instance_id() and (shooter == null or int(h[1]) == shooter.ship.get_instance_id()):
			n += 1
	return n


## Frees the scene and puts the settings back.
func free_scene(tree: SceneTree) -> void:
	if space != null and is_instance_valid(space):
		space.queue_free()
	await tree.physics_frame
	await tree.physics_frame
	for key: StringName in _saved:
		if _saved[key] != null:
			Settings.set_value(key, _saved[key])
	Factions.reset()
	ContactScan.invalidate()
