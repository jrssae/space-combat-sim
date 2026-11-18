extends GutTest
## Every player move puts the frame back on the station's rail first (M7-T71, maintainer 2026-11-17): after `frame drop 500`
## (or `frame orbit 400`) a `station goto`, `gate approach`, `respawn`, `tour <stop>`, `mines view` or `goto` leaves the player at
## rest at the new place with no planet pull, REF Babylon 5 and a closing speed that reads as closing; and the planet is drawn
## after `frame drop 500` (the scaled layer used to read a body's own rail as a free-falling anchor and drew it 90 million km off).

const SCENARIO: String = "res://data/scenarios/free_flight.json"
const PLANET: StringName = &"epsilon_iii"
const PLACE: StringName = &"babylon5"
## Float32 at 27 500 km steps in 2 m.
const FAR_M: float = 5.0

var main: Main
var world: WorldFrame


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
	world = main.world
	await _ticks(70)


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _station() -> Station:
	return main.far_props.station


# The frame moved away and the player falling toward the planet, as the maintainer had it.
func _leave(how: String) -> void:
	var result: ConsoleResult = _run(how)
	assert_true(result.ok, "%s: %s" % [how, result.error])
	assert_false(world.on_home_rail(), "%s: the frame left the station's rail" % how)
	await _ticks(60)


# After `what`, the frame rides the station's rail again, nothing pulls the player, it rests against the station, and the
# station stands on its rail.
func _check_home(what: String) -> void:
	assert_true(world.on_home_rail(), "%s: the frame back on the station's rail (%s)" % [what, world.anchor_text()])
	assert_eq(world.anchor_text(), "rail babylon5", what)
	await _ticks(30)
	var at: Vector3 = main.ship.global_position
	assert_false(world.gravity_active(), "%s: no pull here" % what)
	assert_almost_eq(world.gravity_residual(at), Vector3.ZERO, Vector3.ONE * 1e-6, "%s: no residual pull" % what)
	assert_lt((main.ship.linear_velocity - world.anchored_velocity()).length(), 0.05, "%s: at rest against the station" % what)
	var rail: PackedFloat64Array = world.body_state(PLACE)
	var off_rail: float = Vector3(rail[0], rail[1], rail[2]).distance_to(_station().global_position)
	assert_lt(off_rail, FAR_M, "%s: the station on its rail" % what)
	assert_lt(_station().global_position.distance_to(at), 100_000.0, "%s: beside the station, not 27 000 km off" % what)


# REF Babylon 5, and flying at the station reads as closing: the range drops by the speed it reads.
func _check_readings(what: String) -> void:
	main.flight_reference.update()
	assert_eq(main.flight_reference.frame.label, "BABYLON 5", "%s: REF Babylon 5" % what)
	assert_lt(main.flight_reference.speed_mps(), 0.05, "%s: reads at rest" % what)
	main.ship.set_assist(false)
	var toward: Vector3 = (_station().global_position - main.ship.global_position).normalized()
	main.ship.linear_velocity = world.anchored_velocity() + toward * 20.0
	await _ticks(1)
	var range_before: float = _station().global_position.distance_to(main.ship.global_position)
	await _ticks(60)
	var closed: float = range_before - _station().global_position.distance_to(main.ship.global_position)
	assert_almost_eq(closed, 20.0, 0.5, "%s: 20 m closed in a second toward the station" % what)
	assert_almost_eq(main.flight_reference.speed_mps(), 20.0, 0.2, "%s: the speed reads 20 m/s" % what)


func test_after_a_drop_station_goto_puts_the_player_at_rest_beside_the_bay() -> void:
	await _start()
	await _leave("frame drop 500")
	var result: ConsoleResult = _run("station goto main_docking_bay")
	assert_true(result.ok, result.error)
	var point: Dictionary = _station().hardpoints.tour("main_docking_bay")
	var spot: Vector3 = _station().to_world(point["position"], String(point["body"]))
	assert_lt(main.ship.global_position.distance_to(spot), 1.0, "at the bay's tour point")
	await _check_home("station goto after frame drop")
	await _check_readings("station goto after frame drop")


func test_after_an_orbit_station_goto_puts_the_player_at_rest_beside_the_bay() -> void:
	await _start()
	await _leave("frame orbit 400")
	assert_true(_run("station goto main_docking_bay").ok)
	await _check_home("station goto after frame orbit")
	await _check_readings("station goto after frame orbit")


func test_gate_approach_respawn_and_goto_return_the_frame() -> void:
	await _start()
	var gate: Jumpgate = main.gates.gate()
	await _leave("frame drop 500")
	assert_true(_run("gate approach").ok)
	assert_almost_eq(main.ship.global_position.distance_to(gate.global_position), 6000.0, 50.0, "6 km in front of the gate")
	await _check_home("gate approach")

	await _leave("frame drop 500")
	assert_true(_run("respawn").ok)
	var start: UniversePos = world.to_universe(main.ship.global_position)
	var spawn: UniversePos = main._spawn_position
	assert_lt(Vector3(start.x - spawn.x, start.y - spawn.y, start.z - spawn.z).length(), 1.0, "back at the scenario's start")
	await _check_home("respawn")
	await _check_readings("respawn")

	await _leave("frame orbit 400")
	assert_true(_run("goto babylon 5").ok)
	await _check_home("goto babylon 5")


func test_a_tour_stop_returns_the_frame() -> void:
	await _start()
	var stop_name: String = main.tours.book.order[0]
	await _leave("frame drop 500")
	var result: ConsoleResult = _run("tour %s" % stop_name)
	assert_true(result.ok, result.error)
	await _check_home("tour %s" % stop_name)
	_run("tour stop")


func test_mines_view_returns_the_frame() -> void:
	await _start()
	var near: Vector3 = _station().global_position + Vector3(3000.0, 0.0, 3000.0)
	main.bench.standins.add_mines([{"offset": Vector3.ZERO, "faction": Factions.EARTH_ALLIANCE}], world.to_universe(near))
	await _ticks(2)
	await _leave("frame drop 500")
	assert_true(_run("mines view 300").ok)
	await _check_home("mines view")
	var mines: MineStandin = main.bench.standins.get_node("Mines") as MineStandin
	assert_almost_eq(main.ship.global_position.distance_to(mines.position_of(0)), 300.0, 5.0, "300 m from the mine")


func test_the_planet_is_drawn_after_a_drop() -> void:
	await _start()
	await _leave("frame drop 500")
	var layer: ScaledSpace = get_tree().get_first_node_in_group(ScaledSpace.GROUP) as ScaledSpace
	var camera: Camera3D = get_viewport().get_camera_3d()
	layer.refresh(camera)
	var placed: ScaledPlacement = layer.placement_of(PLANET)
	assert_not_null(placed, "the planet is placed")
	var radius_m: float = float(world.star_system.info(PLANET)["radius_m"])
	var planet: PackedFloat64Array = world.body_state(PLANET)
	var eye: Vector3 = FarProp.drawn_pose(camera).origin
	var to_planet := Vector3(planet[0] - eye.x, planet[1] - eye.y, planet[2] - eye.z)
	gut.p("planet drawn %.1f km off (true %.1f km), %.1f deg across" % [placed.distance_m / 1000.0, to_planet.length() / 1000.0,
			placed.angular_size_deg()])
	assert_almost_eq(placed.distance_m, to_planet.length(), 100.0, "drawn as far off as it is (about 500 km over it)")
	assert_gt(placed.direction.dot(to_planet.normalized()), 0.9999, "drawn where it is")
	assert_true(layer.sphere_of(PLANET).visible, "its sphere shown")
	assert_false(layer.is_dotted(PLANET), "a disc, not a far dot")
	assert_lt(placed.offset.length() + placed.radius, camera.far, "inside the camera's range")
