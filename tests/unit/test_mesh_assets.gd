extends GutTest
## The textured meshes (M4-T30a, architecture §17.18): the Starfury's glb imported with a `StandardMaterial3D` per surface carrying
## the four maps, the glass see-through, the maps imported as 3D wants them (VRAM compressed with mipmaps, the normal map flagged, the
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
	var hull := mesh.surface_get_material(0) as StandardMaterial3D
	var glass := mesh.surface_get_material(1) as StandardMaterial3D
	assert_not_null(hull)
	assert_not_null(glass)
	assert_eq(hull.resource_name, "hull")
	assert_eq(glass.resource_name, "glass")
	for material: StandardMaterial3D in [hull, glass]:
		assert_not_null(material.albedo_texture, "albedo")
		assert_true(material.normal_enabled)
		assert_not_null(material.normal_texture, "normal")
		assert_true(material.ao_enabled)
		assert_same(material.ao_texture, material.roughness_texture, "one ORM map")
		assert_same(material.ao_texture, material.metallic_texture)
		assert_eq(material.ao_texture_channel, BaseMaterial3D.TEXTURE_CHANNEL_RED)
		assert_eq(material.roughness_texture_channel, BaseMaterial3D.TEXTURE_CHANNEL_GREEN)
		assert_eq(material.metallic_texture_channel, BaseMaterial3D.TEXTURE_CHANNEL_BLUE)
		assert_true(material.emission_enabled)
		assert_not_null(material.emission_texture, "emissive")
	assert_eq(hull.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED)
	assert_almost_eq(hull.emission_energy_multiplier, float(entry["surfaces"][0]["emissive_strength"]), 1e-6)
	assert_eq(glass.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA)
	assert_almost_eq(glass.albedo_color.a, 1.0 - float(entry["surfaces"][1]["transmittance"]), 1e-6)
	assert_eq(glass.cull_mode, BaseMaterial3D.CULL_DISABLED)
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
		assert_eq(texture.get_width(), int(entry["atlas_px"]), key)
		var image: Image = texture.get_image()
		assert_true(image.is_compressed(), "%s is VRAM compressed (%d)" % [key, image.get_format()])
		assert_true(image.has_mipmaps(), "%s has mipmaps" % key)
		var sidecar := ConfigFile.new()
		assert_eq(sidecar.load(path + ".import"), OK, "the generator writes the import preset beside the map")
		assert_eq(int(sidecar.get_value("params", "compress/mode", -1)), 2, "%s: VRAM compressed" % key)
		assert_true(bool(sidecar.get_value("params", "mipmaps/generate", false)), key)
		assert_eq(int(sidecar.get_value("params", "compress/normal_map", -1)), int(expected_normal[key]), key)
		assert_eq(int(sidecar.get_value("params", "compress/channel_pack", -1)), int(expected_pack[key]), "%s: colour or data" % key)


func test_an_asset_without_textures_keeps_the_painted_path() -> void:
	var mesh: Mesh = MeshAssets.for_asset(RAIDER)
	assert_not_null(mesh, GEN_ASSETS_HINT)
	if mesh == null:
		return
	assert_false(MeshAssets.is_textured(RAIDER), "the raider is T30b's")
	var material := mesh.surface_get_material(0) as ShaderMaterial
	assert_not_null(material)
	assert_eq(material.shader, MeshAssets.OPAQUE_SHADER)
	assert_true(MeshAssets.materials.has(material), "kept for the lights")


func test_a_textured_material_without_files_is_still_a_material() -> void:
	var material: StandardMaterial3D = MeshAssets.textured_material(_dir(STARFURY), {"name": "x", "blend": true, "transmittance": 0.5})
	assert_null(material.albedo_texture)
	assert_eq(material.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA)
	assert_almost_eq(material.albedo_color.a, 0.5, 1e-6)
