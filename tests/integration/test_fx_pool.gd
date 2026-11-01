extends GutTest
## FxPool (M3-T23, AC32): fixed `GPUParticles3D` pools for hull hits, rams, explosions and debris. The particle node count never
## changes; every process material has no gravity and no damping; a burst inherits its source's velocity; a burst live across a
## rebase is shifted with the world; `settings.particle_density` scales the amounts and 0 costs nothing. Headless has no particle
## simulation, so this tests the pools, the specs and the wiring; how it looks is AC35's.

const DT: float = 1.0 / 60.0
const DRONE_SCENE: String = "res://tests/fixtures/target_drone.tscn"
const SPEC_PATH: String = "res://assets/ships/starfury_aurora.tres"
const RAIDER_ASSET: StringName = &"raider_fighter"
const RAIDER_SPEC_PATH: String = "res://assets/ships/raider_delta_v.tres"

var world: WorldFrame
var pool: FxPool
var _density_backup: float = 1.0


func before_each() -> void:
	_density_backup = float(Settings.get_value(&"particle_density"))
	Settings.set_value(&"particle_density", 1.0)
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	pool = FxPool.new()
	pool.name = "Fx"
	world.add_child(pool)


func after_each() -> void:
	Settings.set_value(&"particle_density", _density_backup)


func _particle_nodes(node: Node) -> int:
	var n: int = 1 if node is GPUParticles3D else 0
	for child: Node in node.get_children():
		n += _particle_nodes(child)
	return n


func _expected_emitters() -> int:
	var total: int = 0
	for effect: int in FxSpecs.COUNT:
		total += int(FxSpecs.spec(effect)["emitters"])
	return total


# --- the pool -------------------------------------------------------------------------------------------------------


func test_the_pool_builds_every_emitter_once_parked() -> void:
	assert_eq(pool.emitter_count(), _expected_emitters())
	assert_eq(_particle_nodes(pool), _expected_emitters())
	assert_eq(pool.busy_count(), 0)
	assert_false(pool.is_processing(), "an idle pool does no per-frame work")
	for effect: int in FxSpecs.COUNT:
		var spec: Dictionary = FxSpecs.spec(effect)
		var emitters: Array[GPUParticles3D] = pool.emitters_of(effect)
		assert_eq(emitters.size(), int(spec["emitters"]))
		for emitter: GPUParticles3D in emitters:
			assert_false(emitter.emitting)
			assert_false(emitter.visible, "a parked emitter is hidden")
			assert_true(emitter.top_level, "it does not follow the pool node")
			assert_true(emitter.local_coords, "its particles live in its frame, so a rebase moves them")
			assert_true(emitter.is_in_group(WorldFrame.SHIFTABLE_GROUP), "a rebase shifts it")
			assert_eq(emitter.amount, int(spec["amount"]))
			assert_almost_eq(emitter.lifetime, float(spec["lifetime_s"]), 1e-6)
			assert_eq(emitter.one_shot, not bool(spec["continuous"]))
			assert_not_null(emitter.draw_pass_1, "it has a mesh to draw")
			assert_not_null(emitter.process_material)


func test_every_process_material_has_zero_gravity_and_zero_damping() -> void:
	# AC32 and the damping guard (architecture 5.4): particles keep the speed they were thrown at.
	for effect: int in FxSpecs.COUNT:
		for emitter: GPUParticles3D in pool.emitters_of(effect):
			var material := emitter.process_material as ParticleProcessMaterial
			assert_not_null(material, "%s has a ParticleProcessMaterial" % emitter.name)
			assert_eq(material.gravity, Vector3.ZERO, "%s: no gravity" % emitter.name)
			assert_eq(material.damping_min, 0.0, "%s: no damping" % emitter.name)
			assert_eq(material.damping_max, 0.0, "%s: no damping" % emitter.name)


func test_the_particle_meshes_are_unshaded_additive_and_emissive() -> void:
	for effect: int in FxSpecs.COUNT:
		var mesh: Mesh = pool.emitters_of(effect)[0].draw_pass_1
		var material := mesh.surface_get_material(0) as StandardMaterial3D if mesh.get_surface_count() > 0 else null
		if material == null:
			material = mesh.get("material") as StandardMaterial3D
		assert_not_null(material, "%s mesh has a material" % FxSpecs.spec(effect)["name"])
		if material != null:
			assert_eq(material.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED)
			assert_eq(material.blend_mode, BaseMaterial3D.BLEND_MODE_ADD)
			assert_ne(material.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED, "transparent, so the hull depth proxy hides it")


# --- a burst --------------------------------------------------------------------------------------------------------


func test_a_burst_is_placed_at_once_and_started_by_the_next_frame() -> void:
	var handle: int = pool.burst(FxSpecs.HIT, Vector3(10.0, 20.0, 30.0), Vector3(0, 0, 1), Vector3(0, 0, -50.0))
	assert_ne(handle, 0)
	assert_eq(pool.busy_count(FxSpecs.HIT), 1)
	var emitter: GPUParticles3D = pool.emitter_of(handle)
	assert_almost_eq(emitter.global_position, Vector3(10.0, 20.0, 30.0), Vector3.ONE * 1e-5)
	assert_almost_eq(emitter.global_basis.y, Vector3(0, 0, 1), Vector3.ONE * 1e-5, "the cone points along the direction")
	assert_false(emitter.visible, "the physics tick only asks; `_process` starts it")
	assert_true(pool.is_processing())
	pool._process(DT)
	assert_true(emitter.visible)
	assert_true(emitter.emitting)


func test_a_burst_inherits_its_sources_velocity_and_never_slows() -> void:
	var handle: int = pool.burst(FxSpecs.EXPLOSION_FRAGMENTS, Vector3.ZERO, Vector3.UP, Vector3(30.0, 0.0, -400.0))
	var emitter: GPUParticles3D = pool.emitter_of(handle)
	pool._process(DT)  # starts it
	for i: int in 120:
		pool._process(DT)
	assert_almost_eq(emitter.global_position, Vector3(30.0, 0.0, -400.0) * (120.0 * DT), Vector3.ONE * 1e-2,
			"it flew at the source's velocity for 2 s with nothing slowing it")
	assert_eq(pool.velocity_of(handle), Vector3(30.0, 0.0, -400.0))


func test_a_one_shot_frees_its_emitter_when_its_last_particle_dies() -> void:
	var handle: int = pool.burst(FxSpecs.HIT, Vector3.ZERO, Vector3.UP, Vector3.ZERO)
	var emitter: GPUParticles3D = pool.emitter_of(handle)
	var life: float = float(FxSpecs.spec(FxSpecs.HIT)["lifetime_s"])
	for i: int in ceili(life / DT) - 2:
		pool._process(DT)
	assert_eq(pool.busy_count(FxSpecs.HIT), 1, "still in flight")
	for i: int in 6:
		pool._process(DT)
	assert_eq(pool.busy_count(FxSpecs.HIT), 0, "free again")
	assert_false(emitter.visible)
	assert_false(pool.is_processing(), "and the pool stops processing when nothing is busy")
	assert_false(pool.is_live(handle), "a finished burst's handle is stale")


func test_a_burst_live_across_a_rebase_is_shifted_with_the_world() -> void:
	var live: int = pool.burst(FxSpecs.RAM, Vector3(100.0, 0.0, 0.0), Vector3.UP, Vector3(0, 0, -10.0))
	pool._process(DT)
	var asked: int = pool.burst(FxSpecs.HIT, Vector3(120.0, 5.0, 0.0), Vector3.UP, Vector3.ZERO)  # asked, not yet started
	var live_before: Vector3 = pool.emitter_of(live).global_position
	var asked_before: Vector3 = pool.emitter_of(asked).global_position
	world.rebase(Vector3(5000.0, 0.0, 0.0))
	assert_almost_eq(pool.emitter_of(live).global_position, live_before - Vector3(5000.0, 0.0, 0.0), Vector3.ONE * 1e-3,
			"a live burst moves with the rebase offset")
	assert_almost_eq(pool.emitter_of(asked).global_position, asked_before - Vector3(5000.0, 0.0, 0.0), Vector3.ONE * 1e-3,
			"and so does one that was asked for in the same tick")
	pool._process(DT)
	assert_almost_eq(pool.emitter_of(live).global_position, live_before - Vector3(5000.0, 0.0, 0.0) + Vector3(0, 0, -10.0 * DT),
			Vector3.ONE * 1e-3, "it flies on from the shifted place")


func test_the_pool_never_grows_when_all_emitters_are_busy_it_reuses_the_oldest() -> void:
	var count: int = int(FxSpecs.spec(FxSpecs.HIT)["emitters"])
	var handles: Array[int] = []
	for i: int in count:
		handles.append(pool.burst(FxSpecs.HIT, Vector3(float(i), 0, 0), Vector3.UP, Vector3.ZERO))
		pool._process(DT)
	assert_eq(pool.busy_count(FxSpecs.HIT), count)
	assert_eq(pool.reused, 0)
	var extra: int = pool.burst(FxSpecs.HIT, Vector3(99.0, 0, 0), Vector3.UP, Vector3.ZERO)
	assert_eq(pool.reused, 1, "one burst had to take a busy emitter")
	assert_eq(pool.busy_count(FxSpecs.HIT), count, "the busy count did not grow")
	assert_eq(pool.emitter_count(), _expected_emitters(), "neither did the pool")
	assert_eq(_particle_nodes(pool), _expected_emitters())
	assert_false(pool.is_live(handles[0]), "the oldest burst lost its emitter")
	assert_true(pool.is_live(handles[1]))
	assert_true(pool.is_live(extra))
	assert_almost_eq(pool.emitter_of(extra).global_position, Vector3(99.0, 0, 0), Vector3.ONE * 1e-5)


func test_a_thousand_bursts_never_change_the_node_count() -> void:
	for i: int in 1000:
		pool.burst(i % FxSpecs.COUNT, Vector3(float(i), 0, 0), Vector3.UP, Vector3(0, 0, -5.0))
		if i % 7 == 0:
			pool._process(DT)
	assert_eq(_particle_nodes(pool), _expected_emitters())
	assert_eq(pool.get_child_count(), _expected_emitters())


# --- density --------------------------------------------------------------------------------------------------------


func test_density_zero_emits_nothing_and_costs_nothing_per_frame() -> void:
	Settings.set_value(&"particle_density", 0.0)
	assert_eq(pool.density, 0.0, "the pool follows the setting")
	for effect: int in FxSpecs.COUNT:
		assert_eq(pool.burst(effect, Vector3.ZERO, Vector3.UP, Vector3.ZERO), 0)
	assert_eq(pool.busy_count(), 0)
	assert_false(pool.is_processing(), "nothing to do, so `_process` stays off")
	assert_eq(pool.bursts, 0)


func test_density_scales_the_amount_of_a_burst() -> void:
	Settings.set_value(&"particle_density", 0.5)
	var handle: int = pool.burst(FxSpecs.EXPLOSION_SPARKS, Vector3.ZERO, Vector3.UP, Vector3.ZERO)
	var emitter: GPUParticles3D = pool.emitter_of(handle)
	var full: int = int(FxSpecs.spec(FxSpecs.EXPLOSION_SPARKS)["amount"])
	assert_almost_eq(float(emitter.amount) * emitter.amount_ratio, float(full) * 0.5, 1.0, "half the particles")
	Settings.set_value(&"particle_density", 1.0)
	handle = pool.burst(FxSpecs.EXPLOSION_SPARKS, Vector3.ZERO, Vector3.UP, Vector3.ZERO)
	assert_eq(pool.emitter_of(handle).amount_ratio, 1.0)


func test_the_schema_has_particle_density_as_a_unit_range() -> void:
	var entry: Dictionary = SettingsSchema.ENTRIES[&"particle_density"]
	assert_eq(entry["type"], TYPE_FLOAT)
	assert_eq(entry["default"], 1.0)
	assert_eq(entry["min"], 0.0)
	assert_eq(entry["max"], 1.0)


# --- vents ----------------------------------------------------------------------------------------------------------


func test_a_vent_emits_for_its_duration_then_its_particles_die_out() -> void:
	var handle: int = pool.burst(FxSpecs.DEBRIS, Vector3.ZERO, Vector3.UP, Vector3.ZERO, 2.0)
	var emitter: GPUParticles3D = pool.emitter_of(handle)
	pool._process(DT)
	assert_true(emitter.emitting)
	assert_false(emitter.one_shot, "a vent keeps emitting until told to stop")
	for i: int in 110:
		pool._process(DT)
	assert_true(emitter.emitting, "still venting at 1.8 s")
	for i: int in 20:
		pool._process(DT)
	assert_false(emitter.emitting, "stopped after 2 s")
	assert_eq(pool.busy_count(FxSpecs.DEBRIS), 1, "its last particles are still flying")
	for i: int in 60:
		pool._process(DT)
	assert_eq(pool.busy_count(FxSpecs.DEBRIS), 0, "and then it is free")


func test_stopping_a_vent_ends_the_emission_at_once_and_a_stale_handle_does_nothing() -> void:
	var handle: int = pool.burst(FxSpecs.DEBRIS, Vector3.ZERO, Vector3.UP, Vector3.ZERO, 4.0)
	var emitter: GPUParticles3D = pool.emitter_of(handle)
	pool._process(DT)
	pool.stop(handle)
	assert_false(emitter.emitting)
	for i: int in 60:
		pool._process(DT)
	assert_eq(pool.busy_count(FxSpecs.DEBRIS), 0, "free within the particle lifetime")
	var again: int = pool.burst(FxSpecs.DEBRIS, Vector3.ZERO, Vector3.UP, Vector3.ZERO, 4.0)
	pool._process(DT)
	pool.stop(handle)  # the old handle must not stop the new burst on the same emitter
	assert_true(pool.is_live(again))
	assert_true(pool.emitter_of(again).emitting, "an old handle cannot stop a newer burst")
	pool.stop(0)
	pool.stop(-5)
	pool.stop(0x7FFF_FFFF)


func test_stopping_a_burst_that_was_only_asked_for_frees_it() -> void:
	var handle: int = pool.burst(FxSpecs.DEBRIS, Vector3.ZERO, Vector3.UP, Vector3.ZERO, 3.0)
	pool.stop(handle)
	assert_eq(pool.busy_count(), 0)


# --- the console ----------------------------------------------------------------------------------------------------


func test_the_pool_registers_its_console_entries() -> void:
	assert_true(DebugConsole.registry.has_provider(&"fx"))
	assert_true(DebugConsole.registry.has_command(&"fxburst"))


# --- wiring: hits ---------------------------------------------------------------------------------------------------


func test_a_bolt_hit_throws_sparks_off_the_hull_at_the_hulls_velocity() -> void:
	var projectiles := Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	var resolver := HitResolver.new()
	add_child_autofree(resolver)
	resolver.set_physics_process(false)
	resolver.fx = pool
	var drone := (load(DRONE_SCENE) as PackedScene).instantiate() as TargetDrone
	drone.faction = Factions.RAIDERS
	drone.set_physics_process(false)
	world.spawn(drone, world.to_universe(Vector3(0.0, 0.0, -100.0)))
	drone.linear_velocity = Vector3(0.0, 3.0, 0.0)
	var bolt := (load(Projectile.SCENE_PATH) as PackedScene).instantiate() as Projectile
	projectiles.add_child(bolt)
	var weapon := WeaponSpec.new()
	weapon.damage = 10.0
	bolt.configure(weapon)
	bolt.faction = Factions.EARTH_ALLIANCE
	bolt.launch(Vector3(0.0, 0.0, -50.0), Vector3(0.0, 0.0, -400.0), SimClock.now())
	bolt.set_physics_process(false)
	bolt._physics_process(DT)
	var hits: Array[HitInfo] = []
	resolver.hit_resolved.connect(func(info: HitInfo) -> void: hits.append(info))
	for i: int in 30:
		bolt._physics_process(DT) if not bolt.is_spent() else null
		resolver.resolve(DT)
		if not hits.is_empty():
			break
	assert_eq(hits.size(), 1, "the bolt hit the drone")
	assert_eq(pool.busy_count(FxSpecs.HIT), 1, "and threw one burst of hit sparks")
	var busy: GPUParticles3D = pool.busy_emitters(FxSpecs.HIT)[0]
	assert_almost_eq(busy.global_position, hits[0].point, Vector3.ONE * 1e-3, "at the hit")
	# The bolt came down -Z onto the +Z face, so the sparks leave toward +Z.
	assert_gt(busy.global_basis.y.dot(Vector3(0, 0, 1)), 0.5, "back off the hull, toward the shooter")


func test_hits_without_a_pool_still_resolve() -> void:
	var resolver := HitResolver.new()
	add_child_autofree(resolver)
	assert_null(resolver.fx)
	resolver.set_physics_process(false)
	resolver.resolve(DT)
	assert_eq(resolver.hits_total, 0)


# --- wiring: debris -------------------------------------------------------------------------------------------------


func _debris_pool() -> DebrisPool:
	var debris := DebrisPool.new()
	debris.name = "Debris"
	world.add_child(debris)
	debris.fx = pool
	return debris


func _raider_chunks() -> Array[Dictionary]:
	var spec := load(RAIDER_SPEC_PATH) as ShipSpec
	var hardpoints: Hardpoints = Hardpoints.load_file(spec.hardpoints_path())
	assert_true(hardpoints.valid, "run scripts/gen_assets.sh, then scripts/run_tests.sh (it imports first)")
	return hardpoints.chunks


func test_every_launched_chunk_vents_with_its_velocity_for_two_to_four_seconds() -> void:
	var debris: DebrisPool = _debris_pool()
	var chunks: Array[Dictionary] = _raider_chunks()
	assert_eq(debris.prepare(RAIDER_ASSET), DebrisPool.SETS_PER_TYPE)
	var launched: Array[DebrisChunk] = debris.burst(RAIDER_ASSET, chunks, Transform3D(Basis.IDENTITY, Vector3(0, 0, -200.0)),
			Vector3(0.0, 0.0, -30.0), Vector3.ZERO, 7)
	assert_eq(pool.busy_count(FxSpecs.DEBRIS), launched.size(), "one vent per chunk")
	assert_eq(pool.busy_emitters(FxSpecs.DEBRIS).size(), launched.size())
	for chunk: DebrisChunk in launched:
		assert_true(chunk.has_vent(), "%s vents" % chunk.name)
		assert_between(pool.vent_s(chunk.vent_handle()), FxSpecs.DEBRIS_MIN_S, FxSpecs.DEBRIS_MAX_S, "vents 2-4 s")
		assert_lt(pool.taken_s(chunk.vent_handle()), DebrisChunk.LIFETIME_S, "and ends before the chunk does")
		assert_eq(pool.velocity_of(chunk.vent_handle()), chunk.velocity, "at the chunk's velocity")
		assert_almost_eq(pool.emitter_of(chunk.vent_handle()).global_position, chunk.global_position, Vector3.ONE * 1e-4)


func test_a_chunk_that_parks_mid_burst_leaves_no_emitter_behind() -> void:
	var debris: DebrisPool = _debris_pool()
	var chunks: Array[Dictionary] = _raider_chunks()
	debris.prepare(RAIDER_ASSET)
	var launched: Array[DebrisChunk] = debris.burst(RAIDER_ASSET, chunks, Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO, 3)
	pool._process(DT)
	var vents: int = pool.busy_count(FxSpecs.DEBRIS)
	assert_eq(vents, launched.size())
	launched[0].park()
	for i: int in 60:
		pool._process(DT)
	assert_eq(pool.busy_count(FxSpecs.DEBRIS), vents - 1, "the released chunk's vent ended within the particle lifetime")
	for chunk: DebrisChunk in launched:
		chunk.park()
	for i: int in 60:
		pool._process(DT)
	assert_eq(pool.busy_count(FxSpecs.DEBRIS), 0, "no vent outlives its chunk")


func test_a_chunk_that_runs_out_of_life_stops_its_vent() -> void:
	var debris: DebrisPool = _debris_pool()
	debris.burst(&"nav_buoy", [] as Array[Dictionary], Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO, 5)  # generic shards
	assert_gt(pool.busy_count(FxSpecs.DEBRIS), 0, "shards vent too")
	for chunk: Node in debris.get_children():
		(chunk as DebrisChunk).advance(DebrisChunk.LIFETIME_S + DebrisChunk.SHRINK_S + 0.1)
	for i: int in 90:
		pool._process(DT)
	assert_eq(pool.busy_count(FxSpecs.DEBRIS), 0)


func test_a_break_up_is_the_same_with_and_without_a_pool() -> void:
	var debris: DebrisPool = _debris_pool()
	var chunks: Array[Dictionary] = _raider_chunks()
	debris.prepare(RAIDER_ASSET)
	var with_pool: Array[DebrisChunk] = debris.burst(RAIDER_ASSET, chunks, Transform3D.IDENTITY, Vector3(0, 0, -10.0), Vector3.ZERO, 11)
	var velocities: Array[Vector3] = []
	for chunk: DebrisChunk in with_pool:
		velocities.append(chunk.velocity)
		chunk.park()
	debris.fx = null
	var without_pool: Array[DebrisChunk] = debris.burst(RAIDER_ASSET, chunks, Transform3D.IDENTITY, Vector3(0, 0, -10.0), Vector3.ZERO, 11)
	for i: int in without_pool.size():
		assert_almost_eq(without_pool[i].velocity, velocities[i], Vector3.ONE * 1e-5, "chunk %d flies the same" % i)


# --- wiring: rams ---------------------------------------------------------------------------------------------------


func test_a_ram_throws_sparks_from_each_hull_reached() -> void:
	DebugConsole.flags.invulnerable = false
	var ram_backup: bool = bool(Settings.get_value(&"ram_damage"))
	Settings.set_value(&"ram_damage", true)
	var projectiles := Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	var rams := RamResolver.new()
	rams.world = world
	rams.fx = pool
	add_child_autofree(rams)
	var spec := load(SPEC_PATH) as ShipSpec
	var ships: Array[Combatant] = []
	for i: int in 2:
		ships.append(ShipAssembly.build(spec, world, projectiles, {
			ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE,
			ShipAssembly.OPT_DISPLAY_NAME: "S%d" % i,
			ShipAssembly.OPT_IS_PLAYER: i == 0,
		}))
		world.spawn(ships[i].ship, world.to_universe(Vector3(0.0, 0.0, -500.0 * i)), Basis.IDENTITY if i == 0 else Basis(Vector3.UP, PI))
	await get_tree().physics_frame
	await get_tree().physics_frame
	ships[0].ship.reset_to(Transform3D(Basis.IDENTITY, Vector3.ZERO))
	ships[0].ship.linear_velocity = Vector3(0, 0, -300.0)
	ships[1].ship.reset_to(Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -45.0)))
	ships[1].ship.linear_velocity = Vector3(0, 0, 300.0)
	for i: int in 30:
		await get_tree().physics_frame
	Settings.set_value(&"ram_damage", ram_backup)
	assert_gt(rams.events, 0, "the ships rammed")
	assert_gte(pool.bursts, 2, "sparks from both hulls")
	assert_eq(pool.bursts, rams.events, "one burst for every hull a ram reached")


# --- the whole game -------------------------------------------------------------------------------------------------


class TestSandbox extends GutTest:
	## AC32 in the real main scene: a 120 s sandbox fight (waves, wingmen, hits, rams, explosions, debris) throws bursts from the
	## pools and the particle node count never changes.
	const SPEED_UP: float = 8.0
	const FIGHT_S: float = 120.0

	var main: Main
	var _scale_backup: float = 1.0

	func before_each() -> void:
		_scale_backup = Engine.time_scale
		get_tree().paused = false
		DebugConsole.flags.invulnerable = true
		ContactScan.invalidate()
		main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
		main.input_source = FakeInputSource.new()
		main.waves_auto_start = false
		add_child_autofree(main)
		await get_tree().physics_frame

	func after_each() -> void:
		Engine.time_scale = _scale_backup
		DebugConsole.flags.invulnerable = false
		ContactScan.invalidate()

	func _count(node: Node) -> int:
		var n: int = 1 if node is GPUParticles3D else 0
		for child: Node in node.get_children():
			n += _count(child)
		return n

	func test_the_main_scene_wires_the_pool_everywhere() -> void:
		assert_not_null(main.fx)
		assert_eq(main.fx.get_parent(), main.world, "the pool lives under World")
		assert_eq(main.rams.fx, main.fx)
		assert_eq(main.director.fx, main.fx)
		assert_eq(main.debris.fx, main.fx)
		assert_eq((main.get_node("Combat/HitResolver") as HitResolver).fx, main.fx)

	func test_the_particle_node_count_never_changes_across_a_120_s_fight() -> void:
		var start: int = _count(main)
		assert_eq(start, main.fx.emitter_count(), "the pool's emitters are the only particle nodes")
		assert_true(DebugConsole.registry.execute("wave start 1")[0].ok)
		Engine.time_scale = SPEED_UP
		var t0: float = SimClock.now()
		var changed: bool = false
		while SimClock.now() - t0 < FIGHT_S:
			await get_tree().physics_frame
			if _count(main) != start:
				changed = true
				break
		Engine.time_scale = 1.0
		gut.p("fight: %.0f s, bursts %d, reused %d, kills %d" % [SimClock.now() - t0, main.fx.bursts, main.fx.reused, main.waves.kills])
		assert_false(changed, "the particle node count changed during the fight")
		assert_eq(_count(main), start)
		assert_gt(main.fx.bursts, 0, "the fight threw sparks")
