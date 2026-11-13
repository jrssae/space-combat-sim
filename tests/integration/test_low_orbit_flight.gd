extends GutTest
## Flying a low orbit (M6-T08, AC5, Q4, Q5): the player's ship in a 400 km circular orbit of the fixture planet reads its speed
## against the circular orbit at its position, so it reads about 0; with assist on and the brake held it keeps its orbit,
## even in a frame boosted 6 km/s off it (where a speed read against the frame would brake it out of orbit and the assist's
## 5 000 m/s cap would hold it back); and the brake settles a ship that is off the orbit into the circular orbit at its
## altitude instead of stopping it against the planet's centre. Flown in Jolt at a hundred times the clock (quick: about 2 s).

const FreeFall: GDScript = preload("res://tests/integration/test_free_fall.gd")
const SPEC_PATH: String = "res://assets/ships/starfury_aurora.tres"
const SPEED_UP: float = 100.0
const STEPS_PER_FRAME: int = 32

var world: WorldFrame
var system: StarSystem
var ship: Ship
var reference: FlightReference
var _fuel_backup: bool
var _rate_backup: int
var _scale_backup: float
var _steps_backup: int
var _clock_backup: float


func before_each() -> void:
	_clock_backup = SimClock.now()
	_fuel_backup = bool(Settings.get_value(&"fuel_unlimited"))
	Settings.set_value(&"fuel_unlimited", true)
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	_steps_backup = Engine.max_physics_steps_per_frame
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	system = FreeFall.fixture_system()
	var radius_m: float = FreeFall.RADIUS_TERRA_M + FreeFall.ALTITUDE_M
	assert_true(world.anchor_in_orbit(system, &"terra", FreeFall.circular_state(radius_m, FreeFall.GM_TERRA)))
	ship = Ship.create(load(SPEC_PATH) as ShipSpec, world)
	ship.console_owner = true  # the player's own model
	world.spawn(ship, world.to_universe(Vector3.ZERO))
	ship.assist_on = true
	ship.set_flight_command(FlightCommand.new())
	reference = FlightReference.new()
	reference.world = world
	reference.ship = ship
	add_child_autofree(reference)
	world.focus = ship
	world.auto_rebase_distance_m = 5000.0  # as in flight: a ship 6 km/s off the frame leaves the origin fast


func after_each() -> void:
	Settings.set_value(&"fuel_unlimited", _fuel_backup)
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup
	SimClock.reset(_clock_backup)  # the fixture's tests after this one read the bodies at the clock they found


func _fast() -> void:
	Engine.max_physics_steps_per_frame = STEPS_PER_FRAME
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP


func _slow() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup


# The anchor's point on its orbit, in the local frame.
func _anchor_local() -> Vector3:
	return world.universe_to_local(UniversePos.new(0.0, 0.0, 0.0, world.origin.system_id))


# The ship's velocity against the planet, and its distance from the planet's centre.
func _about_planet() -> Array:
	var body: Dictionary = world.reference_body(ship.global_position)
	var p: PackedFloat64Array = body["position"]
	var v: PackedFloat64Array = body["velocity"]
	var r: float = (ship.global_position - Vector3(p[0], p[1], p[2])).length()
	return [ship.linear_velocity - Vector3(v[0], v[1], v[2]), r]


func test_a_ship_in_low_orbit_reads_about_zero_against_it() -> void:
	reference.update()
	assert_eq(reference.frame.kind, ReferenceFrame.Kind.BODY, "no place near: the planet is the reference")
	assert_eq(reference.frame.label, "TERRA")
	assert_lt(reference.speed_mps(), 0.01, "in a steady orbit the speed reads about 0, not 7.7 km/s")
	assert_almost_eq(reference.frame.altitude_m, FreeFall.ALTITUDE_M, 2.0)


func test_with_assist_on_and_the_brake_held_it_keeps_its_orbit() -> void:
	await _hold(0.0, 0.01, 0.005)


# 2 500 m/s off the frame is just past the automatic boost's threshold; float32 velocities there step in 2.4e-4 m/s, so a
# pull under about 0.015 m/s^2 rounds away each tick (T01's note, section 5) and the brake corrects what the rounding loses.
func test_it_keeps_its_orbit_in_a_frame_boosted_off_it() -> void:
	await _hold(2500.0, 0.2, 0.01)


# 6 000 m/s off the frame: past the assist's 5 000 m/s safe speed, which a speed read against the frame would hold the ship
# to, and the brake would stop it against the frame. The float32 floor is coarser again (velocities step in 4.9e-4 m/s).
func test_it_keeps_its_orbit_in_a_frame_boosted_past_the_assists_safe_speed() -> void:
	await _hold(6000.0, 0.5, 0.02)


# Holds the brake (assist on) for 20 s in a frame boosted `boost_mps` off the anchor: the ship stays within `budget_m` of the
# anchor's point and reads within `budget_mps` of 0 against the circular orbit.
func _hold(boost_mps: float, budget_m: float, budget_mps: float) -> void:
	if boost_mps > 0.0:
		world.boost(Vector3(0.0, 0.0, -boost_mps))
		await get_tree().physics_frame
		await get_tree().physics_frame
		assert_false(world.riding())
		assert_gt(ship.linear_velocity.length(), boost_mps - 100.0, "every local speed is %.0f m/s" % boost_mps)
	ship.set_flight_command(_brake())
	_fast()
	var worst_m: float = 0.0
	var worst_mps: float = 0.0
	var start: int = Engine.get_physics_frames()
	while Engine.get_physics_frames() - start < 1200:  # 20 s of the brake held, assist on
		await get_tree().physics_frame
		worst_m = maxf(worst_m, ship.global_position.distance_to(_anchor_local()))
		worst_mps = maxf(worst_mps, reference.speed_mps())
	var ticks: int = Engine.get_physics_frames() - start
	_slow()
	assert_lt(worst_m, budget_m, "the brake holds the orbit: at most %.3f m from the anchor's point over %d ticks" % [worst_m,
			ticks])
	assert_lt(worst_mps, budget_mps, "and the speed against the orbit stays about 0 (worst %.4f m/s)" % worst_mps)
	var about: Array = _about_planet()
	assert_almost_eq((about[0] as Vector3).length(), sqrt(FreeFall.GM_TERRA / float(about[1])), 0.1,
			"still circling at the circular speed")
	gut.p("held orbit %.0f m/s off the frame: worst %.3f m, %.4f m/s over %d ticks" % [boost_mps, worst_m, worst_mps, ticks])


func test_the_brake_settles_an_off_orbit_ship_into_the_circular_orbit() -> void:
	ship.linear_velocity = Vector3(25.0, 10.0, 40.0)  # outward, up, and slower than the orbit (prograde is -Z here)
	reference.update()
	assert_gt(reference.speed_mps(), 45.0, "off the orbit by about 48 m/s")
	ship.set_flight_command(_brake())
	_fast()
	var start: int = Engine.get_physics_frames()
	while Engine.get_physics_frames() - start < 1800:  # 30 s of the brake
		await get_tree().physics_frame
	ship.set_flight_command(FlightCommand.new())
	assert_lt(reference.speed_mps(), 0.1, "settled: %.4f m/s against the circular orbit" % reference.speed_mps())
	var about: Array = _about_planet()
	var circular: float = sqrt(FreeFall.GM_TERRA / float(about[1]))
	var v: Vector3 = about[0]
	assert_almost_eq(v.length(), circular, 0.1, "circling at %.2f m/s, the circular %.2f m/s at its altitude" % [v.length(),
			circular])
	assert_gt(v.length(), 7000.0, "not stopped against the planet's centre")
	var worst: float = 0.0
	start = Engine.get_physics_frames()
	while Engine.get_physics_frames() - start < 3600:  # a minute's coast after the brake
		await get_tree().physics_frame
		worst = maxf(worst, reference.speed_mps())
	_slow()
	assert_lt(worst, 0.5, "coasting, the orbit stays circular (worst %.3f m/s against it)" % worst)
	gut.p("settled at %.3f km up, coast worst %.4f m/s" % [(float(about[1]) - FreeFall.RADIUS_TERRA_M) / 1000.0, worst])


func _brake() -> FlightCommand:
	var cmd := FlightCommand.new()
	cmd.brake = true
	return cmd
