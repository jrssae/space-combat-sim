extends GutTest
## Babylon 5's exterior lights (M7-T18) on the real main scene: the hardpoints' points and floods built, every lit section within the
## shader's flood list, the halls' and bays' inner faces left without floods, the floods from the other piece following the drum's
## turn, the beacons blinking by sim time, and no light slot taken: the station's only rig emitters are the bays' lamps, which lose
## their slots to the fight's muzzle flashes.

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


func test_the_lights_follow_the_hardpoints_and_stay_on_the_shared_budget() -> void:
	var station: Station = await _start()
	if station == null:
		pending("the babylon5_station asset is not generated")
		return
	var lights: StationLights = station.station_lights
	assert_not_null(lights, "the station has its lights")
	assert_eq(lights.plan.point_count(), 85, "15 beacons, 60 navigation lights, 10 bay lamps")
	assert_eq((lights.plan.points[StationLightPlan.FRAME_BLINK] as Array).size(), 15, "the beacons blink, on the frame")
	assert_almost_eq(lights.plan.blink_period_s, 4.0, 1e-6, "a 4 s beat (the maintainer, 2026-11-15)")
	assert_almost_eq(lights.plan.blink_off_s, 1.0, 1e-6)
	assert_almost_eq(lights.plan.blink_ramp_s, 1.0, 1e-6)
	assert_almost_eq(lights.plan.blink_full_s, 1.0, 1e-6)
	assert_eq(lights.plan.floods.size(), 74)
	assert_gt(lights.sections.size(), 0)
	assert_lte(lights.max_section_floods(), StationLightPlan.MAX_FLOODS, "every section fits the shader's list")
	var listed: int = 0
	for section: Dictionary in lights.sections:
		listed += (section["fixed"] as PackedInt32Array).size() + (section["turning"] as PackedInt32Array).size()
	assert_lt(listed, lights.plan.floods.size() * lights.sections.size(), "sections hold only the floods that reach them")
	assert_eq(station.find_children("*", "Light3D", true, false).size(), 0, "no light node on the station")
	assert_eq(DebugConsole.registry.read("station_lights.floods").get("value"), 74)


func test_the_inner_faces_take_no_floods() -> void:
	var station: Station = await _start()
	if station == null:
		pending("the babylon5_station asset is not generated")
		return
	var checked: int = 0
	for piece: RenderPiece in [station.frame_piece, station.drum_piece]:
		for s: Dictionary in piece.sections.sections:
			var inner: MeshInstance3D = piece.interior_node(String(s["name"]))
			if inner == null:
				continue
			for k: int in inner.mesh.get_surface_count():
				var material := inner.get_active_material(k) as ShaderMaterial
				if material == null or material.shader != StationHullMaterial.SHADER:
					continue
				var count: Variant = material.get_shader_parameter(&"flood_count")  # null: never set, the shader's 0
				assert_eq(int(count) if count != null else 0, 0, "%s's inner faces take no flood" % s["name"])
				checked += 1
	assert_gt(checked, 0, "the halls and bays have inner faces to check")


func test_floods_over_the_other_piece_follow_the_drum() -> void:
	var station: Station = await _start()
	if station == null:
		pending("the babylon5_station asset is not generated")
		return
	var lights: StationLights = station.station_lights
	var crossing: Dictionary = {}
	for section: Dictionary in lights.sections:
		if section["body"] == StationHardpoints.FRAME and not (section["turning"] as PackedInt32Array).is_empty():
			crossing = section
			break
	assert_false(crossing.is_empty(), "some drum flood reaches over a frame section")
	station.set_spinning(false)
	station.set_drum_angle(0.9)
	station.set_process(false)  # hold the drum where the test put it
	lights._process(0.0)
	var fixed_n: int = (crossing["fixed"] as PackedInt32Array).size()
	var f: Dictionary = lights.plan.floods[(crossing["turning"] as PackedInt32Array)[0]]
	var expected: Vector3 = station.drum_pivot.transform * (f["position"] as Vector3)
	var material: ShaderMaterial = (crossing["materials"] as Array)[0]
	var got: Vector4 = (material.get_shader_parameter(&"flood_pos") as PackedVector4Array)[fixed_n]
	assert_almost_eq(Vector3(got.x, got.y, got.z), expected, Vector3.ONE * 0.01, "the drum's flood carried round to 0.9 rad")


func test_beacons_blink_on_sim_time_and_the_bays_lamps_yield_to_muzzle_flashes() -> void:
	var station: Station = await _start()
	if station == null:
		pending("the babylon5_station asset is not generated")
		return
	var lights: StationLights = station.station_lights
	var world: WorldFrame = WorldFrame.of(station)
	var now: float = world.system_time() if world != null else SimClock.now()
	var level: float = lights.beacon_level()
	assert_almost_eq(level, lights.plan.beacon_level(now), 0.05, "the beacons follow the system's sim time")
	lights._process(0.0)
	var blink: MultiMeshInstance3D = lights.groups[StationLightPlan.FRAME_BLINK]
	assert_true(blink.visible, "the beacons' points stay in the tree's draw; dark, their gain is 0 and the shader drops them")
	assert_almost_eq(lights.gain_of(StationLightPlan.FRAME_BLINK), StationLights.MARKER_GAIN * lights.beacon_level(), 0.25,
			"their brightness follows the fade")
	assert_almost_eq(lights.gain_of(StationLightPlan.DRUM_STEADY), StationLights.MARKER_GAIN, 1e-6, "the nav points stay steady")
	# The station's only rig emitters are the bays' four lamps and the grid's three floods, at the lowest priority.
	var rig: LightRig = LightRig.of(station)
	var owned: int = 0
	for emitter: LightEmitter in rig._emitters:
		if emitter.anchor == station:
			owned += 1
			assert_true(station.bay_lights.emitters.has(emitter) or station.grid_lights.emitters.has(emitter), "%s is a bay lamp or a grid flood" % emitter.label)
			assert_eq(emitter.priority, LightEmitter.PRIORITY_CABIN)
	assert_eq(owned, station.bay_lights.emitters.size() + station.grid_lights.emitters.size())
	# A fight at the docking bay's mouth: seven muzzle flashes take every slot from the bay's lamps.
	var mouth: Vector3 = station.to_global((station.hardpoints.main_docking_bay["main_docking_bay_mouth"] as Vector3) + station.drum_origin
			+ Vector3(0.0, 0.0, -20.0))
	var flashes: Array[LightEmitter] = []
	for k: int in 7:
		var flash := LightEmitter.new("flash_%d" % k, LightEmitter.PRIORITY_MUZZLE_FLASH, Color.WHITE, 2.0, 20.0)
		flash.position = mouth + Vector3(float(k), 0.0, 0.0)
		rig.add_emitter(flash)
		flashes.append(flash)
	rig.update(mouth)
	for emitter: LightEmitter in rig.picked():
		assert_true(emitter == null or flashes.has(emitter), "the flashes hold the slots, not %s" % (emitter.label if emitter else ""))
	for flash: LightEmitter in flashes:
		rig.remove_emitter(flash)


# M7-T69: once the station is its far dot, none of its points is drawn, the beacons included, whatever their beat; `station_lights
# off` darkens them by brightness and leaves their visibility to the far prop.
func test_no_point_is_drawn_once_the_station_is_a_dot() -> void:
	var station: Station = await _start()
	if station == null:
		pending("the babylon5_station asset is not generated")
		return
	var lights: StationLights = station.station_lights
	var far: FarProp = FarProp.of(station)
	assert_not_null(far, "the station is drawn far out by its far prop")
	lights.plan.blink_period_s = 0.0  # the beacons held lit: the case that showed them under the dot
	var camera: Camera3D = get_viewport().get_camera_3d()
	assert_not_null(camera)
	far.held_fade = 1.0
	far.update(camera, 0.0)
	assert_eq(far.path(), &"dot")
	for frame: int in 3:
		lights._process(0.0)
	for group: StringName in lights.groups:
		assert_false((lights.groups[group] as Node3D).is_visible_in_tree(), "%s is not drawn under the dot" % group)
	assert_almost_eq(lights.gain_of(StationLightPlan.FRAME_BLINK), StationLights.MARKER_GAIN, 1e-6, "the beacons are lit all the same")
	far.held_fade = 0.0
	far.update(camera, 0.0)
	lights.set_shown(false)
	lights._process(0.0)
	for group: StringName in lights.groups:
		assert_true((lights.groups[group] as Node3D).visible, "%s is the far prop's to hide" % group)
		assert_eq(lights.gain_of(group), 0.0, "%s is dark with the lights off" % group)
	lights.set_shown(true)
	lights._process(0.0)
	assert_eq(lights.gain_of(StationLightPlan.DRUM_STEADY), StationLights.MARKER_GAIN, "on again")
