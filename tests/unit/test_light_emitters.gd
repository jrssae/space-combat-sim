extends GutTest
## AC31: the pure parts of the ship lights (M3-T22): the nozzle, muzzle-flash and explosion curves, the plume's light colour, and
## `LightEmitter.follow` on an anchor that has left the tree.


func test_a_nozzle_is_dark_at_idle_and_full_at_full_thrust() -> void:
	assert_eq(EmitterCurves.nozzle_energy(0.0), 0.0)
	assert_eq(EmitterCurves.nozzle_energy(0.005), 0.0, "a plume too faint to draw gives no light")
	assert_almost_eq(EmitterCurves.nozzle_energy(1.0), EmitterCurves.NOZZLE_PEAK_ENERGY, 1e-6)
	assert_almost_eq(EmitterCurves.nozzle_energy(0.5), 0.5 * EmitterCurves.NOZZLE_PEAK_ENERGY, 1e-6, "follows the level")
	assert_almost_eq(EmitterCurves.nozzle_energy(2.0), EmitterCurves.NOZZLE_PEAK_ENERGY, 1e-6, "clamped")


func test_the_light_takes_the_plumes_colour_at_display_brightness() -> void:
	var glow := Color(0.7, 0.9, 1.8, 1.0)  # the shared plume material's HDR colour
	var light: Color = EmitterCurves.light_color(glow)
	assert_almost_eq(maxf(light.r, maxf(light.g, light.b)), 1.0, 1e-6, "the brightest channel is full")
	assert_almost_eq(light.r / light.b, glow.r / glow.b, 1e-5, "same hue")
	assert_almost_eq(light.g / light.b, glow.g / glow.b, 1e-5)
	assert_eq(EmitterCurves.light_color(Color(0, 0, 0)), Color.WHITE, "a black glow does not make a black light")


func test_a_nozzle_light_sits_out_along_the_exhaust() -> void:
	assert_almost_eq(EmitterCurves.NOZZLE_OFFSET_M, 1.5, 1e-6)
	assert_almost_eq(EmitterCurves.NOZZLE_RANGE_M, 15.0, 1e-6)


func test_a_muzzle_flash_lasts_sixty_milliseconds() -> void:
	assert_almost_eq(EmitterCurves.FLASH_S, 0.06, 1e-6)
	assert_almost_eq(EmitterCurves.flash_energy(0.0), EmitterCurves.FLASH_PEAK_ENERGY, 1e-6)
	assert_gt(EmitterCurves.flash_energy(0.03), 0.0)
	assert_lt(EmitterCurves.flash_energy(0.03), EmitterCurves.FLASH_PEAK_ENERGY)
	assert_eq(EmitterCurves.flash_energy(0.06), 0.0, "out at 60 ms")
	assert_eq(EmitterCurves.flash_energy(1.0), 0.0)
	assert_eq(EmitterCurves.flash_energy(INF), 0.0, "an idle flash is dark")


func test_the_explosion_light_is_a_triangle_up_to_8_and_out_by_a_quarter_second() -> void:
	assert_eq(Explosion.light_energy(0.0), 0.0)
	assert_almost_eq(Explosion.light_energy(Explosion.LIGHT_S / 3.0), 8.0, 1e-5, "the peak at a third")
	assert_almost_eq(Explosion.light_energy(Explosion.LIGHT_S * 0.5), 6.0, 1e-5, "falling")
	assert_almost_eq(Explosion.light_energy(Explosion.LIGHT_S), 0.0, 1e-5)
	assert_eq(Explosion.light_energy(2.0), 0.0)


func test_an_anchor_that_left_the_tree_is_given_up_without_an_error() -> void:
	var anchor := Node3D.new()  # valid, but never in a tree: asking for its interpolated pose is an engine error
	var emitter := LightEmitter.new("x", LightEmitter.PRIORITY_NOZZLE, Color.WHITE, 2.0)
	emitter.anchor = anchor
	emitter.offset = Vector3(0.0, 5.0, 0.0)
	assert_false(emitter.follow(), "dropped, not placed at the origin")
	assert_eq(emitter.position, Vector3.ZERO)
	anchor.free()


func test_an_anchor_in_the_tree_is_followed_and_a_dark_emitter_is_not_placed() -> void:
	var anchor := Node3D.new()
	anchor.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child_autofree(anchor)
	anchor.global_position = Vector3(10.0, 0.0, 0.0)
	var emitter := LightEmitter.new("x", LightEmitter.PRIORITY_NOZZLE, Color.WHITE, 2.0)
	emitter.anchor = anchor
	emitter.offset = Vector3(0.0, 1.0, 0.0)
	assert_true(emitter.follow())
	assert_eq(emitter.position, Vector3(10.0, 1.0, 0.0))
	emitter.energy = 0.0
	anchor.global_position = Vector3(50.0, 0.0, 0.0)
	assert_true(emitter.follow())
	assert_eq(emitter.position, Vector3(10.0, 1.0, 0.0), "a dark emitter is not worth the transform")
