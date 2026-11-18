extends GutTest
## `frame drop <km> [body]` (M7-T14, maintainer 2026-11-15): the player at rest that high over Epsilon III or the star, the frame
## riding the body's rail, so the ship falls straight in under the body's whole pull (the HUD's ALT counting down); refused
## outside the body's zone (D66), for a negative altitude and for a body the system does not have.

const SPEC_PATH: String = "res://assets/ships/starfury_aurora.tres"
const PLANET: StringName = &"epsilon_iii"
const STAR: StringName = &"epsilon"
const DT: float = 1.0 / 60.0

var world: WorldFrame
var system: StarSystem
var ship: Ship
var _fuel_backup: bool


func before_each() -> void:
	_fuel_backup = bool(Settings.get_value(&"fuel_unlimited"))
	Settings.set_value(&"fuel_unlimited", true)
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	system = StarSystem.load_system(&"local")
	assert_true(world.anchor_on_rail(system, &"babylon5"))
	FlightBatch.attach(world)
	ship = Ship.create(load(SPEC_PATH) as ShipSpec, world)
	world.spawn(ship, world.to_universe(Vector3(120.0, 30.0, -40.0)))
	ship.assist_on = false
	ship.set_flight_command(FlightCommand.new())
	ship.linear_velocity = Vector3(50.0, 0.0, -20.0)
	world.focus = ship
	# Off the scenario's origin, so the drop has to place the ship, not the origin.
	world.rebase(Vector3(1500.0, -200.0, 800.0))


func after_each() -> void:
	Settings.set_value(&"fuel_unlimited", _fuel_backup)


func _run(line: String) -> ConsoleResult:
	var results: Array[ConsoleResult] = DebugConsole.registry.execute(line)
	return results[0]


# The ship's height over `body`'s surface and its velocity against the body, from the frame (what the HUD's ALT reads).
func _against(body: StringName) -> Array:
	var state: PackedFloat64Array = world.body_state(body)
	var at: Vector3 = ship.global_position
	# In 64-bit floats: a million km away a Vector3 steps in 64 m.
	var d: Array[float] = [state[0] - at.x, state[1] - at.y, state[2] - at.z]
	var distance: float = sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2])
	var velocity := Vector3(state[3], state[4], state[5])
	var radius_m: float = float(system.info(body)["radius_m"])
	return [distance - radius_m, ship.linear_velocity - velocity, Vector3(d[0], d[1], d[2]) / distance]


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func test_a_drop_puts_the_ship_at_rest_over_the_planet_and_it_falls_in_at_the_planets_pull() -> void:
	var result: ConsoleResult = _run("frame drop 400")
	assert_true(result.ok, result.error)
	assert_eq(world.anchor_text(), "rail epsilon_iii", "the frame rides the planet's rail, not an orbit round it")
	var start: Array = _against(PLANET)
	assert_almost_eq(float(start[0]), 400_000.0, 1.0, "400 km over the surface")
	assert_almost_eq((start[1] as Vector3).length(), 0.0, 1e-3, "at rest against the planet")
	var reference: Dictionary = world.reference_body(ship.global_position)
	assert_eq(reference.get("id", &""), PLANET, "the planet is the HUD's body")
	await _ticks(120)
	var later: Array = _against(PLANET)
	var r: float = float(system.info(PLANET)["radius_m"]) + 400_000.0
	var g: float = float(system.info(PLANET)["gm"]) / (r * r)
	var down: float = (later[1] as Vector3).dot(later[2] as Vector3)
	gut.p("after 2 s: ALT %.2f m, falling at %.3f m/s (g %.4f m/s^2)" % [later[0], down, g])
	assert_almost_eq(down, g * 120.0 * DT, g * 120.0 * DT * 0.02, "it falls in at the planet's pull there")
	assert_lt((later[1] as Vector3).length() - down, 0.05 * down, "straight in, not round")
	assert_lt(float(later[0]), float(start[0]) - 0.4 * g * 4.0, "the altitude counts down")


func test_a_drop_toward_the_star_falls_at_the_stars_pull() -> void:
	var result: ConsoleResult = _run("frame drop 1000000 epsilon")
	assert_true(result.ok, result.error)
	assert_eq(world.anchor_text(), "rail epsilon")
	var start: Array = _against(STAR)
	assert_almost_eq(float(start[0]), 1.0e9, 1.0, "a million km over the star")
	await _ticks(60)
	var later: Array = _against(STAR)
	var r: float = float(system.info(STAR)["radius_m"]) + 1.0e9
	var g: float = float(system.info(STAR)["gm"]) / (r * r)
	assert_almost_eq((later[1] as Vector3).dot(later[2] as Vector3), g * 60.0 * DT, g * 60.0 * DT * 0.02,
			"it falls in at the star's pull there")
	assert_lt(float(later[0]), float(start[0]), "the altitude counts down")


func test_a_drop_outside_the_bodys_zone_is_refused() -> void:
	var radius_km: float = float(system.info(PLANET)["radius_m"]) / 1000.0
	var zone_km: float = system.zone_radius_m(PLANET) / 1000.0
	var outside: ConsoleResult = _run("frame drop %.0f" % (zone_km - radius_km + 1000.0))
	assert_false(outside.ok, "beyond the planet's zone its pull does not reach")
	assert_string_contains(outside.error, "outside its zone")
	assert_eq(world.anchor_text(), "rail babylon5", "the frame is left as it was")
	assert_true(_run("frame drop %.0f" % (zone_km - radius_km - 1000.0)).ok, "just inside it is not")
	var far: ConsoleResult = _run("frame drop 20000000 epsilon")
	assert_false(far.ok, "20 million km is beyond the star's zone")
	assert_string_contains(far.error, "outside its zone")
	assert_false(_run("frame drop -5").ok, "a negative altitude is refused")
	assert_false(_run("frame drop 400 vega").ok, "a body the system does not have is refused")
	assert_false(_run("frame drop").ok, "an altitude is needed")
