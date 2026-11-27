extends GutTest
## The capitals' far meshes in the game (M10-T89) on the framework's test hull: each piece draws its far mesh past the swap with
## the full mesh and what rides on the piece as its visibility dependents; the console's modes reach every live piece; a hulk's
## lights go out on the far mesh too; the break-up keeps the full chunks.

const ASSET: String = "capital_test_cruiser"
const GEN_ASSETS_HINT: String = "run scripts/gen_assets.sh, then scripts/run_tests.sh (it imports first)"

var manifest: Dictionary
var dir: String


func before_all() -> void:
	manifest = MeshAssets.read_manifest(ASSET)
	dir = ShipSpec.ASSET_ROOT.path_join(ASSET)


func after_each() -> void:
	RenderPiece.set_far_mode(FarMeshRange.Mode.AUTO)


func _piece(name: String) -> RenderPiece:
	var piece := RenderPiece.new()
	piece.build(dir, (manifest.get("pieces", {}) as Dictionary).get(name, {}))
	add_child_autofree(piece)
	return piece


func test_every_piece_draws_its_far_mesh_past_the_swap() -> void:
	assert_false(manifest.is_empty(), GEN_ASSETS_HINT)
	for name: String in (manifest.get("pieces", {}) as Dictionary):
		var piece: RenderPiece = _piece(name)
		var lod: Dictionary = manifest["pieces"][name]["mesh"]["lods"][0]
		assert_not_null(piece.far_node, "%s: %s" % [name, GEN_ASSETS_HINT])
		if piece.far_node == null:
			continue
		assert_not_null(piece.far_node.mesh, name)
		assert_eq(piece.far_node.visibility_range_begin, float(lod["from_m"]), name)
		assert_eq(piece.far_node.visibility_range_begin_margin, float(lod["margin_m"]), name)
		var full: MeshInstance3D = piece.get_node("HullMesh") as MeshInstance3D
		assert_eq(full.get_node(full.visibility_parent), piece.far_node, "%s: the full mesh draws only while the far one does not" % name)
		assert_eq(full.visibility_range_end, 0.0, "%s: the full mesh has no range of its own" % name)


func test_what_is_added_later_goes_with_the_full_mesh() -> void:
	var piece: RenderPiece = _piece("hull")
	if piece.far_node == null:
		fail_test(GEN_ASSETS_HINT)
		return
	var mark: MeshInstance3D = MeshInstance3D.new()
	piece.add_child(mark)
	piece.hide_when_far()
	assert_eq(mark.get_node(mark.visibility_parent), piece.far_node, "a mark or a door added by the ship")
	assert_true(piece.far_node.visibility_parent.is_empty(), "the far mesh depends on nothing")


func test_the_console_mode_reaches_every_live_piece() -> void:
	var a: RenderPiece = _piece("hull")
	var b: RenderPiece = _piece("rotor")
	if a.far_node == null or b.far_node == null:
		fail_test(GEN_ASSETS_HINT)
		return
	assert_true(RenderPiece.far_count() >= 2)
	RenderPiece.set_far_mode(FarMeshRange.Mode.FULL)
	assert_false(a.far_node.visible or b.far_node.visible, "full: no far mesh anywhere")
	RenderPiece.set_far_mode(FarMeshRange.Mode.FAR)
	assert_true(a.far_node.visible and b.far_node.visible)
	assert_almost_eq(a.far_node.visibility_range_begin, FarMeshRange.ALWAYS_M, 1e-6)
	var c: RenderPiece = _piece("hull")
	assert_almost_eq(c.far_node.visibility_range_begin, FarMeshRange.ALWAYS_M, 1e-6, "a piece built now takes the mode")
	RenderPiece.set_far_mode(FarMeshRange.Mode.AUTO)
	assert_eq(a.far_node.visibility_range_begin, float(a.far_lod["from_m"]))


func test_a_hulk_dims_the_far_mesh_glow_too() -> void:
	var piece: RenderPiece = _piece("hull")
	if piece.far_node == null:
		fail_test(GEN_ASSETS_HINT)
		return
	var material: StandardMaterial3D = piece.far_node.get_active_material(0) as StandardMaterial3D
	assert_not_null(material, "the far mesh is drawn with the hull's material pipeline")
	if material == null or not material.emission_enabled:
		pass_test("the test hull's far mesh does not glow")
		return
	var lights: CapitalHulkLights = CapitalHulkLights.collect([piece] as Array[Node])
	lights.apply(0.0)
	var dimmed := piece.far_node.get_active_material(0) as StandardMaterial3D
	assert_ne(dimmed, material, "its own copy, so its sisters stay lit")
	assert_eq(dimmed.emission_energy_multiplier, 0.0)
	lights.release()
	assert_eq(piece.far_node.get_active_material(0), material)


func test_the_break_up_keeps_the_full_chunks() -> void:
	var text: String = FileAccess.get_file_as_string(dir.path_join("hardpoints.json"))
	var hardpoints: Variant = JSON.parse_string(text)
	assert_true(hardpoints is Dictionary, GEN_ASSETS_HINT)
	if not hardpoints is Dictionary:
		return
	for chunk: Dictionary in (hardpoints as Dictionary).get("chunks", []):
		assert_false(String(chunk.get("mesh", "")).contains("_far"), "%s: cut from the full piece" % chunk.get("name", ""))
	assert_eq(manifest["mesh"].get("lods", []), manifest["pieces"]["hull"]["mesh"].get("lods", []), "the top-level mesh is the hull's")
