extends GutTest
## The explosions (M2-T06, architecture §15.7; pooled since M10-T11, roadmap L10): `ExplosionPool` draws every explosion from a
## fixed set of slots through two multimeshes (fireballs, flashes) that share one mesh and one material each. Each explosion
## has its light, flash and fireball on their timelines; it drifts with the velocity it was given, moves with a rebase and frees
## its slot at 1.5 s; with every slot busy the oldest gives its slot up. Its sparks, fragments and gas come from the FxPool
## (M3-T23) and start where it blew up. The light's curve is `test_light_emitters`' (pure) and `test_ship_lights`' (M6-T18).

const RADIUS: float = 6.0

var pool: ExplosionPool
var slot: int = -1


func before_each() -> void:
	pool = ExplosionPool.new()
	add_child_autofree(pool)
	slot = pool.spawn(RADIUS, Vector3(10.0, 0.0, -20.0), Vector3.ZERO)


func test_an_explosion_takes_a_slot_with_its_light() -> void:
	assert_true(pool.is_alive(slot))
	assert_eq(pool.live_count(), 1)
	assert_almost_eq(pool.emitter_of(slot).omni_range, 4.0 * RADIUS, 1e-6)
	assert_eq(pool.radius_of(slot), RADIUS)
	assert_eq(_particle_nodes(pool), 0, "the FxPool makes the particles, not the explosions")


func _particle_nodes(node: Node) -> int:
	var n: int = 1 if node is GPUParticles3D else 0
	for child: Node in node.get_children():
		n += _particle_nodes(child)
	return n


func test_the_flash_is_gone_after_150_ms() -> void:
	pool.advance(0.0)
	assert_eq(pool.drawn(), Vector2i(1, 1), "a fireball and a flash")
	pool.advance(0.1)
	assert_eq(pool.drawn().y, 1)
	pool.advance(0.06)
	assert_eq(pool.drawn(), Vector2i(1, 0), "the flash is over, the fireball burns on")


func test_the_fireball_grows_to_1_2_radius_over_0_8_s_and_the_slot_is_free_by_1_5_s() -> void:
	pool.advance(0.01)
	assert_lt(_drawn_scale(pool.fireballs), 0.4 * RADIUS, "small at first")
	pool.advance(ExplosionPool.FIREBALL_GROW_S - 0.01)
	assert_almost_eq(_drawn_scale(pool.fireballs), 1.2 * RADIUS, 1e-4)
	pool.advance(0.3)
	assert_almost_eq(_drawn_scale(pool.fireballs), 1.2 * RADIUS, 1e-4, "stays at full size while it cools")
	assert_true(pool.is_alive(slot))
	pool.advance(0.5)
	assert_false(pool.is_alive(slot), "gone by 1.5 s")
	assert_eq(pool.live_count(), 0)
	assert_eq(pool.drawn(), Vector2i.ZERO, "nothing drawn")


func test_the_shader_gets_its_age_per_instance() -> void:
	pool.advance(0.7)
	assert_almost_eq(float(pool.drawn_instance(true, 0)["a"]), 0.7, 1e-5)
	var material := pool.fireballs.material_override as ShaderMaterial
	assert_eq(float(material.get_shader_parameter(&"duration")), ExplosionPool.FIREBALL_S)


func test_it_drifts_with_the_ships_velocity() -> void:
	var moved: int = pool.spawn(RADIUS, Vector3(10.0, 0.0, -20.0), Vector3(5.0, 0.0, 0.0))
	pool.step(0.5)
	assert_almost_eq(pool.position_of(moved), Vector3(10.0, 0.0, -10.0), Vector3.ONE * 1e-5)


func test_explosions_share_one_mesh_and_material_and_build_no_node() -> void:
	var children: int = _count_nodes(pool)
	var material: Material = pool.fireballs.material_override
	var mesh: Mesh = pool.fireballs.multimesh.mesh
	for i: int in 40:
		pool.spawn(RADIUS, Vector3.ZERO, Vector3(float(i) * 30.0, 0.0, 0.0))
	pool.advance(0.0)
	assert_eq(_count_nodes(pool), children, "no node per explosion")
	assert_eq(pool.fireballs.material_override, material, "one material")
	assert_eq(pool.fireballs.multimesh.mesh, mesh, "one mesh")
	assert_eq(pool.drawn().x, 41, "all drawn in one multimesh")


func _count_nodes(node: Node) -> int:
	var n: int = 1
	for child: Node in node.get_children():
		n += _count_nodes(child)
	return n


func test_a_full_pool_gives_the_oldest_slot_to_the_newest_explosion() -> void:
	pool.advance(0.5)
	for i: int in ExplosionPool.CAPACITY - 1:
		pool.spawn(RADIUS, Vector3.ZERO, Vector3(0.0, float(i), 0.0))
	assert_eq(pool.live_count(), ExplosionPool.CAPACITY)
	assert_eq(pool.stolen, 0)
	var newest: int = pool.spawn(RADIUS, Vector3.ZERO, Vector3(0.0, 0.0, 999.0))
	assert_eq(newest, slot, "the oldest explosion's slot")
	assert_eq(pool.stolen, 1)
	assert_eq(pool.live_count(), ExplosionPool.CAPACITY, "the pool never grows")
	assert_almost_eq(pool.age_of(newest), 0.0, 1e-6)


func test_a_rebase_moves_the_explosions_and_a_boost_keeps_their_universe_velocity() -> void:
	var world := WorldFrame.new()
	add_child_autofree(world)
	var effects := Node3D.new()
	world.add_child(effects)
	var in_world: ExplosionPool = ExplosionPool.attach(effects)
	var s: int = in_world.spawn(RADIUS, Vector3(10.0, 0.0, 0.0), Vector3(100.0, 0.0, 0.0))
	world.rebase(Vector3(5000.0, 0.0, 0.0))
	assert_almost_eq(in_world.position_of(s), Vector3(-4900.0, 0.0, 0.0), Vector3.ONE * 1e-3, "moved by the rebase")
	world.boosted.emit(Vector3(4.0, 0.0, 0.0))
	assert_almost_eq(in_world.velocity_of(s), Vector3(6.0, 0.0, 0.0), Vector3.ONE * 1e-5)
	assert_eq(ExplosionPool.attach(effects), in_world, "one pool a world")


func test_the_sparks_start_where_it_blew_and_fly_on_with_its_velocity() -> void:
	var world := WorldFrame.new()
	add_child_autofree(world)
	var fx := FxPool.new()
	world.add_child(fx)
	var effects := Node3D.new()
	world.add_child(effects)
	var in_world: ExplosionPool = ExplosionPool.attach(effects)
	in_world.fx = fx
	in_world.spawn(RADIUS, Vector3(10.0, 0.0, -20.0), Vector3(100.0, 0.0, 0.0))
	assert_eq(fx.busy_count(), 3, "one burst of each effect")
	fx._process(0.0)
	var thrown: int = 0
	for effect: int in [FxSpecs.EXPLOSION_SPARKS, FxSpecs.EXPLOSION_FRAGMENTS, FxSpecs.EXPLOSION_GAS]:
		for emitter: GPUParticles3D in fx.emitters_of(effect):
			if emitter.visible:
				thrown += 1
				assert_almost_eq(emitter.global_position, Vector3(100.0, 0.0, 0.0), Vector3.ONE * 1e-3,
						"%s: started where it blew" % emitter.name)
	assert_eq(thrown, 3)


func test_the_reduced_effect_has_no_light_and_only_the_gas() -> void:
	var world := WorldFrame.new()
	add_child_autofree(world)
	var fx := FxPool.new()
	world.add_child(fx)
	var effects := Node3D.new()
	world.add_child(effects)
	var in_world: ExplosionPool = ExplosionPool.attach(effects)
	in_world.fx = fx
	var s: int = in_world.spawn(RADIUS, Vector3.ZERO, Vector3.ZERO, true)
	assert_true(in_world.is_reduced(s))
	assert_false(in_world.is_lit(s))
	assert_eq(fx.busy_count(), 1, "the gas shell only")


func test_a_tiny_radius_is_raised_to_something_visible() -> void:
	var tiny: int = pool.spawn(0.0, Vector3.ZERO, Vector3.ZERO)
	assert_gt(pool.radius_of(tiny), 0.0)


func test_the_shaders_compile_with_the_expected_uniforms() -> void:
	var uniforms: Array[String] = []
	for entry: Dictionary in ExplosionPool.FIREBALL_SHADER.get_shader_uniform_list():
		uniforms.append(String(entry["name"]))
	for name: String in ["duration", "intensity", "noise_scale"]:
		assert_true(uniforms.has(name), "uniform %s" % name)
	var flash: Array[String] = []
	for entry: Dictionary in ExplosionPool.FLASH_SHADER.get_shader_uniform_list():
		flash.append(String(entry["name"]))
	assert_true(flash.has("tint"))


# The first drawn fireball's scale.
func _drawn_scale(_node: MultiMeshInstance3D) -> float:
	return float(pool.drawn_instance(true, 0)["size"])
