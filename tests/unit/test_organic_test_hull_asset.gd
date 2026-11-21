extends GutTest
## The organic part library's test hull (M10-T06, D12.2; `tools/procgen/assets/organic_test_hull.py`) loads in the game: its
## seamless mesh draws with the sheen layer's material (`HullSheenMaterial`, `hull_organic.gdshader`) wearing the manifest's
## numbers, both texture sets, its sections' chunks on the same material, and collision per section.

const ASSET: String = "organic_test_hull"
const GEN_ASSETS_HINT: String = "run scripts/gen_assets.sh, then scripts/run_tests.sh (it imports first)"
const SECTIONS: Array[String] = ["head", "core", "tail", "petals", "claw_r", "claw_l", "legs_r", "legs_l"]

var manifest: Dictionary
var dir: String


func before_all() -> void:
	manifest = MeshAssets.read_manifest(ASSET)
	dir = ShipSpec.ASSET_ROOT.path_join(ASSET)


func _material() -> ShaderMaterial:
	var mesh: Mesh = MeshAssets.for_asset(ASSET)
	return mesh.surface_get_material(0) as ShaderMaterial if mesh != null else null


func test_the_hull_draws_with_the_sheen_layer_inside_its_class_budget() -> void:
	assert_false(manifest.is_empty(), GEN_ASSETS_HINT)
	var mesh: Mesh = MeshAssets.for_asset(ASSET)
	assert_not_null(mesh, GEN_ASSETS_HINT)
	if mesh == null:
		return
	var triangles: int = 0
	for s: int in mesh.get_surface_count():
		triangles += (mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	assert_eq(triangles, int(manifest["mesh"]["triangles"]))
	assert_lte(triangles, 60000, "a cruiser's triangles (Q38)")
	var material := _material()
	assert_not_null(material, "an organic hull's material is the sheen layer's, not the standard one")
	if material == null:
		return
	assert_same(material.shader, HullSheenMaterial.SHADER)
	assert_not_null(material.get_shader_parameter(&"albedo_map"), "its own atlas")
	assert_null(material.get_shader_parameter(&"detail_tile_m"), "a seamless skin is given no plating tile (Q46)")


func test_the_material_wears_the_manifests_sheen() -> void:
	var material := _material()
	assert_not_null(material, GEN_ASSETS_HINT)
	if material == null:
		return
	var sheen: Dictionary = (manifest["mesh"]["surfaces"] as Array)[0]["sheen"]
	for key: String in HullSheenMaterial.SCALARS:
		assert_true(sheen.has(key), "the manifest names %s" % key)
		assert_almost_eq(float(material.get_shader_parameter(StringName(key))), float(sheen[key]), 1e-6, key)
	for key: String in HullSheenMaterial.COLOURS:
		var colour: Array = sheen[key]
		assert_almost_eq(material.get_shader_parameter(StringName(key)) as Vector3, Vector3(colour[0], colour[1], colour[2]), Vector3.ONE * 1e-6, key)
	for key: String in HullSheenMaterial.HARMONICS:
		var coefficients: PackedVector3Array = material.get_shader_parameter(StringName(key))
		assert_eq(coefficients.size(), HullSheenMaterial.SH_COUNT, "%s: nine coefficients" % key)
		assert_almost_eq(coefficients[0].x, float(sheen[key][0][0]), 1e-6, key)
	assert_gt(float(sheen["glow_energy"]), 0.0, "the Vorlon look glows faintly (Q46)")


func test_a_fifth_of_the_ships_wear_the_second_colouring_by_their_own_names() -> void:
	var sheen: Dictionary = (manifest["mesh"]["surfaces"] as Array)[0]["sheen"]
	assert_almost_eq(float(sheen["variant_share"]), 0.2, 1e-6)
	var red: int = 0
	for i: int in 2000:
		var variant: float = HullSheenMaterial.variant_for(sheen, "VORLON %d" % i)
		assert_true(variant == 0.0 or variant == 1.0)
		red += int(variant)
	assert_between(red, 340, 460, "about a fifth of 2 000 names")
	assert_eq(HullSheenMaterial.variant_for(sheen, "KOSH"), HullSheenMaterial.variant_for(sheen, "KOSH"), "a name is one colour, every time")
	assert_eq(HullSheenMaterial.variant_of_mesh(manifest["mesh"], "VORLON 7"), HullSheenMaterial.variant_for(sheen, "VORLON 7"))
	assert_eq(HullSheenMaterial.variant_for({}, "VORLON 7"), 0.0, "a style with no second colouring has none")
	assert_eq(HullSheenMaterial.variant_of_mesh({"surfaces": [{"name": "hull"}]}, "VORLON 7"), 0.0)
	var piece := RenderPiece.new()
	add_child_autofree(piece)
	piece.build(dir, manifest["pieces"]["hull"])
	piece.set_skin_variant(1.0)
	var node := piece.get_child(0) as MeshInstance3D
	assert_eq(float(node.get_instance_shader_parameter(HullSheenMaterial.VARIANT_PARAMETER)), 1.0, "the ship's own copy of the hull turns red")


func test_a_surface_without_a_sheen_keeps_the_standard_material() -> void:
	var plain: Dictionary = (manifest["mesh"]["surfaces"] as Array)[0].duplicate()
	plain.erase("sheen")
	assert_false(HullSheenMaterial.wants(plain))
	assert_true(MeshAssets.paint_material(dir, plain) is StandardMaterial3D)
	assert_true(HullSheenMaterial.wants((manifest["mesh"]["surfaces"] as Array)[0]))


func test_the_low_texture_set_is_a_mip_level_down() -> void:
	var material := _material()
	assert_not_null(material, GEN_ASSETS_HINT)
	if material == null:
		return
	var before: Variant = Settings.get_value(&"texture_detail")
	Settings.set_value(&"texture_detail", &"high")
	var high: int = (material.get_shader_parameter(&"albedo_map") as Texture2D).get_width()
	assert_eq(high, int(manifest["mesh"]["atlas_px"]))
	Settings.set_value(&"texture_detail", &"low")
	for key: String in HullSheenMaterial.MAP_KEYS:
		assert_eq((material.get_shader_parameter(StringName(key + "_map")) as Texture2D).get_width(), high / 2, "%s is half as wide (Q38)" % key)
	Settings.set_value(&"texture_detail", &"high")
	assert_eq((material.get_shader_parameter(&"normal_map") as Texture2D).get_width(), high, "and the high set comes back")
	Settings.set_value(&"texture_detail", before)


func test_every_section_has_a_chunk_on_the_hulls_material_and_collision() -> void:
	var collision: CollisionPieces = CollisionPieces.for_asset(ASSET)
	assert_true(collision.valid, collision.error)
	var hardpoints: Hardpoints = Hardpoints.load_file(dir.path_join("hardpoints.json"))
	assert_true(hardpoints.valid, hardpoints.error)
	var chunks: Dictionary = {}
	for chunk: Dictionary in hardpoints.chunks:
		chunks[chunk["name"]] = chunk
	var names: Array[String] = []
	var share: float = 0.0
	for section: Dictionary in manifest.get("sections", []):
		var section_name: String = section["name"]
		names.append(section_name)
		share += float(section["hull_share"])
		var piece: Dictionary = collision.piece(String(section["collision"]))
		assert_eq((piece.get("shapes", []) as Array).size(), int(section["shapes"]), "%s: its convex shapes" % section_name)
		assert_true(chunks.has(section["chunk"]), "%s: its chunk" % section_name)
	assert_eq(names, SECTIONS)
	assert_almost_eq(share, 1.0, 1e-6)
	var chunk_mesh: Mesh = MeshAssets.chunk_mesh(dir, String(chunks["core"]["mesh"]))
	assert_not_null(chunk_mesh, "the core breaks away as a mesh of its own")
	if chunk_mesh != null:
		assert_same(chunk_mesh.surface_get_material(0), _material(), "wearing the hull's skin and sheen")
	var body: PhysicsBody3D = CollisionBodies.build(collision.piece("legs_r"), false)
	autofree(body)
	assert_eq(body.get_child_count(), int((manifest["sections"] as Array)[6]["shapes"]), "an organic section's collision builds a body")
