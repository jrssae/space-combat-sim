extends GutTest
## The capital framework's test hull (M10-T05, D12.1; `tools/procgen/assets/capital_test_cruiser.py`) loads in the game: every
## piece's textured mesh with the shared detail tile on it, the break-up chunks, the collision per section and the hardpoints.
## What the game does with them is M10-T07's.

const ASSET: String = "capital_test_cruiser"
const GEN_ASSETS_HINT: String = "run scripts/gen_assets.sh, then scripts/run_tests.sh (it imports first)"

var manifest: Dictionary
var dir: String


func before_all() -> void:
	manifest = MeshAssets.read_manifest(ASSET)
	dir = ShipSpec.ASSET_ROOT.path_join(ASSET)


func _triangles(mesh: Mesh) -> int:
	var n: int = 0
	for s: int in mesh.get_surface_count():
		n += (mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return n


func test_every_piece_loads_as_a_textured_mesh_with_the_detail_tile() -> void:
	assert_false(manifest.is_empty(), GEN_ASSETS_HINT)
	var pieces: Dictionary = manifest.get("pieces", {})
	assert_eq(pieces.keys(), ["hull", "rotor"])
	for piece_name: String in pieces:
		var piece := RenderPiece.new()
		add_child_autofree(piece)
		piece.build(dir, pieces[piece_name])
		var mesh: Mesh = piece.mesh()
		assert_not_null(mesh, "%s: %s" % [piece_name, GEN_ASSETS_HINT])
		if mesh == null:
			continue
		assert_eq(_triangles(mesh), int(pieces[piece_name]["mesh"]["triangles"]), piece_name)
		var material := mesh.surface_get_material(0) as StandardMaterial3D
		assert_not_null(material, "%s: a textured material" % piece_name)
		assert_not_null(material.albedo_texture, "%s: its own atlas" % piece_name)
		assert_true(material.detail_enabled and material.uv2_triplanar, "%s: the shared tile laid in its own space" % piece_name)
		assert_almost_eq(material.uv2_scale.x, 1.0 / 16.0, 1e-6, "a 16 m tile")
	assert_same(MeshAssets.for_asset(ASSET), MeshAssets.load_textured(dir, pieces["hull"]["mesh"]), "the asset's mesh is its hull piece")


func test_the_rotating_piece_names_its_pivot_axis_and_spin() -> void:
	var rotor: Dictionary = manifest.get("pieces", {}).get("rotor", {})
	assert_eq((rotor.get("pivot", []) as Array).size(), 3)
	assert_eq(rotor.get("axis", []), [0.0, 0.0, 1.0])
	assert_gt(float(rotor.get("spin_rad_s", 0.0)), 0.0)


func test_the_sections_share_out_the_hull_and_each_has_a_chunk_and_collision() -> void:
	var collision: CollisionPieces = CollisionPieces.for_asset(ASSET)
	assert_true(collision.valid, collision.error)
	var hardpoints: Hardpoints = Hardpoints.load_file(dir.path_join("hardpoints.json"))
	assert_true(hardpoints.valid, hardpoints.error)
	var chunks: Dictionary = {}
	for chunk: Dictionary in hardpoints.chunks:
		chunks[chunk["name"]] = chunk
	var share: float = 0.0
	var sections: Array = manifest.get("sections", [])
	assert_eq(sections.size(), 10)
	for section: Dictionary in sections:
		var section_name: String = section["name"]
		share += float(section["hull_share"])
		var piece: Dictionary = collision.piece(String(section["collision"]))
		assert_eq((piece.get("shapes", []) as Array).size(), int(section["shapes"]), "%s: its convex shapes" % section_name)
		assert_eq((piece.get("hit_volumes", []) as Array).size(), int(section["hit_volumes"]), "%s: its hit volumes" % section_name)
		assert_true(chunks.has(section["chunk"]), "%s: its chunk" % section_name)
		assert_true(ResourceLoader.exists(dir.path_join(String(chunks[section["chunk"]]["mesh"]))), "%s: its chunk's mesh is imported" % section_name)
	assert_almost_eq(share, 1.0, 1e-6)
	assert_not_null(MeshAssets.chunk_mesh(dir, String(chunks["reactor"]["mesh"])), "a hull chunk draws with the hull's maps")


func test_a_sections_collision_builds_a_body() -> void:
	var collision: CollisionPieces = CollisionPieces.for_asset(ASSET)
	var body: PhysicsBody3D = CollisionBodies.build(collision.piece("habitat"), true)
	autofree(body)
	assert_true(body is AnimatableBody3D, "the rotating section's body is driven, as the station's drum")
	assert_eq(body.get_child_count(), 12 + 2 * 2, "the collar's twelve sectors, and an arm and a block on each side")
	for child: Node in body.get_children():
		assert_not_null((child as CollisionShape3D).shape)
