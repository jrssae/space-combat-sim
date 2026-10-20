extends GutTest
## HitResolver (M2-T03, AC3, architecture §15.5): swept bolt hits at any closing speed against `TargetDrone`s.
##
## The tests step the world by hand, in the order of one game tick (§15.3): every bolt moves (`Projectile` physics step),
## the resolver runs, then the drones move on by their velocity (what Jolt does after the callbacks). That is fast,
## deterministic, and does not depend on Jolt. The drones are driven by setting their position, never by physics.

const DRONE_SCENE: String = "res://tests/fixtures/target_drone.tscn"
const DT: float = 1.0 / 60.0
const BOLT_SPEED: float = 400.0
const PHASES: int = 50

var world: WorldFrame
var projectiles: Node3D
var resolver: HitResolver
var drones: Array[TargetDrone] = []
var hits: Array[HitInfo] = []
var shooter: Node3D
var shooter_node_id: int = 0


func before_each() -> void:
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
	shooter_node_id = shooter.get_instance_id()
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
		damage: float = 10.0) -> Projectile:
	var bolt := (load(Projectile.SCENE_PATH) as PackedScene).instantiate() as Projectile
	projectiles.add_child(bolt)
	var weapon := WeaponSpec.new()
	weapon.damage = damage
	bolt.configure(weapon)
	bolt.shooter_id = shooter_node_id if shooter_id < 0 else shooter_id
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


func _live_bolts() -> int:
	var count: int = 0
	for node: Node in projectiles.get_children():
		if node is Projectile and not (node as Projectile).is_spent():
			count += 1
	return count


# --- closing speeds ---------------------------------------------------------------------------------------------


func test_head_on_at_1400_mps_hits_in_every_phase() -> void:
	# A drone flying at 1 000 m/s into bolts that fly at 400 m/s: 1 400 m/s closing, 23 m per tick, against a hull
	# 2 m thick. 50 bolts, staggered so that they reach the drone at 50 different sub-tick phases.
	var drone: TargetDrone = _drone(Vector3.ZERO, Vector3(0.0, 0.0, -1000.0))
	var spacing_s: float = DT * (1.0 + 1.0 / float(PHASES))
	for i: int in PHASES:
		var meet_s: float = 0.5 + float(i) * spacing_s  # the time the bolt would meet the drone's centre
		_bolt(Vector3(0.0, 0.0, -BOLT_SPEED * meet_s - 1000.0 * meet_s), Vector3(0.0, 0.0, BOLT_SPEED))
	_tick_n(ceili((0.5 + float(PHASES) * spacing_s) / DT) + 5)
	assert_eq(hits.size(), PHASES, "all %d bolts hit" % PHASES)
	assert_eq(_live_bolts(), 0, "and every one was spent")
	assert_almost_eq(drone.damageable.hull.hp, drone.damageable.hull.max_hp - 10.0 * PHASES, 1e-3)
	for info: HitInfo in hits:
		assert_almost_eq(info.relative_speed_mps, 1400.0, 1.0)
		assert_eq(info.applied, 10.0)
		assert_eq(info.shooter_id, shooter_node_id)
		assert_eq(info.target_id, drone.get_instance_id())


func test_a_fast_bolt_cannot_tunnel_through_a_thin_target() -> void:
	# 1 400 m/s straight down the wing's thin axis: the box is 0.4 m thick (0.9 with the bolt's radius), one tick moves
	# the bolt 23 m. Cross the wing from above, off the fuselage axis.
	var drone: TargetDrone = _drone(Vector3.ZERO)
	for i: int in PHASES:
		var x: float = 1.2 + 0.015 * float(i)  # outside the capsule (radius 1 + 0.25), inside the wing's half width 2.25
		var bolt: Projectile = _bolt(Vector3(x, 100.0 + 0.37 * float(i), 0.0), Vector3(0.0, -1400.0, 0.0))
		assert_not_null(bolt)
	_tick_n(10)
	assert_eq(hits.size(), PHASES, "every bolt hit the wing")


func test_a_crossing_target_aimed_at_with_the_intercept_solution_is_hit() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260921
	var drone: TargetDrone = _drone(Vector3.ZERO)
	var landed: int = 0
	for trial: int in PHASES:
		for node: Node in projectiles.get_children():
			node.free()
		hits.clear()
		drone.damageable.hull.restore()
		var shooter_pos := Vector3(rng.randf_range(-20.0, 20.0), rng.randf_range(-20.0, 20.0), 0.0)
		var shooter_vel := Vector3(rng.randf_range(-40.0, 40.0), rng.randf_range(-40.0, 40.0), rng.randf_range(-40.0, 40.0))
		var target_pos := shooter_pos + Vector3(rng.randf_range(-300.0, 300.0), rng.randf_range(-300.0, 300.0),
				-rng.randf_range(800.0, 1500.0))
		var target_vel := Vector3(rng.randf_range(-300.0, 300.0), rng.randf_range(-30.0, 30.0), rng.randf_range(-30.0, 30.0))
		var solution: Dictionary = InterceptMath.solve(shooter_pos, shooter_vel, target_pos, target_vel, BOLT_SPEED, 10.0)
		assert_true(solution["ok"], "trial %d has a solution" % trial)
		drone.global_position = target_pos
		drone.velocity = target_vel
		_bolt(shooter_pos, shooter_vel + (solution["aim_dir"] as Vector3) * BOLT_SPEED)
		_tick_n(ceili(float(solution["t"]) / DT) + 6)
		if hits.size() == 1:
			landed += 1
	assert_eq(landed, PHASES, "the intercept solution hits a crossing target in every trial")


func test_a_bolt_passing_0_3_m_outside_the_inflated_volume_never_hits() -> void:
	# The hull capsule (radius 1) plus the bolt's 0.25 m reaches 1.25 m from the axis; the wing's half thickness plus
	# 0.25 is 0.45 m. A pass at 1.55 m above the axis (0.3 m outside the capsule's reach) must miss.
	_drone(Vector3.ZERO)
	for i: int in PHASES:
		_bolt(Vector3(0.01 * float(i), 1.55, 60.0 + 0.41 * float(i)), Vector3(0.0, 0.0, -BOLT_SPEED))
	_tick_n(60)
	assert_eq(hits.size(), 0)
	assert_eq(drones[0].damageable.hull.hp, drones[0].damageable.hull.max_hp)


func test_a_bolt_just_inside_the_reach_hits() -> void:
	_drone(Vector3.ZERO)
	_bolt(Vector3(0.0, 1.20, 60.0), Vector3(0.0, 0.0, -BOLT_SPEED))
	_tick_n(60)
	assert_eq(hits.size(), 1, "1.20 m from the axis is inside the 1.25 m reach")


func test_the_hit_point_is_where_the_bolt_enters_the_inflated_volume() -> void:
	_drone(Vector3.ZERO)
	_bolt(Vector3(0.0, 0.0, -100.0), Vector3(0.0, 0.0, BOLT_SPEED))
	_tick_n(60)
	assert_eq(hits.size(), 1)
	# The capsule's nose is at z = -3 (axis end -2 plus the 1 m cap); the bolt's 0.25 m radius reaches out to -3.25.
	assert_almost_eq(hits[0].point.z, -3.25, 0.3, "at the nose")
	assert_almost_eq(hits[0].point.x, 0.0, 0.01)
	assert_true(hits[0].normal.z < -0.99, "the normal points back along the bolt's path")


# --- who can be hit ---------------------------------------------------------------------------------------------


func test_a_bolt_never_hits_its_shooter() -> void:
	var drone: TargetDrone = _drone(Vector3.ZERO)
	_bolt(Vector3(0.0, 0.0, -100.0), Vector3(0.0, 0.0, BOLT_SPEED), Factions.EARTH_ALLIANCE, drone.get_instance_id())
	_tick_n(60)
	assert_eq(hits.size(), 0)


func test_a_bolt_never_hits_its_own_faction_or_a_neutral() -> void:
	_drone(Vector3.ZERO)
	_bolt(Vector3(0.0, 0.0, -100.0), Vector3(0.0, 0.0, BOLT_SPEED), Factions.RAIDERS)
	_bolt(Vector3(0.0, 0.3, -100.0), Vector3(0.0, 0.0, BOLT_SPEED), Factions.NEUTRAL)
	_bolt(Vector3(0.0, -0.3, -100.0), Vector3(0.0, 0.0, BOLT_SPEED), &"nobody_knows")
	_tick_n(60)
	assert_eq(hits.size(), 0)


func test_the_earliest_of_two_targets_on_the_path_takes_the_hit() -> void:
	var near: TargetDrone = _drone(Vector3(0.0, 0.0, -50.0))
	var far: TargetDrone = _drone(Vector3(0.0, 0.0, -100.0))
	_bolt(Vector3(0.0, 0.0, 100.0), Vector3(0.0, 0.0, -BOLT_SPEED))
	_tick_n(90)
	assert_eq(hits.size(), 1)
	assert_eq(hits[0].target_id, near.get_instance_id())
	assert_eq(far.damageable.hull.hp, far.damageable.hull.max_hp, "the far one is shielded by the near one")


func test_two_bolts_in_the_same_tick_both_land() -> void:
	var drone: TargetDrone = _drone(Vector3.ZERO)
	_bolt(Vector3(0.0, 0.5, -100.0), Vector3(0.0, 0.0, BOLT_SPEED))
	_bolt(Vector3(0.0, -0.5, -100.0), Vector3(0.0, 0.0, BOLT_SPEED))
	_tick_n(60)
	assert_eq(hits.size(), 2)
	assert_eq(drone.damageable.hull.hp, drone.damageable.hull.max_hp - 20.0)


func test_an_inactive_target_cannot_be_hit() -> void:
	var drone: TargetDrone = _drone(Vector3.ZERO)
	drone.visible = false
	_bolt(Vector3(0.0, 0.0, -100.0), Vector3(0.0, 0.0, BOLT_SPEED))
	_tick_n(60)
	assert_eq(hits.size(), 0, "a hidden (parked) ship is not there")
	drone.visible = true
	drone.process_mode = Node.PROCESS_MODE_DISABLED
	assert_false(drone.damageable.is_active(), "nor is a disabled one")


func test_a_rotated_target_is_swept_in_its_own_frame() -> void:
	var drone: TargetDrone = _drone(Vector3.ZERO)
	drone.global_basis = Basis(Vector3.UP, deg_to_rad(90.0))  # its z axis now points along world x
	# A bolt travelling along world z at x = 2: the capsule (now along x, nose at x = -3 / +3) is crossed at its middle.
	_bolt(Vector3(0.0, 0.0, -100.0), Vector3(0.0, 0.0, BOLT_SPEED))
	_bolt(Vector3(2.0, 3.0, -100.0), Vector3(0.0, 0.0, BOLT_SPEED))  # 3 m above the axis: misses
	_tick_n(60)
	assert_eq(hits.size(), 1)


# --- rebase ---------------------------------------------------------------------------------------------------


func test_a_rebase_between_launch_and_impact_gives_one_hit_at_the_right_point() -> void:
	var drone: TargetDrone = _drone(Vector3.ZERO)
	var drone_universe: UniversePos = world.to_universe(drone.global_position)
	_bolt(Vector3(0.0, 0.0, -300.0), Vector3(0.0, 0.0, BOLT_SPEED))
	_tick_n(15)
	assert_eq(hits.size(), 0, "still flying")
	world.rebase(Vector3(5000.0, 0.0, 0.0))
	_tick_n(60)
	assert_eq(hits.size(), 1, "exactly one hit, none along the jump")
	var expected: Vector3 = world.universe_to_local(drone_universe) + Vector3(0.0, 0.0, -3.25)
	assert_almost_eq(hits[0].point, expected, Vector3.ONE * 0.3)


func test_a_rebase_in_the_middle_of_the_hit_tick_is_harmless() -> void:
	# The jump lands between the bolt's move and the resolve of the tick that would hit: everything shifted together.
	_drone(Vector3.ZERO)
	var bolt: Projectile = _bolt(Vector3(0.0, 0.0, -9.0), Vector3(0.0, 0.0, BOLT_SPEED))  # one tick moves it 6.7 m, past the 3.25 m reach
	bolt._physics_process(DT)
	world.rebase(Vector3(-7000.0, 300.0, 0.0))
	resolver.resolve(DT)
	assert_eq(hits.size(), 1)


# --- cost ---------------------------------------------------------------------------------------------------


func test_64_bolts_against_8_targets_resolve_well_under_two_milliseconds() -> void:
	for i: int in 8:
		_drone(Vector3(float(i) * 400.0, 0.0, 0.0))
	for i: int in 64:
		_bolt(Vector3(float(i % 8) * 400.0 + 50.0, 20.0 + float(i / 8) * 5.0, 100.0), Vector3(0.0, 0.0, -BOLT_SPEED))
	var total_us: int = 0
	var ticks: int = 20
	for i: int in ticks:
		_tick()
		total_us += resolver.resolve_us
	assert_eq(resolver.projectiles_last_tick, 64)
	assert_eq(resolver.pairs_tested, 64 * 8, "every bolt against every hostile ship")
	var mean_us: float = float(total_us) / float(ticks)
	gut.p("64 bolts x 8 targets: %.0f us per tick (mean of %d)" % [mean_us, ticks])
	assert_true(mean_us < 2000.0, "mean %.0f us" % mean_us)


func test_the_combat_provider_reports_the_work() -> void:
	_drone(Vector3.ZERO)
	_bolt(Vector3(0.0, 0.0, -10.0), Vector3(0.0, 0.0, BOLT_SPEED))
	_tick_n(3)
	var registry: ConsoleRegistry = DebugConsole.registry
	assert_true(registry.has_provider(&"combat"))
	assert_eq(registry.format_path("combat.hits"), "combat.hits = 1")
	assert_string_contains(registry.format_path("combat.last_hit"), "applied")
