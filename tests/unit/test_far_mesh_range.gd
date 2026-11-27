extends GutTest
## FarMeshRange (M10-T89): where a capital piece's far mesh takes over. The far mesh fades in over the margin either side of its
## swap distance while the full hull, its visibility dependent, still draws; past the band only the far mesh draws. The fade is
## a function of distance alone, so a ship sitting on the boundary never flaps.

const LOD: Dictionary = {"file": "x_far.glb", "triangles": 3000, "from_m": 13500.0, "margin_m": 1350.0}


func test_the_far_level_is_the_first_lods_entry_with_a_file_and_a_distance() -> void:
	assert_eq(FarMeshRange.lod_of({"lods": [LOD]}), LOD)
	assert_true(FarMeshRange.lod_of({"lods": []}).is_empty(), "a hull built before T89")
	assert_true(FarMeshRange.lod_of({}).is_empty())
	assert_true(FarMeshRange.lod_of({"lods": [{"file": "", "from_m": 10.0}]}).is_empty())
	assert_true(FarMeshRange.lod_of({"lods": [{"file": "a.glb", "from_m": 0.0}]}).is_empty())


func test_swap_distances_by_mode() -> void:
	var auto := FarMeshRange.Mode.AUTO
	assert_eq(FarMeshRange.shown(5000.0, LOD, auto), FarMeshRange.Shown.FULL)
	assert_eq(FarMeshRange.shown(12149.0, LOD, auto), FarMeshRange.Shown.FULL, "just before the band")
	assert_eq(FarMeshRange.shown(12151.0, LOD, auto), FarMeshRange.Shown.BOTH, "the band starts a margin before the swap")
	assert_eq(FarMeshRange.shown(14849.0, LOD, auto), FarMeshRange.Shown.BOTH)
	assert_eq(FarMeshRange.shown(14851.0, LOD, auto), FarMeshRange.Shown.FAR, "and ends a margin after it")
	assert_eq(FarMeshRange.shown(40000.0, LOD, FarMeshRange.Mode.FULL), FarMeshRange.Shown.FULL, "full: never the far mesh")
	assert_eq(FarMeshRange.shown(10.0, LOD, FarMeshRange.Mode.FAR), FarMeshRange.Shown.FAR, "far: always")
	assert_eq(FarMeshRange.shown(40000.0, {}, auto), FarMeshRange.Shown.FULL, "a piece without one")


func test_the_cross_fade_has_no_gap_and_cannot_flap() -> void:
	# Hysteresis by construction: the far mesh's opacity is a smooth function of distance, and the full hull draws whenever it is
	# not opaque, so moving back and forth over the swap only moves the fade (no frame shows neither, none pops).
	var auto := FarMeshRange.Mode.AUTO
	var last: float = -1.0
	var d: float = 11000.0
	while d < 16000.0:
		var alpha: float = FarMeshRange.far_alpha(d, LOD, auto)
		var shown: FarMeshRange.Shown = FarMeshRange.shown(d, LOD, auto)
		assert_true(alpha >= last - 1e-6, "the far mesh only grows more opaque outward (%.0f m)" % d)
		assert_true(shown != FarMeshRange.Shown.FAR or alpha >= 0.999, "the full hull stops only behind an opaque far mesh")
		last = alpha
		d += 25.0
	assert_almost_eq(FarMeshRange.far_alpha(13500.0, LOD, auto), 0.5, 1e-6, "half way at the swap")
	assert_eq(FarMeshRange.far_alpha(13600.0, LOD, auto), FarMeshRange.far_alpha(13600.0, LOD, auto), "no state: the same answer")


func test_the_margin_stays_inside_the_swap() -> void:
	assert_eq(FarMeshRange.margin_m({"from_m": 1000.0, "margin_m": 900.0}, FarMeshRange.Mode.AUTO), 500.0)
	assert_eq(FarMeshRange.margin_m(LOD, FarMeshRange.Mode.FAR), 0.0)


func test_apply_sets_the_node_range() -> void:
	var node: MeshInstance3D = autofree(MeshInstance3D.new())
	FarMeshRange.apply(node, LOD, FarMeshRange.Mode.AUTO)
	assert_eq(node.visibility_range_begin, 13500.0)
	assert_eq(node.visibility_range_begin_margin, 1350.0)
	assert_eq(node.visibility_range_end, 0.0, "drawn however far: beyond the camera the far plane takes it")
	assert_eq(node.visibility_range_fade_mode, GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF)
	assert_true(node.visible)
	FarMeshRange.apply(node, LOD, FarMeshRange.Mode.FULL)
	assert_false(node.visible, "hidden: out of the dependency tree, so the full hull draws at every range")
	FarMeshRange.apply(node, LOD, FarMeshRange.Mode.FAR)
	assert_true(node.visible)
	assert_almost_eq(node.visibility_range_begin, FarMeshRange.ALWAYS_M, 1e-6)
	assert_eq(node.visibility_range_fade_mode, GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED)


func test_mode_names() -> void:
	assert_eq(FarMeshRange.mode_named("auto"), FarMeshRange.Mode.AUTO)
	assert_eq(FarMeshRange.mode_named("FULL"), FarMeshRange.Mode.FULL)
	assert_eq(FarMeshRange.mode_named("far"), FarMeshRange.Mode.FAR)
	assert_eq(FarMeshRange.mode_named("near"), -1)
	assert_eq(FarMeshRange.mode_name(FarMeshRange.Mode.FAR), "far")
