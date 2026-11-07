extends GutTest
## The hit resolver at scale (M4-T08, architecture §17.7): with the broad phase (`HitBroadPhase`) the resolver tests only the
## projectile and hull pairs that can meet this tick, so its work follows the pairs near each other, not projectiles times
## hulls; and it lands exactly the hits the GDScript resolver landed when it tested every pair (maintainer, Q9:
## bit-identical; recorded). Also the projectile kinds (bolt, beam, missile, mine): each a sphere of its own radius swept
## along the tick's flight, so a 3 km beam or a 1 km hull goes through the same sweep.
##
## Like `test_hit_resolver`, the tests step the world by hand in the order of one game tick: bolts move, the resolver runs,
## the drones move on by their velocity.

const DRONE_SCENE: String = "res://tests/fixtures/target_drone.tscn"
const DT: float = 1.0 / 60.0
const FIXTURE: String = "hit_scale"
const BOLT_SPEED: float = 400.0

var world: WorldFrame
var projectiles: Node3D
var resolver: HitResolver
var drones: Array[TargetDrone] = []
var hits: Array[HitInfo] = []
var shooter: Node3D
var _friendly_fire_backup: bool


func before_each() -> void:
	_friendly_fire_backup = bool(Settings.get_value(&"friendly_fire"))
	Settings.set_value(&"friendly_fire", false)
	_build()


func after_each() -> void:
	Settings.set_value(&"friendly_fire", _friendly_fire_backup)


# A fresh world, resolver and shooter; the old ones are freed.
func _build() -> void:
	if world != null and is_instance_valid(world):
		world.free()
	if resolver != null and is_instance_valid(resolver):
		resolver.free()
	if shooter != null and is_instance_valid(shooter):
		shooter.free()
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	projectiles = Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	resolver = HitResolver.new()
	add_child_autofree(resolver)
	resolver.set_physics_process(false)  # the tests call resolve() themselves
	shooter = Node3D.new()
	shooter.name = "Shooter"
	add_child_autofree(shooter)
	hits.clear()
	drones.clear()
	resolver.hit_resolved.connect(func(info: HitInfo) -> void: hits.append(info))


func _drone(at: Vector3, velocity: Vector3 = Vector3.ZERO, p_faction: StringName = Factions.RAIDERS) -> TargetDrone:
	var drone := (load(DRONE_SCENE) as PackedScene).instantiate() as TargetDrone
	drone.faction = p_faction
	drone.set_physics_process(false)
	world.spawn(drone, world.to_universe(at))
	drone.velocity = velocity
	drone.linear_velocity = velocity
	drones.append(drone)
	return drone


func _bolt(at: Vector3, velocity: Vector3, p_faction: StringName = Factions.EARTH_ALLIANCE, shooter_id: int = -1,
		kind: StringName = Projectile.KIND_BOLT) -> Projectile:
	var bolt := (load(Projectile.SCENE_PATH) as PackedScene).instantiate() as Projectile
	projectiles.add_child(bolt)
	var weapon := WeaponSpec.new()
	weapon.damage = 10.0
	bolt.configure(weapon)
	bolt.set_kind(kind)
	bolt.shooter_id = shooter.get_instance_id() if shooter_id < 0 else shooter_id
	bolt.faction = p_faction
	bolt.launch(at, velocity, SimClock.now())
	bolt.set_physics_process(false)
	return bolt


## One tick: bolts move, the resolver runs, drones move on.
func _tick() -> void:
	for node: Node in projectiles.get_children():
		var bolt := node as Projectile
		if bolt != null and not bolt.is_spent():
			bolt._physics_process(DT)
	resolver.resolve(DT)
	for drone: TargetDrone in drones:
		drone.global_position += drone.velocity * DT


func _tick_n(count: int) -> void:
	for i: int in count:
		_tick()


# The hits so far as plain values (drone index, shooter, point, normal, speed, damage), comparable across worlds.
func _hit_log() -> Array:
	var out: Array = []
	for info: HitInfo in hits:
		var target: int = -1
		for k: int in drones.size():
			if is_instance_valid(drones[k]) and drones[k].get_instance_id() == info.target_id:
				target = k
		var shooter_index: int = -2 if info.shooter_id == shooter.get_instance_id() else -1
		for k: int in drones.size():
			if is_instance_valid(drones[k]) and drones[k].get_instance_id() == info.shooter_id:
				shooter_index = k
		out.append([target, shooter_index, info.point, info.normal, info.relative_speed_mps, info.applied])
	return out


# --- the work ------------------------------------------------------------------------------------------------------


# 24 drones 250 m apart, 300 bolts flying between the first two (each way, from one at the other).
func _fleet_between_two() -> void:
	for k: int in 24:
		_drone(Vector3(float(k % 4) * 250.0, float((k / 4) % 3) * 250.0, float(k / 12) * 250.0))
	var a: TargetDrone = drones[0]
	var b: TargetDrone = drones[1]
	var rng := RandomNumberGenerator.new()
	rng.seed = 24300
	for i: int in 300:
		var x: float = rng.randf_range(15.0, 235.0)
		var off := Vector3(0.0, rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0))
		if i % 2 == 0:
			_bolt(Vector3(x, 0.0, 0.0) + off, Vector3(BOLT_SPEED, 0.0, 0.0), Factions.EARTH_ALLIANCE, a.get_instance_id())
		else:
			_bolt(Vector3(x, 0.0, 0.0) + off, Vector3(-BOLT_SPEED, 0.0, 0.0), Factions.EARTH_ALLIANCE, b.get_instance_id())


func test_a_fleet_of_24_with_300_bolts_tests_at_most_3_pairs_a_bolt() -> void:
	var recorded: Variant = ParityFixture.stored(FIXTURE, "fleet_of_24")
	_build()
	var stats: Array = _fleet()
	assert_eq(resolver.broad_phase.path(), &"native", "the native path")
	gut.p("at most %d pairs tested in a tick, %.2f a bolt (every pair: %d)" % [stats[0], stats[1], 300 * 24])
	assert_gt(stats[0], 0, "the bolts reach the drones")
	assert_lte(stats[1], 3.0, "at most 3 pairs tested a bolt")
	assert_gt(hits.size(), 50, "many bolts land")
	assert_eq(ParityFixture.encode(_hit_log()), recorded, "the GDScript path's hits, bit for bit (recorded, M4-T37)")


# The fleet between two shooters for 45 ticks: [the most pairs tested in a tick, the most a bolt].
func _fleet() -> Array:
	_fleet_between_two()
	var worst_per_bolt: float = 0.0
	var most: int = 0
	for t: int in 45:
		_tick()
		if resolver.projectiles_last_tick > 0:
			worst_per_bolt = maxf(worst_per_bolt, float(resolver.pairs_visited) / float(resolver.projectiles_last_tick))
		most = maxi(most, resolver.pairs_visited)
	return [most, worst_per_bolt]


func test_a_seeded_melee_lands_the_same_hits_as_testing_every_pair() -> void:
	# The hits when every pair is tested (the GDScript resolver handed a broad phase that tested every pair) are recorded
	# (M4-T37; that resolver's own walk went in M4-T42).
	var reference: Variant = ParityFixture.stored(FIXTURE, "melee_every_pair")
	assert_not_null(reference, "the every-pair melee was recorded")
	if reference == null:
		return
	gut.p("the melee lands %d hits when every pair is tested" % (reference as Array).size())
	assert_gt((reference as Array).size(), 30, "the melee lands hits")
	_build()
	_melee()
	assert_eq(ParityFixture.encode(_hit_log()), reference, "native: the same hits as testing every pair, bit for bit")


# 30 drones moving in a 600 m ball, two sides, 400 bolts aimed with the intercept solution and a seeded spread; 120 ticks.
func _melee() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7108
	for k: int in 30:
		var faction: StringName = Factions.RAIDERS if k % 2 == 0 else Factions.EARTH_ALLIANCE
		_drone(Vector3(rng.randf_range(-300, 300), rng.randf_range(-300, 300), rng.randf_range(-300, 300)),
				Vector3(rng.randf_range(-60, 60), rng.randf_range(-60, 60), rng.randf_range(-60, 60)), faction)
	for i: int in 400:
		var from: TargetDrone = drones[rng.randi_range(0, drones.size() - 1)]
		var to: TargetDrone = drones[rng.randi_range(0, drones.size() - 1)]
		if to == from:
			continue
		var faction: StringName = Factions.EARTH_ALLIANCE if from.faction == Factions.RAIDERS else Factions.RAIDERS
		var start: Vector3 = from.global_position + Vector3(rng.randf_range(-5, 5), rng.randf_range(-5, 5), 8.0)
		var speed: float = BOLT_SPEED * rng.randf_range(1.0, 2.5)
		var solution: Dictionary = InterceptMath.solve(start, from.velocity, to.global_position, to.velocity, speed, 10.0)
		var aim: Vector3 = solution["aim_dir"] if solution["ok"] else (to.global_position - start).normalized()
		aim = (aim + Vector3(rng.randf_range(-0.004, 0.004), rng.randf_range(-0.004, 0.004), rng.randf_range(-0.004, 0.004))).normalized()
		_bolt(start, from.velocity + aim * speed, faction, from.get_instance_id())
	_tick_n(120)


# --- the hit pins of test_hit_resolver, on both paths ----------------------------------------------------------------


func test_a_grazing_bolt_hits_inside_the_reach_and_misses_outside() -> void:
	_build()
	_drone(Vector3.ZERO)
	_bolt(Vector3(0.0, 1.20, 60.0), Vector3(0.0, 0.0, -BOLT_SPEED))  # inside the 1.25 m reach
	_bolt(Vector3(0.5, -1.55, 60.0), Vector3(0.0, 0.0, -BOLT_SPEED))  # 0.3 m outside it
	_tick_n(60)
	assert_eq(hits.size(), 1, "only the bolt inside the reach hits")


func test_a_bolt_that_crosses_a_thin_wing_in_one_tick_hits() -> void:
	_build()
	_drone(Vector3.ZERO)
	for i: int in 20:
		_bolt(Vector3(1.2 + 0.05 * float(i), 100.0 + 0.37 * float(i), 0.0), Vector3(0.0, -1400.0, 0.0))
	_tick_n(10)
	assert_eq(hits.size(), 20, "23 m a tick through a 0.4 m wing, every bolt hits")


func test_friendly_fire_off_and_on() -> void:
	for friendly_fire: bool in [false, true]:
		_build()
		Settings.set_value(&"friendly_fire", friendly_fire)
		_drone(Vector3.ZERO)
		_bolt(Vector3(0.0, 0.0, -100.0), Vector3(0.0, 0.0, BOLT_SPEED), Factions.RAIDERS)
		_tick_n(60)
		assert_eq(hits.size(), 1 if friendly_fire else 0, "friendly fire %s" % friendly_fire)


# --- projectile kinds and hull sizes ---------------------------------------------------------------------------------


func test_each_kind_carries_its_own_hit_radius() -> void:
	for kind: StringName in Projectile.KINDS:
		assert_gt(Projectile.hit_radius_for(kind), 0.0, "%s has a hit radius" % kind)
	assert_eq(Projectile.hit_radius_for(Projectile.KIND_BOLT), 0.25, "a bolt keeps the pulse cannon's 0.25 m")
	assert_gt(Projectile.hit_radius_for(Projectile.KIND_MISSILE), Projectile.hit_radius_for(Projectile.KIND_BOLT))
	assert_gt(Projectile.hit_radius_for(Projectile.KIND_MINE), Projectile.hit_radius_for(Projectile.KIND_MISSILE))
	assert_eq(Projectile.hit_radius_for(&"no_such_kind"), Projectile.hit_radius_for(Projectile.KIND_BOLT))
	var bolt := (load(Projectile.SCENE_PATH) as PackedScene).instantiate() as Projectile
	add_child_autofree(bolt)
	assert_eq(bolt.kind, Projectile.KIND_BOLT, "a projectile is a bolt unless told otherwise")
	bolt.set_kind(Projectile.KIND_MISSILE)
	assert_eq(bolt.kind, Projectile.KIND_MISSILE)
	assert_eq(bolt.hit_radius_m, Projectile.hit_radius_for(Projectile.KIND_MISSILE))


func test_a_missile_hits_where_a_bolt_on_the_same_line_misses() -> void:
	_build()
	_drone(Vector3.ZERO)
	_bolt(Vector3(0.0, 2.5, 60.0), Vector3(0.0, 0.0, -BOLT_SPEED))
	_tick_n(60)
	assert_eq(hits.size(), 0, "a bolt 2.5 m above the axis misses")
	_bolt(Vector3(0.0, 2.5, 60.0), Vector3(0.0, 0.0, -BOLT_SPEED), Factions.EARTH_ALLIANCE, -1, Projectile.KIND_MISSILE)
	_tick_n(60)
	assert_eq(hits.size(), 1, "a missile on the same line hits")


func test_a_3_km_beam_hits_the_first_hull_along_it_in_the_tick_it_fires() -> void:
	_build()
	var near: TargetDrone = _drone(Vector3(0.0, 0.0, -1000.0))
	var far: TargetDrone = _drone(Vector3(0.0, 0.0, -2000.0))
	for k: int in 40:
		_drone(Vector3(float(k) * 150.0 + 300.0, 0.0, -1500.0))  # beside the beam, never on it
	# A beam is a projectile that flies its whole length in one tick.
	_bolt(Vector3.ZERO, Vector3(0.0, 0.0, -3000.0 / DT), Factions.EARTH_ALLIANCE, -1, Projectile.KIND_BEAM)
	_tick()
	assert_eq(hits.size(), 1, "the beam lands in the tick it fires")
	if hits.size() == 1:
		assert_eq(hits[0].target_id, near.get_instance_id(), "on the nearer hull")
	assert_eq(far.damageable.hull.hp, far.damageable.hull.max_hp, "the far one is shielded")


func test_a_1_km_hull_is_hit_anywhere_along_it() -> void:
	_build()
	var capital: TargetDrone = _drone(Vector3(0.0, 0.0, -2000.0))
	# A 100 x 100 x 1 000 m box hull in place of the drone's own shapes.
	capital.damageable.shapes = [HitShape.make_box(Transform3D.IDENTITY, Vector3(100.0, 100.0, 1000.0))] as Array[HitShape]
	capital.damageable.bounding_radius = capital.damageable.shapes[0].extent_radius()
	for k: int in 30:
		_drone(Vector3(float(k % 6) * 250.0 - 625.0, 400.0, float(k / 6) * 250.0 - 2500.0))  # fighters above it
	for k: int in 9:
		var z: float = -2450.0 + float(k) * 112.0
		_bolt(Vector3(-300.0, 0.0, z), Vector3(BOLT_SPEED, 0.0, 0.0))
	var most: int = 0
	for t: int in 60:
		_tick()
		most = maxi(most, resolver.pairs_visited)
	assert_eq(hits.size(), 9, "every bolt along the hull's length hits it")
	for info: HitInfo in hits:
		assert_eq(info.target_id, capital.get_instance_id())
		assert_almost_eq(info.point.x, -50.25, 0.1, "on its side")
	gut.p("at most %d pairs tested in a tick for 9 bolts" % most)


func test_the_combat_provider_shows_the_broad_phase_work_and_path() -> void:
	_drone(Vector3.ZERO)
	_bolt(Vector3(0.0, 0.0, -10.0), Vector3(0.0, 0.0, BOLT_SPEED))
	_tick()
	var registry: ConsoleRegistry = DebugConsole.registry
	assert_string_contains(registry.format_path("combat.pairs_visited"), "combat.pairs_visited = 1")
	assert_string_contains(registry.format_path("combat.hit_path"), String(resolver.broad_phase.path()))
