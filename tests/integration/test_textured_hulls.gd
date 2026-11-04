extends GutTest
## Every other hull textured (M4-T30d): with `ship_render` at its new default, `mesh`, a nav buoy, a raider's break-up chunk, a capital
## and the station draw their textured meshes with no splat node shown; a far dot takes its colour from the manifest's `mean_albedo`;
## the buoy and the chunk still switch back to splats for the comparison.

const GEN_ASSETS_HINT: String = "run scripts/gen_assets.sh and import first"
const RAIDER_SPEC: String = "res://assets/ships/raider_delta_v.tres"

var world: WorldFrame


func before_each() -> void:
	Settings.set_value(&"ship_render", SettingsSchema.ENTRIES[&"ship_render"]["default"])
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)


func after_each() -> void:
	Settings.set_value(&"ship_render", SettingsSchema.ENTRIES[&"ship_render"]["default"])


# Splat nodes under `node` that would be drawn.
func _visible_splats(node: Node) -> int:
	var n: int = 1 if node is GaussianSplatNode and (node as Node3D).is_visible_in_tree() else 0
	for child: Node in node.get_children():
		n += _visible_splats(child)
	return n


func _all_splats(node: Node) -> int:
	var n: int = 1 if node is GaussianSplatNode else 0
	for child: Node in node.get_children():
		n += _all_splats(child)
	return n


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


func test_the_default_render_path_is_the_mesh() -> void:
	assert_eq(SettingsSchema.ENTRIES[&"ship_render"]["default"], &"mesh")
	assert_true((SettingsSchema.ENTRIES[&"ship_render"]["choices"] as Array).has(&"splat"), "the splat path stays for comparison until T31")


func test_a_buoy_draws_its_textured_mesh_and_switches_back_to_splats() -> void:
	var buoy: NavBuoy = NavBuoy.create("NAV TEST")
	world.spawn(buoy, world.to_universe(Vector3(0.0, 0.0, -20.0)))
	var textured: Mesh = MeshAssets.for_asset("nav_buoy")
	assert_not_null(textured, GEN_ASSETS_HINT)
	if textured == null:
		return
	var drawn: Array[MeshInstance3D] = _textured_instances(buoy)
	assert_eq(drawn.size(), 1, "one textured body")
	assert_same(drawn[0].mesh, textured)
	assert_eq(_visible_splats(buoy), 0)
	assert_true(buoy.beacon.visible, "the beacon still shines")
	Settings.set_value(&"ship_render", &"splat")
	assert_eq(_visible_splats(buoy), 1, "the comparison path")
	assert_eq(_textured_instances(buoy).size(), 0)
	Settings.set_value(&"ship_render", &"mesh")
	assert_eq(_textured_instances(buoy).size(), 1, "live")


func test_a_raider_chunk_draws_its_mesh_on_the_parents_materials() -> void:
	var spec := load(RAIDER_SPEC) as ShipSpec
	var hardpoints: Hardpoints = Hardpoints.load_file(spec.hardpoints_path())
	assert_true(hardpoints.valid, GEN_ASSETS_HINT)
	if not hardpoints.valid:
		return
	var entry: Dictionary = hardpoints.chunks[0]
	assert_true(String(entry.get("mesh", "")).ends_with(".glb"), "hardpoints name the chunk's mesh")
	var parent: Mesh = MeshAssets.for_asset("raider_fighter")
	var chunk: DebrisChunk = DebrisChunk.create(entry, ShipSpec.ASSET_ROOT.path_join("raider_fighter"), true)
	world.add_child(chunk)
	chunk.launch(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -30.0)), Vector3.ZERO, Vector3.ZERO)
	var drawn: Array[MeshInstance3D] = _textured_instances(chunk)
	assert_eq(drawn.size(), 1)
	if drawn.is_empty():
		return
	assert_same(drawn[0].mesh.surface_get_material(0), parent.surface_get_material(0), "the parent's maps: it instances with the hull")
	assert_lt(drawn[0].mesh.get_faces().size(), parent.get_faces().size())
	assert_eq(_visible_splats(chunk), 0)
	Settings.set_value(&"ship_render", &"splat")
	assert_eq(_visible_splats(chunk), 1)


func test_a_capital_draws_its_textured_box_and_owns_no_splats() -> void:
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
	assert_eq(_all_splats(cap), 0, "the splat look went from the stand-ins (T31 removes the rest)")
	assert_false((cap.get_node(^"HullMesh") as Node3D).visible)


func test_the_station_draws_both_pieces_textured_and_owns_no_splats() -> void:
	var station := StationStandin.new()
	assert_true(station.build(), GEN_ASSETS_HINT)
	world.spawn(station, world.to_universe(Vector3(0.0, 0.0, -6000.0)))
	assert_eq(_textured_instances(station).size(), 2, "the frame and the turning drum")
	assert_eq(_all_splats(station), 0)
	assert_almost_eq(station.drum_piece.mesh().get_aabb().size.x, 8000.0 / 9.0, 5.0)


func test_a_far_dot_takes_the_manifests_mean_albedo() -> void:
	var manifest: Dictionary = SplatLod.read_manifest("raider_fighter")
	var mean: Array = (manifest.get("mesh", {}) as Dictionary).get("mean_albedo", [])
	assert_eq(mean.size(), 3, GEN_ASSETS_HINT)
	if mean.size() != 3:
		return
	var srgb := Color(float(mean[0]), float(mean[1]), float(mean[2])).linear_to_srgb()
	var lit := Color(srgb.r * FarDots.LIGHT_LEVEL, srgb.g * FarDots.LIGHT_LEVEL, srgb.b * FarDots.LIGHT_LEVEL).srgb_to_linear()
	var paint: Color = FarDots.asset_paint("raider_fighter", null)
	assert_almost_eq(paint.r, lit.r, 1e-4)
	assert_almost_eq(paint.g, lit.g, 1e-4)
	assert_almost_eq(paint.b, lit.b, 1e-4)
	assert_eq(FarDots.asset_paint("no_such_asset", null), Color(FarDots.DEFAULT_PAINT.r * FarDots.LIGHT_LEVEL,
			FarDots.DEFAULT_PAINT.g * FarDots.LIGHT_LEVEL, FarDots.DEFAULT_PAINT.b * FarDots.LIGHT_LEVEL).srgb_to_linear(),
			"no manifest and no splats: the default paint")
