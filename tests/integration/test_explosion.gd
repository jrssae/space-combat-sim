extends GutTest
## Explosion (M2-T06, architecture §15.7): the code-made effect of a destroyed ship. It has the light, the billboard flash,
## the fireball, sparks and embers; each one follows its timeline; it drifts with the velocity it was given, moves with a
## rebase, and frees itself after 3 s.

const RADIUS: float = 6.0

var explosion: Explosion


func before_each() -> void:
	explosion = Explosion.create(RADIUS, Vector3(10.0, 0.0, -20.0))
	add_child_autofree(explosion)


func test_it_has_every_component() -> void:
	assert_not_null(explosion.light)
	assert_not_null(explosion.flash)
	assert_not_null(explosion.fireball)
	assert_eq(explosion.sparks.amount, Explosion.SPARK_COUNT)
	assert_eq(explosion.embers.amount, Explosion.EMBER_COUNT)
	for particles: GPUParticles3D in [explosion.sparks, explosion.embers]:
		assert_true(particles.one_shot, "one shot")
		assert_false(particles.local_coords, "world space: the sparks leave the drifting ball behind")
		assert_eq(particles.explosiveness, 1.0)
	assert_almost_eq(explosion.sparks.lifetime, 1.2, 1e-6)
	assert_eq(explosion.embers.lifetime, 3.0)
	assert_almost_eq(explosion.light.omni_range, 4.0 * RADIUS, 1e-6)
	assert_false(explosion.light.shadow_enabled)
	assert_eq(explosion.radius_m, RADIUS)


func test_sparks_and_embers_fly_at_their_speeds() -> void:
	var sparks := explosion.sparks.process_material as ParticleProcessMaterial
	assert_eq(sparks.initial_velocity_min, 40.0)
	assert_eq(sparks.initial_velocity_max, 150.0)
	var embers := explosion.embers.process_material as ParticleProcessMaterial
	assert_eq(embers.initial_velocity_min, 5.0)
	assert_eq(embers.initial_velocity_max, 20.0)
	assert_eq(sparks.gravity, Vector3.ZERO)


func test_the_light_peaks_at_8_and_is_out_by_a_quarter_second() -> void:
	explosion.advance(0.0)
	assert_eq(explosion.light.light_energy, 0.0, "starts dark")
	explosion.advance(Explosion.LIGHT_S / 3.0)
	assert_almost_eq(explosion.light.light_energy, 8.0, 1e-4, "the peak")
	explosion.advance(Explosion.LIGHT_S * 2.0 / 3.0)
	assert_almost_eq(explosion.light.light_energy, 0.0, 1e-4, "out after 0.25 s")
	assert_false(explosion.light.visible)


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


func test_the_scene_builds_itself_when_instanced() -> void:
	var instanced := (load("res://src/combat/explosion.tscn") as PackedScene).instantiate() as Explosion
	add_child_autofree(instanced)
	assert_not_null(instanced.fireball)
	assert_not_null(instanced.sparks.get_parent())
	assert_eq(instanced.get_child_count(), 5)


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
