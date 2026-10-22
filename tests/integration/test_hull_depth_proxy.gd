extends GutTest
## The hull depth proxy on the ship and on the nav buoys (architecture §7.2): an opaque black copy of the fallback mesh
## whose vertices sit just inside the surface, there to write the depth that splats do not, so transparent effects
## behind a hull are hidden by it. It exists, reuses whatever fallback mesh is loaded, is on exactly when the splats
## are, and its shader insets along the normal. That the effects really vanish behind the hull needs a GPU: (H).

const SPEC_PATH: String = "res://assets/ships/starfury_aurora.tres"
const SHADER_PATH: String = "res://assets/shaders/hull_depth_proxy.gdshader"

var world: WorldFrame
var ship: Ship


func before_each() -> void:
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	ship = Ship.create(load(SPEC_PATH) as ShipSpec, world)
	world.spawn(ship, world.to_universe(Vector3.ZERO))


func _spawn_buoy(at: Vector3 = Vector3(0.0, 0.0, -50.0)) -> NavBuoy:
	var buoy: NavBuoy = NavBuoy.create("TEST BUOY")
	world.spawn(buoy, world.to_universe(at))
	return buoy


# --- ship ------------------------------------------------------------------------------------------------------


func test_the_ship_has_a_depth_proxy_that_is_a_mesh_instance() -> void:
	var proxy: Node = ship.get_node_or_null(^"HullDepthProxy")
	assert_not_null(proxy, "HullDepthProxy exists")
	assert_true(proxy is MeshInstance3D, "a MeshInstance3D")
	assert_true(proxy is HullDepthProxy)
	assert_eq(ship.hull_depth_proxy, proxy)
	assert_eq(proxy.get_parent(), ship, "rides with the hull")
	assert_eq(ship.hull_depth_proxy.transform, Transform3D.IDENTITY, "same frame as the fallback mesh")


func test_the_proxy_reuses_the_loaded_fallback_mesh() -> void:
	assert_not_null(ship.hull_mesh_fallback.mesh, "precondition: the fallback mesh is loaded (run scripts/gen_assets.sh)")
	assert_eq(ship.hull_depth_proxy.mesh, ship.hull_mesh_fallback.mesh, "the very same Mesh resource")
	assert_eq(ship.hull_depth_proxy.transform, ship.hull_mesh_fallback.transform)


func test_the_proxy_follows_the_fallback_mesh_when_the_ship_is_rebuilt() -> void:
	ship.hull_mesh_fallback.mesh = null
	ship.setup(load(SPEC_PATH) as ShipSpec, world)
	assert_not_null(ship.hull_mesh_fallback.mesh)
	assert_eq(ship.hull_depth_proxy.mesh, ship.hull_mesh_fallback.mesh, "a rebuild re-reads the mesh for both")


func test_the_proxy_is_visible_while_the_splats_are_and_hidden_with_the_fallback() -> void:
	assert_false(ship.is_fallback_mesh_active(), "headless keeps the splat path")
	assert_true(ship.hull_splats.visible)
	assert_true(ship.hull_depth_proxy.visible, "splats on: the proxy is on")
	assert_eq(ship.hull_depth_proxy.visible, not ship.hull_mesh_fallback.visible, "opposite to the fallback mesh")

	ship.use_fallback_mesh(true)
	assert_true(ship.hull_mesh_fallback.visible)
	assert_false(ship.hull_splats.visible)
	assert_false(ship.hull_depth_proxy.visible, "fallback shown: the proxy would only black out the mesh")
	assert_eq(ship.hull_depth_proxy.visible, not ship.hull_mesh_fallback.visible)

	ship.use_fallback_mesh(false)
	assert_true(ship.hull_depth_proxy.visible)
	assert_false(ship.hull_mesh_fallback.visible)
	assert_eq(ship.hull_depth_proxy.visible, ship.hull_splats.visible, "on exactly when the splats are")


func test_a_ship_told_to_use_the_fallback_before_it_is_ready_starts_without_the_proxy() -> void:
	var early: Ship = Ship.create(load(SPEC_PATH) as ShipSpec, world)
	early.use_fallback_mesh(true)
	world.spawn(early, world.to_universe(Vector3(0.0, 0.0, 100.0)))
	assert_true(early.hull_mesh_fallback.visible)
	assert_false(early.hull_depth_proxy.visible)


func test_splat_status_group_toggles_the_proxy_with_the_hull() -> void:
	var status := SplatStatus.new()
	add_child_autofree(status)
	assert_true(ship.is_in_group(SplatStatus.MESH_GROUP))
	status.set_fallback(true)
	assert_true(ship.hull_mesh_fallback.visible)
	assert_false(ship.hull_depth_proxy.visible)
	status.set_fallback(false)
	assert_false(ship.hull_mesh_fallback.visible)
	assert_true(ship.hull_depth_proxy.visible)


func test_the_proxy_material_is_an_opaque_unshaded_black_back_face_culled_shader() -> void:
	var material := ship.hull_depth_proxy.material_override as ShaderMaterial
	assert_not_null(material, "a ShaderMaterial")
	assert_eq(material.shader.resource_path, SHADER_PATH)
	var code: String = material.shader.code
	assert_string_contains(code, "shader_type spatial")
	assert_string_contains(code, "unshaded", "no lighting")
	assert_string_contains(code, "cull_back", "back faces culled")
	assert_string_contains(code, "depth_draw_opaque", "writes depth")
	assert_string_contains(code, "ALBEDO = vec3(0.0)", "black")
	assert_false(code.contains("ALPHA"), "opaque: no alpha written")
	assert_false(code.contains("blend_"), "no blending")
	assert_true(code.contains("VERTEX -= NORMAL * inset_m"), "vertices move inward along NORMAL by the exported inset")
	assert_true(code.contains("uniform float inset_m"), "the inset is an exported uniform")
	assert_eq(ship.hull_depth_proxy.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


func test_the_inset_defaults_to_four_centimetres_and_is_exported() -> void:
	assert_almost_eq(HullDepthProxy.DEFAULT_INSET_M, 0.04, 1e-9)
	assert_almost_eq(ship.hull_depth_proxy.inset_m, 0.04, 1e-9)
	var material := ship.hull_depth_proxy.material_override as ShaderMaterial
	assert_almost_eq(float(material.get_shader_parameter(HullDepthProxy.INSET_PARAMETER)), 0.04, 1e-9, "reaches the shader")
	ship.hull_depth_proxy.inset_m = 0.1
	assert_almost_eq(float(material.get_shader_parameter(HullDepthProxy.INSET_PARAMETER)), 0.1, 1e-9, "and follows edits")
	var exported: bool = false
	for property: Dictionary in ship.hull_depth_proxy.get_property_list():
		if property["name"] == "inset_m" and (int(property["usage"]) & PROPERTY_USAGE_EDITOR) != 0:
			exported = true
	assert_true(exported, "inset_m is an @export")


func test_each_proxy_has_its_own_material_so_insets_can_differ() -> void:
	var buoy: NavBuoy = _spawn_buoy()
	buoy.depth_proxy.inset_m = 0.01
	assert_almost_eq(ship.hull_depth_proxy.inset_m, 0.04, 1e-9, "the ship is untouched")
	assert_ne(buoy.depth_proxy.material_override, ship.hull_depth_proxy.material_override)
	assert_almost_eq(float((ship.hull_depth_proxy.material_override as ShaderMaterial).get_shader_parameter(&"inset_m")), 0.04, 1e-9)


# --- nav buoy ---------------------------------------------------------------------------------------------------


func test_the_buoy_has_a_depth_proxy_on_its_fallback_mesh() -> void:
	var buoy: NavBuoy = _spawn_buoy()
	assert_true(buoy.get_node_or_null(^"BuoyDepthProxy") is HullDepthProxy)
	assert_not_null(buoy.mesh_fallback.mesh, "precondition: the buoy fallback mesh is loaded (run scripts/gen_assets.sh)")
	assert_eq(buoy.depth_proxy.mesh, buoy.mesh_fallback.mesh, "the same mesh")
	assert_true(buoy.depth_proxy.material_override is ShaderMaterial)


func test_the_buoy_proxy_toggles_opposite_to_its_fallback() -> void:
	var buoy: NavBuoy = _spawn_buoy()
	assert_true(buoy.depth_proxy.visible, "splats on")
	assert_false(buoy.mesh_fallback.visible)
	buoy.use_fallback_mesh(true)
	assert_true(buoy.mesh_fallback.visible)
	assert_false(buoy.depth_proxy.visible)
	assert_false(buoy.splats.visible)
	buoy.use_fallback_mesh(false)
	assert_true(buoy.depth_proxy.visible)
	assert_eq(buoy.depth_proxy.visible, not buoy.mesh_fallback.visible)
