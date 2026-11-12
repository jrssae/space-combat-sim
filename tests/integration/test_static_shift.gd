extends TestSteps
## The rebase cascade (M6-T06, L4): a rebase, and the frame's drift off its anchor, shift the static rows in place: no new
## version, the solid rows not gathered again, the scan's columns kept. Every answer the statics give afterwards (the contact
## scan's statics, the hit sweep's and the ram broad phase's rock pairs, the core's copy) is the one a fresh build of the same
## rows at their new places gives.

const DT: float = 1.0 / 60.0
const DRONE_SCENE: String = "res://tests/fixtures/target_drone.tscn"
const ROCKS: int = 200

var world: WorldFrame
var projectiles: Node3D
var standins: StandinDirector
var sim: SimCore
var drones: Array[TargetDrone] = []


func before_each() -> void:
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
	standins.set_physics_process(false)
	sim = SimCore.attach(world)
	drones.clear()


func after_each() -> void:
	StaticRows.clear()
	ContactScan.invalidate()


func test_a_rebase_and_a_drift_leave_the_statics_answering_as_a_fresh_build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 61
	var rocks: Array[Dictionary] = []
	for s: int in ROCKS:
		rocks.append({"offset": Vector3(rng.randf_range(-6000.0, 6000.0), rng.randf_range(-1500.0, 1500.0),
				rng.randf_range(-6000.0, 6000.0)), "radius": exp(rng.randf_range(log(20.0), log(200.0)))})
	standins.add_asteroids(rocks, world.to_universe(Vector3.ZERO))
	var mine_rows: Array[Dictionary] = []
	for i: int in 3:
		mine_rows.append({"offset": (rocks[i]["offset"] as Vector3) + Vector3(0.0, -400.0, 0.0), "faction": Factions.RAIDERS})
	standins.add_mines(mine_rows, world.to_universe(Vector3.ZERO))
	# Drones skimming past rocks 7 m off their faces (the ram broad phase pairs them, nothing rams), and bolts closing on rocks.
	for i: int in 6:
		var rock: Dictionary = rocks[i * 30]
		_drone((rock["offset"] as Vector3) + Vector3(0.0, float(rock["radius"]) + 7.0, 0.0), Vector3(600.0, 0.0, 0.0))
	for i: int in 20:
		var rock: Dictionary = rocks[i * 10]
		_bolt((rock["offset"] as Vector3) + Vector3(0.0, 0.0, float(rock["radius"]) + 12.0), Vector3(0.0, 0.0, -1000.0))
	var resolvers: Array = _resolvers()
	var before: Dictionary = _answers(resolvers[0], resolvers[1])
	assert_gt((before["hit"] as PackedInt64Array).size(), 0, "the bolts are paired with rocks")
	assert_gt((before["ram"] as PackedInt64Array).size(), 0, "the drones are paired with rocks")
	assert_gt((before["statics"] as Array).size(), 0, "the drones see rocks and their mines")
	var version: int = StaticRows.version
	var solid_version: int = StaticRows.solid_version
	var builds: int = StaticRows.solid_builds
	var solid: StaticRows.Solid = StaticRows.solid()
	var columns: Dictionary = StaticRows.scan_columns()
	var moves: int = StaticRows.moves

	world.rebase(Vector3(1834.25, -611.5, 4020.125))
	world._drift_anchored(PackedFloat64Array([-0.8333, 0.0125, 3.3]))  # the frame fell this far: the statics move back
	var shifted: Dictionary = _answers(resolvers[0], resolvers[1])

	assert_eq(StaticRows.moves, moves + 2, "two shifts")
	assert_eq(StaticRows.version, version, "a shift is not a new version of the rows")
	assert_eq(StaticRows.solid_version, solid_version, "nor of the solid rows")
	assert_eq(StaticRows.solid_builds, builds, "the solid rows were not gathered again")
	assert_same(StaticRows.solid(), solid, "the same solid rows, shifted in place")
	assert_same(StaticRows.scan_columns(), columns, "the scan's columns kept")
	assert_eq(solid.positions, _solid_positions(), "the solid rows hold the rows' new places")
	assert_eq(sim.core.static_positions(), StaticRows.positions, "the core took the new places")

	# A fresh build: the same rows registered again where they are now, and new resolvers.
	var rows: Array = [StaticRows.ids.duplicate(), StaticRows.positions.duplicate(), StaticRows.radii.duplicate(),
			StaticRows.kinds.duplicate(), StaticRows.factions.duplicate()]
	StaticRows.clear()
	for s: int in (rows[0] as PackedInt64Array).size():
		StaticRows.register(rows[0][s], rows[1][s], rows[2][s], rows[3][s], rows[4][s], world)
	var fresh_resolvers: Array = _resolvers()
	var fresh: Dictionary = _answers(fresh_resolvers[0], fresh_resolvers[1])
	assert_gt(StaticRows.solid_builds, builds, "the fresh build gathered its solid rows")
	for key: String in ["statics", "hit", "ram", "core"]:
		assert_eq(shifted[key], fresh[key], "%s: the shifted statics answer as a fresh build" % key)
	assert_ne(shifted["core"], before["core"], "and the rows did move")


# Every answer the statics give now: each drone's nearest statics, the hit sweep's and the ram broad phase's rock pairs
# through the resolvers as they keep their grids, and the core's static rows.
func _answers(hits: HitResolver, rams: RamResolver) -> Dictionary:
	sim.sync_now()
	ContactScan.invalidate()
	var scan: ContactScan = ContactScan.shared(get_tree())
	var statics: Array = []
	for drone: TargetDrone in drones:
		for c: Contact in scan.statics_for(drone.get_instance_id(), drone.global_position, Factions.RAIDERS, 8, 1.0e5):
			statics.append([c.id, c.kind, c.position, c.bounding_radius])
	var hit_keys: PackedInt64Array = hits._rock_pairs(sim)
	rams._resolve_rocks(sim, DT)  # takes the rocks' places as the resolver does each tick; the drones pass clear
	var ram_keys: PackedInt64Array = rams._rocks.kept_pairs_hulls_core(sim.core, DT, RamResolver.MARGIN_M)
	return {"statics": statics, "hit": hit_keys, "ram": ram_keys, "core": sim.core.static_positions()}


func _solid_positions() -> PackedVector3Array:
	var out := PackedVector3Array()
	for s: int in StaticRows.ids.size():
		if StaticRows.kinds[s] == BodyKind.STATIC:
			out.append(StaticRows.positions[s])
	return out


func _drone(at: Vector3, velocity: Vector3) -> void:
	var drone := (load(DRONE_SCENE) as PackedScene).instantiate() as TargetDrone
	drone.faction = Factions.RAIDERS
	drone.velocity = velocity
	drone.set_physics_process(false)
	world.spawn(drone, world.to_universe(at))
	drone.damageable.invulnerable = true
	drones.append(drone)


func _bolt(at: Vector3, velocity: Vector3) -> void:
	var bolt := (load(Projectile.SCENE_PATH) as PackedScene).instantiate() as Projectile
	projectiles.add_child(bolt)
	bolt.configure(WeaponSpec.new())
	bolt.faction = Factions.EARTH_ALLIANCE
	bolt.launch(at, velocity, SimClock.now())
	bolt.set_physics_process(false)


func _resolvers() -> Array:
	var hits := HitResolver.new()
	add_child_autofree(hits)
	hits.set_physics_process(false)
	var rams := RamResolver.new()
	add_child_autofree(rams)
	rams.set_physics_process(false)
	return [hits, rams]
