extends GutTest
## The bays' red lamps (M7-T25, M7-T32) on the real main scene: two emitters at the manifest's `main_docking_bay_red_*` lights,
## down the mouth on its axis, and two at its `cargo_bay_red_*` lights, in the cargo bay; red, in the light rig's competition: in
## each bay its own two win slots. The docking bay's inner doors carry the walls' detail tile.

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


func test_red_lamps_light_each_bay_up_close() -> void:
	var station: Station = await _start()
	if station == null:
		pending("the babylon5_station asset is not generated")
		return
	assert_not_null(station.bay_lights, "the bays have their lamps")
	var mouth_lamps: Array[LightEmitter] = []
	var cargo_lamps: Array[LightEmitter] = []
	for lamp: LightEmitter in station.bay_lights.emitters:
		(mouth_lamps if lamp.label.begins_with("main_docking_bay_red_") else cargo_lamps).append(lamp)
	assert_eq(mouth_lamps.size(), 2, "two down the docking bay's mouth")
	assert_eq(cargo_lamps.size(), 2, "two in the cargo bay (M7-T32)")
	var lock: StationAirlock = station.airlock
	var mouth: Vector3 = (station.hardpoints.main_docking_bay["main_docking_bay_mouth"] as Vector3) + station.drum_origin
	var rig: LightRig = LightRig.of(station)
	for lamp: LightEmitter in station.bay_lights.emitters:
		assert_true(rig.has_emitter(lamp), "%s competes for the rig's slots" % lamp.label)
		assert_gt(lamp.color.r, 4.0 * lamp.color.g, "%s is red" % lamp.label)
		lamp.follow()
	for lamp: LightEmitter in mouth_lamps:
		var local: Vector3 = station.to_local(lamp.position)
		assert_lt(Vector2(local.x, local.y).length(), 0.01, "%s on the bay's axis" % lamp.label)
		assert_between(lock.depth_of(local), mouth.z - lock.doors_at.z, 0.0, "%s down the mouth, short of the doors" % lamp.label)
	var cargo: Dictionary = station.hardpoints.cargo_bay
	var box := AABB(cargo["cargo_bay_clear_min"], (cargo["cargo_bay_clear_max"] as Vector3) - (cargo["cargo_bay_clear_min"] as Vector3))
	for lamp: LightEmitter in cargo_lamps:
		assert_true(box.has_point(station.to_local(lamp.position)), "%s inside the cargo bay" % lamp.label)
	# Each bay's own two win slots when the camera is in it; the other bay's, 340 m off, do not take them from it.
	for case: Array in [[station.to_global(mouth + Vector3(0.0, 0.0, 20.0)), mouth_lamps, "the docking bay's mouth"],
			[station.to_global(cargo["cargo_bay_entry"] as Vector3), cargo_lamps, "the cargo bay"]]:
		rig.update(case[0])
		var picked: int = 0
		for emitter: LightEmitter in rig.picked():
			picked += 1 if emitter != null and (case[1] as Array).has(emitter) else 0
		assert_eq(picked, 2, "inside %s both its lamps hold slots" % case[2])
	assert_eq(DebugConsole.registry.read("bay_lights.lamps").get("value"), 4)
	# The inner doors lie among the bay's plating and take the hull's detail tile; the Cobra bays' doors do not.
	var leaves: Dictionary = {}
	for node: MultiMeshInstance3D in station.drum_piece.prop_nodes():
		leaves[String(node.name)] = (node.multimesh.mesh.surface_get_material(0) as StandardMaterial3D).detail_enabled
	assert_true(bool(leaves.get("Props_AirlockLeafUpper", false)), "the docking bay's doors carry the walls' detail tile")
	assert_false(bool(leaves.get("Props_DoorLeaf1R", true)), "a Cobra door keeps its own face")
