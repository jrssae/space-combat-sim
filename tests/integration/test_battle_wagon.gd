extends GutTest
## The raiders' Battle Wagon in the real main scene (M8-T09, D83, AC8), headless: it is built from its generated hull with its
## compound collision, twenty berths in its two launch tubes, eight plasma turrets and four missile racks; it comes out of its
## own jump point with ten fighters on its berths and launches them ahead through the tubes' bow mouths; called home, they
## come in through the stern mouths; its racks fire on a hostile fighter in reach, its turrets on one that attacked it (D61),
## and both hold fire on one out of reach.
## Its numbers are data (`data/capitals/capitals.json`), and free flight's raids and the sandbox scenario bring it by data.

const SEED: int = 5
## Ticks per real tick: the physics rate and the time scale raised together, so each step is still 1/60 s of sim time.
const SPEED_UP: float = 4.0
const WAGON: StringName = CapitalStandin.BATTLE_WAGON

var main: Main
var carriers: CarrierJumps
var _rate_backup: int = 60
var _scale_backup: float = 1.0


func before_each() -> void:
	get_tree().paused = false
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.scenario_seed = SEED
	add_child_autofree(main)
	await wait_physics_frames(2)
	DebugConsole.flags.invulnerable = true
	main.ships.prepare(ShipPool.DEFAULT_TYPE, 12)
	carriers = CarrierJumps.attach(main.world)


func after_each() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	DebugConsole.flags.invulnerable = false
	get_tree().paused = false


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute_tokens(line.split(" ", false))


func _fly(seconds: float, done: Callable = Callable()) -> void:
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < seconds:
		await get_tree().physics_frame
		if done.is_valid() and bool(done.call()):
			break
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup


# A Battle Wagon for the raiders, at rest `offset` from the player, its bow to -Z.
func _wagon(offset: Vector3) -> CapitalStandin:
	var cap: CapitalStandin = CapitalStandin.create(WAGON, Factions.RAIDERS, "WAGON", main.world.rest_velocity())
	cap.world = main.world
	main.world.spawn(cap, main.world.to_universe(main.ship.global_position + offset), Basis.IDENTITY)
	await wait_physics_frames(2)
	return cap


func _turret_shots(cap: CapitalStandin) -> int:
	var n: int = 0
	for mount: TurretMount in cap.mounts:
		n += mount.shots
	return n


# The wagon comes in with ten fighters on its berths; returns its run once it stands off with them launched.
func _bring_in() -> CarrierRun:
	assert_true(_run("transit wagon").ok)
	var run: CarrierRun = carriers.runs()[0]
	await _fly(90.0, func() -> bool: return run.state == CarrierRun.State.STANDOFF)
	return run


func test_the_hull_is_a_capital_body_with_its_tubes_turrets_and_racks() -> void:
	var cap: CapitalStandin = await _wagon(Vector3(0.0, 9000.0, 0.0))
	assert_not_null(cap.spec, "its numbers come from its ShipSpec")
	assert_eq(cap.spec.asset_id, "raider_battle_wagon")
	assert_almost_eq(cap.mass, cap.spec.mass, 1.0)
	assert_eq(cap.targetable.kind, Targetable.Kind.CAPITAL)
	assert_almost_eq(cap.damageable.hull.max_hp, cap.spec.hull_max, 1e-3)
	assert_true(JumpCapability.can_open(cap), "it opens its own jump points")
	assert_eq(cap.linear_damp, 0.0)
	assert_eq(cap.linear_damp_mode, RigidBody3D.DAMP_MODE_REPLACE, "zero damping")
	var manifest: Dictionary = MeshAssets.read_manifest("raider_battle_wagon")
	var shapes: int = 0
	for child: Node in cap.get_children():
		shapes += 1 if child is CollisionShape3D else 0
	var listed: int = 0
	for piece: Dictionary in (manifest["collision"] as Dictionary)["pieces"]:
		listed += (piece["shapes"] as Array).size()
	assert_eq(shapes, listed, "every shape of the manifest's compound")
	assert_eq(cap.damageable.shapes.size(), shapes, "and a hit volume for each")
	var dims: Dictionary = manifest["dimensions_m"]
	assert_almost_eq(cap.length_m(), float(dims["length"]), 0.5, "the class's box is the hull's")
	assert_almost_eq(2.0 * cap.half_extents().x, float(dims["span"]), 0.5)
	assert_eq(cap.drawn_mesh().get_surface_count(), 6, "the hull draws a surface per chunk, each with its own maps")
	assert_not_null(cap.dock)
	assert_eq(cap.dock.cradles.count(), 20, "twenty berths: two tubes, two lanes each, five deep")
	for i: int in cap.dock.cradles.count():
		assert_eq(cap.dock.cradles.lanes[i], 1, "a berth has its own ways out and home")
		assert_almost_eq(cap.dock.cradles.release_dirs[i], Vector3.FORWARD, Vector3.ONE * 1e-4, "out ahead, through the bow mouth")
		assert_almost_eq(cap.dock.cradles.approach_dirs[i], Vector3.BACK, Vector3.ONE * 1e-4, "home from astern")
	assert_eq(cap.mounts.size(), 8, "eight plasma turrets")
	assert_eq(cap.mounts[0].weapon, cap.spec.turret_weapon)
	assert_eq(cap.spec.turret_weapon.resource_path, "res://assets/weapons/turret_raider_plasma.tres")
	assert_almost_eq(cap.mounts[0].barrel_m, 11.25, 1e-3, "the shared turret at two and a half times its size")
	assert_gt(cap.mounts[0].yaw.get_child_count(), 0, "with its own model")
	assert_not_null(cap.racks)
	assert_eq(cap.racks.count(), 4, "four missile racks")
	assert_eq(cap.racks.schedule.missiles_left(), 24, "six cells each")
	assert_lt((cap.jump_anchor["position"] as Vector3).z, -400.0, "its point opens ahead of its bow")
	assert_gt(float(cap.jump_anchor["mouth_radius_m"]), 120.0, "and clears its ring")


func test_its_numbers_are_data() -> void:
	assert_eq(CapitalData.jump_recharge_s(WAGON), 240.0, "a raider carrier's drive: the longest recharge (D83)")
	assert_eq(CapitalData.jump_recharge_s(WAGON), CapitalData.jump_recharge_s(CapitalStandin.STRIKE_CARRIER))
	var racks: Dictionary = CapitalData.missile_racks(WAGON)
	assert_eq(int(racks["cells"]), 6)
	assert_eq(float(racks["range_m"]), 3000.0)
	assert_true(CapitalData.missile_racks(CapitalStandin.STRIKE_CARRIER).is_empty(), "the strike carrier has none")
	var cap: CapitalStandin = CapitalStandin.create(WAGON, Factions.RAIDERS, "WAGON", Vector3.ZERO)
	assert_eq(cap.jump_drive.recharge_s, 240.0)
	cap.free()


func test_its_racks_fire_on_a_hostile_fighter_in_reach_and_its_turrets_on_one_that_attacked_it() -> void:
	var cap: CapitalStandin = await _wagon(Vector3(700.0, 120.0, -300.0))
	for mount: TurretMount in cap.mounts:
		assert_gt(mount.slot(), -1, "%s is on the core's turret rows" % mount.mount_name)
		assert_eq(mount.faction, Factions.RAIDERS)
	# What its racks have in flight: guided missiles of the wagon's, at the player.
	var seen: Dictionary = {}
	var watch: Callable = func() -> void:
		for node: Node in main.projectiles.get_children():
			var shot := node as Projectile
			if shot != null and MissileStandin.of(shot) != null and shot.shooter_id == cap.get_instance_id():
				seen[shot.get_instance_id()] = MissileStandin.of(shot).target_id
	await _fly(8.0, func() -> bool:
		watch.call()
		return cap.racks.launches > 1)
	assert_gt(cap.racks.launches, 1, "its racks launch missiles at the player in reach")
	assert_eq(cap.racks.schedule.missiles_left(), 24 - cap.racks.launches, "each from a rack's cells")
	assert_gt(seen.size(), 0, "the missiles fly")
	for id: int in seen:
		assert_eq(seen[id], main.ship.get_instance_id(), "guided at the player")
	assert_eq(_turret_shots(cap), 0, "its turrets are gunners' (D61): they hold fire on a ship that has not attacked")
	# The player's bolt hits the wagon (what the hit sweep tells the core): now its turrets answer.
	SimCore.for_tree(get_tree()).note_hit(cap.get_instance_id(), main.ship.get_instance_id())
	await _fly(12.0, func() -> bool: return _turret_shots(cap) > 3)
	assert_gt(_turret_shots(cap), 3, "its plasma turrets fire on its attacker")
	assert_eq(int(DebugConsole.registry.read("carriers.turret_shots")["value"]), 0, "(the readout is the newest raid carrier's: none here)")
	assert_eq(cap.damageable.hull.fraction(), 1.0, "its own fire does not hit it")
	cap.set_faction(Factions.EARTH_ALLIANCE)
	for mount: TurretMount in cap.mounts:
		assert_eq(mount.faction, Factions.EARTH_ALLIANCE, "its turrets change sides with it")


func test_it_holds_fire_on_a_fighter_out_of_reach() -> void:
	var cap: CapitalStandin = await _wagon(Vector3(0.0, 4500.0, 0.0))
	await _fly(6.0)
	SimCore.for_tree(get_tree()).note_hit(cap.get_instance_id(), main.ship.get_instance_id())
	await _fly(4.0)
	assert_eq(_turret_shots(cap), 0, "4.5 km: beyond its turrets' 1.6 km, even at its attacker")
	assert_eq(cap.racks.launches, 0, "and beyond its racks' 3 km (data), though a missile would reach")
	assert_eq(cap.racks.schedule.missiles_left(), 24)


func test_it_jumps_in_with_ten_fighters_on_its_berths_and_launches_them_from_its_tubes() -> void:
	assert_true(_run("transit wagon").ok)
	assert_eq(carriers.runs().size(), 1)
	var run: CarrierRun = carriers.runs()[0]
	var cap: CapitalStandin = run.carrier
	assert_eq(cap.ship_class, WAGON)
	assert_eq(run.arrival.opener, cap, "it opened the point itself")
	assert_eq(cap.dock.docked_count(), 10, "its fighters ride in on the berths of its tubes")
	assert_eq(String(DebugConsole.registry.read("carriers.class")["value"]), "battle_wagon")
	for i: int in 10:
		assert_eq(cap.dock.cradles.states[i], CarrierCradles.State.DOCKED, "the front rows of every lane first")
	var ahead_of_mouths: Dictionary = {}
	cap.dock.launched.connect(func(ship: Ship) -> void:
		var local: Vector3 = cap.global_transform.affine_inverse() * ship.global_position
		ahead_of_mouths[ship] = [local, cap.global_basis.inverse() * (ship.linear_velocity - cap.linear_velocity)])
	await _fly(90.0, func() -> bool: return run.state == CarrierRun.State.STANDOFF)
	assert_eq(run.state, CarrierRun.State.STANDOFF, "clear of its point and its fighters out, it stands off")
	assert_eq(cap.dock.docked_count(), 0)
	assert_eq(cap.dock.launches, 10)
	assert_eq(ahead_of_mouths.size(), 10)
	var mouth_z: float = cap.dock.cradles.positions[0].z - 14.0
	for ship: Ship in ahead_of_mouths:
		var local: Vector3 = ahead_of_mouths[ship][0]
		var push: Vector3 = ahead_of_mouths[ship][1]
		assert_lt(local.z, mouth_z - 10.0, "let go ahead of its tube's bow mouth")
		assert_almost_eq(absf(local.x), 9.7, 0.3, "on its lane")
		assert_almost_eq(absf(local.y), 45.65, 0.5, "on its tube's axis")
		assert_lt(push.z, -20.0, "flying out ahead")
		assert_false(Damageable.of(ship).hull.destroyed, "unhurt by its launch")
	assert_eq(cap.damageable.hull.fraction(), 1.0, "nothing scraped the wagon")


func test_called_home_its_fighters_come_in_through_the_stern_mouths() -> void:
	var run: CarrierRun = await _bring_in()
	var cap: CapitalStandin = run.carrier
	assert_eq(run.state, CarrierRun.State.STANDOFF)
	for body: RigidBody3D in run.fighters:
		Damageable.of(body).invulnerable = true
	cap.damageable.invulnerable = true
	# Each fighter's place in the wagon's frame while its berth draws it in: behind its berth, on its lane.
	var worst_off_lane: float = 0.0
	var seen_astern: int = 0
	assert_true(_run("carrier recall").ok)
	var astern: Dictionary = {}
	await _fly(240.0, func() -> bool:
		for body: RigidBody3D in run.fighters:
			var ship := body as Ship
			if ship == null or not cap.dock.is_handling(ship) or cap.dock._rows.phase_of(ship.get_instance_id()) != 2:
				continue
			var local: Vector3 = cap.global_transform.affine_inverse() * ship.global_position
			worst_off_lane = maxf(worst_off_lane, absf(absf(local.x) - 9.7))
			if not astern.has(ship) and local.z > 60.0:
				astern[ship] = true
		return cap.dock.docked_count() == 10 or carriers.runs().is_empty())
	seen_astern = astern.size()
	assert_eq(cap.dock.dockings, 10, "every fighter came home to a berth")
	assert_eq(seen_astern, 10, "each drawn in from behind the stern mouth")
	assert_lt(worst_off_lane, 0.5, "along its lane")
	for body: RigidBody3D in run.fighters:
		assert_false(Damageable.of(body).hull.destroyed)


func test_free_flight_brings_it_for_a_share_of_the_raids_and_the_sandbox_for_all() -> void:
	var free: EncounterDirector = EncounterDirector.create(main, EncounterDirector.pools_file(&"free_flight"))
	assert_almost_eq(free.wagon_share, 0.25, 1e-6, "a quarter of free flight's raids (data)")
	free.seed_value = 11
	var wagons: int = 0
	for index: int in 400:
		var options: Dictionary = free.carrier_for(index)
		assert_eq(options, free.carrier_for(index), "every fighter of one raid comes with the same carrier")
		wagons += 1 if String(options.get("class", "")) == "battle_wagon" else 0
		assert_eq(String(options["arrival"]), "docked")
	assert_between(wagons, 60, 140, "about a quarter")
	free.wagon_share = 0.0
	assert_false(free.carrier_for(3).has("class"), "none without a share: the raiders' strike carrier")
	free.free()
	var sandbox: EncounterDirector = EncounterDirector.create(main, EncounterDirector.pools_file(&"battle_wagon_raid"))
	assert_not_null(sandbox, "the sandbox scenario has its pools file")
	assert_eq(String(sandbox.carrier_for(0)["class"]), "battle_wagon", "every raid of the sandbox comes with it")
	sandbox.free()
	var scenario: Dictionary = ScenarioLoader.load("res://data/scenarios/battle_wagon_raid.json")
	assert_true(bool(scenario.get("ok", true)), "the sandbox scenario loads: %s" % str(scenario.get("error", "")))
	assert_true(Main.SCENARIO_CHOICES.has(&"battle_wagon_raid"))
