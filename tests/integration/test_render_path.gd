extends GutTest
## The render comparison's switch (M4-T27, Q24, architecture §17.16): the same scene builds with splat hulls or with the painted mesh
## of the same surface, by `settings.ship_render`, live; hybrid draws the mesh past `settings.ship_mesh_beyond_m`; far dots stay.
## The capitals and the station take the same two looks.

var world: WorldFrame
var projectiles: Node3D
var pool: ShipPool
var player: Combatant
var camera: Camera3D


func before_each() -> void:
	Settings.set_value(&"ship_render", &"splat")
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	projectiles = Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	pool = ShipPool.new()
	pool.name = "Ships"
	world.add_child(pool)
	pool.world = world
	pool.projectiles = projectiles
	player = ShipAssembly.build(load("res://assets/ships/starfury_aurora.tres") as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE,
		ShipAssembly.OPT_DISPLAY_NAME: "PLAYER",
		ShipAssembly.OPT_CONSOLE_OWNER: true,
	})
	world.spawn(player.ship, world.to_universe(Vector3.ZERO))
	pool.player = player.ship
	assert_eq(pool.prepare(ShipPool.DEFAULT_TYPE, 1), 1)
	camera = Camera3D.new()
	world.add_child(camera)
	camera.make_current()


func after_each() -> void:
	Settings.set_value(&"ship_render", &"splat")
	Settings.set_value(&"ship_mesh_beyond_m", 400.0)


func _raider(at: Vector3) -> Ship:
	var made: Combatant = pool.acquire("RAIDER 1", world.to_universe(at), Basis.IDENTITY, Vector3.ZERO, null, ShipPool.DEFAULT_TYPE)
	assert_not_null(made)
	return made.ship


func _splat_nodes_shown(ship: Ship) -> int:
	var n: int = 0
	for node: GaussianSplatNode in ship.splat_nodes():
		n += 1 if node.visible else 0
	return n


func _switch(ship: Ship) -> void:
	(ship.get_node(^"LodSwitcher") as LodSwitcher).update()


func test_mesh_draws_the_painted_mesh_and_no_splats_live() -> void:
	var ship: Ship = _raider(Vector3(0.0, 0.0, -100.0))
	assert_not_null(ship.paint_mesh(), "run scripts/gen_assets.sh and import first")
	assert_eq(_splat_nodes_shown(ship), 1, "splats by default")
	assert_false(ship.is_drawing_paint_mesh())
	Settings.set_value(&"ship_render", &"mesh")
	assert_true(ship.is_drawing_paint_mesh())
	assert_eq(_splat_nodes_shown(ship), 0)
	assert_eq(ship.visible_splat_count(), 0)
	assert_true(ship.hull_depth_proxy.visible, "the lean ship's one hull node draws the mesh")
	assert_same(ship.hull_depth_proxy.mesh, ship.paint_mesh())
	assert_null(ship.hull_depth_proxy.material_override, "the mesh's own paint materials")
	Settings.set_value(&"ship_render", &"splat")
	assert_eq(_splat_nodes_shown(ship), 1)
	assert_ne(ship.hull_depth_proxy.mesh, ship.paint_mesh(), "back to the depth proxy")


func test_the_players_ship_draws_its_mesh_and_hides_the_proxy() -> void:
	var ship: Ship = player.ship
	Settings.set_value(&"ship_render", &"mesh")
	assert_true(ship.is_drawing_paint_mesh())
	assert_true(ship.hull_mesh_fallback.visible)
	assert_same(ship.hull_mesh_fallback.mesh, ship.paint_mesh())
	assert_false(ship.hull_depth_proxy.visible, "the mesh writes depth itself")
	ship.set_cockpit_interior_visible(true)
	assert_false(ship.is_drawing_paint_mesh(), "inside, the cockpit view keeps the fallback mesh it was built around")
	assert_same(ship.hull_mesh_fallback.mesh, ship.fallback_mesh())
	ship.set_cockpit_interior_visible(false)


func test_hybrid_draws_splats_near_and_the_mesh_far_with_hysteresis() -> void:
	Settings.set_value(&"ship_render", &"hybrid")
	Settings.set_value(&"ship_mesh_beyond_m", 400.0)
	var ship: Ship = _raider(Vector3(0.0, 0.0, -300.0))
	_switch(ship)
	assert_false(ship.is_drawing_paint_mesh(), "300 m: splats")
	ship.global_position = Vector3(0.0, 0.0, -500.0)
	_switch(ship)
	assert_true(ship.is_drawing_paint_mesh(), "500 m: the mesh")
	assert_eq(_splat_nodes_shown(ship), 0)
	ship.global_position = Vector3(0.0, 0.0, -380.0)
	_switch(ship)
	assert_true(ship.is_drawing_paint_mesh(), "a tenth inside it holds")
	ship.global_position = Vector3(0.0, 0.0, -350.0)
	_switch(ship)
	assert_false(ship.is_drawing_paint_mesh())


func test_far_dots_stay_on_the_mesh_path() -> void:
	Settings.set_value(&"ship_render", &"mesh")
	var ship: Ship = _raider(Vector3(0.0, 0.0, -5000.0))
	_switch(ship)
	assert_true(ship.is_far_dot())
	assert_false(ship.hull_depth_proxy.visible, "a dot draws no hull")


func test_a_capital_takes_the_box_splat_or_mesh_look() -> void:
	var cap: CapitalStandin = CapitalStandin.create(&"cruiser", Factions.EARTH_ALLIANCE, "CAP 1", Vector3.ZERO)
	world.spawn(cap, world.to_universe(Vector3(0.0, 0.0, -800.0)))
	assert_eq(cap.look, CapitalStandin.LOOK_BOX)
	cap.set_look(CapitalStandin.LOOK_SPLAT)
	var piece: RenderPiece = cap.hull_piece()
	assert_not_null(piece, "run scripts/gen_assets.sh and import first")
	if piece == null:
		return
	assert_false((cap.get_node(^"HullMesh") as Node3D).visible)
	assert_gt(piece.visible_splats(), 0)
	assert_false(piece.is_mesh_shown())
	cap.set_look(CapitalStandin.LOOK_MESH)
	assert_eq(piece.visible_splats(), 0)
	assert_true(piece.is_mesh_shown())
	assert_eq(piece.mesh().get_aabb().size.round(), Vector3(60.0, 40.0, 300.0))
	cap.set_look(CapitalStandin.LOOK_BOX)
	assert_true((cap.get_node(^"HullMesh") as Node3D).visible)
	assert_false(piece.visible)


func test_the_station_builds_both_ways_with_a_turning_drum() -> void:
	var station := StationStandin.new()
	assert_true(station.build(), "run scripts/gen_assets.sh and import first")
	world.spawn(station, world.to_universe(Vector3(0.0, 0.0, -3000.0)))
	station.set_look(RenderPiece.Look.SPLAT)
	await get_tree().process_frame
	assert_gt(station.visible_splats(), 0)
	assert_false(station.frame_piece.is_mesh_shown())
	var before: Basis = station.drum_pivot.basis
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gt(before.z.dot(station.drum_pivot.basis.z), 0.999, "turns about its long axis")
	assert_ne(before.x, station.drum_pivot.basis.x, "the drum turns")
	station.set_look(RenderPiece.Look.MESH)
	assert_eq(station.visible_splats(), 0)
	assert_true(station.frame_piece.is_mesh_shown())
	assert_true(station.drum_piece.is_mesh_shown())
	var drum_box: AABB = station.drum_piece.mesh().get_aabb()
	assert_almost_eq(drum_box.size.x, 8000.0 / 9.0, 5.0, "the drum is a ninth of the length across")
	assert_almost_eq(station.length_m, 8000.0, 1.0)
