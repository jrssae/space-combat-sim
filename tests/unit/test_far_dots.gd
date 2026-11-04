extends GutTest
## Far-ship dots (M4-T11, architecture §17.10): past `settings.far_ship_dot_m` from the camera an AI ship draws no splat node,
## proxy, plume or marker, only a point in the world's one `FarDots` multimesh; back inside it shows its level of detail again.
## The dot follows the ship every frame and a rebase at once; a parked ship leaves none; the player's ship is never a dot; and
## nothing here makes GDGS start a render state of its own (headless has none to count: the GPU check reads `render states 1`).

const SH_C0: float = 0.28209479177387814

var world: WorldFrame
var projectiles: Node3D
var pool: ShipPool
var camera: Camera3D
var _size_backup: Vector2i = Vector2i.ZERO
var _far_backup: Variant = null


func before_each() -> void:
	# These cases count splat levels: the splat path (the default is the mesh from M4-T30d; test_render_path has dots on the mesh path).
	Settings.set_value(&"ship_render", &"splat")
	# Headless windows are 64 x 64 px; the level of detail is about a real screen.
	_size_backup = get_tree().root.size
	get_tree().root.size = Vector2i(1920, 1080)
	_far_backup = Settings.get_value(&"far_ship_dot_m")
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
	assert_eq(pool.prepare(ShipPool.DEFAULT_TYPE, 2), 2)
	camera = Camera3D.new()
	camera.fov = 75.0
	camera.far = 50000.0
	add_child_autofree(camera)
	camera.make_current()


func after_each() -> void:
	get_tree().root.size = _size_backup
	Settings.set_value(&"far_ship_dot_m", _far_backup)
	Settings.set_value(&"ship_render", SettingsSchema.ENTRIES[&"ship_render"]["default"])


func _far_m() -> float:
	return float(Settings.get_value(&"far_ship_dot_m"))


func _acquire(at: Vector3) -> Combatant:
	var made: Combatant = pool.acquire("RAIDER", world.to_universe(at), Basis.IDENTITY, Vector3.ZERO, null, ShipPool.DEFAULT_TYPE)
	assert_not_null(made)
	return made


func _dots() -> FarDots:
	return FarDots.of(world)


func _visible_levels(ship: Ship) -> int:
	var n: int = 0
	for node: GaussianSplatNode in ship.splat_nodes():
		n += 1 if node.is_visible_in_tree() else 0
	return n


func _frames(n: int = 2) -> void:
	for i: int in n:
		await get_tree().process_frame


func _move(ship: Ship, at: Vector3) -> void:
	ship.global_position = at
	ship.reset_physics_interpolation()


# --- the dot's paint ---------------------------------------------------------------------------------------------------


func _splats(colours: Array[Color], opacities: Array[float]) -> GaussianResource:
	var res := GaussianResource.new()
	res.point_count = colours.size()
	var data := PackedFloat32Array()
	data.resize(60 * colours.size())
	for i: int in colours.size():
		data[60 * i + 10] = opacities[i]
		data[60 * i + 12] = (colours[i].r - 0.5) / SH_C0
		data[60 * i + 13] = (colours[i].g - 0.5) / SH_C0
		data[60 * i + 14] = (colours[i].b - 0.5) / SH_C0
	res.point_data_float = data
	return res


func test_the_paint_is_the_opacity_weighted_mean_of_the_splats() -> void:
	var res: GaussianResource = _splats([Color(1.0, 0.0, 0.0), Color(0.0, 0.0, 1.0)] as Array[Color], [0.75, 0.25] as Array[float])
	var paint: Color = FarDots.paint_color(res)
	assert_almost_eq(paint.r, 0.75, 1e-4)
	assert_almost_eq(paint.g, 0.0, 1e-4)
	assert_almost_eq(paint.b, 0.25, 1e-4)


func test_no_splats_give_a_neutral_grey() -> void:
	assert_eq(FarDots.paint_color(null), FarDots.DEFAULT_PAINT)
	assert_eq(FarDots.paint_color(GaussianResource.new()), FarDots.DEFAULT_PAINT)


# --- far and near ------------------------------------------------------------------------------------------------------


func test_a_ship_past_the_dot_distance_shows_no_splat_node_and_one_dot() -> void:
	var raider: Combatant = _acquire(Vector3(0.0, 0.0, -(_far_m() + 500.0)))
	await _frames()
	assert_true(raider.ship.is_far_dot())
	assert_eq(_visible_levels(raider.ship), 0, "no splat level")
	assert_false(raider.ship.hull_depth_proxy.is_visible_in_tree(), "no proxy")
	assert_false(raider.thrusters.is_visible_in_tree(), "no plumes")
	assert_false((raider.ship.get_node(^"RunningLights") as Node3D).is_visible_in_tree(), "no markers")
	assert_not_null(_dots())
	assert_eq(_dots().dot_count(), 1, "one dot")
	assert_almost_eq(_dots().dot_position(0), raider.ship.global_position, Vector3.ONE * 1e-3)
	assert_almost_eq(_dots().dot_radius(0), raider.ship.bounding_radius(), 1e-4, "sized by the hull")


func test_back_inside_it_shows_its_level_and_the_dot_goes() -> void:
	var raider: Combatant = _acquire(Vector3(0.0, 0.0, -(_far_m() + 500.0)))
	await _frames()
	assert_eq(_dots().dot_count(), 1)
	_move(raider.ship, Vector3(0.0, 0.0, -1000.0))
	await _frames()
	assert_false(raider.ship.is_far_dot())
	assert_eq(_visible_levels(raider.ship), 1, "one level again")
	assert_true(raider.ship.splat_nodes()[raider.ship.lod_levels().find(raider.ship.lod_level())].visible, "the level it is at")
	assert_true(raider.ship.hull_depth_proxy.is_visible_in_tree())
	assert_eq(_dots().dot_count(), 0)


func test_the_dot_holds_until_the_ship_is_a_tenth_inside() -> void:
	var raider: Combatant = _acquire(Vector3(0.0, 0.0, -(_far_m() + 500.0)))
	await _frames()
	_move(raider.ship, Vector3(0.0, 0.0, -0.95 * _far_m()))
	await _frames()
	assert_true(raider.ship.is_far_dot(), "still a dot just inside")
	_move(raider.ship, Vector3(0.0, 0.0, -0.85 * _far_m()))
	await _frames()
	assert_false(raider.ship.is_far_dot(), "detail again a tenth inside")
	_move(raider.ship, Vector3(0.0, 0.0, -0.99 * _far_m()))
	await _frames()
	assert_false(raider.ship.is_far_dot(), "and no dot until past the distance")


func test_the_dot_tracks_the_ship_each_frame() -> void:
	var raider: Combatant = _acquire(Vector3(0.0, 0.0, -(_far_m() + 500.0)))
	await _frames()
	for step: int in 3:
		var at := Vector3(100.0 * step, 50.0, -(_far_m() + 800.0 + 200.0 * step))
		_move(raider.ship, at)
		await _frames(2)  # `process_frame` fires before the nodes' `_process`: the second wait sees the first frame's dots
		assert_almost_eq(_dots().dot_position(0), raider.ship.get_global_transform_interpolated().origin, Vector3.ONE * 1e-3,
				"frame %d" % step)


func test_the_rebase_shifts_the_dots_at_once() -> void:
	var raider: Combatant = _acquire(Vector3(0.0, 0.0, -(_far_m() + 500.0)))
	await _frames()
	var before: Vector3 = _dots().dot_position(0)
	world.rebase(Vector3(1000.0, 0.0, 0.0))
	assert_almost_eq(_dots().dot_position(0), before - Vector3(1000.0, 0.0, 0.0), Vector3.ONE * 1e-3, "no frame at the old place")
	assert_almost_eq(_dots().dot_position(0), raider.ship.global_position, Vector3.ONE * 1e-3)


func test_a_parked_ship_leaves_no_dot() -> void:
	var raider: Combatant = _acquire(Vector3(0.0, 0.0, -(_far_m() + 500.0)))
	await _frames()
	assert_eq(_dots().dot_count(), 1)
	pool.release(raider)
	await _frames()
	assert_eq(_dots().dot_count(), 0)


func test_two_far_ships_are_two_dots_in_one_multimesh() -> void:
	_acquire(Vector3(0.0, 0.0, -(_far_m() + 500.0)))
	_acquire(Vector3(300.0, 0.0, -(_far_m() + 900.0)))
	await _frames()
	assert_eq(_dots().dot_count(), 2)
	assert_eq(_dots().multimesh.visible_instance_count, 2)
	var dots_nodes: int = 0
	for child: Node in world.get_children():
		dots_nodes += 1 if child is FarDots else 0
	assert_eq(dots_nodes, 1, "one multimesh for the world")


func test_the_players_ship_is_never_a_dot() -> void:
	var player: Combatant = ShipAssembly.build(load("res://assets/ships/starfury_aurora.tres") as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE,
		ShipAssembly.OPT_CONSOLE_OWNER: true,
	})
	world.spawn(player.ship, world.to_universe(Vector3(0.0, 0.0, -(_far_m() + 2000.0))))
	await _frames()
	assert_false(player.ship.is_far_dot())
	assert_eq(_visible_levels(player.ship), 1)


func test_the_setting_moves_the_distance() -> void:
	var raider: Combatant = _acquire(Vector3(0.0, 0.0, -(_far_m() + 500.0)))
	await _frames()
	assert_true(raider.ship.is_far_dot())
	Settings.set_value(&"far_ship_dot_m", _far_m() + 5000.0)
	await _frames()
	assert_false(raider.ship.is_far_dot(), "inside the new distance")


func test_the_dots_start_no_render_state_or_viewport() -> void:
	_acquire(Vector3(0.0, 0.0, -(_far_m() + 500.0)))
	await _frames()
	assert_true(_dots() is MultiMeshInstance3D, "a plain multimesh, not a viewport")
	assert_lte(int(GaussianRenderManager.get_stats().get("render_states", 0)), 1, "GDGS's render state count stays at most 1")
