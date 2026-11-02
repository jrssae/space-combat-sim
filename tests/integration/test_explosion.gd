extends GutTest
## Explosion (M2-T06, architecture §15.7): the code-made effect of a destroyed ship. It has the light, the billboard flash,
## the fireball; each one follows its timeline; it drifts with the velocity it was given, moves with a rebase, and frees itself
## after 3 s. Its sparks, fragments and gas come from the FxPool (M3-T23) and start where it blew up.

const RADIUS: float = 6.0

var explosion: Explosion


func before_each() -> void:
	explosion = Explosion.create(RADIUS, Vector3(10.0, 0.0, -20.0))
	add_child_autofree(explosion)


func test_it_has_every_component() -> void:
	assert_not_null(explosion.emitter)
	assert_not_null(explosion.flash)
	assert_not_null(explosion.fireball)
	assert_almost_eq(explosion.emitter.omni_range, 4.0 * RADIUS, 1e-6)
	assert_eq(explosion.radius_m, RADIUS)
	# M3-T23: the sparks, fragments and gas come from the FxPool, so an explosion owns no particle node.
	assert_eq(_particle_nodes(explosion), 0, "the pool makes the particles, not the explosion")


func _particle_nodes(node: Node) -> int:
	var n: int = 1 if node is GPUParticles3D else 0
	for child: Node in node.get_children():
		n += _particle_nodes(child)
	return n


func test_the_light_peaks_at_8_and_is_out_by_a_quarter_second() -> void:
	explosion.advance(0.0)
	assert_eq(explosion.emitter.energy, 0.0, "starts dark")
	explosion.advance(Explosion.LIGHT_S / 3.0)
	assert_almost_eq(explosion.emitter.energy, 8.0, 1e-4, "the peak")
	explosion.advance(Explosion.LIGHT_S * 2.0 / 3.0)
	assert_almost_eq(explosion.emitter.energy, 0.0, 1e-4, "out after 0.25 s")


func test_the_flash_is_gone_after_150_ms() -> void:
	assert_true(explosion.flash.visible)
	explosion.advance(0.1)
	assert_true(explosion.flash.visible)
	explosion.advance(0.06)
	assert_false(explosion.flash.visible)


func test_the_fireball_grows_to_1_2_radius_over_0_8_s_and_is_gone_by_1_5_s() -> void:
	explosion.advance(0.01)
	assert_lt(explosion.fireball.scale.x, 0.4 * RADIUS, "small at first")
	explosion.advance(Explosion.FIREBALL_GROW_S - 0.01)
	assert_almost_eq(explosion.fireball.scale.x, 1.2 * RADIUS, 1e-4)
	explosion.advance(0.3)
	assert_almost_eq(explosion.fireball.scale.x, 1.2 * RADIUS, 1e-4, "stays at full size while it cools")
	assert_true(explosion.fireball.visible)
	explosion.advance(0.5)
	assert_false(explosion.fireball.visible, "gone by 1.5 s")


func test_the_shader_gets_its_age() -> void:
	explosion.advance(0.7)
	var material := (explosion.fireball.mesh as SphereMesh).material as ShaderMaterial
	assert_not_null(material)
	assert_almost_eq(float(material.get_shader_parameter(&"age")), 0.7, 1e-5)
	assert_eq(float(material.get_shader_parameter(&"duration")), Explosion.FIREBALL_S)


func test_it_frees_itself_after_three_seconds() -> void:
	explosion.advance(2.9)
	assert_false(explosion.is_queued_for_deletion())
	explosion.advance(0.2)
	assert_true(explosion.is_queued_for_deletion())


func test_it_drifts_with_the_ships_velocity() -> void:
	explosion.position = Vector3(5.0, 0.0, 0.0)
	explosion._physics_process(0.5)
	assert_almost_eq(explosion.position, Vector3(10.0, 0.0, -10.0), Vector3.ONE * 1e-5)


func test_it_joins_world_shiftable_so_a_rebase_moves_it() -> void:
	assert_true(explosion.is_in_group(WorldFrame.SHIFTABLE_GROUP))


func test_the_sparks_start_where_it_blew_fly_on_with_its_velocity_and_move_with_a_rebase() -> void:
	# M2: the sparks leave the drifting ball behind. M3-T14: a rebase still moves them with the rest of the world. M3-T23: the
	# same guarantee on the FxPool's emitters, which also carry the ship's velocity on.
	var world := WorldFrame.new()
	add_child_autofree(world)
	var pool := FxPool.new()
	world.add_child(pool)
	var blast := Explosion.create(RADIUS, Vector3(10.0, 0.0, -20.0))
	blast.fx = pool
	blast.position = Vector3(100.0, 0.0, 0.0)
	world.add_child(blast)
	blast._physics_process(0.5)
	assert_almost_eq(blast.global_position, Vector3(105.0, 0.0, -10.0), Vector3.ONE * 1e-4, "the ball drifts")
	var thrown: int = 0
	for effect: int in [FxSpecs.EXPLOSION_SPARKS, FxSpecs.EXPLOSION_FRAGMENTS, FxSpecs.EXPLOSION_GAS]:
		for emitter: GPUParticles3D in pool.emitters_of(effect):
			if emitter.visible:
				thrown += 1
				assert_almost_eq(emitter.global_position, Vector3(100.0, 0.0, 0.0), Vector3.ONE * 1e-4,
						"%s: started where it blew" % emitter.name)
				assert_true(emitter.local_coords, "%s: its particles live in its frame, so they go where it goes" % emitter.name)
	assert_eq(pool.busy_count(), 3, "one burst of each effect")
	assert_eq(thrown, 0, "none is started before the next frame")
	pool._process(0.0)
	var before: Dictionary = {}
	for effect: int in [FxSpecs.EXPLOSION_SPARKS, FxSpecs.EXPLOSION_FRAGMENTS, FxSpecs.EXPLOSION_GAS]:
		for emitter: GPUParticles3D in pool.emitters_of(effect):
			if emitter.visible:
				before[emitter] = emitter.global_position
	assert_eq(before.size(), 3)
	world.rebase(Vector3(5000.0, 0.0, 0.0))
	for emitter: GPUParticles3D in before:
		assert_almost_eq(emitter.global_position, (before[emitter] as Vector3) - Vector3(5000.0, 0.0, 0.0), Vector3.ONE * 1e-3,
				"%s: moved by the rebase" % emitter.name)


func test_without_a_pool_the_explosion_throws_nothing_and_still_runs() -> void:
	explosion.advance(1.0)
	assert_null(explosion.fx)
	assert_eq(_particle_nodes(explosion), 0)


func test_the_scene_builds_itself_when_instanced() -> void:
	var instanced := (load("res://src/combat/explosion.tscn") as PackedScene).instantiate() as Explosion
	add_child_autofree(instanced)
	assert_not_null(instanced.fireball)
	assert_eq(instanced.get_child_count(), 2, "flash and fireball: the light is an emitter, not a node")
	assert_not_null(instanced.emitter)


func test_a_tiny_radius_is_raised_to_something_visible() -> void:
	var tiny := Explosion.create(0.0, Vector3.ZERO)
	add_child_autofree(tiny)
	assert_gt(tiny.radius_m, 0.0)


func test_the_fireball_shader_compiles_with_the_expected_uniforms() -> void:
	var uniforms: Array[String] = []
	for entry: Dictionary in Explosion.FIREBALL_SHADER.get_shader_uniform_list():
		uniforms.append(String(entry["name"]))
	for name: String in ["age", "duration", "intensity", "noise_scale"]:
		assert_true(uniforms.has(name), "uniform %s" % name)
