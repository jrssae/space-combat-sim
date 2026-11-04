extends GutTest
## The node diet for AI ships (M4-T11, architecture §17.10). A pooled AI ship is built lean: its body, the collision shapes as
## shape owners of the body (no node each), its splat levels, the depth proxy (which also draws the fallback mesh), its plumes as
## one multimesh, its running lights as one multimesh, and the gameplay components. The player's ship keeps every node it had.
## A near lean ship draws at most three surfaces (the proxy, the plumes, the markers); what that is in draw calls on the GPU is
## measured by the fullscreen check, not here.

const DT: float = 1.0 / 60.0
## Nodes of a lean AI ship's own, besides its guns: each muzzle adds a marker and a flash (the weapons' nodes, not changed here).
const OWN_NODES_MAX: int = 16
## Surfaces a near lean ship draws while its plumes burn and its lights are on (the muzzle flashes only while it fires).
const SURFACES_MAX: int = 3

var world: WorldFrame
var projectiles: Node3D
var pool: ShipPool
var player: Combatant


func before_each() -> void:
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
	assert_eq(pool.prepare(ShipPool.ALLY_TYPE, 1), 1)


func _count(node: Node) -> int:
	var n: int = 1
	for child: Node in node.get_children(true):
		n += _count(child)
	return n


func _collect(node: Node, type: Variant, out: Array = []) -> Array:
	if is_instance_of(node, type):
		out.append(node)
	for child: Node in node.get_children(true):
		_collect(child, type, out)
	return out


func _acquire(type: StringName, at: Vector3) -> Combatant:
	var made: Combatant = pool.acquire("SHIP", world.to_universe(at), Basis.IDENTITY, Vector3.ZERO, null, type)
	assert_not_null(made)
	return made


# Surfaces drawn by the ship's visible geometry: a mesh's surfaces, a multimesh's mesh's surfaces while it draws an instance.
func _surfaces(ship: Ship) -> int:
	var n: int = 0
	for node: Variant in _collect(ship, GeometryInstance3D):
		var geometry := node as GeometryInstance3D
		if not geometry.is_visible_in_tree():
			continue
		if geometry is MultiMeshInstance3D:
			var mm: MultiMesh = (geometry as MultiMeshInstance3D).multimesh
			if mm != null and mm.mesh != null and (mm.visible_instance_count != 0 and mm.instance_count > 0):
				n += mm.mesh.get_surface_count()
		elif geometry is MeshInstance3D and (geometry as MeshInstance3D).mesh != null:
			n += (geometry as MeshInstance3D).mesh.get_surface_count()
	return n


func _burn(ship: Ship) -> void:
	var burn := FlightCommand.new()
	burn.main_left = 1.0
	burn.main_right = 1.0
	ship.set_flight_command(burn)


# --- the lean set --------------------------------------------------------------------------------------------------------


func test_a_pooled_ai_ship_has_at_most_sixteen_nodes_besides_its_guns() -> void:
	for c: Combatant in pool.all_ships():
		assert_true(c.ship.lean, "%s is built lean" % c.ship.spec.asset_id)
		var muzzles: int = c.ship.get_muzzles().size()
		var nodes: int = _count(c.ship)
		gut.p("%s: %d nodes, %d of them its %d muzzles and their flashes" % [c.ship.spec.asset_id, nodes, 2 * muzzles, muzzles])
		assert_lte(nodes - 2 * muzzles, OWN_NODES_MAX, "%s: %d nodes" % [c.ship.spec.asset_id, nodes])


func test_the_players_ship_keeps_every_node() -> void:
	var ship: Ship = player.ship
	assert_false(ship.lean)
	assert_eq(_collect(ship, CollisionShape3D).size(), ship.get_hardpoints().collision.size(), "a node per hit volume")
	assert_false(player.thrusters.instanced)
	assert_not_null(player.thrusters.cone(0), "a node per plume")
	assert_eq((ship.get_node(^"RunningLights") as RunningLights).markers().size(), 3, "three marker meshes")
	assert_not_null(ship.cockpit_interior)
	assert_not_null(ship.cockpit_anchor)
	assert_not_null(ship.hull_mesh_fallback)
	gut.p("player: %d nodes" % _count(ship))


func test_a_lean_ship_has_no_collision_nodes_but_its_body_has_every_shape() -> void:
	for c: Combatant in pool.all_ships():
		assert_eq(_collect(c.ship, CollisionShape3D).size(), 0, "no CollisionShape3D on %s" % c.ship.spec.asset_id)
		assert_eq(PhysicsServer3D.body_get_shape_count(c.ship.get_rid()), c.ship.get_hardpoints().collision.size(),
				"every hit volume is a shape of the body")


func test_a_lean_ship_is_hit_by_a_ray_through_its_hull() -> void:
	var raider: Combatant = _acquire(ShipPool.DEFAULT_TYPE, Vector3(0.0, 0.0, -200.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var at: Vector3 = raider.ship.global_position
	var query := PhysicsRayQueryParameters3D.create(at + Vector3(0.0, 50.0, 0.0), at - Vector3(0.0, 50.0, 0.0))
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
	assert_false(hit.is_empty(), "the ray meets the hull")
	assert_eq(hit.get("collider"), raider.ship)


func test_a_lean_ship_drops_the_cockpit_and_the_extra_fallback_node() -> void:
	for c: Combatant in pool.all_ships():
		assert_null(c.ship.cockpit_interior, "no interior on an AI ship")
		assert_null(c.ship.cockpit_anchor)
		assert_null(c.ship.hull_mesh_fallback, "the proxy node draws the fallback mesh")
		assert_not_null(c.ship.fallback_mesh(), "the fallback mesh is still loaded")


func test_a_lean_ship_shows_its_fallback_mesh_on_the_proxy_node() -> void:
	var raider: Combatant = _acquire(ShipPool.DEFAULT_TYPE, Vector3(0.0, 0.0, -200.0))
	var proxy: HullDepthProxy = raider.ship.hull_depth_proxy
	assert_eq(proxy.mesh.get_surface_count(), 1, "the proxy is one surface")
	assert_not_null(proxy.material_override, "drawn black")
	raider.ship.use_fallback_mesh(true)
	assert_true(proxy.visible)
	assert_eq(proxy.mesh, raider.ship.fallback_mesh(), "the fallback mesh with its own materials")
	assert_null(proxy.material_override)
	for node: GaussianSplatNode in raider.ship.splat_nodes():
		assert_false(node.visible)
	raider.ship.use_fallback_mesh(false)
	assert_eq(proxy.mesh.get_surface_count(), 1)
	assert_not_null(proxy.material_override)


# --- plumes ---------------------------------------------------------------------------------------------------------------


func test_a_lean_ships_plumes_are_one_multimesh_that_follows_the_levels() -> void:
	var raider: Combatant = _acquire(ShipPool.DEFAULT_TYPE, Vector3(0.0, 0.0, -200.0))
	var tv: ThrusterVisuals = raider.thrusters
	assert_true(tv.instanced)
	assert_eq(_collect(tv, MeshInstance3D).size(), 0, "no plume nodes")
	assert_eq(tv.get_child_count(), 0)
	assert_not_null(tv.multimesh)
	assert_eq(tv.multimesh.instance_count, tv.glow_count(), "one instance per nozzle")
	assert_eq(tv.multimesh.mesh.get_surface_count(), 1, "cone and core in one surface")
	_burn(raider.ship)
	await get_tree().physics_frame
	await get_tree().physics_frame
	tv.advance(1.0)
	var main_index: int = -1
	var layout: ThrusterLayout = raider.ship.get_layout()
	for i: int in layout.nozzle_count():
		if ThrusterLayout.is_main_group(layout.nozzle_groups[i]):
			main_index = i
			break
	assert_gt(main_index, -1)
	var level: float = tv.glow_level(main_index)
	assert_gt(level, 0.5, "a main plume burns")
	assert_true(tv.glow_shown(main_index))
	assert_almost_eq(tv.instance_color(main_index).a, level, 1e-6, "the level is the instance's alpha")
	var xform: Transform3D = tv.instance_transform(main_index)
	assert_almost_eq(xform.origin, layout.nozzle_positions[main_index], Vector3.ONE * 1e-5, "at the nozzle")
	assert_almost_eq(xform.basis.y.length(), tv.main_length_m * level, 1e-4, "its length follows the level")
	assert_gt(xform.basis.y.normalized().dot(layout.nozzle_exhausts[main_index].normalized()), 0.999, "along the exhaust")
	tv.reset()
	assert_false(tv.glow_shown(main_index), "reset puts it out")
	assert_eq(tv.instance_color(main_index).a, 0.0)


func test_a_lean_ships_nozzle_lights_sit_where_the_plume_nodes_put_them() -> void:
	var raider: Combatant = _acquire(ShipPool.DEFAULT_TYPE, Vector3(0.0, 0.0, -200.0))
	var tv: ThrusterVisuals = raider.thrusters
	var layout: ThrusterLayout = raider.ship.get_layout()
	var lights: int = 0
	for i: int in tv.glow_count():
		var light: LightEmitter = tv.nozzle_light(i)
		if light == null:
			continue
		lights += 1
		assert_eq(light.anchor, tv)
		var expected: Vector3 = layout.nozzle_positions[i] + layout.nozzle_exhausts[i].normalized() * EmitterCurves.NOZZLE_OFFSET_M
		assert_almost_eq(light.offset, expected, Vector3.ONE * 1e-5)
	assert_gt(lights, 0)


func test_the_tinted_plume_material_is_shared_by_every_ship_of_a_colour() -> void:
	var one: Combatant = _acquire(ShipPool.DEFAULT_TYPE, Vector3(0.0, 0.0, -200.0))
	assert_eq(pool.prepare(ShipPool.DEFAULT_TYPE, 1), 1)
	var two: Combatant = _acquire(ShipPool.DEFAULT_TYPE, Vector3(100.0, 0.0, -200.0))
	assert_ne(one, two)
	var material := one.thrusters.plume_material() as StandardMaterial3D
	assert_not_null(material)
	assert_eq(material.albedo_color, one.ship.spec.engine_glow_color)
	assert_true(material.vertex_color_use_as_albedo, "the instance colour carries the level")
	assert_eq(two.thrusters.plume_material(), material, "one material per colour")


# --- running lights ---------------------------------------------------------------------------------------------------


func test_a_lean_ships_running_lights_are_one_multimesh_of_three() -> void:
	var raider: Combatant = _acquire(ShipPool.DEFAULT_TYPE, Vector3(0.0, 0.0, -200.0))
	var lights := raider.ship.get_node(^"RunningLights") as RunningLights
	assert_true(lights.instanced)
	assert_eq(lights.get_child_count(), 0, "no marker nodes")
	assert_eq(lights.marker_count(), 3)
	var nav: Dictionary = raider.ship.get_hardpoints().nav_lights
	assert_almost_eq(lights.marker_position(0), nav["port"] as Vector3, Vector3.ONE * 1e-5)
	assert_almost_eq(lights.marker_position(1), nav["starboard"] as Vector3, Vector3.ONE * 1e-5)
	assert_almost_eq(lights.marker_position(2), nav["top"] as Vector3, Vector3.ONE * 1e-5)
	var red: Color = lights.marker_tint(0)
	var green: Color = lights.marker_tint(1)
	assert_gt(red.r, 3.0 * red.g, "port is red")
	assert_gt(green.g, 3.0 * green.r, "starboard is green")
	assert_true(lights.markers_shown(), "on at spawn")
	raider.ship.running_lights = false
	assert_false(lights.markers_shown(), "dark")
	raider.ship.running_lights = true
	assert_true(lights.markers_shown())
	pool.release(raider)
	assert_false(lights.markers_shown(), "a parked ship shows none")


# --- what a near ship draws ---------------------------------------------------------------------------------------------


func test_a_near_lean_ship_draws_at_most_three_surfaces() -> void:
	var raider: Combatant = _acquire(ShipPool.DEFAULT_TYPE, Vector3(0.0, 0.0, -200.0))
	var ally: Combatant = _acquire(ShipPool.ALLY_TYPE, Vector3(100.0, 0.0, -200.0))
	for c: Combatant in [raider, ally]:
		_burn(c.ship)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for c: Combatant in [raider, ally]:
		c.thrusters.advance(1.0)
		assert_true(c.ship.running_lights)
		var surfaces: int = _surfaces(c.ship)
		gut.p("%s: %d surfaces drawn" % [c.ship.spec.asset_id, surfaces])
		assert_lte(surfaces, SURFACES_MAX, c.ship.spec.asset_id)
	player.thrusters.advance(1.0)
	gut.p("player: %d surfaces drawn" % _surfaces(player.ship))
