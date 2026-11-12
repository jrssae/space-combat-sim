extends TestSteps
## Rocks and mines as static rows (M4-T29, architecture §17.16, Q27). T07's asteroids and T12's mines are rows with no node:
## each is registered once (`StaticRows`), moved only by its own world's rebase, and no per-tick path walks them. Bolts still
## hit rocks and ships still ram them, through a kept grid in the hit and ram resolvers; a mine leaves the rows when it goes
## off and comes back when it is laid again. A side knows its own mines and steers clear of them; an enemy's are hidden from
## it until they go off; rocks are obstacles for everyone.

const DRONE_SCENE: String = "res://tests/fixtures/target_drone.tscn"
const RAIDER_SPEC: String = "res://assets/ships/raider_delta_v.tres"
const DT: float = 1.0 / 60.0
const MINE_START_M: float = 1000.0
const MINE_SPEED_MPS: float = 100.0
const LANE_SPACING_M: float = 8000.0
const SETTINGS: Array[StringName] = [&"ai_nearest_k", &"ai_nearest_static_k", &"ram_damage",
		&"friendly_fire"]

var world: WorldFrame
var projectiles: Node3D
var standins: StandinDirector
var now_s: float = 0.0
var _saved: Dictionary = {}


## Swept closest distance from a ship to a fixed point, tick by tick (after every script).
class Monitor extends Node:
	var ship: Node3D = null
	var point: Vector3 = Vector3.ZERO
	var min_m: float = INF
	var _prev: Vector3 = Vector3.ZERO

	func _init() -> void:
		process_physics_priority = 500

	func watch(p_ship: Node3D, p_point: Vector3) -> void:
		ship = p_ship
		point = p_point
		_prev = ship.global_position - point

	func _physics_process(_delta: float) -> void:
		var rel: Vector3 = ship.global_position - point
		var d: Vector3 = rel - _prev
		var len_sq: float = d.length_squared()
		var t: float = 0.0 if len_sq < 1e-12 else clampf(-_prev.dot(d) / len_sq, 0.0, 1.0)
		min_m = minf(min_m, (_prev + d * t).length())
		_prev = rel


func before_each() -> void:
	for key: StringName in SETTINGS:
		_saved[key] = Settings.get_value(key)
		Settings.reset(key)
	Settings.set_value(&"ram_damage", true)
	ContactScan.invalidate()
	StaticRows.clear()
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	projectiles = Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	standins = StandinDirector.new()
	standins.name = "Standins"
	standins.world = world
	standins.projectiles = projectiles
	world.add_child(standins)
	standins.set_physics_process(false)  # stepped by hand
	now_s = SimClock.now() + 100.0


func after_each() -> void:
	for key: StringName in SETTINGS:
		Settings.set_value(key, _saved[key])
	StaticRows.clear()
	ContactScan.invalidate()
	Factions.reset()


func _paths() -> Array[bool]:
	return [true]  # the native path; M4-T37 removed the GDScript one


func _drone(at: Vector3, faction: StringName = Factions.RAIDERS, velocity: Vector3 = Vector3.ZERO) -> TargetDrone:
	var drone := (load(DRONE_SCENE) as PackedScene).instantiate() as TargetDrone
	drone.faction = faction
	drone.velocity = velocity
	drone.set_physics_process(false)
	world.spawn(drone, world.to_universe(at))
	return drone


func _bolt(at: Vector3, velocity: Vector3, faction: StringName = Factions.RAIDERS) -> Projectile:
	var bolt := (load(Projectile.SCENE_PATH) as PackedScene).instantiate() as Projectile
	projectiles.add_child(bolt)
	bolt.configure(WeaponSpec.new())
	bolt.faction = faction
	bolt.launch(at, velocity, now_s)
	bolt.set_physics_process(false)
	return bolt


func _resolvers() -> Array:
	var hits := HitResolver.new()
	add_child_autofree(hits)
	hits.set_physics_process(false)
	var rams := RamResolver.new()
	add_child_autofree(rams)
	rams.set_physics_process(false)
	return [hits, rams]


# A seeded slab of `count` rocks of 20 to 200 m (log-uniform), 20 by 5 by 20 km round the origin.
static func _slab(rng: RandomNumberGenerator, count: int) -> Array[Dictionary]:
	var rocks: Array[Dictionary] = []
	for s: int in count:
		rocks.append({"offset": Vector3(rng.randf_range(-10000.0, 10000.0), rng.randf_range(-2500.0, 2500.0),
				rng.randf_range(-10000.0, 10000.0)), "radius": exp(rng.randf_range(log(20.0), log(200.0)))})
	return rocks


# --- rocks ---------------------------------------------------------------------------------------------------------


func test_a_thousand_rocks_are_registered_once_and_no_tick_walks_them() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 29
	var registrations: int = StaticRows.registrations
	var rocks: Array[Dictionary] = _slab(rng, 1000)
	var field: AsteroidField = standins.add_asteroids(rocks, world.to_universe(Vector3.ZERO))
	assert_eq(StaticRows.registrations - registrations, 1000, "each rock registered once, when the field is built")
	assert_eq(StaticRows.solid().ids.size(), 1000, "every rock is a solid row")
	assert_eq(field.get_child_count(), 1, "one multimesh and no node per rock")
	var drones: Array[TargetDrone] = []
	for i: int in 6:
		drones.append(_drone(Vector3(float(i) * 300.0, 4000.0, 0.0), Factions.RAIDERS, Vector3(0.0, -20.0, 0.0)))
	for i: int in 40:  # each falling onto a rock of the slab
		var rock: Vector3 = rocks[i * 20]["offset"]
		_bolt(rock + Vector3(0.0, float(rocks[i * 20]["radius"]) + 300.0, 0.0), Vector3(0.0, -1000.0, 0.0),
				Factions.EARTH_ALLIANCE)
	var resolvers: Array = _resolvers()
	var hits: HitResolver = resolvers[0]
	var rams: RamResolver = resolvers[1]
	var builds: int = -1
	var worst_static_pairs: int = 0
	for tick: int in 30:
		for bolt: Projectile in _live_bolts():
			bolt._physics_process(DT)
		hits.resolve(DT)
		rams.resolve(DT)
		if tick == 0:
			builds = StaticRows.solid_builds
		assert_eq(hits.hulls_last_tick, 6, "tick %d: the hit resolver gathered the drones' hulls, no rock" % tick)
		assert_eq(rams.hulls_last_tick, 6, "tick %d: so did the ram resolver" % tick)
		worst_static_pairs = maxi(worst_static_pairs, hits.static_pairs_visited)
	assert_eq(StaticRows.registrations - registrations, 1000, "no rock registered again")
	assert_eq(StaticRows.solid_builds, builds, "the solid rows were not rebuilt tick by tick")
	gut.p("worst rock pairs the hit resolver tested in a tick: %d (40 bolts, 1 000 rocks)" % worst_static_pairs)
	assert_gt(worst_static_pairs, 0, "bolts in the slab were put to the rocks near them")
	assert_lt(worst_static_pairs, 40 * 20, "the kept grid hands a bolt its neighbouring rocks only")
	for native: bool in _paths():
		ContactScan.invalidate()
		var scan: ContactScan = ContactScan.shared(get_tree())
		assert_eq(scan._node_count, 6, "%s scan: the drones are its only node rows" % scan.path())
		assert_eq(scan._body_ids.size(), 6 + 1000, "%s scan: then the rocks as rows" % scan.path())
		var contacts: Array[Contact] = scan.contacts_for(drones[0].get_instance_id(), drones[0].global_position,
				Factions.RAIDERS, 1.0e6)
		assert_eq(contacts.size(), 5, "%s scan: the other drones are the contacts, never a rock" % scan.path())


func _live_bolts() -> Array[Projectile]:
	var out: Array[Projectile] = []
	for node: Node in projectiles.get_children():
		var bolt := node as Projectile
		if bolt != null and not bolt.is_spent():
			out.append(bolt)
	return out


func test_a_bolt_hits_a_rock() -> void:
	var rocks: Array[Dictionary] = [{"offset": Vector3(0.0, 0.0, -1000.0), "radius": 50.0},
			{"offset": Vector3(400.0, 0.0, -2000.0), "radius": 120.0}]
	var field: AsteroidField = standins.add_asteroids(rocks, world.to_universe(Vector3.ZERO))
	for native: bool in _paths():
		var hits: HitResolver = _resolvers()[0]
		var infos: Array[HitInfo] = []
		hits.hit_resolved.connect(func(info: HitInfo) -> void: infos.append(info))
		var bolt: Projectile = _bolt(Vector3(0.0, 0.0, -800.0), Vector3(0.0, 0.0, -1000.0))
		for i: int in 30:
			if bolt.is_spent():
				break
			bolt._physics_process(DT)
			hits.resolve(DT)
		var label: String = "native" if native else "gdscript"
		assert_true(bolt.is_spent(), "%s: the bolt stopped" % label)
		assert_eq(infos.size(), 1, "%s: the bolt hit the rock in its path" % label)
		if infos.size() == 1:
			assert_eq(infos[0].target_id, field.row_id(0), "%s: the rock's row" % label)
			assert_almost_eq(infos[0].point.z, -950.0, 1.0, "%s: on the rock's face" % label)
			assert_eq(infos[0].applied, 0.0, "%s: rocks do not break" % label)


func test_a_ship_flying_into_a_rock_is_rammed() -> void:
	var rocks: Array[Dictionary] = [{"offset": Vector3(0.0, 0.0, -1000.0), "radius": 50.0}]
	var field: AsteroidField = standins.add_asteroids(rocks, world.to_universe(Vector3.ZERO))
	for native: bool in _paths():
		var rams: RamResolver = _resolvers()[1]
		var infos: Array[HitInfo] = []
		rams.ram_resolved.connect(func(info: HitInfo) -> void: infos.append(info))
		# The drone's nose (its capsule reaches 3 m along -z) 0.3 m from the rock's face, closing at 40 m/s.
		var drone: TargetDrone = _drone(Vector3(0.0, 0.0, -950.0 + 3.0 + 0.3), Factions.RAIDERS, Vector3(0.0, 0.0, -40.0))
		rams.resolve(DT)
		var label: String = "native" if native else "gdscript"
		assert_eq(infos.size(), 1, "%s: one ram, on the drone" % label)
		if infos.size() == 1:
			assert_eq(infos[0].target_id, drone.get_instance_id(), "%s: the drone took it" % label)
			assert_eq(infos[0].shooter_id, field.row_id(0), "%s: from the rock" % label)
		assert_string_contains(rams.last_ram, "prop", false)
		assert_true(drone.damageable.hull.destroyed, "%s: 40 m/s into a rock is lethal" % label)
		drone.queue_free()
		await _ticks(1)


func test_a_ship_grazing_a_rock_is_hurt_by_its_closing_speed_only() -> void:
	var rocks: Array[Dictionary] = [{"offset": Vector3(0.0, 0.0, -1000.0), "radius": 50.0}]
	standins.add_asteroids(rocks, world.to_universe(Vector3.ZERO))
	var rams: RamResolver = _resolvers()[1]
	var infos: Array[HitInfo] = []
	rams.ram_resolved.connect(func(info: HitInfo) -> void: infos.append(info))
	# The nose 2 cm off the rock's face, 40 m/s along it and 3 m/s into it: under the drone's 5 m/s safe change.
	var drone: TargetDrone = _drone(Vector3(0.0, 0.0, -950.0 + 3.0 + 0.02), Factions.RAIDERS, Vector3(40.0, 0.0, -3.0))
	rams.resolve(DT)
	assert_gt(rams.static_pairs_visited, 0, "the drone was tested against the rock")
	assert_eq(infos.size(), 0, "a scrape at 3 m/s does no harm")
	assert_false(drone.damageable.hull.destroyed)
	assert_eq(drone.damageable.hull.hp, drone.damageable.hull.max_hp)
	drone.queue_free()
	await _ticks(1)


func test_head_on_strips_the_motion_along_the_rock() -> void:
	var ship: Dictionary = {"start": Vector3(0.0, 0.0, 10.0), "velocity": Vector3(40.0, 0.0, -12.0)}
	var rock: Dictionary = {"start": Vector3.ZERO}
	var cut: Dictionary = RamResolver.head_on(ship, rock, Vector3(0.0, 0.0, 5.0))
	assert_almost_eq(cut["velocity"], Vector3(0.0, 0.0, -12.0), Vector3.ONE * 1e-4, "only the 12 m/s into the rock")
	assert_eq(ship["velocity"], Vector3(40.0, 0.0, -12.0), "the ship's own record is untouched")


# --- rebase --------------------------------------------------------------------------------------------------------


func test_a_rebase_moves_rocks_and_mines_once() -> void:
	var rocks: Array[Dictionary] = [{"offset": Vector3(100.0, 0.0, -1000.0), "radius": 40.0},
			{"offset": Vector3(-300.0, 50.0, -2000.0), "radius": 80.0}]
	var field: AsteroidField = standins.add_asteroids(rocks, world.to_universe(Vector3.ZERO))
	var mines: MineStandin = standins.add_mines([{"offset": Vector3(500.0, 0.0, -1500.0), "faction": Factions.RAIDERS}],
			world.to_universe(Vector3.ZERO))
	var rock_before: Vector3 = StaticRows.position_of(field.row_id(1))
	var mine_before: Vector3 = StaticRows.position_of(mines.row_id(0))
	assert_eq(mine_before, mines.position_of(0), "the mine's row is where the mine is")
	var offset := Vector3(1000.0, -200.0, 500.0)
	world.rebase(offset)
	assert_eq(StaticRows.position_of(field.row_id(1)), rock_before - offset, "the rock's row moved once")
	assert_eq(StaticRows.position_of(mines.row_id(0)), mine_before - offset, "the mine's row moved once")
	assert_almost_eq(StaticRows.position_of(mines.row_id(0)).distance_to(mines.position_of(0)), 0.0, 1e-3,
			"and is still where the mine is")
	var xform: Transform3D = PhysicsServer3D.body_get_state(field.body_rids()[1], PhysicsServer3D.BODY_STATE_TRANSFORM)
	assert_almost_eq(xform.origin.distance_to(rock_before - offset), 0.0, 1e-3, "the rock's physics body moved with it")
	# The resolvers see the rock at its new place.
	var hits: HitResolver = _resolvers()[0]
	var at: Vector3 = rock_before - offset
	var bolt: Projectile = _bolt(at + Vector3(0.0, 0.0, 200.0), Vector3(0.0, 0.0, -1000.0))
	for i: int in 30:
		if bolt.is_spent():
			break
		bolt._physics_process(DT)
		hits.resolve(DT)
	assert_true(bolt.is_spent(), "a bolt at the rock's new place hits it")


# --- mines ---------------------------------------------------------------------------------------------------------


func test_a_mine_leaves_the_rows_when_it_fires_and_comes_back_when_laid_again() -> void:
	var mines: MineStandin = standins.add_mines([{"offset": Vector3(0.0, 0.0, -1000.0), "faction": Factions.EARTH_ALLIANCE},
			{"offset": Vector3(0.0, 0.0, -3000.0), "faction": Factions.EARTH_ALLIANCE}], world.to_universe(Vector3.ZERO))
	var first: int = mines.row_id(0)
	assert_true(StaticRows.has(first), "a laid mine is a row")
	assert_true(StaticRows.has(mines.row_id(1)))
	var at: int = StaticRows.ids.find(first)
	assert_eq(StaticRows.kinds[at], BodyKind.MINE, "of kind mine")
	assert_eq(StaticRows.factions[at], Factions.EARTH_ALLIANCE, "owned by its side")
	assert_eq(StaticRows.radii[at], MineStandin.TRIGGER_RADIUS_M, "as big as its trigger")
	assert_eq(StaticRows.solid().ids.size(), 0, "a mine is not solid: bolts and rams pass it")
	var hostile: TargetDrone = _drone(Vector3(0.0, 0.0, -1010.0))
	var sim: SimCore = SimCore.attach(world)  # the mines step on the core's rows (M4-T37: their GDScript step is gone)
	for i: int in MineStandin.TRIGGER_TICKS:
		sim.sync_now()  # the rows as the bodies stand now: this test steps the stand-ins by hand
		standins.step(DT, now_s)
		now_s += DT
	assert_false(mines.is_alive(0), "the hostile set it off")
	assert_false(StaticRows.has(first), "a mine that went off is no longer a row")
	assert_true(StaticRows.has(mines.row_id(1)), "the other stays")
	hostile.global_position = Vector3(0.0, 0.0, 5000.0)
	for i: int in roundi(MineStandin.RELAY_S / DT) + MineStandin.TRIGGER_TICKS:
		sim.sync_now()
		standins.step(DT, now_s)
		now_s += DT
	assert_true(mines.is_alive(0), "laid again")
	assert_true(StaticRows.has(first), "and a row again, with the same id")
	assert_eq(StaticRows.position_of(first), mines.position_of(0), "in its place")
	standins.remove_mines()
	assert_false(StaticRows.has(first) or StaticRows.has(mines.row_id(1)), "removing the belts removes their rows")


func test_a_side_knows_its_own_mines_and_not_an_enemys_and_rocks_are_for_everyone() -> void:
	standins.add_mines([{"offset": Vector3(0.0, 0.0, -300.0), "faction": Factions.RAIDERS},
			{"offset": Vector3(0.0, 0.0, 300.0), "faction": Factions.EARTH_ALLIANCE}], world.to_universe(Vector3.ZERO))
	var field: AsteroidField = standins.add_asteroids([{"offset": Vector3(300.0, 0.0, 0.0), "radius": 60.0}],
			world.to_universe(Vector3.ZERO))
	var raider: TargetDrone = _drone(Vector3.ZERO, Factions.RAIDERS)
	var ally: TargetDrone = _drone(Vector3(0.0, 50.0, 0.0), Factions.EARTH_ALLIANCE)
	var mines: MineStandin = standins.mines()
	for native: bool in _paths():
		ContactScan.invalidate()
		var scan: ContactScan = ContactScan.shared(get_tree())
		var label: String = scan.path()
		var raider_sees: Array[int] = _ids(scan.statics_for(raider.get_instance_id(), raider.global_position, Factions.RAIDERS, 4))
		var ally_sees: Array[int] = _ids(scan.statics_for(ally.get_instance_id(), ally.global_position, Factions.EARTH_ALLIANCE, 4))
		assert_eq(raider_sees, [mines.row_id(0), field.row_id(0)] as Array[int], "%s: a raider sees its mine and the rock" % label)
		assert_eq(ally_sees, [mines.row_id(1), field.row_id(0)] as Array[int], "%s: an ally sees its own mine and the rock" % label)


static func _ids(list: Array[Contact]) -> Array[int]:
	var out: Array[int] = []
	for c: Contact in list:
		out.append(c.id)
	return out


func _ai_ship(display_name: String, faction: StringName, at: Vector3, velocity: Vector3) -> Combatant:
	var c: Combatant = ShipAssembly.build(load(RAIDER_SPEC) as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: faction,
		ShipAssembly.OPT_DISPLAY_NAME: display_name,
		ShipAssembly.OPT_FORCE_ASSIST: true,
		ShipAssembly.OPT_AI: true,
	})
	world.spawn(c.ship, world.to_universe(at), Basis.looking_at(velocity.normalized(), Vector3.UP))
	c.ship.linear_velocity = velocity
	return c


func test_a_fighter_steers_round_its_own_mine_and_flies_straight_over_an_enemy_one() -> void:
	# A raider on patrol straight at a mine row (registered alone, so nothing goes off): round its own side's, straight over
	# an Earth Alliance one it cannot know about.
	var cases: Array[Dictionary] = []
	for native: bool in _paths():
		cases.append({"native": native, "mine": Factions.RAIDERS})
		cases.append({"native": native, "mine": Factions.EARTH_ALLIANCE})
	for i: int in cases.size():
		ContactScan.invalidate()
		StaticRows.clear()
		var mine := Vector3(float(i) * LANE_SPACING_M, 0.0, 0.0)
		ContactScan.register_static(StaticRows.new_id(), mine, MineStandin.TRIGGER_RADIUS_M, BodyKind.MINE, cases[i]["mine"],
				world)
		var ship: Combatant = _ai_ship("RUNNER %d" % i, Factions.RAIDERS, mine + Vector3(0.0, 0.0, MINE_START_M),
				Vector3(0.0, 0.0, -MINE_SPEED_MPS))
		var ahead := Vector3(0.0, 0.0, -3000.0)
		var made: Dictionary = BrainFactory.from_behaviour({"type": "patrol", "cruise_mps": MINE_SPEED_MPS,
				"waypoints": [[ahead.x, ahead.y, ahead.z], [2.0 * ahead.x, 2.0 * ahead.y, 2.0 * ahead.z]]},
				world.to_universe(ship.ship.global_position), i)
		assert_true(made["ok"], made["error"])
		ship.driver.brain = made["brain"]
		var monitor := Monitor.new()
		add_child(monitor)
		monitor.watch(ship.ship, mine)
		await _ticks(roundi((MINE_START_M / MINE_SPEED_MPS + 2.0) * float(Engine.physics_ticks_per_second)))
		var own: bool = cases[i]["mine"] == Factions.RAIDERS
		var label: String = "%s mine on the %s path" % ["its own" if own else "an enemy", "native" if cases[i]["native"]
				else "GDScript"]
		gut.p("%s: closest %.1f m (trigger %.1f m)" % [label, monitor.min_m, MineStandin.TRIGGER_RADIUS_M])
		if own:
			assert_gt(monitor.min_m, MineStandin.TRIGGER_RADIUS_M, "%s: kept out of its trigger" % label)
		else:
			assert_lt(monitor.min_m, 20.0, "%s: flown straight over, unseen" % label)
		monitor.free()
		ship.ship.queue_free()
		await _ticks(1)
