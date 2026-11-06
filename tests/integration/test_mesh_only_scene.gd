extends GutTest
## The guard for M4-T31 (architecture §17.20): the game draws meshes only. The real main scene with the player, its buoys, its
## parked break-up chunks, a capital and the station holds no node and no compositor effect from an addon other than the vendored
## ones the project keeps, and no other addon is installed or names a class. The checks go by script paths, never by class, so this
## file compiles whatever addons exist.

## The addons the project keeps (docs/third-party.md): the test runner and the lens flare.
const KEPT_ADDONS: Array[String] = ["gut", "lens_effects"]
const ADDONS_DIR: String = "res://addons/"
const GEN_ASSETS_HINT: String = "run scripts/gen_assets.sh and import first"

var main: Main


func before_each() -> void:
	get_tree().paused = false
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	add_child_autofree(main)
	await get_tree().physics_frame
	await get_tree().physics_frame


func after_each() -> void:
	get_tree().paused = false


# Whether a script path lies in an addon the project does not keep.
static func _from_other_addon(path: String) -> bool:
	if not path.begins_with(ADDONS_DIR):
		return false
	return not KEPT_ADDONS.has(path.trim_prefix(ADDONS_DIR).get_slice("/", 0))


# Whether `object`'s script, or a script it extends, comes from an addon the project does not keep.
static func _foreign(object: Object) -> bool:
	var script := object.get_script() as Script
	while script != null:
		if _from_other_addon(script.resource_path):
			return true
		script = script.get_base_script()
	return false


func _foreign_nodes(node: Node, out: Array[String] = []) -> Array[String]:
	if _foreign(node):
		out.append(String(node.get_path()))
	for child: Node in node.get_children(true):
		_foreign_nodes(child, out)
	return out


# The compositor effects of every environment and camera under `node` that come from an addon the project does not keep.
func _foreign_effects(node: Node, out: Array[String] = []) -> Array[String]:
	var compositor: Compositor = null
	if node is WorldEnvironment:
		compositor = (node as WorldEnvironment).compositor
	elif node is Camera3D:
		compositor = (node as Camera3D).compositor
	if compositor != null:
		for effect: CompositorEffect in compositor.compositor_effects:
			if effect != null and _foreign(effect):
				out.append("%s: %s" % [node.get_path(), (effect.get_script() as Script).resource_path])
	for child: Node in node.get_children(true):
		_foreign_effects(child, out)
	return out


func test_the_main_scene_with_every_kind_of_hull_holds_no_foreign_node() -> void:
	assert_not_null(main.ship, "the player")
	assert_gt(main.buoys.size(), 0, "buoys")
	assert_gt(main.debris.set_count(), 0, "parked break-up chunks (%s)" % GEN_ASSETS_HINT)
	var cap: CapitalStandin = CapitalStandin.create(&"destroyer", Factions.EARTH_ALLIANCE, "CAP 1", Vector3.ZERO)
	main.world.spawn(cap, main.world.to_universe(Vector3(0.0, 0.0, -1500.0)))
	cap.set_look(CapitalStandin.LOOK_MESH)
	assert_not_null(cap.hull_piece(), GEN_ASSETS_HINT)
	var station := StationStandin.new()
	assert_true(station.build(), GEN_ASSETS_HINT)
	main.world.spawn(station, main.world.to_universe(Vector3(0.0, 0.0, -9000.0)))
	await get_tree().process_frame
	assert_eq(_foreign_nodes(main), [] as Array[String])


func test_no_environment_or_camera_runs_a_foreign_compositor_effect() -> void:
	assert_eq(_foreign_effects(main), [] as Array[String])


func test_only_the_kept_addons_are_installed_and_name_classes() -> void:
	var installed: Array[String] = []
	installed.assign(DirAccess.get_directories_at(ADDONS_DIR))
	installed.sort()
	assert_eq(installed, KEPT_ADDONS)
	var named: Array[String] = []
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		if _from_other_addon(String(entry.get("path", ""))):
			named.append("%s (%s)" % [entry.get("class", ""), entry.get("path", "")])
	assert_eq(named, [] as Array[String], "no class name resolves into a removed addon")
