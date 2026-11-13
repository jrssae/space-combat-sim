extends GutTest
## The station drawn in sections (M7-T19, D72): one mesh per section with its own levels of detail, the drum's sections turning as
## one body, and the Cobra doors' near-only props instanced under the drum's waist section with their own atlas.

const GEN_ASSETS_HINT: String = "run scripts/gen_assets.sh and import first"

var world: WorldFrame
var station: StationStandin


func before_each() -> void:
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	station = StationStandin.new()
	if not station.build():
		station.free()
		station = null
		return
	world.spawn(station, world.to_universe(Vector3(0.0, 0.0, -9000.0)))


func _pieces() -> Dictionary:
	return MeshAssets.read_manifest(StationStandin.ASSET_ID).get("pieces", {})


func test_each_piece_draws_one_mesh_per_section_at_its_origin() -> void:
	if station == null:
		fail_test(GEN_ASSETS_HINT)
		return
	for name: String in ["drum", "frame"]:
		var piece: RenderPiece = station.drum_piece if name == "drum" else station.frame_piece
		var listed: Array = (_pieces()[name]["mesh"] as Dictionary).get("sections", [])
		assert_between(listed.size(), 10, 20, "%s: 10 to 20 sections" % name)
		assert_not_null(piece.sections, name)
		assert_null(piece.mesh(), "%s: no whole mesh is drawn" % name)
		var materials: Dictionary = {}
		for item: Dictionary in listed:
			var node: MeshInstance3D = piece.section_node(String(item["name"]))
			assert_not_null(node, String(item["name"]))
			if node == null:
				continue
			var origin: Array = item["origin"]
			assert_eq(node.position, Vector3(origin[0], origin[1], origin[2]))
			assert_not_null(node.mesh, "%s is imported" % item["name"])
			assert_eq(node.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			assert_eq(node.visibility_range_end, 0.0, "the hull is drawn at every distance")
			materials[node.mesh.surface_get_material(0)] = true
		assert_eq(materials.size(), 1, "%s: every section draws with the piece's one material" % name)


func test_the_big_sections_have_levels_of_detail_of_their_own() -> void:
	if station == null:
		fail_test(GEN_ASSETS_HINT)
		return
	var with_lods: int = 0
	var big: int = 0
	for piece: RenderPiece in [station.drum_piece, station.frame_piece]:
		for s: Dictionary in piece.sections.sections:
			if int(s["triangles"]) < 1500:
				continue
			big += 1
			var mesh: Mesh = piece.section_node(String(s["name"])).mesh
			var lods: Array = RenderingServer.mesh_get_surface(mesh.get_rid(), 0).get("lods", [])
			if lods.size() > 0:
				with_lods += 1
	assert_gt(big, 10)
	assert_gt(with_lods, big / 2, "the importer gave most big sections a chain of their own (%d of %d)" % [with_lods, big])


func test_the_drums_sections_turn_as_one_body() -> void:
	if station == null:
		fail_test(GEN_ASSETS_HINT)
		return
	station.set_process(false)
	station.drum_pivot.basis = Basis(Vector3.BACK, 1.1)
	var pivot: Transform3D = station.drum_pivot.global_transform
	for s: Dictionary in station.drum_piece.sections.sections:
		var node: MeshInstance3D = station.drum_piece.section_node(String(s["name"]))
		var expected: Transform3D = pivot * station.drum_piece.transform * Transform3D(Basis.IDENTITY, s["origin"])
		assert_true(node.global_transform.is_equal_approx(expected), "%s rides the drum" % s["name"])
	# A joint between two sections: the same point seen from either side lands at one place however the drum is turned.
	var sections: Array[Dictionary] = station.drum_piece.sections.sections
	for k: int in range(1, sections.size()):
		var joint := Vector3(300.0, 0.0, float(sections[k]["z0"]))
		var a: MeshInstance3D = station.drum_piece.section_node(String(sections[k - 1]["name"]))
		var b: MeshInstance3D = station.drum_piece.section_node(String(sections[k]["name"]))
		var from_a: Vector3 = a.global_transform * (joint - (sections[k - 1]["origin"] as Vector3))
		var from_b: Vector3 = b.global_transform * (joint - (sections[k]["origin"] as Vector3))
		assert_almost_eq(from_a, from_b, Vector3.ONE * 1e-3, "no seam opens at %s" % sections[k]["name"])


func test_the_cobra_doors_props_are_instanced_under_the_waist() -> void:
	if station == null:
		fail_test(GEN_ASSETS_HINT)
		return
	var props: Dictionary = _pieces()["drum"].get("props", {})
	assert_false(props.is_empty(), GEN_ASSETS_HINT)
	var nodes: Array[MultiMeshInstance3D] = station.drum_piece.prop_nodes()
	assert_eq(nodes.size(), 14, "twelve door leaves (M7-T05: six doors, two leaves each), the clamps and the gantries")
	var counts: Dictionary = {}
	for node: MultiMeshInstance3D in nodes:
		assert_eq(node.get_parent(), station.drum_piece.section_node("waist"))
		if String(node.name).begins_with("Props_DoorLeaf"):  # the leaves are the doors: drawn as far as the hull
			assert_gt(node.visibility_range_end, 10_000.0)
		else:
			assert_eq(node.visibility_range_end, float(props["near_m"]))
			assert_between(node.visibility_range_end, 1000.0, 2000.0, "about 1 to 2 km")
		assert_eq(node.visibility_range_end_margin, float(props["margin_m"]))
		assert_eq(node.visibility_range_fade_mode, GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF)
		assert_eq(node.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		assert_not_null(node.multimesh.mesh)
		var material := node.multimesh.mesh.surface_get_material(0) as StandardMaterial3D
		assert_not_null(material.albedo_texture if material != null else null, "the props' own atlas")
		assert_eq(material.albedo_texture.get_height(), 4096, "the props' atlas, not the hull's")
		counts[String(node.name)] = node.multimesh.instance_count
	assert_eq(counts.get("Props_Clamp"), 24)
	assert_eq(counts.get("Props_Gantry"), 24)
	assert_eq(counts.get("Props_DoorLeaf3R"), 4, "one of each leaf on every arm")


func test_a_door_leaf_lies_on_its_door() -> void:
	if station == null:
		fail_test(GEN_ASSETS_HINT)
		return
	var waist: MeshInstance3D = station.drum_piece.section_node("waist")
	var leaves: Array[Transform3D] = []
	for group: Dictionary in station.drum_piece.sections.groups_in("waist"):
		if group["kind"] == "door_leaf_1_r":
			leaves = group["transforms"]
	# (The instance transforms are read from the manifest's data: a headless run's rendering server keeps none.)
	assert_eq(leaves.size(), 4, "one per arm")
	# The top arm's door 1: on the top face between its creases (x 0, M7-T21), on the doors' plane (r 236.5), at station z 1 055.5
	# (the drum frame's z about its centre at z 3 000).
	var hits: int = 0
	for t: Transform3D in leaves:
		if (waist.transform * t.origin).distance_to(Vector3(0.0, 236.5, 1055.5 - 3000.0)) < 0.01:
			hits += 1
	assert_eq(hits, 1, "one on the top arm")
