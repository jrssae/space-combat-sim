extends GutTest
## The textured meshes (M4-T30a, architecture §17.18): the Starfury's glb imported with a material per surface carrying the four
## maps (since M4-T30b the livery shader and the hull glass shader), the glass see-through, the maps imported as 3D wants them (VRAM compressed with mipmaps, the normal map flagged, the
## albedo and emissive packed for colour and the others for data), and the painted path still there for an asset without textures.

const STARFURY: String = "starfury_aurora"
const RAIDER: String = "raider_fighter"
const GEN_ASSETS_HINT: String = "run scripts/gen_assets.sh, then scripts/run_tests.sh (it imports first)"


func _manifest(asset_id: String) -> Dictionary:
	return SplatLod.read_manifest(asset_id)


func _dir(asset_id: String) -> String:
	return ShipSpec.ASSET_ROOT.path_join(asset_id)


func _triangles(mesh: Mesh) -> int:
	var n: int = 0
	for s: int in mesh.get_surface_count():
		var indices: Variant = mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX]
		n += (indices as PackedInt32Array).size() / 3 if indices != null else 0
	return n


func test_the_starfury_gives_two_surfaces_with_a_textured_material_each() -> void:
	var mesh: Mesh = MeshAssets.for_asset(STARFURY)
	assert_not_null(mesh, GEN_ASSETS_HINT)
	if mesh == null:
		return
	assert_true(MeshAssets.is_textured(STARFURY))
	assert_eq(mesh.get_surface_count(), 2, "the hull and the glass")
	var entry: Dictionary = _manifest(STARFURY)["mesh"]
	assert_eq(_triangles(mesh), int(entry["triangles"]))
	var box: AABB = mesh.get_aabb()
	var lo: Array = entry["aabb_min"]
	var hi: Array = entry["aabb_max"]
	assert_almost_eq(box.position, Vector3(lo[0], lo[1], lo[2]), Vector3.ONE * 0.01)
	assert_almost_eq(box.end, Vector3(hi[0], hi[1], hi[2]), Vector3.ONE * 0.01)
	# M4-T30b: the Starfury takes liveries, so its hull is the livery shader and its glass the hull glass shader (Q36).
	var hull := mesh.surface_get_material(0) as ShaderMaterial
	var glass := mesh.surface_get_material(1) as ShaderMaterial
	assert_not_null(hull)
	assert_not_null(glass)
	assert_eq(hull.shader, MeshAssets.LIVERY_SHADER)
	assert_eq(glass.shader, MeshAssets.HULL_GLASS_SHADER)
	assert_eq(hull.resource_name, "hull")
	assert_eq(glass.resource_name, "glass")
	for key: StringName in [&"albedo_map", &"normal_map", &"orm_map", &"emissive_map", &"digit_map"]:
		assert_not_null(hull.get_shader_parameter(key), String(key))
	for key: StringName in [&"albedo_map", &"orm_map", &"emissive_map"]:
		assert_not_null(glass.get_shader_parameter(key), String(key))
	assert_almost_eq(float(hull.get_shader_parameter(&"emission_energy")), float(entry["surfaces"][0]["emissive_strength"]), 1e-6)
	assert_almost_eq(float(glass.get_shader_parameter(&"glass_alpha")), 1.0 - float(entry["surfaces"][1]["transmittance"]), 1e-6)
	var spans: PackedVector2Array = hull.get_shader_parameter(&"pattern_span")
	assert_eq(spans.size(), MeshAssets.MAX_PATTERNS)
	var patterns: Dictionary = entry["livery"]["patterns"]
	assert_eq(int(spans[patterns.keys().find("bands")].y), (patterns["bands"] as Array).size(), "the table in the section's order")
	assert_same(MeshAssets.for_asset(STARFURY), mesh, "loaded once and shared, so every copy instances")
	assert_same(PaintMeshes.for_asset(STARFURY), mesh, "the old name gives the same mesh")


func test_the_maps_import_compressed_with_mipmaps_the_normal_flagged() -> void:
	var entry: Dictionary = _manifest(STARFURY).get("mesh", {})
	if entry.is_empty():
		fail_test(GEN_ASSETS_HINT)
		return
	var surface: Dictionary = entry["surfaces"][0]
	var expected_normal: Dictionary = {"albedo": 2, "emissive": 2, "normal": 1, "orm": 2}
	var expected_pack: Dictionary = {"albedo": 0, "emissive": 0, "normal": 1, "orm": 1}
	for key: String in ["albedo", "normal", "orm", "emissive"]:
		var path: String = _dir(STARFURY).path_join(surface[key])
		var texture := load(path) as Texture2D
		assert_not_null(texture, path)
		if texture == null:
			continue
		assert_eq(texture.get_width(), int(entry["map_px"][key]), key)  # M4-T30b: the normal map at twice the atlas, the rest at it
		assert_eq(int(entry["map_px"][key]), int(entry["atlas_px"]) * (2 if key == "normal" else 1), key)
		var image: Image = texture.get_image()
		assert_true(image.is_compressed(), "%s is VRAM compressed (%d)" % [key, image.get_format()])
		assert_true(image.has_mipmaps(), "%s has mipmaps" % key)
		var sidecar := ConfigFile.new()
		assert_eq(sidecar.load(path + ".import"), OK, "the generator writes the import preset beside the map")
		assert_eq(int(sidecar.get_value("params", "compress/mode", -1)), 2, "%s: VRAM compressed" % key)
		assert_true(bool(sidecar.get_value("params", "mipmaps/generate", false)), key)
		assert_eq(int(sidecar.get_value("params", "compress/normal_map", -1)), int(expected_normal[key]), key)
		assert_eq(int(sidecar.get_value("params", "compress/channel_pack", -1)), int(expected_pack[key]), "%s: colour or data" % key)


func test_a_painted_entry_keeps_the_paint_shader() -> void:
	# Every hull is textured from M4-T30d; T27's painted mesh is still loaded by its own entry (the sheet's painted look).
	assert_true(MeshAssets.is_textured(RAIDER), "the raider is textured from M4-T30d")
	var entry: Dictionary = SplatLod.read_manifest(RAIDER).get("paint_mesh", {})
	var mesh: Mesh = MeshAssets.load_entry(_dir(RAIDER), entry) if not entry.is_empty() else null
	assert_not_null(mesh, GEN_ASSETS_HINT)
	if mesh == null:
		return
	var material := mesh.surface_get_material(0) as ShaderMaterial
	assert_not_null(material)
	assert_eq(material.shader, MeshAssets.OPAQUE_SHADER)
	assert_true(MeshAssets.materials.has(material), "kept for the lights")


func test_a_textured_material_without_files_is_still_a_material() -> void:
	var material: StandardMaterial3D = MeshAssets.textured_material(_dir(STARFURY), {"name": "x", "blend": true, "transmittance": 0.5})
	assert_null(material.albedo_texture)
	assert_eq(material.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA)
	assert_almost_eq(material.albedo_color.a, 0.5, 1e-6)


func test_the_livery_zone_survives_the_import() -> void:
	# M4-T30b (review, Minor 1): the hull shader reads each vertex's zone as round(COLOR.r * 255); an import that converted the colour
	# would paint nothing while everything else passed.
	var mesh: Mesh = MeshAssets.for_asset(STARFURY)
	if mesh == null:
		fail_test(GEN_ASSETS_HINT)
		return
	var colours: Variant = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	assert_not_null(colours, "the hull keeps its vertex colours")
	if colours == null:
		return
	var seen: Dictionary = {}
	for colour: Color in colours as PackedColorArray:
		var zone: float = colour.r * 255.0
		assert_almost_eq(zone, roundf(zone), 0.02, "a whole zone number")
		seen[int(roundf(zone))] = true
	for zone: int in range(1, 8):
		assert_true(seen.has(zone), "zone %d is on the hull" % zone)
	assert_false(seen.keys().any(func(z: int) -> bool: return z > 7), "no zone beyond the table")
