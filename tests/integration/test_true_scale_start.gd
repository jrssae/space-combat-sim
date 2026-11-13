extends GutTest
## The scenarios at true scale in the real main scene (M6-T09, AC6, Q7, Q9): free flight starts beside the station's stand-in
## with the planet ahead and lit, its epoch drawn from the run's seed and the sim clock at 0; the gate on the station's rail
## 50 km ahead, facing it; the station is the HUD's reference. A scenario with a set epoch keeps it.

const STATION: StringName = &"babylon5"
const PLANET: StringName = &"epsilon_iii"

var main: Main


func before_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()


func after_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()


func _start(path: String, seed_value: int) -> void:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = path
	main.scenario_seed = seed_value
	main.raider_pool_size = 0
	main.ally_pool_size = 0
	main.waves_auto_start = false
	add_child_autofree(main)
	await _ticks(3)


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func test_free_flight_starts_beside_the_station_lit_with_the_planet_ahead() -> void:
	await _start(ScenarioLoader.FREE_FLIGHT_PATH, 3)
	var spec: Dictionary = ScenarioLoader.load(ScenarioLoader.FREE_FLIGHT_PATH)["frame"]
	var system: StarSystem = main.star_system.system
	var expected: float = ScenarioFrame.seeded_epoch(spec, system, 3, PackedFloat64Array([0, 0, 0]), Vector3.FORWARD)
	assert_eq(main.world.epoch_s, expected, "the epoch drawn from the run's seed")
	assert_lt(SimClock.now(), 1.0, "the sim clock still starts at 0")
	assert_almost_eq(main.world.system_time(), expected + SimClock.now(), 1.0e-6)
	assert_eq(main.world.anchor_text(), "rail babylon5")
	var station: StationStandin = main.far_props.station
	assert_not_null(station, "the station's stand-in is placed for good")
	assert_not_null(FarProp.of(station), "dressed for the far field")
	var u: UniversePos = main.world.to_universe(station.global_position)
	var at := Vector3(u.x, u.y, u.z)
	assert_almost_eq(at, Vector3(5500.0, -1200.0, -6000.0), Vector3.ONE * 0.01, "where free flight puts it")
	var gate: Jumpgate = main.gates.gate()
	assert_almost_eq(gate.global_position.distance_to(station.global_position), 50000.0, 10.0, "the gate on the rail, 50 km on")
	assert_gt(-gate.global_basis.z.dot((station.global_position - gate.global_position).normalized()), 0.999,
			"its front toward the station")
	var layer: ScaledSpace = main.space_environment.scaled_space
	var camera: Camera3D = main.camera_rig.active_camera()
	layer.refresh(camera)
	var planet: ScaledPlacement = layer.placement_of(PLANET)
	assert_not_null(planet, "the planet is drawn")
	var off_axis: float = rad_to_deg(planet.direction.angle_to(-camera.global_basis.z))
	assert_lt(off_axis, ScenarioFrame.VIEW_DEG + 5.0, "the planet in view ahead (%.1f degrees off the view)" % off_axis)
	assert_gt(layer.key_light(), 0.999, "lit at the start")
	assert_eq(main.flight_reference.frame.label, "BABYLON 5", "the station is the reference")
	assert_almost_eq(main.flight_reference.frame.position.distance_to(station.global_position), 0.0, 0.01,
			"and the reference is at its stand-in")
	assert_eq(main.star_system.frame["kind"], ScenarioFrame.KIND_PLACE)


func test_another_seed_another_start_and_a_set_epoch_is_kept() -> void:
	await _start(ScenarioLoader.FREE_FLIGHT_PATH, 11)
	var first: float = main.world.epoch_s
	main.queue_free()
	await _ticks(2)
	await _start(ScenarioLoader.FREE_FLIGHT_PATH, 12)
	assert_ne(main.world.epoch_s, first, "free flight seeds its epoch per run")
	main.queue_free()
	await _ticks(2)
	await _start(ScenarioLoader.SANDBOX_PATH, 12)
	assert_eq(main.world.epoch_s, 540148.0, "the sandbox sets its own")
	assert_not_null(main.far_props.station)
	main.space_environment.scaled_space.refresh(main.camera_rig.active_camera())
	assert_gt(main.space_environment.scaled_space.key_light(), 0.999)
