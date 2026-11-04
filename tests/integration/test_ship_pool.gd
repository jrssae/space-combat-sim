extends GutTest
## ShipPool (M2-T05, AC6, architecture §15.6): raiders are built once and then only switched. No pooled ship enters or leaves
## the tree; parked ships are hidden, not processing, not targetable and not
## hittable; `acquire` places a ship within 1 mm of its `UniversePos` at the requested velocity; an empty pool returns
## null with one warning; and the `raiders` console surface works.

const POOL_SIZE: int = 3
const DT: float = 1.0 / 60.0

var world: WorldFrame
var projectiles: Node3D
var pool: ShipPool
var player: Combatant


func before_each() -> void:
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
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
	pool.player = player.ship
	assert_eq(pool.prepare(ShipPool.DEFAULT_TYPE, POOL_SIZE), POOL_SIZE)


func _pooled_nodes() -> int:
	return _count_pooled_nodes(get_tree().root)


func _count_pooled_nodes(node: Node) -> int:
	var n: int = 1 if _pooled(node) else 0
	for child: Node in node.get_children():
		n += _count_pooled_nodes(child)
	return n


func _console(line: String) -> ConsoleResult:
	var results: Array[ConsoleResult] = DebugConsole.registry.execute(line)
	assert_eq(results.size(), 1, "one statement: " + line)
	return results[0]


# --- the pool ----------------------------------------------------------------------------------------------------


func test_the_pool_is_built_parked() -> void:
	assert_eq(pool.pool_size(), POOL_SIZE)
	assert_eq(pool.free_count(), POOL_SIZE)
	assert_eq(pool.alive().size(), 0)
	for node: Node in pool.get_children():
		var ship := node as Ship
		assert_not_null(ship)
		assert_eq(ship.get_parent(), pool, "ships live under World/Ships")
		assert_true(ship.is_in_group(WorldFrame.SHIFTABLE_GROUP))


func test_parked_raiders_are_hidden_inert_untargetable_and_unhittable() -> void:
	for combatant: Combatant in pool._all:
		assert_false(combatant.ship.visible)
		assert_false(combatant.ship.is_visible_in_tree())
		assert_eq(combatant.ship.process_mode, Node.PROCESS_MODE_DISABLED)
		assert_false(combatant.ship.can_process(), "not processing")
		assert_false(combatant.targetable.is_active(), "not targetable")
		assert_false(combatant.damageable.is_active(), "not hittable")
	player.ship.targeting.refresh()
	assert_eq(player.ship.targeting.candidates().size(), 0, "the player's targeting does not see parked ships")


func test_acquire_places_the_ship_at_its_universe_position_with_the_velocity() -> void:
	var at := UniversePos.new(123.456, -7.891, -2345.678)
	var basis := Basis(Vector3.UP, deg_to_rad(33.0))
	var velocity := Vector3(4.0, -2.0, -50.0)
	var raider: Combatant = pool.acquire("RAIDER 1", at, basis, velocity)
	assert_not_null(raider)
	var placed: UniversePos = world.to_universe(raider.ship.global_position)
	assert_lt(placed.distance_to(at), 1e-3, "within 1 mm")
	assert_eq(raider.ship.linear_velocity, velocity)
	assert_eq(raider.ship.angular_velocity, Vector3.ZERO)
	assert_true(raider.ship.global_basis.is_equal_approx(basis))
	assert_true(raider.ship.visible)
	assert_true(raider.ship.can_process())
	assert_true(raider.targetable.is_active())
	assert_true(raider.damageable.is_active())
	assert_eq(raider.display_name, "RAIDER 1")
	assert_eq(raider.targetable.display_name, "RAIDER 1")
	assert_eq(raider.faction, Factions.RAIDERS)
	assert_eq(pool.free_count(), POOL_SIZE - 1)
	assert_eq(pool.alive(), [raider])


func test_acquire_gives_a_fresh_ship_every_time() -> void:
	var raider: Combatant = pool.acquire("RAIDER 1", UniversePos.new(0.0, 0.0, -100.0))
	raider.damageable.hull.apply(40.0)
	raider.ship.get_fuel_tank().draw(1.0e9, 1.0)
	raider.cannon.set_charge_fraction(0.0)
	pool.release(raider)
	var seen_it_again: bool = false
	for i: int in POOL_SIZE:
		var again: Combatant = pool.acquire("RAIDER %d" % (i + 2), UniversePos.new(float(i) * 50.0, 0.0, -100.0))
		assert_eq(again.damageable.hull.hp, again.damageable.hull.max_hp, "full hull")
		assert_eq(again.cannon.charge_fraction(), 1.0, "full capacitor")
		assert_eq(again.ship.get_fuel_tank().fraction(), 1.0, "full tank")
		assert_false(again.damageable.hull.destroyed)
		seen_it_again = seen_it_again or again == raider
	assert_true(seen_it_again, "the released ship came back")


func test_a_reused_ship_shows_nothing_of_its_last_pilot() -> void:
	var raider: Combatant = pool.acquire("RAIDER 1", UniversePos.new(0.0, 0.0, -100.0))
	var burn := FlightCommand.new()
	burn.main_left = 1.0
	burn.main_right = 1.0
	raider.ship.set_flight_command(burn)
	await get_tree().physics_frame
	await get_tree().physics_frame
	raider.thrusters.advance(1.0)
	var lit: int = 0
	for i: int in raider.thrusters.glow_count():
		lit += 1 if raider.thrusters.glow_level(i) > 0.5 else 0
	assert_gt(lit, 0, "the plumes burn")
	var flash := raider.ship.get_muzzles()[0].get_node("MuzzleFlash") as MuzzleFlash
	flash.trigger()
	flash.advance(0.01)
	assert_true(flash.is_active(), "a flash at the gun")
	var switcher := raider.ship.get_node("LodSwitcher") as LodSwitcher
	switcher.far = true
	raider.ship.set_far_dot(true)
	for i: int in POOL_SIZE - 1:  # the others in use, so the next acquire takes this one again
		pool.acquire("RAIDER %d" % (i + 2), UniversePos.new(float(i + 1) * 50.0, 0.0, -100.0))
	pool.release(raider)
	var again: Combatant = pool.acquire("RAIDER 9", UniversePos.new(0.0, 0.0, -200.0))
	assert_eq(again, raider, "the same ship, for its next pilot")
	for i: int in again.thrusters.glow_count():
		assert_eq(again.thrusters.glow_level(i), 0.0, "plume %d starts cold" % i)
		var light: LightEmitter = again.thrusters.nozzle_light(i)
		if light != null:
			assert_eq(light.energy, 0.0, "its nozzle light %d too" % i)
		assert_false(again.thrusters.glow_shown(i), "plume %d hidden" % i)
	assert_false(flash.is_active(), "no rest of the last flash")
	assert_false(flash.visible)
	assert_eq(flash.light_emitter().energy, 0.0)
	assert_false(switcher.far, "drawn in full until its switcher next looks")
	assert_false(again.ship.is_far_dot())


func test_release_parks_the_ship_again() -> void:
	var raider: Combatant = pool.acquire("RAIDER 1", UniversePos.new(0.0, 0.0, -100.0), Basis.IDENTITY, Vector3(0.0, 0.0, -9.0))
	pool.release(raider)
	assert_false(raider.ship.visible)
	assert_eq(raider.ship.process_mode, Node.PROCESS_MODE_DISABLED)
	assert_eq(raider.ship.linear_velocity, Vector3.ZERO)
	assert_false(raider.targetable.is_active())
	assert_eq(pool.free_count(), POOL_SIZE)
	pool.release(raider)  # a second release is ignored
	assert_eq(pool.free_count(), POOL_SIZE)


func test_an_empty_pool_returns_null_with_one_warning() -> void:
	for i: int in POOL_SIZE:
		assert_not_null(pool.acquire("RAIDER %d" % i, UniversePos.new(float(i) * 50.0, 0.0, -100.0)))
	assert_null(pool.acquire("one too many", UniversePos.new(0.0, 0.0, -500.0)))
	assert_push_warning_count(1)


func test_pooled_nodes_never_enter_or_leave_the_tree() -> void:
	var before: int = _pooled_nodes()
	assert_gt(before, 0)
	for cycle: int in 20:
		var raiders: Array[Combatant] = []
		for i: int in POOL_SIZE:
			raiders.append(pool.acquire("R%d" % i, UniversePos.new(float(i) * 60.0, 0.0, -200.0 - float(cycle))))
		assert_eq(_pooled_nodes(), before, "cycle %d: all acquired" % cycle)
		for raider: Combatant in raiders:
			pool.release(raider)
		assert_eq(_pooled_nodes(), before, "cycle %d: all released" % cycle)


func test_a_rebase_moves_parked_and_active_ships_alike() -> void:
	var raider: Combatant = pool.acquire("RAIDER 1", UniversePos.new(10.0, 0.0, -300.0))
	var universe_before: UniversePos = world.to_universe(raider.ship.global_position)
	world.rebase(Vector3(4000.0, 0.0, 0.0))
	assert_lt(world.to_universe(raider.ship.global_position).distance_to(universe_before), 1e-3)
	var parked: Ship = pool._free[0].ship
	assert_lt(world.to_universe(parked.global_position).y, -9.0e5, "still parked far below")


# --- the raider flying in the world -----------------------------------------------------------------------------


func test_an_acquired_raider_is_targeted_and_hit_like_any_ship() -> void:
	var raider: Combatant = pool.acquire("RAIDER 1", UniversePos.new(0.0, 0.0, -300.0))
	var cmd := CombatCommand.new()
	cmd.target_next = true
	player.ship.targeting.refresh()
	player.ship.targeting.apply(cmd)
	assert_eq(player.ship.targeting.selected_name(), "RAIDER 1")
	var resolver := HitResolver.new()
	add_child_autofree(resolver)
	resolver.set_physics_process(false)
	var bolt := (load(Projectile.SCENE_PATH) as PackedScene).instantiate() as Projectile
	projectiles.add_child(bolt)
	bolt.configure(player.ship.spec.weapon)
	bolt.shooter_id = player.ship.get_instance_id()
	bolt.faction = Factions.EARTH_ALLIANCE
	bolt.launch(Vector3(0.0, 0.0, -250.0), Vector3(0.0, 0.0, -400.0), SimClock.now())
	bolt.set_physics_process(false)
	for i: int in 30:
		bolt._physics_process(DT)
		resolver.resolve(DT)
	assert_eq(raider.damageable.hull.hp, raider.damageable.hull.max_hp - 10.0)


# --- console -----------------------------------------------------------------------------------------------------


func test_raiders_provider_and_spawn_command() -> void:
	var registry: ConsoleRegistry = DebugConsole.registry
	assert_eq(registry.format_path("raiders.pool_size"), "raiders.pool_size = 3")
	assert_eq(registry.format_path("raiders.free"), "raiders.free = 3")
	assert_true(_console("spawn raider 50").ok)
	assert_eq(registry.format_path("raiders.alive"), "raiders.alive = 1")
	var raider: Combatant = pool.alive()[0]
	assert_eq(raider.display_name, "RAIDER 1")
	assert_almost_eq(raider.ship.global_position, Vector3(0.0, 0.0, -50.0), Vector3.ONE * 1e-3, "ahead of the player")
	assert_almost_eq(-raider.ship.global_basis.z, Vector3(0.0, 0.0, 1.0), Vector3.ONE * 1e-4, "nose toward the player")
	assert_string_contains(registry.format_path("raiders.list"), "RAIDER 1")
	assert_true(_console("spawn raider 80").ok)
	assert_eq(pool.alive()[1].display_name, "RAIDER 2", "the next free number")


func test_spawn_yaw_and_pitch_turn_the_raider_to_show_a_side_or_the_top() -> void:
	assert_true(_console("spawn raider 50 90 0").ok)
	var side: Combatant = pool.alive()[0]
	assert_almost_eq(absf(side.ship.global_basis.z.dot(Vector3.UP)), 0.0, 1e-4, "yaw 90 stays level")
	assert_almost_eq(absf(side.ship.global_basis.z.z), 0.0, 1e-4, "and its nose is now sideways to the player")
	assert_true(_console("spawn raider 90 0 90").ok)
	var top: Combatant = pool.alive()[1]
	assert_almost_eq(absf(top.ship.global_basis.y.z), 1.0, 1e-4, "pitch 90: its top faces the player")


func test_despawn_all_and_target() -> void:
	_console("spawn raider 50")
	_console("spawn raider 80")
	player.ship.targeting.refresh()
	var cmd := CombatCommand.new()
	cmd.target_next = true
	player.ship.targeting.apply(cmd)
	assert_true(_console("despawn target").ok)
	assert_eq(pool.alive().size(), 1)
	assert_true(_console("despawn all").ok)
	assert_eq(pool.alive().size(), 0)
	assert_eq(pool.free_count(), POOL_SIZE)
	assert_false(_console("despawn target").ok, "nothing selected")


func test_spawn_with_an_empty_pool_fails_politely() -> void:
	for i: int in POOL_SIZE:
		_console("spawn raider %d" % (40 + 20 * i))
	assert_false(_console("spawn raider 200").ok)
	assert_push_warning_count(1)


func test_next_name_reuses_the_lowest_free_number() -> void:
	var a: Combatant = pool.acquire(pool.next_name(), UniversePos.new(0.0, 0.0, -100.0))
	var b: Combatant = pool.acquire(pool.next_name(), UniversePos.new(50.0, 0.0, -100.0))
	assert_eq([a.display_name, b.display_name], ["RAIDER 1", "RAIDER 2"])
	pool.release(a)
	assert_eq(pool.next_name(), "RAIDER 1")


# --- behaviours through the console (M2-T07) -----------------------------------------------------------------------


func test_spawn_with_a_behaviour_gives_the_raider_that_brain() -> void:
	for behaviour: String in ["idle", "patrol", "attack", "aggro"]:
		pool.release(pool.alive()[0]) if not pool.alive().is_empty() else null
		assert_true(_console("spawn raider %s 400" % behaviour).ok, behaviour)
		var raider: Combatant = pool.alive()[0]
		assert_not_null(raider.driver.brain, behaviour)
		assert_eq(raider.driver.brain.describe()["behaviour"], behaviour)


func test_spawn_without_a_behaviour_is_an_idle_raider_as_before() -> void:
	assert_true(_console("spawn raider 80 10 5").ok)
	var raider: Combatant = pool.alive()[0]
	assert_true(raider.driver.brain is IdleBrain)
	assert_almost_eq(raider.ship.global_position.length(), 80.0, 1e-3)


func test_spawn_rejects_nonsense() -> void:
	assert_false(_console("spawn raider banana").ok)
	assert_false(_console("spawn raider attack 100 0 0 7").ok)
	assert_false(_console("spawn raider attack soon").ok)
	assert_eq(pool.alive().size(), 0)


func test_selected_brain_describes_the_selected_raiders_state() -> void:
	_console("spawn raider attack 900")
	var registry: ConsoleRegistry = DebugConsole.registry
	assert_eq(registry.format_path("raiders.selected_brain"), "raiders.selected_brain = none", "nothing selected")
	assert_true(_console("set targeting.selected \"RAIDER 1\"").ok)
	assert_string_contains(registry.format_path("raiders.selected_brain"), "behaviour: attack")
	assert_string_contains(registry.format_path("raiders.selected_brain"), "state: approach")


func test_a_released_raider_loses_its_brain() -> void:
	_console("spawn raider attack 400")
	var raider: Combatant = pool.alive()[0]
	pool.release(raider)
	assert_null(raider.driver.brain)


func test_patrol_spawn_waypoints_are_around_the_spawn_point() -> void:
	_console("spawn raider patrol 500")
	var brain := pool.alive()[0].driver.brain as PatrolBrain
	assert_eq(brain.waypoints.size(), 3)
	var spawn_at: Vector3 = pool.alive()[0].ship.global_position
	for waypoint: UniversePos in brain.waypoints:
		assert_lt(world.universe_to_local(waypoint).distance_to(spawn_at), 1000.0)


# A node the pools build once at load and only switch afterwards (D22): a pooled ship or a pooled break-up chunk.
static func _pooled(node: Node) -> bool:
	return (node is DebrisChunk and not (node as DebrisChunk).one_shot) or (node is Ship and node.get_parent() is ShipPool)
