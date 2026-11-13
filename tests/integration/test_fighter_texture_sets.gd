extends GutTest
## The Starfury's and the raider's two texture sets (M7-T15): every surface names a low set, and `settings.texture_detail` swaps the
## maps of the hull already loaded: the Starfury's livery and glass shaders and the raider's paint, the glow map shared.

const GEN_ASSETS_HINT: String = "run scripts/gen_assets.sh and import first"
const FIGHTERS: Array[String] = ["starfury_aurora", "raider_fighter"]


func _dir(asset_id: String) -> String:
	return ShipSpec.ASSET_ROOT.path_join(asset_id)


# The file one of a material's maps was loaded from.
func _map_path(material: Material, key: String) -> String:
	var map: Texture2D = null
	if material is ShaderMaterial:
		map = (material as ShaderMaterial).get_shader_parameter(StringName(key + "_map")) as Texture2D
	else:
		var standard := material as StandardMaterial3D
		map = {"albedo": standard.albedo_texture, "normal": standard.normal_texture, "orm": standard.roughness_texture}[key]
	return map.resource_path if map != null else ""


func _glow(material: Material) -> Texture2D:
	if material is ShaderMaterial:
		return (material as ShaderMaterial).get_shader_parameter(&"emissive_map") as Texture2D
	return (material as StandardMaterial3D).emission_texture


func test_the_texture_detail_setting_switches_both_fighters() -> void:
	var before: Variant = Settings.get_value(&"texture_detail")
	Settings.set_value(&"texture_detail", &"high")
	for asset_id: String in FIGHTERS:
		var surfaces: Array = (MeshAssets.read_manifest(asset_id).get("mesh", {}) as Dictionary).get("surfaces", [])
		var mesh: Mesh = MeshAssets.for_asset(asset_id)
		assert_false(surfaces.is_empty(), "%s has surfaces (%s)" % [asset_id, GEN_ASSETS_HINT])
		assert_not_null(mesh, "%s imported (%s)" % [asset_id, GEN_ASSETS_HINT])
		if surfaces.is_empty() or mesh == null:
			continue
		for i: int in mesh.get_surface_count():
			var material: Material = mesh.surface_get_material(i)
			var surface: Dictionary = MeshAssets._surface_named(surfaces, String(material.resource_name), i)
			var low: Dictionary = (surface.get("detail", {}) as Dictionary).get("low", {})
			assert_eq(low.keys(), MeshAssets.DETAIL_KEYS, "%s %s names a low set" % [asset_id, material.resource_name])
			# Glass draws no normal map; the paint draws all three.
			var keys: Array[String] = MeshAssets.GLASS_DETAIL_KEYS if bool(surface.get("blend", false)) else MeshAssets.DETAIL_KEYS
			var glow: Texture2D = _glow(material)
			Settings.set_value(&"texture_detail", &"high")
			for key: String in keys:
				assert_eq(_map_path(material, key), _dir(asset_id).path_join(String(surface[key])), "%s high %s" % [asset_id, key])
			Settings.set_value(&"texture_detail", &"low")
			for key: String in keys:
				assert_eq(_map_path(material, key), _dir(asset_id).path_join(String(low.get(key, ""))), "%s low %s" % [asset_id, key])
			assert_same(_glow(material), glow, "%s: the glow is one map for both sets" % asset_id)
			Settings.set_value(&"texture_detail", &"high")
		assert_same(MeshAssets.for_asset(asset_id), mesh, "%s: one mesh and material, so every copy still instances" % asset_id)
	Settings.set_value(&"texture_detail", before)
