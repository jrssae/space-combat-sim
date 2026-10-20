extends GutTest
## The raider flying in Jolt, headless (M2-T05, AC5): the M1 flight rules with the raider spec and its generated
## hardpoints (two nacelles instead of four pods). Straight-line thrust, no pitch or roll torque from the pods, one nacelle
## alone yaws the nose away from it (sign only: the lever arm is short), assist stops a spin, brake stops drift.
##
## Expected values come from the `ShipSpec` and the layout built from `hardpoints.json`, never literals. Timing is
## the same as in `test_ship_physics.gd`: `_align()` then commands apply in that tick.

const SPEC_PATH: String = "res://assets/ships/raider_delta_v.tres"
const GEN_ASSETS_HINT: String = "run scripts/gen_assets.sh, then scripts/run_tests.sh (it imports first)"
const ONE_DEG: float = PI / 180.0

var world: WorldFrame
var spec: ShipSpec
var ship: Ship


func before_each() -> void:
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	spec = load(SPEC_PATH) as ShipSpec
	ship = _spawn_ship(Vector3.ZERO)


func _spawn_ship(at: Vector3) -> Ship:
	var s: Ship = Ship.create(spec, world)
	world.spawn(s, world.to_universe(at))
	assert_true(s.get_layout().valid, "raider has a valid thruster layout (%s)" % GEN_ASSETS_HINT)
	return s


func _dt() -> float:
	return 1.0 / float(Engine.physics_ticks_per_second)


func _ticks(seconds: float) -> int:
	return roundi(seconds * float(Engine.physics_ticks_per_second))


func _align() -> void:
	await get_tree().physics_frame


func _step(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _cmd(main_left: float = 0.0, main_right: float = 0.0, brake: bool = false) -> FlightCommand:
	var cmd := FlightCommand.new()
	cmd.main_left = main_left
	cmd.main_right = main_right
	cmd.brake = brake
	return cmd


func _nozzle_count(group: int) -> int:
	return ship.get_layout().nozzles_in_group(group).size()


# --- the layout ----------------------------------------------------------------------------------------------------


func test_the_raider_has_two_nacelles_with_a_main_and_a_retro_each() -> void:
	var layout: ThrusterLayout = ship.get_layout()
	assert_eq(layout.pod_names, PackedStringArray(["l", "r"]))
	assert_eq(_nozzle_count(ThrusterLayout.Group.R_MAIN), 1)
	assert_eq(_nozzle_count(ThrusterLayout.Group.L_MAIN), 1)
	assert_eq(_nozzle_count(ThrusterLayout.Group.R_RETRO), 1)
	assert_eq(_nozzle_count(ThrusterLayout.Group.L_RETRO), 1)
	assert_eq(ship.get_muzzles().size(), 4, "four spike guns")
	assert_eq(ship.mass, spec.mass)
	assert_eq(ship.inertia, spec.inertia)


func test_pod_thrust_makes_no_pitch_or_roll_torque() -> void:
	for group: int in ThrusterLayout.GROUP_COUNT:
		var axis: Vector3 = ship.get_layout().torque_axis(group)
		assert_lt(absf(axis.x), 1e-6, "%s: no pitch torque" % ThrusterLayout.GROUP_NAMES[group])
		assert_lt(absf(axis.z), 1e-6, "%s: no roll torque" % ThrusterLayout.GROUP_NAMES[group])


func test_the_ship_is_built_with_the_newtonian_body_settings() -> void:
	assert_eq(ship.gravity_scale, 0.0)
	assert_eq(ship.linear_damp_mode, RigidBody3D.DAMP_MODE_REPLACE)
	assert_eq(ship.angular_damp_mode, RigidBody3D.DAMP_MODE_REPLACE)
	assert_eq(ship.linear_damp, 0.0)
	assert_eq(ship.angular_damp, 0.0)


# --- AC5: straight line -----------------------------------------------------------------------------------------


func test_both_mains_accelerate_straight_at_the_formula_rate() -> void:
	ship.assist_on = false
	var mains: int = _nozzle_count(ThrusterLayout.Group.R_MAIN) + _nozzle_count(ThrusterLayout.Group.L_MAIN)
	var burn: int = _ticks(2.0)
	var expected: float = 0.5 * mains * spec.pod_main_thrust / spec.mass * float(burn) * _dt()
	await _align()
	ship.set_flight_command(_cmd(0.5, 0.5))
	var max_w: float = 0.0
	for i: int in burn:
		await _step(1)
		max_w = maxf(max_w, ship.angular_velocity.length())
	var speed: float = ship.linear_velocity.length()
	gut.p("raider: speed after 2 s %.4f m/s, expected %.4f (%.3f %%), max |w| %s rad/s" % [speed, expected, 100.0 * (speed - expected) / expected, str(max_w)])
	assert_almost_eq(speed, expected, 0.01 * expected, "speed = 0.5 * 2 * T / m * 2 s within 1 %")
	assert_lt(max_w, 1e-3, "|w| < 1e-3 rad/s while burning")
	assert_almost_eq(ship.forward().dot(ship.linear_velocity.normalized()), 1.0, 1e-6, "straight ahead")


# --- AC5: one nacelle alone ---------------------------------------------------------------------------------------


func _kick(cmd: FlightCommand) -> Vector3:
	ship.assist_on = false
	await _align()
	ship.set_flight_command(cmd)
	await _step(_ticks(0.5))
	return ship.body_angular_velocity()


func test_the_right_nacelle_alone_yaws_the_nose_left() -> void:
	var w: Vector3 = await _kick(_cmd(0.0, 1.0))
	assert_gt(w.y, 0.0, "the right nacelle pushes from the right: nose left (+Y)")
	assert_lt(absf(w.x), 1e-3, "no pitch")
	assert_lt(absf(w.z), 1e-3, "no roll")


func test_the_left_nacelle_alone_yaws_the_nose_right() -> void:
	var w: Vector3 = await _kick(_cmd(1.0, 0.0))
	assert_lt(w.y, 0.0, "nose right")
	assert_lt(absf(w.x), 1e-3)
	assert_lt(absf(w.z), 1e-3)


# --- AC5: assist and brake ----------------------------------------------------------------------------------------


func test_assist_on_stops_a_45_dps_yaw_spin_within_a_second_and_a_half() -> void:
	ship.assist_on = true
	await _align()
	ship.angular_velocity = ship.global_basis * Vector3(0.0, deg_to_rad(45.0), 0.0)
	ship.set_flight_command(_cmd())
	var stopped_at: int = -1
	for i: int in _ticks(1.5):
		await _step(1)
		if stopped_at < 0 and ship.angular_velocity.length() < ONE_DEG:
			stopped_at = i + 1
	gut.p("raider assist: < 1 deg/s after %.3f s" % (float(stopped_at) * _dt()))
	assert_gt(stopped_at, 0, "stopped within 1.5 s")
	assert_lt(ship.angular_velocity.length(), ONE_DEG)


func test_assist_off_does_not_damp_the_spin() -> void:
	ship.assist_on = false
	var spin: float = deg_to_rad(45.0)
	await _align()
	ship.angular_velocity = ship.global_basis * Vector3(0.0, spin, 0.0)
	ship.set_flight_command(_cmd())
	var worst: float = 0.0
	for i: int in _ticks(2.0):
		await _step(1)
		worst = maxf(worst, absf(ship.angular_velocity.length() - spin) / spin)
	assert_lt(worst, 0.005, "the spin does not decay (within 0.5 % over 2 s)")


func test_brake_stops_drift_in_both_assist_modes() -> void:
	var other: Ship = _spawn_ship(Vector3(2000.0, 0.0, 0.0))  # far apart: both modes in one run
	ship.assist_on = true
	other.assist_on = false
	var v_body := Vector3(6.0, -3.0, -40.0)
	await _align()
	var ships: Array[Ship] = [ship, other]
	var stopped_at: Array[int] = [-1, -1]
	var max_w: Array[float] = [0.0, 0.0]
	for s: Ship in ships:
		s.linear_velocity = s.global_basis * v_body
		s.set_flight_command(_cmd(0.0, 0.0, true))
	for i: int in _ticks(9.0):
		await _step(1)
		for k: int in ships.size():
			max_w[k] = maxf(max_w[k], ships[k].angular_velocity.length())
			if stopped_at[k] < 0 and ships[k].linear_velocity.length() < 0.5:
				stopped_at[k] = i + 1
	for k: int in ships.size():
		var mode: String = "assist on" if ships[k].assist_on else "assist off"
		gut.p("raider brake %s: |v| < 0.5 m/s after %.3f s" % [mode, float(stopped_at[k]) * _dt()])
		assert_gt(stopped_at[k], 0, "%s: |v| < 0.5 m/s within 9 s" % mode)
		assert_lt(ships[k].linear_velocity.length(), 0.5, "%s: still stopped at 9 s" % mode)
		assert_lt(max_w[k], ONE_DEG, "%s: |w| < 1 deg/s throughout" % mode)


func test_an_empty_tank_cuts_the_nacelles() -> void:
	Settings.set_value(&"fuel_unlimited", false)
	ship.assist_on = false
	ship.get_fuel_tank().set_kg(0.0)
	await _align()
	ship.set_flight_command(_cmd(1.0, 1.0))
	await _step(_ticks(1.0))
	Settings.set_value(&"fuel_unlimited", true)
	assert_lt(ship.linear_velocity.length(), 0.5, "no reaction mass, no thrust")
