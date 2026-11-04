extends GutTest
## Liveries on the textured hull (M4-T30b, Q35, Q36): a ship acquired as `ALPHA 2` draws the Alpha livery and number 02 (its hull
## node's instance uniforms), the player's ship is Alpha 01, a Starfury with no wing is plain, Starfuries of four wings share one
## hull material, the `livery` command and provider, and the glass's red cabin glow following `settings.cabin_glow_level`.

var world: WorldFrame
var projectiles: Node3D
var pool: ShipPool
var player: Combatant
var camera: Camera3D
var section: Dictionary


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
	section = MeshAssets.livery_section("starfury_aurora")


func after_each() -> void:
	Settings.set_value(&"ship_render", &"splat")
	Settings.set_value(&"cabin_glow_level", 0.3)


func _hull_node(ship: Ship) -> HullDepthProxy:
	for child: Node in ship.get_children():
		if child is HullDepthProxy:
			return child as HullDepthProxy
	return null


func _ally(callsign: String, z: float = -100.0) -> Combatant:
	pool.prepare(ShipPool.ALLY_TYPE, pool.pool_size(ShipPool.ALLY_TYPE) + 1)
	return pool.acquire(callsign, world.to_universe(Vector3(0.0, 0.0, z)), Basis.IDENTITY, Vector3.ZERO, null, ShipPool.ALLY_TYPE)


func _pattern(name: String) -> int:
	return (section["patterns"] as Dictionary).keys().find(name)


func test_an_ally_named_alpha_2_draws_the_alpha_livery_and_02() -> void:
	assert_false(section.is_empty(), "run scripts/gen_assets.sh first")
	var ally: Combatant = _ally("ALPHA 2")
	assert_not_null(ally)
	var node: HullDepthProxy = _hull_node(ally.ship)
	assert_eq(node.get_instance_shader_parameter(&"livery_pattern"), _pattern("bands"))
	assert_eq(node.get_instance_shader_parameter(&"livery_number"), 2)
	var row: Array = section["liveries"]["alpha"]["primary"]
	var primary: Color = node.get_instance_shader_parameter(&"livery_primary")
	assert_true(primary.is_equal_approx(Color(row[0], row[1], row[2])), str(primary))
	assert_eq(ally.ship.livery.describe(), "alpha 02 (bands)")


func test_the_players_ship_is_alpha_01() -> void:
	var node := player.ship.get_node(^"HullMeshFallback") as MeshInstance3D
	assert_eq(node.get_instance_shader_parameter(&"livery_pattern"), _pattern("bands"))
	assert_eq(node.get_instance_shader_parameter(&"livery_number"), 1)
	assert_eq(player.ship.livery.number_text(), "01")


func test_a_starfury_without_a_wing_is_plain() -> void:
	var stray: Combatant = _ally("SHEET")
	var node: HullDepthProxy = _hull_node(stray.ship)
	assert_eq(node.get_instance_shader_parameter(&"livery_pattern"), 0)
	assert_eq(node.get_instance_shader_parameter(&"livery_number"), 0)
	assert_eq(stray.ship.livery.pattern, "plain")


func test_four_wings_share_one_hull_material() -> void:
	var nodes: Array[HullDepthProxy] = []
	var z: float = -100.0
	for callsign: String in ["ALPHA 2", "BETA 2", "DELTA 3", "ZETA 4"]:
		nodes.append(_hull_node(_ally(callsign, z).ship))
		z -= 40.0
	var mesh: Mesh = nodes[0].mesh
	var material: Material = mesh.surface_get_material(0)
	assert_true(material is ShaderMaterial, "the livery shader")
	for node: HullDepthProxy in nodes:
		assert_same(node.mesh, mesh)
		assert_same(node.mesh.surface_get_material(0), material)
		assert_null(node.material_override)
	var patterns: Array = nodes.map(func(n: HullDepthProxy) -> int: return int(n.get_instance_shader_parameter(&"livery_pattern")))
	assert_eq(patterns, [_pattern("bands"), _pattern("nose_band"), _pattern("chevron"), _pattern("pinstripe")])


func test_the_livery_command_and_provider() -> void:
	var look := LookScene.new()
	look.world = world
	look.pool = pool
	look.player = player.ship
	look.key_star = DirectionalLight3D.new()
	add_child_autofree(look.key_star)
	add_child_autofree(look)
	var ally: Combatant = _ally("ALPHA 2")
	var results: Array = DebugConsole.registry.execute("livery delta 7 alpha 2")
	assert_true((results[0] as ConsoleResult).ok, str((results[0] as ConsoleResult).lines))
	assert_eq(_hull_node(ally.ship).get_instance_shader_parameter(&"livery_number"), 7)
	assert_eq(ally.ship.livery.pattern, "chevron")
	results = DebugConsole.registry.execute("livery plain")
	assert_true((results[0] as ConsoleResult).ok)
	assert_eq(player.ship.livery.pattern, "plain")
	assert_eq(String(DebugConsole.registry.read("livery.player")["value"]), "plain - (plain)")
	var listed: PackedStringArray = DebugConsole.registry.read("livery.list")["value"]
	assert_true(listed.has("ALPHA 2: delta 07 (chevron)"), str(listed))
	results = DebugConsole.registry.execute("livery alpha 2 nobody")
	assert_false((results[0] as ConsoleResult).ok)


func test_the_glass_glows_red_at_the_cabin_glow_level() -> void:
	var mesh: Mesh = MeshAssets.for_asset("starfury_aurora")
	var glass := mesh.surface_get_material(1) as ShaderMaterial
	assert_not_null(glass, "the glass is the hull glass shader")
	var strength: float = float((SplatLod.read_manifest("starfury_aurora")["mesh"]["surfaces"][1] as Dictionary)["emissive_strength"])
	Settings.set_value(&"cabin_glow_level", 0.3)
	assert_almost_eq(float(glass.get_shader_parameter(&"glow_energy")), strength, 1e-6)
	Settings.set_value(&"cabin_glow_level", 0.9)
	assert_almost_eq(float(glass.get_shader_parameter(&"glow_energy")), strength * 3.0, 1e-5, "live")
	Settings.set_value(&"cabin_glow_level", 0.0)
	assert_almost_eq(float(glass.get_shader_parameter(&"glow_energy")), 0.0, 1e-9)


func test_the_cockpit_is_grey_lit_red() -> void:
	var interior := player.ship.get_node(^"CockpitInterior") as MeshInstance3D
	assert_not_null(interior.mesh)
	var seen: int = 0
	for s: int in interior.mesh.get_surface_count():
		var material := interior.mesh.surface_get_material(s) as BaseMaterial3D
		if material == null or not MeshMaterials.COCKPIT_GLOW.has(String(material.resource_name)):
			continue
		seen += 1
		var albedo: Color = material.albedo_color
		var top: float = maxf(albedo.r, maxf(albedo.g, albedo.b))
		assert_lt((top - minf(albedo.r, minf(albedo.g, albedo.b))) / maxf(top, 1e-6), 0.08, "%s is grey" % material.resource_name)
		var glow: Color = material.emission
		assert_gt(glow.r, 3.0 * maxf(glow.g, glow.b), "%s glows red" % material.resource_name)
	assert_gt(seen, 3)
