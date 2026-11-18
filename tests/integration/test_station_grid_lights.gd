extends GutTest
## The floodlights on the heavy cannons and the bow tower (M7-T57) on the real main scene: one emitter ahead of and above each of
## H1, H2 and I5, warm white, in the light rig's competition, so a camera at the tour's heavy cannon stop has them in its slots.

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


func test_the_cannons_and_the_tower_have_their_floods() -> void:
	var station: Station = await _start()
	if station == null or station.grid_lights == null:
		pending("the babylon5_station asset is not generated")
		return
	var lights: StationGridLights = station.grid_lights
	assert_eq(lights.emitters.size(), 3, "H1, H2 and I5")
	var rig: LightRig = LightRig.of(station)
	for emitter: LightEmitter in lights.emitters:
		assert_true(rig.has_emitter(emitter), "%s competes for the rig's slots" % emitter.label)
		var mount: Dictionary = station.hardpoints.mount(emitter.label.trim_prefix("grid_flood_"))
		var from_mount: Vector3 = emitter.offset - (mount["position"] as Vector3)
		assert_lt(from_mount.z, 0.0, "%s stands ahead of its mount, on the side the guns face" % emitter.label)
		assert_gt(from_mount.y, 0.0, "%s stands above its mount" % emitter.label)
		assert_lt(from_mount.length(), emitter.omni_range, "%s reaches its mount" % emitter.label)
		assert_gt(emitter.color.r, emitter.color.b, "%s is warm white" % emitter.label)
	assert_eq(DebugConsole.registry.read("grid_lights.floods").get("value"), 3)
	# At the tour's heavy cannon stop the floods win slots.
	var book: Dictionary = TourBook.load_file()
	var camera: Vector3 = (book["book"] as TourBook).points["heavy_cannons"]["camera"]
	rig.update(station.to_global(camera))
	var held: int = 0
	for emitter: LightEmitter in rig.picked():
		held += 1 if emitter != null and lights.emitters.has(emitter) else 0
	assert_eq(held, 3, "all three hold slots from the stop's camera")
