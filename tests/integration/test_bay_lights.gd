extends GutTest
## The main docking bay's red lamps (M7-T25) on the real main scene: two emitters at the manifest's `main_docking_bay_red_*`
## lights, down the mouth on its axis, red, in the light rig's competition: near the mouth they win its slots. The inner doors
## carry the walls' detail tile.

const SCENARIO: String = "res://data/scenarios/station_launch.json"

var main: Main


func _start() -> Station:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = SCENARIO
	main.raider_pool_size = 0
	main.waves_auto_start = false
	add_child_autofree(main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return main.far_props.station


func test_two_red_lamps_down_the_mouth_light_it_up_close() -> void:
	var station: Station = await _start()
	if station == null:
		pending("the babylon5_station asset is not generated")
		return
	assert_not_null(station.bay_lights, "the bay has its lamps")
	var lamps: Array[LightEmitter] = station.bay_lights.emitters
	assert_eq(lamps.size(), 2)
	var lock: StationAirlock = station.airlock
	var mouth: Vector3 = (station.hardpoints.main_docking_bay["main_docking_bay_mouth"] as Vector3) + station.drum_origin
	var rig: LightRig = LightRig.of(station)
	for lamp: LightEmitter in lamps:
		assert_true(rig.has_emitter(lamp), "%s competes for the rig's slots" % lamp.label)
		assert_gt(lamp.color.r, 4.0 * lamp.color.g, "%s is red" % lamp.label)
		lamp.follow()
		var local: Vector3 = station.to_local(lamp.position)
		assert_lt(Vector2(local.x, local.y).length(), 0.01, "%s on the bay's axis" % lamp.label)
		assert_between(lock.depth_of(local), mouth.z - lock.doors_at.z, 0.0, "%s down the mouth, short of the doors" % lamp.label)
	var near: Vector3 = station.to_global(mouth + Vector3(0.0, 0.0, 20.0))  # just inside the mouth
	rig.update(near)
	var picked: int = 0
	for emitter: LightEmitter in rig.picked():
		picked += 1 if emitter != null and lamps.has(emitter) else 0
	assert_eq(picked, 2, "inside the mouth both lamps hold slots")
	assert_eq(DebugConsole.registry.read("bay_lights.lamps").get("value"), 2)
	# The inner doors lie among the bay's plating and take the hull's detail tile; the Cobra bays' doors do not.
	var leaves: Dictionary = {}
	for node: MultiMeshInstance3D in station.drum_piece.prop_nodes():
		leaves[String(node.name)] = (node.multimesh.mesh.surface_get_material(0) as StandardMaterial3D).detail_enabled
	assert_true(bool(leaves.get("Props_AirlockLeafUpper", false)), "the docking bay's doors carry the walls' detail tile")
	assert_false(bool(leaves.get("Props_DoorLeaf1R", true)), "a Cobra door keeps its own face")
