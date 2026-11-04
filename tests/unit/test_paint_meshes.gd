extends GutTest
## The painted meshes (M4-T27, architecture §17.16): each hull's own surface imported as one mesh with the paint shader on it, filled
## from the manifest; the lights the splats get; and how a big piece picks its splat level.

const RAIDER: String = "raider_fighter"
const STARFURY: String = "starfury_aurora"


func _manifest(asset_id: String) -> Dictionary:
	return SplatLod.read_manifest(asset_id)


func _triangles(mesh: Mesh) -> int:
	var n: int = 0
	for s: int in mesh.get_surface_count():
		var indices: Variant = mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX]
		n += (indices as PackedInt32Array).size() / 3 if indices != null else 0
	return n


func test_a_ship_asset_gives_its_mesh_with_one_paint_material_per_surface() -> void:
	var mesh: Mesh = PaintMeshes.for_asset(RAIDER)
	assert_not_null(mesh, "run scripts/gen_assets.sh and import first")
	if mesh == null:
		return
	assert_eq(mesh.get_surface_count(), 1, "the raider has no glass: one opaque surface")
	var material := mesh.surface_get_material(0) as ShaderMaterial
	assert_not_null(material)
	assert_eq(material.shader, PaintMeshes.OPAQUE_SHADER)
	assert_true(PaintMeshes.materials.has(material), "kept for the lights")
	assert_same(PaintMeshes.for_asset(RAIDER), mesh, "loaded once and shared")


func test_the_mesh_holds_the_manifests_triangles_and_box() -> void:
	for asset_id: String in [RAIDER, STARFURY]:
		var mesh: Mesh = PaintMeshes.for_asset(asset_id)
		if mesh == null:
			fail_test("%s has no painted mesh" % asset_id)
			continue
		var entry: Dictionary = _manifest(asset_id)["paint_mesh"]
		assert_eq(_triangles(mesh), int(entry["triangles"]), asset_id)
		var box: AABB = mesh.get_aabb()
		var lo: Array = entry["aabb_min"]
		var hi: Array = entry["aabb_max"]
		assert_almost_eq(box.position, Vector3(lo[0], lo[1], lo[2]), Vector3.ONE * 0.01, asset_id)
		assert_almost_eq(box.end, Vector3(hi[0], hi[1], hi[2]), Vector3.ONE * 0.01, asset_id)


func test_the_starfury_glass_is_its_own_see_through_surface() -> void:
	var mesh: Mesh = PaintMeshes.for_asset(STARFURY)
	if mesh == null:
		fail_test("no painted Starfury")
		return
	assert_eq(mesh.get_surface_count(), 2)
	var shaders: Array = []
	for s: int in mesh.get_surface_count():
		shaders.append((mesh.surface_get_material(s) as ShaderMaterial).shader)
	assert_true(shaders.has(PaintMeshes.OPAQUE_SHADER))
	assert_true(shaders.has(PaintMeshes.GLASS_SHADER))


func test_the_material_table_and_panel_grid_come_from_the_manifest() -> void:
	var entry: Dictionary = _manifest(RAIDER)["paint_mesh"]
	var material: ShaderMaterial = PaintMeshes.make_material(entry, false)
	var albedo: PackedVector3Array = material.get_shader_parameter(&"paint_albedo")
	var paneled: PackedFloat32Array = material.get_shader_parameter(&"paint_paneled")
	var table: Array = entry["materials"]
	for k: int in table.size():
		var c: Array = table[k]["albedo"]
		assert_almost_eq(albedo[k], Vector3(c[0], c[1], c[2]), Vector3.ONE * 1e-5)
		assert_eq(paneled[k] > 0.5, bool(table[k]["paneled"]))
	assert_almost_eq(float(material.get_shader_parameter(&"panel_size_m")), float(entry["panel"]["size_m"]), 1e-6)
	var glass: ShaderMaterial = PaintMeshes.make_material({"materials": [{"albedo": [0, 0, 0], "transmittance": 0.7}]}, true)
	assert_almost_eq(float(glass.get_shader_parameter(&"glass_alpha")), 0.3, 1e-6)


func test_the_uv_codes_decode_to_a_material_in_the_table() -> void:
	var mesh: Mesh = PaintMeshes.for_asset(STARFURY)
	if mesh == null:
		fail_test("no painted Starfury")
		return
	var count: int = (_manifest(STARFURY)["paint_mesh"]["materials"] as Array).size()
	for s: int in mesh.get_surface_count():
		var uv: PackedVector2Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_TEX_UV]
		var worst: float = 0.0
		for i: int in range(0, uv.size(), 97):
			var code: Vector2 = uv[i]
			worst = maxf(worst, maxf(absf(code.x - roundf(code.x)), absf(code.y - roundf(code.y))))
			var material: int = int(roundf(code.y)) / 97
			assert_true(material >= 0 and material < count, "material %d of %d" % [material, count])
		assert_lt(worst, 0.25, "the codes survive the import as whole numbers")


func test_the_lights_are_the_rigs_packed_as_gdgs_packs_them() -> void:
	var rig := SplatLightRig.new()
	var key := DirectionalLight3D.new()
	key.name = "KeyStar"
	rig.add_child(key)
	add_child_autofree(rig)
	rig.key_star.light_energy = 1.5
	rig.key_star.look_at_from_position(Vector3.ZERO, Vector3(0.0, 0.0, -1.0))
	var omni := rig.slots()[1] as OmniLight3D
	omni.light_energy = 2.0
	omni.omni_range = 15.0
	omni.global_position = Vector3(1.0, 2.0, 3.0)
	var lights := PaintMeshLights.new()
	add_child_autofree(lights)
	assert_eq(lights.pack(rig), 2, "the key star and the one shining slot")
	assert_almost_eq(lights._vectors[0], Vector3(0.0, 0.0, 1.0), Vector3.ONE * 1e-5, "towards the star")
	assert_almost_eq(lights._colors[0].a, 0.0, 1e-6, "directional")
	assert_almost_eq(lights._colors[0].r, 1.5, 1e-5, "colour times energy")
	assert_almost_eq(lights._vectors[1], Vector3(1.0, 2.0, 3.0), Vector3.ONE * 1e-5)
	assert_almost_eq(lights._colors[1].a, 1.0, 1e-6, "omni")
	assert_almost_eq(lights._params[1].r, 1.0 / 15.0, 1e-6, "1 / range")
	assert_eq(lights.pack(null), 0)


func test_a_piece_shows_the_coarsest_level_that_stays_sharp() -> void:
	var spacings := PackedFloat32Array([4.0, 8.0, 16.0, 32.0])
	var px_per_m: float = 1080.0 / (2.0 * tan(deg_to_rad(70.0) * 0.5))  # 771 px per metre at 1 m
	assert_eq(RenderPiece.level_for(spacings, 1000.0, 0.0, px_per_m), 0, "4 m at 1 km is 3 px: the finest")
	assert_eq(RenderPiece.level_for(spacings, 12000.0, 0.0, px_per_m), 2, "16 m at 12 km is 1 px")
	assert_eq(RenderPiece.level_for(spacings, 40000.0, 0.0, px_per_m), 3)
	assert_eq(RenderPiece.level_for(spacings, 5000.0, 4000.0, px_per_m), 0, "measured from the nearest point")
