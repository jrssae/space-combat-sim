extends GutTest
## The civilian ships as textured meshes (M5-T27, AC12): the nine hulls, the Bokmai's cargo pod and every turret model import as
## meshes with their maps, at the manifest's size; each break-up chunk draws on its hull's materials; the hardpoints parse.

const GEN_ASSETS_HINT: String = "run scripts/gen_assets.sh and import first"
const HULLS: Array[String] = [
	"saturn_3_freighter", "saturn_4_transport", "saturn_4_tanker", "saturn_8_transport", "saturn_8_tanker",
	"skylark_transport", "narn_transport", "centauri_brezebel", "brakiri_bokmai",
]
const POD_HULL: String = "brakiri_bokmai"
## Godot's importer may weld a few vertices; the box must still match the manifest's to a centimetre.
const AABB_TOLERANCE_M: float = 0.01


func _dir(asset_id: String) -> String:
	return ShipSpec.ASSET_ROOT.path_join(asset_id)


# Whether every surface of `mesh` draws with an albedo map (the textured material MeshAssets builds).
func _is_textured(mesh: Mesh) -> bool:
	if mesh == null or mesh.get_surface_count() == 0:
		return false
	for i: int in mesh.get_surface_count():
		var material := mesh.surface_get_material(i) as StandardMaterial3D
		if material == null or material.albedo_texture == null or material.normal_texture == null:
			return false
	return true


# `mesh` matches its manifest section: textured, the same box, the same triangle count.
func _assert_matches(mesh: Mesh, section: Dictionary, label: String) -> void:
	assert_not_null(mesh, "%s imported (%s)" % [label, GEN_ASSETS_HINT])
	if mesh == null:
		return
	assert_true(_is_textured(mesh), "%s draws with its maps" % label)
	var lo: Array = section.get("aabb_min", [])
	var hi: Array = section.get("aabb_max", [])
	var aabb: AABB = mesh.get_aabb()
	var want := AABB(Vector3(lo[0], lo[1], lo[2]), Vector3(hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]))
	assert_almost_eq(aabb.position, want.position, Vector3.ONE * AABB_TOLERANCE_M, "%s box corner" % label)
	assert_almost_eq(aabb.size, want.size, Vector3.ONE * AABB_TOLERANCE_M, "%s box size" % label)
	assert_eq(mesh.get_faces().size() / 3, int(section.get("triangles", -1)), "%s triangles" % label)


func test_every_hull_imports_as_a_textured_mesh() -> void:
	for asset_id: String in HULLS:
		var section: Dictionary = MeshAssets.read_manifest(asset_id).get("mesh", {})
		assert_false(section.is_empty(), "%s has a mesh section (%s)" % [asset_id, GEN_ASSETS_HINT])
		if section.is_empty():
			continue
		assert_eq(String(section.get("file", "")), asset_id + ".glb")
		_assert_matches(MeshAssets.for_asset(asset_id), section, asset_id)


func test_every_turret_model_imports_as_a_textured_mesh() -> void:
	for asset_id: String in HULLS:
		var turret: Dictionary = MeshAssets.read_manifest(asset_id).get("turret", {})
		var section: Dictionary = turret.get("mesh", {})
		assert_false(section.is_empty(), "%s names its turret's mesh (%s)" % [asset_id, GEN_ASSETS_HINT])
		if section.is_empty():
			continue
		_assert_matches(MeshAssets.load_textured(_dir(asset_id), section), section, asset_id + " turret")


func test_the_bokmai_pod_imports_as_a_textured_mesh() -> void:
	var pod: Dictionary = MeshAssets.read_manifest(POD_HULL).get("pod", {})
	var section: Dictionary = pod.get("mesh", {})
	assert_false(section.is_empty(), "the Bokmai names its pod's mesh (%s)" % GEN_ASSETS_HINT)
	if section.is_empty():
		return
	_assert_matches(MeshAssets.load_textured(_dir(POD_HULL), section), section, "pod")


func test_hardpoints_parse_and_every_chunk_draws_on_its_hulls_materials() -> void:
	for asset_id: String in HULLS:
		var hardpoints: Hardpoints = Hardpoints.load_file(_dir(asset_id).path_join("hardpoints.json"))
		assert_true(hardpoints.valid, "%s hardpoints parse (%s)" % [asset_id, GEN_ASSETS_HINT])
		if not hardpoints.valid:
			continue
		var parent: Mesh = MeshAssets.for_asset(asset_id)
		if parent == null:
			continue
		var faces: int = 0
		for entry: Dictionary in hardpoints.chunks:
			var chunk: Mesh = MeshAssets.chunk_mesh(_dir(asset_id), String(entry.get("mesh", "")))
			assert_not_null(chunk, "%s chunk %s" % [asset_id, entry.get("name")])
			if chunk == null:
				continue
			assert_same(chunk.surface_get_material(0), parent.surface_get_material(0), "%s: a chunk shares its hull's maps" % asset_id)
			faces += chunk.get_faces().size()
		assert_eq(faces, parent.get_faces().size(), "%s: the chunks share out the hull's triangles" % asset_id)
