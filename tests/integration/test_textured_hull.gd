extends GutTest
## The textured hull in the scene (M4-T30a): the player's ship and a lean pooled ship draw the textured mesh with `ship_render` at
## `mesh` and the far dot still applies; `ambient_level` lights the environment live; the `sheet` command parks and clears its ship.

const ENVIRONMENT_PATH: String = "res://src/environment/space_environment.tscn"

var world: WorldFrame
var projectiles: Node3D
var pool: ShipPool
var player: Combatant
var camera: Camera3D


func before_each() -> void:
	Settings.set_value(&"ship_render", &"mesh")
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
	camera = Camera3D.new()
	world.add_child(camera)
	camera.make_current()


func after_each() -> void:
	Settings.set_value(&"ship_render", &"splat")
	Settings.set_value(&"ambient_level", 0.3)
	Settings.set_value(&"far_ship_dot_m", 3000.0)


func _hull_node(ship: Ship) -> HullDepthProxy:
	for child: Node in ship.get_children():
		if child is HullDepthProxy:
			return child as HullDepthProxy
	return null


func test_the_player_and_a_lean_ally_draw_the_textured_mesh() -> void:
	var textured: Mesh = MeshAssets.for_asset("starfury_aurora")
	assert_not_null(textured, "run scripts/gen_assets.sh and import first")
	if textured == null:
		return
	assert_true(player.ship.is_drawing_paint_mesh())
	assert_same(player.ship.paint_mesh(), textured)
	var fallback := player.ship.get_node(^"HullMeshFallback") as MeshInstance3D
	assert_same(fallback.mesh, textured, "the player's hull node shows the textured mesh")
	assert_true(fallback.visible)
	assert_eq(pool.prepare(ShipPool.ALLY_TYPE, 1), 1)
	var ally: Combatant = pool.acquire("ALPHA 2", world.to_universe(Vector3(0.0, 0.0, -100.0)), Basis.IDENTITY, Vector3.ZERO, null, ShipPool.ALLY_TYPE)
	assert_not_null(ally)
	var proxy: HullDepthProxy = _hull_node(ally.ship)
	assert_not_null(proxy, "a lean ship draws through its one hull node")
	assert_true(proxy.is_drawing_fallback())
	assert_same(proxy.source_mesh(), textured)
	assert_true(proxy.visible)
	# Far away it is a dot and the mesh is hidden.
	Settings.set_value(&"far_ship_dot_m", 500.0)
	camera.global_position = Vector3(0.0, 0.0, 5000.0)
	(ally.ship.get_node(^"LodSwitcher") as LodSwitcher).update()
	assert_true(ally.ship.is_far_dot())
	assert_false(proxy.visible)


func test_ambient_level_lights_the_environment_live() -> void:
	var env := (load(ENVIRONMENT_PATH) as PackedScene).instantiate() as SpaceEnvironment
	add_child_autofree(env)
	var environment: Environment = env.world_environment.environment
	assert_eq(environment.ambient_light_source, Environment.AMBIENT_SOURCE_COLOR)
	assert_almost_eq(environment.ambient_light_energy, 0.3, 1e-6)
	assert_eq(environment.ambient_light_color, Color.WHITE)
	Settings.set_value(&"ambient_level", 0.55)
	assert_almost_eq(env.world_environment.environment.ambient_light_energy, 0.55, 1e-6, "live")


func test_the_sheet_parks_a_ship_and_clears_it() -> void:
	var star := DirectionalLight3D.new()
	add_child_autofree(star)
	var before: Transform3D = star.global_transform
	var look := LookScene.new()
	look.world = world
	look.pool = pool
	look.player = player.ship
	look.key_star = star
	add_child_autofree(look)
	assert_eq(look.show("no_such_asset", 30.0, &"lit", &"textured").is_empty(), false, "only pooled ship assets and the props")
	assert_eq(look.show("starfury_aurora", 30.0, &"lit", &"textured"), "")
	assert_true(look.is_active())
	assert_eq(pool.alive(ShipPool.ALLY_TYPE).size(), 1)
	var parked: Ship = look.parked().ship
	assert_almost_eq(parked.global_position.distance_to(camera.global_position), 30.0, 0.5)
	assert_false(player.ship.visible, "the player's own hull is out of the picture")
	assert_eq(StringName(Settings.get_value(&"ship_render")), &"mesh")
	assert_ne(star.global_transform, before, "the key star turned")
	assert_eq(look.show("starfury_aurora", 150.0, &"dark", &"splat"), "", "a second shot replaces the first")
	assert_eq(pool.alive(ShipPool.ALLY_TYPE).size(), 1)
	assert_eq(StringName(Settings.get_value(&"ship_render")), &"splat")
	assert_eq(look.show("starfury_aurora", 8.0, &"lit", &"painted"), "")
	assert_same(_hull_node(look.parked().ship).source_mesh(), MeshAssets.load_entry(ShipSpec.ASSET_ROOT.path_join("starfury_aurora"),
			SplatLod.read_manifest("starfury_aurora")["paint_mesh"]), "the painted look swaps in T27's mesh")
	look.clear()
	assert_false(look.is_active())
	assert_eq(pool.alive(ShipPool.ALLY_TYPE).size(), 0)
	assert_true(player.ship.visible)
	assert_eq(star.global_transform, before)
	assert_eq(StringName(Settings.get_value(&"ship_render")), &"mesh", "the setting from before the sheet")


func test_a_prop_that_cannot_be_parked_puts_everything_back() -> void:
	# M4-T30d fix round 1: a ship is parked, then a prop the sheet cannot build (no chunks under this root) ends the sheet cleanly.
	var star := DirectionalLight3D.new()
	add_child_autofree(star)
	var before: Transform3D = star.global_transform
	var look := LookScene.new()
	look.world = world
	look.pool = pool
	look.player = player.ship
	look.key_star = star
	add_child_autofree(look)
	Settings.set_value(&"ship_render", &"mesh")
	assert_eq(look.show("starfury_aurora", 30.0, &"lit", &"splat"), "")
	assert_false(player.ship.visible)
	look.asset_root = "res://no_such_root"
	assert_ne(look.show("raider_fighter_chunks", 30.0, &"dark", &"textured"), "", "no chunks to park")
	assert_false(look.is_active())
	assert_eq(pool.alive(ShipPool.ALLY_TYPE).size(), 0, "the parked ship went back to the pool")
	assert_true(player.ship.visible, "the player's hull is shown again")
	assert_eq(star.global_transform, before, "the key star is back")
	assert_eq(StringName(Settings.get_value(&"ship_render")), &"mesh", "the setting from before the sheet")
