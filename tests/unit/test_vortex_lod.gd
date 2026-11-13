extends GutTest
## A jump vortex's detail by its size on screen (M6-T20, AC13): the layers drop finest first as the mouth's projected radius
## falls, each fading over its own band so no step shows, down to the soft disc; the coarse mesh swaps with a margin; only the
## nearest few points carry a light.


func test_the_projected_radius_follows_size_distance_and_field() -> void:
	var px: float = VortexLod.px_per_unit(60.0, 1080.0)
	assert_almost_eq(px, 540.0 / tan(deg_to_rad(30.0)), 1e-3, "half the height over the tangent of half the field")
	assert_almost_eq(VortexLod.projected_radius_px(100.0, 10000.0, px), 100.0 * px / 10000.0, 1e-4)
	assert_almost_eq(VortexLod.projected_radius_px(200.0, 20000.0, px), VortexLod.projected_radius_px(100.0, 10000.0, px), 1e-4,
			"twice as big twice as far looks the same")
	assert_eq(VortexLod.projected_radius_px(100.0, 50.0, px), VortexLod.MAX_PX, "inside the mouth: as large as it gets")
	assert_lt(VortexLod.projected_radius_px(60.0, 50000.0, px), 1.5, "a fighter's point 50 km off is about a pixel")


func test_the_finest_hairs_go_first_and_the_coarse_cloud_last() -> void:
	for layer: int in range(1, VortexLod.LAYER_COUNT):
		var finer: Vector2 = VortexLod.BANDS_PX[layer - 1]
		var coarser: Vector2 = VortexLod.BANDS_PX[layer]
		assert_lt(coarser.y, finer.x, "%s is whole before %s starts to fade" % [VortexLod.LAYER_NAMES[layer],
				VortexLod.LAYER_NAMES[layer - 1]])
	assert_eq(VortexLod.LAYER_NAMES, [&"finest", &"fine", &"broad", &"patches", &"octave", &"cloud"] as Array[StringName])
	var full: PackedFloat32Array = VortexLod.weights(1000.0)
	for w: float in full:
		assert_eq(w, 1.0, "close up everything is drawn")
	var disc: PackedFloat32Array = VortexLod.weights(1.0)
	for w: float in disc:
		assert_eq(w, 0.0, "a pixel across: the soft disc alone")


func test_each_level_lies_between_two_bands_and_a_blend_inside_one() -> void:
	for level: int in VortexLod.LEVEL_COUNT:
		var r: float = VortexLod.radius_for_level(level)
		assert_eq(VortexLod.level(r), level, "%.1f px is level %d" % [r, level])
		assert_false(VortexLod.blending(r), "no layer half drawn at %.1f px" % r)
		var w: PackedFloat32Array = VortexLod.weights(r)
		assert_eq(w, VortexLod.level_weights(level), "the forced level %d draws what its size draws" % level)
	var mid: Vector2 = VortexLod.BANDS_PX[0]
	assert_true(VortexLod.blending((mid.x + mid.y) * 0.5), "inside the finest hairs' band")
	assert_almost_eq(VortexLod.weight(VortexLod.Layer.FINEST, (mid.x + mid.y) * 0.5), 0.5, 1e-4, "half faded mid band")


func test_no_layer_pops_between_levels() -> void:
	# Down from 1 000 px to half a pixel in 0.5 % steps: no weight moves more than a few hundredths a step, and none comes back.
	var last: PackedFloat32Array = VortexLod.weights(1000.0)
	var r: float = 1000.0
	var worst: float = 0.0
	while r > 0.5:
		r *= 0.995
		var w: PackedFloat32Array = VortexLod.weights(r)
		for layer: int in VortexLod.LAYER_COUNT:
			assert_true(w[layer] <= last[layer], "%s never comes back as the vortex shrinks" % VortexLod.LAYER_NAMES[layer])
			worst = maxf(worst, last[layer] - w[layer])
		last = w
	assert_lt(worst, 0.025, "the largest step of any layer's weight, 0.5 percent smaller on screen: %.4f" % worst)


func test_the_coarse_mesh_swaps_with_a_margin() -> void:
	assert_false(VortexLod.coarse_mesh(VortexLod.COARSE_MESH_PX + 1.0, false))
	assert_true(VortexLod.coarse_mesh(VortexLod.COARSE_MESH_PX - 0.1, false), "small enough: the coarse mesh")
	assert_true(VortexLod.coarse_mesh(VortexLod.COARSE_MESH_PX + 1.0, true), "inside the margin it stays coarse")
	assert_false(VortexLod.coarse_mesh(VortexLod.FULL_MESH_PX + 0.1, true), "past the margin the full mesh again")
	assert_lt(VortexLod.FULL_MESH_PX, VortexLod.BANDS_PX[VortexLod.Layer.PATCHES].x, "only once the patches are gone")


func test_only_the_nearest_few_points_carry_a_light() -> void:
	var distances := PackedFloat32Array([900.0, 100.0, 5000.0, 300.0, 50.0, 300.5])
	assert_eq(VortexLod.lit(distances), PackedInt32Array([4, 1, 3]), "the three nearest, nearest first")
	assert_eq(VortexLod.lit(distances, 1), PackedInt32Array([4]))
	assert_eq(VortexLod.lit(PackedFloat32Array([7.0])), PackedInt32Array([0]), "fewer points than lights: all lit")
	assert_eq(VortexLod.lit(PackedFloat32Array()), PackedInt32Array())
	assert_eq(VortexLod.LIT_POINTS, 3)
