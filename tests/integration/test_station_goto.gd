extends GutTest
## `station goto <point>` right after `play station_launch` (M7-T63): the launch ends first, then the player rests at the tour point
## against what is near it, and 30 s later has not been rammed or hurt, whichever of the station's moving parts is close.

const DT: float = 1.0 / 60.0
const SCENARIO: String = "res://data/scenarios/station_launch.json"
const HOLD_TICKS: int = 1800
const POINTS: Array[String] = ["bow", "main_docking_bay", "cargo_bay", "cobra_arm", "grid_tower", "drum", "vanes", "reactor"]

var main: Main


# A slow file: eight points of 30 s each; runs with GUT_SLOW=1.
@warning_ignore("untyped_declaration")  # GutTest declares it untyped
func should_skip_script():
	return SlowTests.skip_reason()


func before_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()


func after_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()


func _start() -> void:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = SCENARIO
	main.raider_pool_size = 0
	main.waves_auto_start = false
	add_child_autofree(main)
	for i: int in 70:
		await get_tree().physics_frame


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


func _survives(point_name: String) -> void:
	await _start()
	var rams_before: int = main.rams.events
	var result: ConsoleResult = _run("station goto %s" % point_name)
	assert_true(result.ok, "%s: the goto is accepted" % point_name)
	for i: int in 1600:  # the launch lets go when its arm is clear of the frame
		if not main.launches.locks_controls():
			break
		await get_tree().physics_frame
	await get_tree().physics_frame
	assert_false(main.launches.locks_controls(), "%s: the launch is over" % point_name)
	var hull: HullHealth = Damageable.of(main.ship).hull
	for i: int in HOLD_TICKS:
		await get_tree().physics_frame
		if main.rams.events != rams_before or hull.hp < hull.max_hp:
			break
	assert_eq(main.rams.events, rams_before, "%s: no ram in 30 s" % point_name)
	assert_true(main.player_alive, "%s: the player lives" % point_name)
	assert_eq(hull.hp, hull.max_hp, "%s: the hull is whole" % point_name)
	# A point on the turning drum cannot be held (a free ship flies straight, the drum turns): only the frame's are.
	var station: Station = main.far_props.station
	var point: Dictionary = station.hardpoints.tour(point_name)
	if String(point["body"]) == StationHardpoints.FRAME:
		var there: Vector3 = station.to_world(point["position"], StationHardpoints.FRAME)
		assert_lt(main.ship.global_position.distance_to(there), 20.0, "%s: the player stayed at rest against its point" % point_name)


func test_the_tour_points_are_the_ones_tested() -> void:
	await _start()
	var names: Array[String] = []
	for entry: Dictionary in main.far_props.station.hardpoints.tour_points:
		names.append(String(entry["name"]))
	assert_eq(names, POINTS, "a new tour point needs its own survival test here")


func test_survives_bow() -> void:
	await _survives("bow")


func test_survives_main_docking_bay() -> void:
	await _survives("main_docking_bay")


func test_survives_cargo_bay() -> void:
	await _survives("cargo_bay")


func test_survives_cobra_arm() -> void:
	await _survives("cobra_arm")


func test_survives_grid_tower() -> void:
	await _survives("grid_tower")


func test_survives_drum() -> void:
	await _survives("drum")


func test_survives_vanes() -> void:
	await _survives("vanes")


func test_survives_reactor() -> void:
	await _survives("reactor")


# Council round 1 (O3): a second goto during the same launch takes the place of the first.
func test_the_last_goto_asked_during_a_launch_wins() -> void:
	await _start()
	assert_true(main.launches.locks_controls(), "(a launch in progress)")
	assert_true(_run("station goto bow").ok)
	assert_true(_run("station goto cargo_bay").ok, "a second goto is accepted")
	for i: int in 1600:
		if not main.launches.locks_controls():
			break
		await get_tree().physics_frame
	await get_tree().physics_frame
	var station: Station = main.far_props.station
	var point: Dictionary = station.hardpoints.tour("cargo_bay")
	var there: Vector3 = station.to_world(point["position"], String(point["body"]))
	assert_lt(main.ship.global_position.distance_to(there), 50.0, "at the second point")


# Council round 1 (O3): a goto still waiting when the player dies is dropped: a later launch's release leaves the player be.
func test_a_goto_waiting_on_a_launch_is_dropped_when_the_player_dies() -> void:
	await _start()
	assert_true(_run("station goto bow").ok)
	Damageable.of(main.ship).invulnerable = false
	Damageable.of(main.ship).kill()
	await get_tree().physics_frame
	assert_false(main.player_alive, "(the player died before the release)")
	main.respawn()
	await get_tree().physics_frame
	var before: Vector3 = main.ship.global_position
	main.launches.player_released.emit()  # as the next launch's release would
	assert_lt(main.ship.global_position.distance_to(before), 1.0, "the dropped goto does not move the player")
