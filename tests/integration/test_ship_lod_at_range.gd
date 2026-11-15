extends GutTest
## Every ship keeps its shape at range (M7-T26): each hull's textured mesh carries the importer's levels of detail, thin enough at
## the coarsest for a ship a few pixels across; a ship turns into a far dot by its size on screen, not a fixed distance, so a
## 100 m freighter holds its shape ten times farther out than a fighter; and there is no stage where a ship is drawn as a disc
## bigger than a few pixels (the grey sphere the maintainer saw past 2.7 km).

## The most triangles any hull's coarsest level may keep: what a ship a few pixels across costs (the raider's 7 086 is the most;
## its thin, open panels leave the importer little to fold).
const COARSEST_MAX_TRIANGLES: int = 8000
## The farthest view checked, m (the cameras' far plane).
const FAR_M: float = 50000.0

var world: WorldFrame
var projectiles: Node3D
var pool: ShipPool
var camera: Camera3D
var _size_backup: Vector2i = Vector2i.ZERO


func before_each() -> void:
	# Headless windows are 64 x 64 px; the rule is about a real screen.
	_size_backup = get_tree().root.size
	get_tree().root.size = Vector2i(1920, 1080)
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
	camera = Camera3D.new()
	camera.fov = 75.0
	camera.far = FAR_M
	add_child_autofree(camera)
	camera.make_current()


func after_each() -> void:
	get_tree().root.size = _size_backup


# Every AI hull type: the catalog less the player's own (the ally flies the same hull).
func _ai_types() -> Array[StringName]:
	var out: Array[StringName] = []
	for type: StringName in ShipCatalog.types():
		if type != ShipCatalog.PLAYER_TYPE:
			out.append(type)
	return out


func _acquire(type: StringName) -> Combatant:
	assert_eq(pool.prepare(type, 1), 1, "%s builds" % type)
	var made: Combatant = pool.acquire(String(type).to_upper(), world.to_universe(Vector3(0.0, 0.0, -500.0)), Basis.IDENTITY,
			Vector3.ZERO, null, type)
	assert_not_null(made)
	return made


# Triangles in each of `mesh`'s levels on its first surface (the hull), full detail first: the importer's levels are kept in the
# mesh's surface data, readable without a renderer.
static func _level_triangles(mesh: Mesh) -> Array[int]:
	var out: Array[int] = []
	var surfaces: Array = mesh.get("_surfaces")
	if surfaces.is_empty():
		return out
	var hull: Dictionary = surfaces[0]
	var wide: bool = int(hull.get("vertex_count", 0)) > 65535
	out.append(int(hull.get("index_count", 0)) / 3)
	var lods: Array = hull.get("lods", [])
	for k: int in range(1, lods.size(), 2):
		var data: Variant = lods[k]
		var indices: int = (data as PackedByteArray).size() / (4 if wide else 2) if data is PackedByteArray \
				else (data as PackedInt32Array).size()
		out.append(indices / 3)
	return out


func _px(radius_m: float, distance_m: float) -> float:
	return radius_m * FarProp.k_of(camera) / distance_m


# --- the levels of detail --------------------------------------------------------------------------------------------------


func test_every_hull_has_levels_of_detail_and_a_thin_coarsest_level() -> void:
	var checked: Dictionary = {}
	for type: StringName in ShipCatalog.types():
		var asset_id: String = ShipCatalog.spec_for(type).asset_id
		if checked.has(asset_id):
			continue
		checked[asset_id] = true
		var mesh: Mesh = MeshAssets.for_asset(asset_id)
		assert_not_null(mesh, "%s has a textured mesh (run scripts/gen_assets.sh and import)" % asset_id)
		if mesh == null:
			continue
		var levels: Array[int] = _level_triangles(mesh)
		assert_gt(levels.size(), 1, "%s has levels of detail besides the full mesh: %s" % [asset_id, levels])
		if levels.size() < 2:
			continue
		var coarsest: int = levels[levels.size() - 1]
		assert_lte(coarsest, COARSEST_MAX_TRIANGLES, "%s at its coarsest: %d of %d triangles" % [asset_id, coarsest, levels[0]])
		assert_lt(float(coarsest), 0.7 * float(levels[0]), "%s thins out: %s" % [asset_id, levels])
		for k: int in range(1, levels.size()):
			assert_lt(levels[k], levels[k - 1], "%s: each level has fewer triangles than the one before" % asset_id)
	assert_gte(checked.size(), 11, "every hull in the catalog")


func test_the_levels_are_the_same_on_every_load() -> void:
	# The importer's levels come from the generated mesh alone: two loads of every hull give the same chain.
	for type: StringName in [&"saturn_3_freighter", &"starfury_ally", &"narn_transport"] as Array[StringName]:
		var path: String = ShipSpec.ASSET_ROOT.path_join(ShipCatalog.spec_for(type).asset_id)
		var a: Array[int] = _level_triangles(_fresh_mesh(path))
		var b: Array[int] = _level_triangles(_fresh_mesh(path))
		assert_false(a.is_empty())
		assert_eq(a, b, "%s: the same levels on every load" % type)


func _fresh_mesh(dir: String) -> Mesh:
	var glb: String = dir.path_join(dir.get_file() + ".glb")
	var scene := ResourceLoader.load(glb, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var root: Node = scene.instantiate()
	var found: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	var mesh: Mesh = (found[0] as MeshInstance3D).mesh if not found.is_empty() else null
	root.free()
	return mesh


# --- the switch by size on screen ------------------------------------------------------------------------------------------


func test_every_hull_keeps_its_mesh_until_a_few_pixels_across_then_is_a_dot_never_a_big_disc() -> void:
	var dot_px: float = float(Settings.get_value(&"far_ship_dot_px"))
	for type: StringName in _ai_types():
		var c: Combatant = _acquire(type)
		var ship: Ship = c.ship
		var switcher := ship.get_node(^"LodSwitcher") as LodSwitcher
		var radius: float = ship.bounding_radius()
		var bad: Array[String] = []
		# Out from 500 m to the far plane and back in, in steps of a fifth, past the switch both ways.
		var distances: Array[float] = []
		var d: float = 500.0
		while d <= FAR_M:
			distances.append(d)
			d *= 1.2
		var back: Array[float] = distances.duplicate()
		back.reverse()
		distances.append_array(back)
		for distance: float in distances:
			ship.global_position = Vector3(0.0, 0.0, -distance)
			switcher.update()
			var px: float = _px(radius, distance)
			if ship.is_far_dot():
				if px >= dot_px / LodSwitcherMath.FAR_RETURN:
					bad.append("a dot %.1f px across at %.0f m" % [2.0 * px, distance])
			else:
				if not ship.hull.is_visible_in_tree():
					bad.append("neither hull nor dot at %.0f m" % distance)
				if px < dot_px:
					bad.append("still a mesh at %.2f px at %.0f m" % [px, distance])
		assert_eq(bad, [] as Array[String], "%s (radius %.0f m)" % [type, radius])
		pool.release(c)


func test_a_freighter_holds_its_shape_far_beyond_where_a_fighter_turns() -> void:
	var saturn: Combatant = _acquire(&"saturn_3_freighter")
	var narn: Combatant = _acquire(&"narn_transport")
	var fighter: Combatant = _acquire(&"starfury_ally")
	# The maintainer's case: past 2.7 km the Saturn 3 and the Narn transport were grey spheres.
	for c: Combatant in [saturn, narn, fighter] as Array[Combatant]:
		c.ship.global_position = Vector3(0.0, 0.0, -5000.0)
		(c.ship.get_node(^"LodSwitcher") as LodSwitcher).update()
	assert_false(saturn.ship.is_far_dot(), "the Saturn 3 is a mesh at 5 km")
	assert_false(narn.ship.is_far_dot(), "the Narn transport is a mesh at 5 km")
	assert_true(fighter.ship.is_far_dot(), "a Starfury is a few pixels at 5 km on 1 080 lines, so a dot")
	var m_per_m: float = LodSwitcher.dot_scale(camera)
	var saturn_m: float = LodSwitcherMath.dot_distance_m(saturn.ship.bounding_radius(), FarProp.k_of(camera),
			float(Settings.get_value(&"far_ship_dot_px")))
	assert_almost_eq(saturn_m, saturn.ship.bounding_radius() * m_per_m, 1e-3)
	assert_gt(saturn_m, 5.0 * fighter.ship.bounding_radius() * m_per_m, "five times the fighter's distance and more")


func test_the_switch_follows_the_screen_not_a_fixed_distance() -> void:
	var c: Combatant = _acquire(&"saturn_3_freighter")
	var switcher := c.ship.get_node(^"LodSwitcher") as LodSwitcher
	var at_1080: float = c.ship.bounding_radius() * LodSwitcher.dot_scale(camera)
	c.ship.global_position = Vector3(0.0, 0.0, -1.5 * at_1080)
	switcher.update()
	assert_true(c.ship.is_far_dot(), "a dot past its dot distance on 1 080 lines")
	get_tree().root.size = Vector2i(3840, 2160)
	switcher.update()
	assert_false(c.ship.is_far_dot(), "twice the lines: twice the distance, so its mesh again")
	get_tree().root.size = Vector2i(1920, 1080)
	switcher.update()
	assert_true(c.ship.is_far_dot())
	camera.fov = 30.0
	switcher.update()
	assert_false(c.ship.is_far_dot(), "a narrow view magnifies it: its mesh again")


func test_a_small_window_counts_as_1080_lines() -> void:
	# A headless test window (64 px) or a 960x540 capture never turns a ship into a dot sooner than 1 080 lines would (the fix
	# for the lights of a raider 300 m out going dark headless).
	var c: Combatant = _acquire(&"raider_fighter")
	var switcher := c.ship.get_node(^"LodSwitcher") as LodSwitcher
	var at_1080: float = c.ship.bounding_radius() * LodSwitcher.dot_scale(camera)
	for size: Vector2i in [Vector2i(960, 540), Vector2i(64, 64)] as Array[Vector2i]:
		get_tree().root.size = size
		assert_almost_eq(c.ship.bounding_radius() * LodSwitcher.dot_scale(camera), at_1080, 1e-3, "%s" % size)
		c.ship.global_position = Vector3(0.0, 0.0, -0.8 * at_1080)
		switcher.update()
		assert_false(c.ship.is_far_dot(), "a mesh inside the 1 080-line distance at %s" % size)
