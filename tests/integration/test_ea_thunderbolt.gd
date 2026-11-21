extends GutTest
## The Thunderbolt as a model (M10-T50; M11 gives it a `ShipSpec`): it imports as a textured mesh that takes wing liveries,
## its low texture set is a mip level down and the hull's and the glass's materials take that set's own glow map (the first
## fighter whose low set is written smaller), and its hardpoints and chunks read as a fighter's. Skips, saying why, without
## the generated asset.

const ASSET_ID: String = "ea_thunderbolt"
const GEN_ASSETS_HINT: String = "run scripts/gen_assets.sh and import first"
## Godot's importer may weld a few vertices; the box must still match the manifest's to a centimetre.
const AABB_TOLERANCE_M: float = 0.01
const HULL_KEYS: Array[String] = ["albedo", "normal", "orm", "emissive"]
const GLASS_KEYS: Array[String] = ["albedo", "orm", "emissive"]

var _detail_before: Variant


func before_each() -> void:
	_detail_before = Settings.get_value(&"texture_detail")


func after_each() -> void:
	Settings.set_value(&"texture_detail", _detail_before)


func _dir() -> String:
	return ShipSpec.ASSET_ROOT.path_join(ASSET_ID)


func _section() -> Dictionary:
	return MeshAssets.read_manifest(ASSET_ID).get("mesh", {})


func _skipped() -> bool:
	if _section().is_empty() or MeshAssets.for_asset(ASSET_ID) == null:
		pending("%s is not generated (%s)" % [ASSET_ID, GEN_ASSETS_HINT])
		return true
	return false


func _map(material: Material, key: String) -> Texture2D:
	return (material as ShaderMaterial).get_shader_parameter(StringName(key + "_map")) as Texture2D


func test_it_imports_as_a_textured_mesh_that_takes_wing_liveries() -> void:
	if _skipped():
		return
	var section: Dictionary = _section()
	var mesh: Mesh = MeshAssets.for_asset(ASSET_ID)
	assert_eq(String(section.get("file", "")), ASSET_ID + ".glb")
	assert_eq(mesh.get_surface_count(), 2, "the hull and the glass")
	var hull := mesh.surface_get_material(0) as ShaderMaterial
	var glass := mesh.surface_get_material(1) as ShaderMaterial
	assert_true(hull != null and hull.shader == MeshAssets.LIVERY_SHADER, "the hull draws with the fighters' livery shader")
	assert_true(glass != null and glass.shader == MeshAssets.HULL_GLASS_SHADER, "the canopy with the glass shader")
	var lo: Array = section["aabb_min"]
	var hi: Array = section["aabb_max"]
	var aabb: AABB = mesh.get_aabb()
	assert_almost_eq(aabb.position, Vector3(lo[0], lo[1], lo[2]), Vector3.ONE * AABB_TOLERANCE_M, "box corner")
	assert_almost_eq(aabb.end, Vector3(hi[0], hi[1], hi[2]), Vector3.ONE * AABB_TOLERANCE_M, "box end")
	assert_eq(mesh.get_faces().size() / 3, int(section["triangles"]), "triangles")
	var livery_section: Dictionary = MeshAssets.livery_section(ASSET_ID)
	assert_false(livery_section.is_empty(), "the manifest carries the livery table")
	var livery: Livery = Livery.for_wing("alpha", 7, livery_section)
	assert_not_null(livery)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	add_child_autofree(instance)
	livery.apply(instance)
	assert_eq(int(instance.get_instance_shader_parameter(&"livery_number")), 7, "a wing's number rides on the instance")


func test_the_low_set_is_a_mip_level_down_and_brings_its_own_glow_map() -> void:
	if _skipped():
		return
	var section: Dictionary = _section()
	var mesh: Mesh = MeshAssets.for_asset(ASSET_ID)
	var atlas_px: int = int(section["atlas_px"])
	for i: int in mesh.get_surface_count():
		var material: Material = mesh.surface_get_material(i)
		var surface: Dictionary = MeshAssets._surface_named(section["surfaces"] as Array, String(material.resource_name), i)
		var low: Dictionary = (surface.get("detail", {}) as Dictionary).get("low", {})
		assert_eq(low.keys(), HULL_KEYS, "%s names a low set of all four maps" % material.resource_name)
		var keys: Array[String] = GLASS_KEYS if bool(surface.get("blend", false)) else HULL_KEYS
		Settings.set_value(&"texture_detail", &"high")
		for key: String in keys:
			var map: Texture2D = _map(material, key)
			assert_not_null(map, "%s high %s" % [material.resource_name, key])
			if map != null:
				assert_eq(map.resource_path, _dir().path_join(String(surface[key])), "%s high %s" % [material.resource_name, key])
				assert_eq(map.get_width(), int((section["map_px"] as Dictionary)[key]), "%s high %s is full size" % [material.resource_name, key])
		Settings.set_value(&"texture_detail", &"low")
		for key: String in keys:
			var map: Texture2D = _map(material, key)
			assert_not_null(map, "%s low %s" % [material.resource_name, key])
			if map != null:
				assert_eq(map.resource_path, _dir().path_join(String(low[key])), "%s low %s is the set's own" % [material.resource_name, key])
				assert_eq(map.get_width() * 2, int((section["map_px"] as Dictionary)[key]), "%s low %s is a mip level down" % [material.resource_name, key])
		Settings.set_value(&"texture_detail", &"high")
		assert_eq(_map(material, "emissive").get_width(), atlas_px, "%s: back on the high set the glow map is the full one" % material.resource_name)
	assert_same(MeshAssets.for_asset(ASSET_ID), mesh, "one mesh and material, so every copy still instances")


func test_a_fighter_whose_low_set_keeps_the_full_glow_map_is_left_as_it_was() -> void:
	# The Starfury's low set (M7-T15) names three maps: its glow map is one for both sets, as before this hull.
	var mesh: Mesh = MeshAssets.for_asset("starfury_aurora")
	if mesh == null:
		pending("starfury_aurora is not generated (%s)" % GEN_ASSETS_HINT)
		return
	for i: int in mesh.get_surface_count():
		var material: Material = mesh.surface_get_material(i)
		Settings.set_value(&"texture_detail", &"high")
		var glow: Texture2D = _map(material, "emissive")
		assert_not_null(glow)
		Settings.set_value(&"texture_detail", &"low")
		assert_same(_map(material, "emissive"), glow, "%s keeps its glow map" % material.resource_name)


func test_its_hardpoints_and_chunks_read_as_a_fighters() -> void:
	if _skipped():
		return
	var hp: Hardpoints = Hardpoints.load_file(_dir().path_join("hardpoints.json"))
	assert_true(hp.valid, hp.error)
	assert_eq(hp.muzzles.size(), 5, "the nose battery's three and the wing roots' two")
	assert_eq((hp.raw.get("pods", []) as Array).size(), 4)
	assert_eq((hp.raw.get("rcs", []) as Array).size(), 12)
	assert_gt(hp.collision.size(), 20)
	var names: Array[String] = []
	for entry: Dictionary in hp.chunks:
		names.append(String(entry["name"]))
		var chunk: DebrisChunk = DebrisChunk.create(entry, _dir())
		add_child_autofree(chunk)
		assert_not_null(chunk.textured_mesh, "chunk %s has its textured mesh" % entry["name"])
	assert_eq(names, ["cabin", "arm_ur", "arm_lr", "arm_ul", "arm_ll"] as Array[String], "the X-fighter's cabin and four arms")
