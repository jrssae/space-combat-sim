extends GutTest
## `goto <nav point>` (M7-T67): the player is put clear of a bay, the station, the gate, a NAV buoy or a body, at rest against it and
## facing it, and the station and the gate keep their universe positions; with no argument it lists the nav points; a mission refuses.

const SCENARIO: String = "res://data/scenarios/free_flight.json"
const MISSION: String = "res://tests/fixtures/missions/test_mission.json"
const HOLD_TICKS: int = 600
## Float32 at 27 500 km steps in 2 m.
const FAR_M: float = 5.0

var main: Main


func before_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()


func after_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()


func _start(scenario: String = SCENARIO) -> void:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = scenario
	main.raider_pool_size = 0
	main.waves_auto_start = false
	add_child_autofree(main)
	for i: int in 70:
		await get_tree().physics_frame


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


# How far a place stands from where the ephemeris puts its rail now, m (the anchor moves, so universe numbers against it do not hold).
func _off_rail(node: Node3D, id: StringName) -> float:
	var rail: PackedFloat64Array = main.world.body_state(id)
	var at: Vector3 = node.global_position
	return Vector3(rail[0] - at.x, rail[1] - at.y, rail[2] - at.z).length()


func _universe_of(node: Node3D) -> Vector3:
	var u: UniversePos = main.world.to_universe(node.global_position)
	return Vector3(u.x, u.y, u.z)


# Goes to `place_name`, then checks the player stands clear, faces `target`, rests against it and is not rammed over 10 s.
func _arrive(place_name: String, target: Node3D, target_velocity: Vector3) -> void:
	var rams_before: int = main.rams.events
	var result: ConsoleResult = _run("goto %s" % place_name)
	assert_true(result.ok, "%s: accepted (%s)" % [place_name, result.text() if result.has_method(&"text") else ""])
	var to_target: Vector3 = target.global_position - main.ship.global_position
	assert_gt(to_target.length(), 200.0, "%s: clear of it" % place_name)
	assert_gt((-main.ship.global_basis.z).dot(to_target.normalized()), 0.99, "%s: facing it" % place_name)
	assert_lt((main.ship.linear_velocity - target_velocity).length(), 0.5, "%s: at rest against it" % place_name)
	var hull: HullHealth = Damageable.of(main.ship).hull
	for i: int in HOLD_TICKS:
		await get_tree().physics_frame
	assert_eq(main.rams.events, rams_before, "%s: no ram in 10 s" % place_name)
	assert_eq(hull.hp, hull.max_hp, "%s: the hull is whole" % place_name)
	assert_lt((main.ship.linear_velocity - target_velocity).length(), 1.0, "%s: still at rest against it" % place_name)


func test_the_list_names_every_nav_point() -> void:
	await _start()
	var text: String = _run("goto").text()
	var lines: PackedStringArray = text.split("\n")
	for expected: String in ["BABYLON 5", "BABYLON 5 DOCKING BAY", "BABYLON 5 CARGO BAY", main.gates.gate().display_name, "Epsilon III", "Epsilon"]:
		assert_true(lines.has(expected), "the list has %s (%s)" % [expected, text])
	for buoy: NavBuoy in main.buoys:
		assert_true(lines.has(buoy.display_name), "the list has %s" % buoy.display_name)


func test_prefix_matching() -> void:
	var names := PackedStringArray(["BABYLON 5", "BABYLON 5 DOCKING BAY", "NAV ALPHA", "NAV BETA", "Epsilon", "Epsilon III"])
	assert_eq(NavGoto.match_names(names, "nav a"), PackedStringArray(["NAV ALPHA"]), "a unique prefix, any case")
	assert_eq(NavGoto.match_names(names, "nav").size(), 2, "an ambiguous prefix lists its matches")
	assert_eq(NavGoto.match_names(names, "babylon 5"), PackedStringArray(["BABYLON 5"]), "an exact name wins over longer ones")
	assert_eq(NavGoto.match_names(names, "epsilon"), PackedStringArray(["Epsilon"]), "an exact name wins over longer ones")
	assert_eq(NavGoto.match_names(names, "zeta").size(), 0, "no match")


func test_a_prefix_and_an_ambiguity_at_the_console() -> void:
	await _start()
	assert_true(_run("goto babylon 5 dock").ok, "a unique prefix goes")
	var ambiguous: ConsoleResult = _run("goto babylon 5 ")
	assert_true(ambiguous.ok, "BABYLON 5 is exact")
	var several: ConsoleResult = _run("goto b")
	assert_false(several.ok, "'b' fits several")
	assert_string_contains(several.text(), "BABYLON 5 CARGO BAY")


func test_goto_the_docking_bay() -> void:
	await _start()
	var station: Station = main.far_props.station
	await _arrive("babylon 5 docking bay", station.docking_bay, main.world.rest_velocity())


func test_goto_the_cargo_bay() -> void:
	await _start()
	var station: Station = main.far_props.station
	await _arrive("babylon 5 cargo bay", station.cargo_bay, main.world.rest_velocity())


func test_goto_the_station() -> void:
	await _start()
	var station: Station = main.far_props.station
	var before: Vector3 = _universe_of(station)
	await _arrive("babylon 5", station, main.world.rest_velocity())
	assert_lt(_universe_of(station).distance_to(before), FAR_M, "the station did not move")


func test_goto_the_gate() -> void:
	await _start()
	var gate: Jumpgate = main.gates.gate()
	var before: Vector3 = _universe_of(gate)
	await _arrive(gate.display_name, gate, main.world.rest_velocity())
	assert_lt(_universe_of(gate).distance_to(before), FAR_M, "the gate did not move")


func test_goto_a_nav_point() -> void:
	await _start()
	assert_false(main.buoys.is_empty(), "(the scenario has NAV points)")
	var buoy: NavBuoy = main.buoys[0]
	await _arrive(buoy.display_name, buoy, buoy.targetable.get_target_velocity())


func test_goto_a_body_is_a_safe_orbit_and_the_station_stays() -> void:
	await _start()
	var station: Station = main.far_props.station
	var rams_before: int = main.rams.events
	assert_true(_run("goto Epsilon III").ok, "accepted")
	var planet: PackedFloat64Array = main.world.body_state(&"epsilon_iii")
	var at: Vector3 = main.ship.global_position
	var d := Vector3(planet[0] - at.x, planet[1] - at.y, planet[2] - at.z)
	var info: Dictionary = main.world.star_system.info(&"epsilon_iii")
	assert_gt(d.length() - float(info["radius_m"]), float(info["atmosphere_top_m"]), "above the atmosphere")
	assert_gt((-main.ship.global_basis.z).dot(d.normalized()), 0.99, "facing the planet")
	var layer: ScaledSpace = main.space_environment.scaled_space
	layer.refresh(get_viewport().get_camera_3d())
	assert_gt((-d.normalized()).dot(layer.sun_direction()), 0.9, "on the day side (M7-T68)")
	assert_lt(_off_rail(station, &"babylon5"), FAR_M, "the station kept its universe position")
	assert_lt(_off_rail(main.gates.gate(), &"jumpgate"), 4.0 * FAR_M, "the gate kept its universe position")
	for i: int in HOLD_TICKS:
		await get_tree().physics_frame
	assert_eq(main.rams.events, rams_before, "no ram in 10 s")
	assert_true(main.player_alive, "the player lives")
	var after: PackedFloat64Array = main.world.body_state(&"epsilon_iii")
	var now: Vector3 = main.ship.global_position
	var alt: float = Vector3(after[0] - now.x, after[1] - now.y, after[2] - now.z).length() - float(info["radius_m"])
	assert_gt(alt, float(info["atmosphere_top_m"]), "still above the atmosphere after 10 s")
	# Back to the station from the orbit: the frame returns to its rail and the player stands clear of it.
	assert_true(_run("goto babylon 5").ok, "back to the station")
	assert_lt(_off_rail(station, &"babylon5"), FAR_M, "the station is on its rail")
	assert_gt(main.ship.global_position.distance_to(station.global_position), 200.0, "clear of the station")


func test_refused_in_a_mission() -> void:
	await _start(MISSION)
	var result: ConsoleResult = _run("goto babylon 5")
	assert_false(result.ok, "no goto in a mission")
