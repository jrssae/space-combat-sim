extends GutTest
## Allied ships from the pool (M3-T08, AC7, architecture §15.6, §16 D35): a `starfury_ally` is built once with its catalog faction,
## draws the Starfury's LOD1 splats, flies the Starfury `ShipSpec` numbers (the M1 AC5 formula for a straight burn), is named per
## acquire, and the number of `GaussianSplatNode`s in the tree never changes across acquire / release cycles (D22). The
## `raiders` and `allies` providers and `spawn ally` work on the console. The inner class runs the real main scene: allies in the
## sandbox do not count as raiders, are not cleared by the waves, and make no kills.

const ALLY: StringName = ShipPool.ALLY_TYPE
const RAIDER: StringName = ShipPool.DEFAULT_TYPE
const ALLY_COUNT: int = 3
const STARFURY_SPEC_PATH: String = "res://assets/ships/starfury_aurora.tres"
const GEN_ASSETS_HINT: String = "run scripts/gen_assets.sh, then scripts/run_tests.sh (it imports first)"
const DT: float = 1.0 / 60.0

var world: WorldFrame
var projectiles: Node3D
var pool: ShipPool
var player: Combatant
var starfury: ShipSpec


func before_each() -> void:
	starfury = load(STARFURY_SPEC_PATH) as ShipSpec
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
	player = ShipAssembly.build(starfury, world, projectiles, {
		ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE,
		ShipAssembly.OPT_DISPLAY_NAME: "PLAYER",
		ShipAssembly.OPT_CONSOLE_OWNER: true,
	})
	world.spawn(player.ship, world.to_universe(Vector3.ZERO))
	pool.player = player.ship
	assert_eq(pool.prepare(ALLY, ALLY_COUNT), ALLY_COUNT)
	assert_eq(pool.prepare(RAIDER, 1), 1)


func _splat_nodes() -> int:
	return _count_splat_nodes(get_tree().root)


func _count_splat_nodes(node: Node) -> int:
	var n: int = 1 if node is GaussianSplatNode else 0
	for child: Node in node.get_children():
		n += _count_splat_nodes(child)
	return n


func _console(line: String) -> ConsoleResult:
	var results: Array[ConsoleResult] = DebugConsole.registry.execute(line)
	assert_eq(results.size(), 1, "one statement: " + line)
	return results[0]


func _ally_at(z: float, ally_name: String = "ALPHA 2") -> Combatant:
	return pool.acquire(ally_name, UniversePos.new(0.0, 0.0, z), Basis.IDENTITY, Vector3.ZERO, null, ALLY)


# --- the pool ----------------------------------------------------------------------------------------------------


func test_allies_are_built_parked_with_the_catalog_faction() -> void:
	assert_eq(pool.pool_size(ALLY), ALLY_COUNT)
	assert_eq(pool.pool_size(RAIDER), 1)
	assert_eq(pool.pool_size(), ALLY_COUNT + 1, "no type is every ship")
	assert_eq(pool.free_count(ALLY), ALLY_COUNT)
	for combatant: Combatant in pool.all_ships():
		var type: StringName = pool.type_of(combatant)
		assert_eq(combatant.faction, ShipCatalog.faction_for(type), "%s flies its catalog faction" % type)
		assert_eq(combatant.targetable.faction, combatant.faction)
		assert_eq(combatant.damageable.faction, combatant.faction)
		assert_false(combatant.ship.visible)
		assert_eq(combatant.ship.process_mode, Node.PROCESS_MODE_DISABLED)
		assert_false(combatant.targetable.is_active(), "parked: not targetable")
		assert_false(combatant.damageable.is_active(), "parked: not hittable")
		assert_not_null(combatant.driver, "a pooled ship has a driver")
		assert_true(combatant.ship.force_assist, "AI ships fly with assist always on")
	assert_eq(pool.type_of(pool.all_ships()[0]), ALLY)
	assert_eq(pool.all_ships()[0].faction, Factions.EARTH_ALLIANCE)
	assert_eq(pool.all_ships()[ALLY_COUNT].faction, Factions.RAIDERS)


func test_an_ally_draws_the_lod1_hull_without_a_cockpit_interior() -> void:
	var manifest: ManifestReader = ManifestReader.load_dir("res://assets/generated/starfury_aurora")
	assert_true(manifest.is_valid(), "%s (%s)" % [manifest.errors_text(), GEN_ASSETS_HINT])
	var ally: Ship = pool.all_ships()[0].ship
	var hull: GaussianResource = ally.hull_splats.gaussian
	assert_not_null(hull, "the LOD1 hull loaded (%s)" % GEN_ASSETS_HINT)
	assert_eq(hull.resource_path, manifest.lod_path(manifest.lods[1]))
	assert_eq(hull.point_count, int(manifest.lods[1]["splats"]))
	assert_lt(hull.point_count, int(manifest.lods[0]["splats"]) / 3, "well under half the player's splats")
	assert_eq(player.ship.hull_splats.gaussian.point_count, int(manifest.lods[0]["splats"]), "the player keeps LOD0")
	assert_null(ally.cockpit_interior.mesh, "no first-person interior for an ally")
	assert_not_null(player.ship.cockpit_interior.mesh)
	assert_eq(ally.hull_mesh_fallback.mesh.get_surface_count(), player.ship.hull_mesh_fallback.mesh.get_surface_count(),
			"the same hull mesh as the fallback")


func test_an_ally_has_the_starfurys_body_hardpoints_and_guns() -> void:
	var ally: Ship = pool.all_ships()[0].ship
	assert_eq(ally.mass, starfury.mass)
	assert_eq(ally.inertia, starfury.inertia)
	assert_eq(ally.get_layout().pod_names, player.ship.get_layout().pod_names)
	assert_eq(ally.get_layout().nozzle_count(), player.ship.get_layout().nozzle_count())
	assert_eq(ally.get_muzzles().size(), player.ship.get_muzzles().size())
	assert_eq(pool.all_ships()[0].cannon.weapon, player.cannon.weapon, "the Starfury's pulse cannon")
	assert_eq(pool.all_ships()[0].damageable.hull.max_hp, starfury.hull_max)
	assert_false(pool.all_ships()[0].damageable.respects_god_mode, "god mode protects the player only")


func test_acquire_takes_a_ship_of_the_asked_type_and_names_it_per_acquire() -> void:
	var ally: Combatant = _ally_at(-200.0, "ALPHA 2")
	assert_not_null(ally)
	assert_eq(pool.type_of(ally), ALLY)
	assert_eq(ally.display_name, "ALPHA 2")
	assert_eq(ally.targetable.display_name, "ALPHA 2")
	assert_eq(ally.faction, Factions.EARTH_ALLIANCE)
	assert_true(ally.targetable.is_active())
	assert_eq(pool.free_count(ALLY), ALLY_COUNT - 1)
	assert_eq(pool.free_count(RAIDER), 1, "the raider pool is untouched")
	var raider: Combatant = pool.acquire("RAIDER 1", UniversePos.new(50.0, 0.0, -200.0))
	assert_eq(pool.type_of(raider), RAIDER, "the default type is still the raider")
	assert_eq(raider.faction, Factions.RAIDERS)
	pool.release(ally)
	assert_eq(ally.targetable.display_name, "", "a parked ship loses its callsign")
	var again: Combatant = pool.acquire("ALPHA 3", UniversePos.new(0.0, 0.0, -250.0), Basis.IDENTITY, Vector3.ZERO, null, ALLY)
	assert_eq(again.display_name, "ALPHA 3", "named afresh each time")


func test_alive_is_per_type() -> void:
	var a: Combatant = _ally_at(-200.0)
	var b: Combatant = _ally_at(-300.0, "ALPHA 3")
	var r: Combatant = pool.acquire("RAIDER 1", UniversePos.new(100.0, 0.0, -200.0))
	assert_eq(pool.alive().size(), 3)
	assert_eq(pool.alive(ALLY), [a, b])
	assert_eq(pool.alive(RAIDER), [r])
	assert_eq(pool.alive(&"battleship"), [])
	pool.release(a)
	assert_eq(pool.alive(ALLY), [b])


func test_next_name_takes_the_callsign_prefix_from_the_caller() -> void:
	assert_eq(pool.next_name(), "RAIDER 1", "raiders by default")
	assert_eq(pool.next_name("ALPHA", ShipPool.ALLY_FIRST_NUMBER), "ALPHA 2", "ALPHA 1 is the player")
	var a: Combatant = _ally_at(-200.0, pool.next_name("ALPHA", 2))
	var b: Combatant = _ally_at(-300.0, pool.next_name("ALPHA", 2))
	assert_eq([a.display_name, b.display_name], ["ALPHA 2", "ALPHA 3"])
	pool.release(a)
	assert_eq(pool.next_name("ALPHA", 2), "ALPHA 2", "the lowest free number again")
	assert_eq(pool.next_name(), "RAIDER 1", "the raiders' numbers are their own")


func test_an_empty_ally_pool_returns_null_with_one_warning_and_leaves_the_raiders_alone() -> void:
	for i: int in ALLY_COUNT:
		assert_not_null(_ally_at(-200.0 - 60.0 * float(i), "ALPHA %d" % (i + 2)))
	assert_null(_ally_at(-500.0, "ALPHA 9"))
	assert_push_warning_count(1)
	assert_eq(pool.free_count(RAIDER), 1)


func test_splat_nodes_never_enter_or_leave_the_tree_across_acquire_and_release_cycles() -> void:
	var before: int = _splat_nodes()
	assert_gt(before, 0)
	for cycle: int in 12:
		var ships: Array[Combatant] = []
		for i: int in ALLY_COUNT:
			ships.append(pool.acquire("ALPHA %d" % (i + 2), UniversePos.new(60.0 * float(i), 0.0, -200.0 - float(cycle)),
					Basis.IDENTITY, Vector3.ZERO, null, ALLY))
		ships.append(pool.acquire("RAIDER 1", UniversePos.new(0.0, 80.0, -300.0)))
		assert_eq(_splat_nodes(), before, "cycle %d: all acquired" % cycle)
		for combatant: Combatant in ships:
			pool.release(combatant)
		assert_eq(_splat_nodes(), before, "cycle %d: all released" % cycle)


func test_an_ally_is_a_friend_to_the_players_targeting() -> void:
	var ally: Combatant = _ally_at(-300.0)
	player.ship.targeting.refresh()
	assert_true(player.ship.targeting.select_by_name("ALPHA 2"), "selectable by name")
	assert_false(Factions.is_hostile(player.faction, ally.faction))
	player.ship.targeting.clear_selection()
	assert_false(player.ship.targeting.select_nearest_hostile(), "the nearest hostile does not pick a wingman")


func test_a_missing_manifest_warns_once_for_the_lod_and_draws_no_splats() -> void:
	var ghost_spec: ShipSpec = ShipCatalog.spec_for(ALLY).duplicate() as ShipSpec
	ghost_spec.asset_id = "no_such_ship"
	var ghost: Ship = Ship.create(ghost_spec, world)
	world.spawn(ghost, world.to_universe(Vector3(0.0, 300.0, 0.0)))
	assert_null(ghost.hull_splats.gaussian)
	# The hardpoints, the manifest and the hull mesh are each missing: three problems, three messages, none about the LOD twice.
	assert_push_warning_count(3)


func test_a_lod_the_manifest_does_not_list_warns_once_and_draws_lod0() -> void:
	var odd_spec: ShipSpec = ShipCatalog.spec_for(ALLY).duplicate() as ShipSpec
	odd_spec.splat_lod = 5
	var odd: Ship = Ship.create(odd_spec, world)
	world.spawn(odd, world.to_universe(Vector3(0.0, 300.0, 0.0)))
	assert_eq(odd.hull_splats.gaussian.point_count, player.ship.hull_splats.gaussian.point_count, "LOD0 instead")
	assert_push_warning_count(1)


# --- flying: the M1 AC5 straight-line formula ----------------------------------------------------------------------


func test_both_mains_accelerate_an_ally_straight_at_the_starfury_formula_rate() -> void:
	var ally: Combatant = _ally_at(-1000.0)
	var layout: ThrusterLayout = ally.ship.get_layout()
	assert_true(layout.valid, "valid thruster layout (%s)" % GEN_ASSETS_HINT)
	var mains: int = layout.nozzles_in_group(ThrusterLayout.Group.R_MAIN).size() + layout.nozzles_in_group(ThrusterLayout.Group.L_MAIN).size()
	assert_eq(mains, 4, "four pod main nozzles, as the Starfury's")
	var burn: int = roundi(2.0 * float(Engine.physics_ticks_per_second))
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	# The expected rate comes from the Starfury's spec, not the ally's: the ally must fly those numbers.
	var expected: float = 0.5 * float(mains) * starfury.pod_main_thrust / starfury.mass * float(burn) * dt
	await get_tree().physics_frame
	var cmd := FlightCommand.new()
	cmd.main_left = 0.5
	cmd.main_right = 0.5
	ally.ship.set_flight_command(cmd)
	var max_w: float = 0.0
	for i: int in burn:
		await get_tree().physics_frame
		ally.ship.set_flight_command(cmd)  # no brain: hold the command
		max_w = maxf(max_w, ally.ship.angular_velocity.length())
	var speed: float = ally.ship.linear_velocity.length()
	gut.p("ally: speed after 2 s %.4f m/s, expected %.4f (%.3f %%), max |w| %s rad/s" % [speed, expected, 100.0 * (speed - expected) / expected, str(max_w)])
	assert_almost_eq(speed, expected, 0.01 * expected, "speed = 0.5 * 4 * T / m * 2 s within 1 %")
	assert_lt(max_w, 1e-3, "|w| < 1e-3 rad/s while burning")
	assert_almost_eq(ally.ship.forward().dot(ally.ship.linear_velocity.normalized()), 1.0, 1e-6, "straight ahead")


# --- console -----------------------------------------------------------------------------------------------------


func test_the_allies_provider_and_spawn_ally() -> void:
	var registry: ConsoleRegistry = DebugConsole.registry
	assert_eq(registry.format_path("allies.pool_size"), "allies.pool_size = 3")
	assert_eq(registry.format_path("allies.free"), "allies.free = 3")
	assert_eq(registry.format_path("raiders.pool_size"), "raiders.pool_size = 1", "the raiders provider counts raiders only")
	assert_true(_console("spawn ally idle 60").ok)
	assert_eq(registry.format_path("allies.alive"), "allies.alive = 1")
	assert_eq(registry.format_path("raiders.alive"), "raiders.alive = 0")
	var ally: Combatant = pool.alive(ALLY)[0]
	assert_eq(ally.display_name, "ALPHA 2", "the player is ALPHA 1")
	assert_almost_eq(ally.ship.global_position, Vector3(0.0, 0.0, -60.0), Vector3.ONE * 1e-3, "ahead of the player")
	assert_almost_eq(-ally.ship.global_basis.z, Vector3(0.0, 0.0, 1.0), Vector3.ONE * 1e-4, "nose toward the player")
	assert_true(ally.driver.brain is IdleBrain)
	assert_string_contains(registry.format_path("allies.list"), "ALPHA 2")
	assert_true(_console("spawn ally 80 30 10").ok, "the behaviour word is optional")
	assert_eq(pool.alive(ALLY)[1].display_name, "ALPHA 3")


func test_spawn_ally_ai_flies_the_ally_profile() -> void:
	assert_true(_console("spawn ally ai 900").ok)
	var ally: Combatant = pool.alive(ALLY)[0]
	assert_true(ally.driver.brain is AiPilot)
	assert_eq((ally.driver.brain as AiPilot).profile.resource_path, AiProfile.PATHS[&"ally_starfury"])
	pool.release(ally)
	assert_true(_console("spawn raider ai 900").ok)
	assert_eq((pool.alive(RAIDER)[0].driver.brain as AiPilot).profile.resource_path, AiProfile.PATHS[&"raider"], "raiders keep theirs")


func test_spawn_ally_rejects_nonsense_and_other_behaviours() -> void:
	assert_false(_console("spawn ally banana").ok)
	assert_false(_console("spawn ally attack 500").ok, "allies take idle or ai")
	assert_false(_console("spawn ally patrol 500").ok)
	assert_false(_console("spawn ally idle 100 0 0 7").ok)
	assert_false(_console("spawn ally idle soon").ok)
	assert_eq(pool.alive().size(), 0)


func test_spawn_ally_with_an_empty_pool_fails_politely() -> void:
	for i: int in ALLY_COUNT:
		assert_true(_console("spawn ally idle %d" % (60 + 40 * i)).ok)
	assert_false(_console("spawn ally idle 300").ok)
	assert_push_warning_count(1)


func test_despawn_returns_allies_too() -> void:
	_console("spawn ally idle 60")
	_console("spawn raider idle 120")
	player.ship.targeting.refresh()
	assert_true(player.ship.targeting.select_by_name("ALPHA 2"))
	assert_true(_console("despawn target").ok, "any pooled ship")
	assert_eq(pool.alive(ALLY).size(), 0)
	assert_eq(pool.alive(RAIDER).size(), 1)
	_console("spawn ally idle 60")
	assert_eq(pool.alive().size(), 2)
	assert_true(_console("despawn all").ok)
	assert_eq(pool.alive().size(), 0)
	assert_eq(pool.free_count(), pool.pool_size())


func test_the_selected_brain_is_per_provider() -> void:
	_console("spawn ally ai 900")
	_console("spawn raider attack 900")
	var registry: ConsoleRegistry = DebugConsole.registry
	player.ship.targeting.refresh()
	assert_true(_console("set targeting.selected \"ALPHA 2\"").ok)
	assert_string_contains(registry.format_path("allies.selected_brain"), "behaviour: ")
	assert_eq(registry.format_path("raiders.selected_brain"), "raiders.selected_brain = none", "the selected ship is not a raider")
	assert_true(_console("set targeting.selected \"RAIDER 1\"").ok)
	assert_string_contains(registry.format_path("raiders.selected_brain"), "behaviour: attack")
	assert_eq(registry.format_path("allies.selected_brain"), "allies.selected_brain = none")


# --- allies in the sandbox ---------------------------------------------------------------------------------------


class TestAlliesInTheSandbox:
	extends GutTest

	var main: Main
	var source: FakeInputSource

	func before_each() -> void:
		get_tree().paused = false
		DebugConsole.flags.invulnerable = true
		source = FakeInputSource.new()
		main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
		main.input_source = source
		main.waves_auto_start = false
		add_child_autofree(main)
		await _ticks(2)

	func after_each() -> void:
		DebugConsole.flags.invulnerable = false
		Engine.time_scale = 1.0
		get_tree().paused = false

	func _ticks(n: int) -> void:
		for i: int in n:
			await get_tree().physics_frame

	func _exec(line: String) -> ConsoleResult:
		return DebugConsole.registry.execute(line)[0]

	func test_the_sandbox_builds_an_ally_pool_beside_the_raiders() -> void:
		assert_gt(main.ships.pool_size(ShipPool.ALLY_TYPE), 0, "the sandbox scenario pools allies")
		assert_eq(main.ships.pool_size(ShipPool.DEFAULT_TYPE), 6)
		assert_eq(main.ships.pool_size(), main.ships.pool_size(ShipPool.ALLY_TYPE) + 6)

	# The ally this test spawned (the newest one in play).
	func _spawned_ally() -> Combatant:
		var allies: Array[Combatant] = main.ships.alive(ShipPool.ALLY_TYPE)
		return allies[allies.size() - 1]

	func test_an_ally_is_not_a_raider_to_the_waves() -> void:
		var allies_before: int = main.ships.alive(ShipPool.ALLY_TYPE).size()
		assert_true(_exec("spawn ally idle 80").ok)
		assert_eq(main.ships.alive(ShipPool.ALLY_TYPE).size(), allies_before + 1)
		assert_eq(DebugConsole.registry.format_path("waves.alive"), "waves.alive = 0", "waves.alive counts raiders")
		assert_eq(main.waves.plan.state, WavePlan.State.IDLE)
		_exec("wave start 1")
		Engine.time_scale = 4.0
		var t0: float = SimClock.now()
		while main.waves.plan.state != WavePlan.State.ACTIVE and SimClock.now() - t0 < 60.0:
			await _ticks(1)
		await _ticks(3)
		assert_eq(main.ships.alive(ShipPool.ALLY_TYPE).size(), allies_before + 1, "starting a wave leaves the ally in play")
		assert_eq(main.ships.alive(ShipPool.DEFAULT_TYPE).size(), 3, "TARGET PRACTICE: three raiders")
		assert_string_contains(main.status_line, "RAIDERS 3")
		_exec("wave stop")
		assert_eq(main.ships.alive(ShipPool.ALLY_TYPE).size(), allies_before + 1, "stopping the waves leaves the ally in play")
		assert_eq(main.ships.alive(ShipPool.DEFAULT_TYPE).size(), 0)

	func test_a_destroyed_ally_is_no_kill() -> void:
		var kills_before: int = main.waves.kills
		var raider_deaths: Array[int] = [0]
		var ship_deaths: Array[Combatant] = []
		main.director.raider_destroyed.connect(func(_c: Combatant, _i: HitInfo) -> void: raider_deaths[0] += 1)
		main.director.ship_destroyed.connect(func(c: Combatant, _i: HitInfo) -> void: ship_deaths.append(c))
		assert_true(_exec("spawn ally idle 80").ok)
		var ally: Combatant = _spawned_ally()
		main.ship.targeting.refresh()
		assert_true(_exec("set targeting.selected \"%s\"" % ally.display_name).ok)
		assert_true(_exec("kill target").ok)
		assert_eq(main.waves.kills, kills_before, "an ally's death is not a kill")
		assert_eq(raider_deaths[0], 0)
		assert_eq(ship_deaths, [ally])
		assert_true(_exec("spawn raider idle 80").ok)
		main.ship.targeting.refresh()
		assert_true(_exec("set targeting.selected \"RAIDER 1\"").ok)
		assert_true(_exec("kill target").ok)
		assert_eq(main.waves.kills, kills_before + 1)
		assert_eq(raider_deaths[0], 1)
		assert_eq(ship_deaths.size(), 2)
