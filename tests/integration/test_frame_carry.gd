extends GutTest
## `frame orbit`, `frame drop` and `frame rail` carry the player, not the world (M7-T66, maintainer 2026-11-17): after them
## Babylon 5 still stands on its rail, the gate beside it and the planet where the ephemeris puts it, so the station ends up
## over 22 000 km away; the player is on the orbit (or at rest over the planet) asked for, and `frame rail babylon5` brings
## it back to the start with everything where the scenario put it.

const SCENARIO: String = "res://data/scenarios/free_flight.json"
const PLANET: StringName = &"epsilon_iii"
const PLACE: StringName = &"babylon5"
## Babylon 5 is 27 500 km out; a float32 coordinate there steps in 2 m.
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


# Waits `n` ticks, then takes the next tick's sample now, as its first slot will: between ticks the anchor has stepped but
# the ephemeris still reads the last tick's time, so a rail would read a tick behind.
func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame
	world.sample_gravity(world.system_time())


func _station() -> Station:
	return main.far_props.station


# How far the station stands from where the ephemeris puts its rail now, in metres.
func _off_rail() -> float:
	var rail: PackedFloat64Array = world.body_state(PLACE)
	var at: Vector3 = _station().global_position
	return Vector3(rail[0] - at.x, rail[1] - at.y, rail[2] - at.z).length()


# The ship's height over the planet's surface and its velocity against the planet (64-bit sums).
func _over_planet() -> Array:
	var planet: PackedFloat64Array = world.body_state(PLANET)
	var at: Vector3 = main.ship.global_position
	var d := PackedFloat64Array([at.x - planet[0], at.y - planet[1], at.z - planet[2]])
	var r: float = sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2])
	var radius_m: float = float(world.star_system.info(PLANET)["radius_m"])
	return [r - radius_m, main.ship.linear_velocity - Vector3(planet[3], planet[4], planet[5]), r]


func _universe(at: UniversePos) -> Vector3:
	return Vector3(at.x, at.y, at.z)


func _gate_from_station() -> Vector3:
	return main.gates.gate().global_position - _station().global_position


func test_an_orbit_carries_the_player_and_leaves_the_station_and_the_gate_on_their_rail() -> void:
	await _start()
	assert_lt(_off_rail(), FAR_M, "the scenario stands the station on its rail")
	var gate_before: Vector3 = _gate_from_station()
	var start_km: float = _station().global_position.distance_to(main.ship.global_position) / 1000.0
	var result: ConsoleResult = _run("frame orbit 400")
	assert_true(result.ok, result.error)
	assert_eq(world.anchor_text(), "orbit epsilon_iii", "the frame rides a free-falling anchor on the orbit")
	await _ticks(60)
	var over: Array = _over_planet()
	var r: float = float(over[2])
	var circular: float = sqrt(float(world.star_system.info(PLANET)["gm"]) / r)
	gut.p("from %.1f km off the station: ALT %.2f m, %.3f m/s against the planet (circular %.3f), station %.0f km off, %.2f m off its rail" % [
			start_km, over[0], (over[1] as Vector3).length(), circular,
			_station().global_position.length() / 1000.0, _off_rail()])
	assert_almost_eq(float(over[0]), 400_000.0, 5.0, "400 km over Epsilon III")
	assert_almost_eq((over[1] as Vector3).length(), circular, 0.05, "at the circular orbit's speed")
	assert_lt(_off_rail(), FAR_M, "the station stayed on its rail")
	# The orbit starts on the day side (M7-T68): however the station stands, it is its orbit less the player's away or more.
	var apart: float = 2.75e7 - r - 10_000.0
	assert_gt(_station().global_position.distance_to(main.ship.global_position), apart, "so it is over 22 000 km away")
	assert_almost_eq(_gate_from_station(), gate_before, Vector3.ONE * FAR_M, "the gate stayed beside it")
	var rail: PackedFloat64Array = world.body_state(PLACE)
	assert_almost_eq(world.anchored_velocity(), Vector3(rail[3], rail[4], rail[5]), Vector3.ONE * 0.01,
			"what is tied to the anchor moves at its rail's velocity")
	await _ticks(600)
	assert_lt(_off_rail(), FAR_M, "ten seconds on, the station still follows its rail")
	assert_almost_eq(float(_over_planet()[0]), 400_000.0, 5.0, "and the player still circles at 400 km")


func test_a_drop_carries_the_player_and_rail_brings_it_back_to_the_start() -> void:
	await _start()
	var station_start: Vector3 = _universe(_station().universe_position())
	var gate_before: Vector3 = _gate_from_station()
	# A rock's row beside the station: rows have no node, and go back as exactly as the nodes do.
	var row_at: Vector3 = _station().global_position + Vector3(900.0, 40.0, -300.0)
	var row: int = StaticRows.new_id()
	StaticRows.register(row, row_at, 25.0, BodyKind.STATIC, Factions.NEUTRAL, world)
	var row_start: Vector3 = _universe(world.to_universe(row_at))
	var result: ConsoleResult = _run("frame drop 500")
	assert_true(result.ok, result.error)
	assert_eq(world.anchor_text(), "rail epsilon_iii")
	var start: Array = _over_planet()
	assert_almost_eq(float(start[0]), 500_000.0, 1.0, "500 km over Epsilon III")
	assert_almost_eq((start[1] as Vector3).length(), 0.0, 1e-3, "at rest against it")
	await _ticks(120)
	assert_lt(float(_over_planet()[0]), 500_000.0 - 5.0, "falling in")
	assert_lt(_off_rail(), FAR_M, "the station stayed on its rail")
	assert_almost_eq(_gate_from_station(), gate_before, Vector3.ONE * FAR_M, "the gate stayed beside it")
	result = _run("frame rail babylon5")
	assert_true(result.ok, result.error)
	await _ticks(60)
	assert_eq(world.anchor_text(), "rail babylon5")
	assert_true(world.riding(), "riding the station's rail again")
	assert_lt(_off_rail(), FAR_M, "the station on its rail")
	assert_almost_eq(_universe(_station().universe_position()), station_start, Vector3.ONE * 0.01,
			"exactly where the scenario put it")
	assert_almost_eq(_universe(world.to_universe(StaticRows.position_of(row))), row_start, Vector3.ONE * 0.01,
			"the rock's row too")
	StaticRows.unregister(row)
	assert_lt(_universe(world.to_universe(main.ship.global_position)).length(), 1.0, "the player back at the scenario's origin")
	assert_lt(main.ship.linear_velocity.length(), 0.01, "at rest against the station")
