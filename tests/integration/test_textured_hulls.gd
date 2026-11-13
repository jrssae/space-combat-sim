extends GutTest
## Every other hull textured (M4-T30d): a nav buoy, a raider's break-up chunk, a capital and the station draw their textured meshes;
## a capital switches between the box and the textured hull; the station's drum turns; a far dot takes its colour from the
## manifest's `mean_albedo`.

const GEN_ASSETS_HINT: String = "run scripts/gen_assets.sh and import first"
const RAIDER_SPEC: String = "res://assets/ships/raider_delta_v.tres"

var world: WorldFrame


func before_each() -> void:
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)


# The textured mesh a node draws: a visible MeshInstance3D under `node` whose first surface carries an albedo map.
func _textured_instances(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D and (node as MeshInstance3D).is_visible_in_tree() and (node as MeshInstance3D).mesh != null:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		var material: Material = mesh.surface_get_material(0) if mesh.get_surface_count() > 0 else null
		if (material is StandardMaterial3D and (material as StandardMaterial3D).albedo_texture != null) \
				or (material is ShaderMaterial and (material as ShaderMaterial).get_shader_parameter(&"albedo_map") != null):
			out.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		out.append_array(_textured_instances(child))
	return out


func test_a_buoy_draws_its_textured_mesh() -> void:
	var buoy: NavBuoy = NavBuoy.create("NAV TEST")
	world.spawn(buoy, world.to_universe(Vector3(0.0, 0.0, -20.0)))
	var textured: Mesh = MeshAssets.for_asset("nav_buoy")
	assert_not_null(textured, GEN_ASSETS_HINT)
	if textured == null:
		return
	var drawn: Array[MeshInstance3D] = _textured_instances(buoy)
	assert_eq(drawn.size(), 1, "one textured body")
	assert_same(drawn[0].mesh, textured)
	assert_true(buoy.beacon.visible, "the beacon still shines")


func test_a_raider_chunk_draws_its_mesh_on_the_parents_materials() -> void:
	var spec := load(RAIDER_SPEC) as ShipSpec
	var hardpoints: Hardpoints = Hardpoints.load_file(spec.hardpoints_path())
	assert_true(hardpoints.valid, GEN_ASSETS_HINT)
	if not hardpoints.valid:
		return
	var entry: Dictionary = hardpoints.chunks[0]
	assert_true(String(entry.get("mesh", "")).ends_with(".glb"), "hardpoints name the chunk's mesh")
	var parent: Mesh = MeshAssets.for_asset("raider_fighter")
	var chunk: DebrisChunk = DebrisChunk.create(entry, ShipSpec.ASSET_ROOT.path_join("raider_fighter"))
	world.add_child(chunk)
	chunk.launch(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -30.0)), Vector3.ZERO, Vector3.ZERO)
	var drawn: Array[MeshInstance3D] = _textured_instances(chunk)
	assert_eq(drawn.size(), 1)
	if drawn.is_empty():
		return
	assert_same(drawn[0].mesh.surface_get_material(0), parent.surface_get_material(0), "the parent's maps: it instances with the hull")
	assert_lt(drawn[0].mesh.get_faces().size(), parent.get_faces().size())


func test_a_capital_draws_its_textured_box() -> void:
	var cap: CapitalStandin = CapitalStandin.create(&"destroyer", Factions.EARTH_ALLIANCE, "CAP 1", Vector3.ZERO)
	world.spawn(cap, world.to_universe(Vector3(0.0, 0.0, -1500.0)))
	cap.set_look(CapitalStandin.LOOK_MESH)
	var piece: RenderPiece = cap.hull_piece()
	assert_not_null(piece, GEN_ASSETS_HINT)
	if piece == null:
		return
	assert_true(piece.is_mesh_shown())
	assert_eq(_textured_instances(cap).size(), 1)
	assert_eq(piece.mesh().get_aabb().size.round(), Vector3(110.0, 70.0, 600.0))
	assert_false((cap.get_node(^"HullMesh") as Node3D).visible)


func test_a_capital_takes_the_box_or_the_textured_mesh_look() -> void:
	var cap: CapitalStandin = CapitalStandin.create(&"cruiser", Factions.EARTH_ALLIANCE, "CAP 1", Vector3.ZERO)
	world.spawn(cap, world.to_universe(Vector3(0.0, 0.0, -800.0)))
	assert_eq(cap.look, CapitalStandin.LOOK_BOX)
	cap.set_look(CapitalStandin.LOOK_MESH)
	var piece: RenderPiece = cap.hull_piece()
	assert_not_null(piece, GEN_ASSETS_HINT)
	if piece == null:
		return
	assert_false((cap.get_node(^"HullMesh") as Node3D).visible)
	assert_true(piece.is_mesh_shown())
	assert_eq(piece.mesh().get_aabb().size.round(), Vector3(60.0, 40.0, 300.0))
	cap.set_look(CapitalStandin.LOOK_BOX)
	assert_true((cap.get_node(^"HullMesh") as Node3D).visible)
	assert_false(piece.visible)


func test_the_station_draws_both_pieces_textured() -> void:
	var station := StationStandin.new()
	assert_true(station.build(), GEN_ASSETS_HINT)
	world.spawn(station, world.to_universe(Vector3(0.0, 0.0, -6000.0)))
	var sections: int = station.frame_piece.sections.sections.size() + station.drum_piece.sections.sections.size()
	assert_eq(_textured_instances(station).size(), sections, "the frame's and the turning drum's sections (M7-T19)")
	assert_almost_eq(station.drum_piece.bounds().size.x, 2.0 * 417.0, 5.0, "the bands across (M7-T04)")


func test_a_far_dot_takes_the_manifests_mean_albedo() -> void:
	var manifest: Dictionary = MeshAssets.read_manifest("raider_fighter")
	var mean: Array = (manifest.get("mesh", {}) as Dictionary).get("mean_albedo", [])
	assert_eq(mean.size(), 3, GEN_ASSETS_HINT)
	if mean.size() != 3:
		return
	var srgb := Color(float(mean[0]), float(mean[1]), float(mean[2])).linear_to_srgb()
	var lit := Color(srgb.r * FarDots.LIGHT_LEVEL, srgb.g * FarDots.LIGHT_LEVEL, srgb.b * FarDots.LIGHT_LEVEL).srgb_to_linear()
	var paint: Color = FarDots.asset_paint("raider_fighter")
	assert_almost_eq(paint.r, lit.r, 1e-4)
	assert_almost_eq(paint.g, lit.g, 1e-4)
	assert_almost_eq(paint.b, lit.b, 1e-4)
	assert_eq(FarDots.asset_paint("no_such_asset"), Color(FarDots.DEFAULT_PAINT.r * FarDots.LIGHT_LEVEL,
			FarDots.DEFAULT_PAINT.g * FarDots.LIGHT_LEVEL, FarDots.DEFAULT_PAINT.b * FarDots.LIGHT_LEVEL).srgb_to_linear(),
			"no manifest: the default paint")


func test_the_station_drum_turns_about_its_long_axis() -> void:
	var station := StationStandin.new()
	assert_true(station.build(), GEN_ASSETS_HINT)
	world.spawn(station, world.to_universe(Vector3(0.0, 0.0, -3000.0)))
	await get_tree().process_frame
	assert_true(station.frame_piece.is_mesh_shown())
	assert_true(station.drum_piece.is_mesh_shown())
	var before: Basis = station.drum_pivot.basis
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gt(before.z.dot(station.drum_pivot.basis.z), 0.999, "turns about its long axis")
	assert_ne(before.x, station.drum_pivot.basis.x, "the drum turns")
	assert_almost_eq(station.length_m, 8000.0, 1.0)
