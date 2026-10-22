extends GutTest
## PilotSteering (M2-T07, architecture §15.8): pure outer-loop steering in pilot terms.

const RATES := Vector3(1.0, 0.8, 1.5)  # rad/s pitch, yaw, roll limits
const TOL: float = 1e-6


func _cap() -> ShipCapability:
	var cap := ShipCapability.new()
	cap.a_main = 20.0
	cap.a_retro = 8.0
	cap.a_rcs = Vector2(10.0, 6.0)
	cap.rate_max_rad = RATES
	return cap


# --- face ----------------------------------------------------------------------------------------------------------


func test_a_direction_dead_ahead_commands_nothing() -> void:
	assert_eq(PilotSteering.face(Basis.IDENTITY, Vector3.FORWARD, RATES), Vector3.ZERO)
	assert_eq(PilotSteering.angle_to(Basis.IDENTITY, Vector3.FORWARD), 0.0)


func test_a_target_to_the_right_yaws_right_and_above_pitches_up() -> void:
	var right: Vector3 = PilotSteering.face(Basis.IDENTITY, Vector3(1.0, 0.0, -1.0), RATES)
	assert_gt(right.y, 0.0, "yaw right is positive")
	assert_almost_eq(right.x, 0.0, TOL)
	var left: Vector3 = PilotSteering.face(Basis.IDENTITY, Vector3(-1.0, 0.0, -1.0), RATES)
	assert_lt(left.y, 0.0)
	var up: Vector3 = PilotSteering.face(Basis.IDENTITY, Vector3(0.0, 1.0, -1.0), RATES)
	assert_gt(up.x, 0.0, "pitch up is positive")
	var down: Vector3 = PilotSteering.face(Basis.IDENTITY, Vector3(0.0, -1.0, -1.0), RATES)
	assert_lt(down.x, 0.0)


func test_the_rate_is_the_gain_times_the_angle_in_pilot_terms() -> void:
	var angle: float = deg_to_rad(10.0)
	var rot: Vector3 = PilotSteering.face(Basis.IDENTITY, Vector3(sin(angle), 0.0, -cos(angle)), RATES)
	assert_almost_eq(rot.y, PilotSteering.K_FACE * angle / RATES.y, 1e-6, "rot_y = K * angle / rate_max_y")
	var pitched: Vector3 = PilotSteering.face(Basis.IDENTITY, Vector3(0.0, sin(angle), -cos(angle)), RATES)
	assert_almost_eq(pitched.x, PilotSteering.K_FACE * angle / RATES.x, 1e-6)


func test_large_errors_saturate_and_roll_is_never_commanded() -> void:
	var rot: Vector3 = PilotSteering.face(Basis.IDENTITY, Vector3(1.0, 1.0, 0.2), RATES)
	assert_lte(absf(rot.x), 1.0)
	assert_lte(absf(rot.y), 1.0)
	assert_eq(rot.z, 0.0)
	assert_almost_eq(absf(rot.x), 1.0, TOL, "a big error saturates pitch")


func test_a_direction_dead_astern_pitches_up() -> void:
	var rot: Vector3 = PilotSteering.face(Basis.IDENTITY, Vector3.BACK, RATES)
	assert_gt(rot.x, 0.0)
	assert_eq(rot.y, 0.0)


func test_the_direction_is_taken_in_the_ships_own_frame() -> void:
	var turned := Basis(Vector3.UP, deg_to_rad(90.0))  # nose now along world -X
	var rot: Vector3 = PilotSteering.face(turned, Vector3(-1.0, 0.0, 0.0), RATES)
	assert_eq(rot, Vector3.ZERO, "already facing it")
	var behind_right: Vector3 = PilotSteering.face(turned, Vector3(-1.0, 0.0, -0.5), RATES)
	assert_gt(behind_right.y, 0.0, "world -Z is to the nose's right when it points along -X")


func test_a_zero_direction_commands_nothing() -> void:
	assert_eq(PilotSteering.face(Basis.IDENTITY, Vector3.ZERO, RATES), Vector3.ZERO)


func test_angle_to_is_the_angle_between_nose_and_direction() -> void:
	assert_almost_eq(PilotSteering.angle_to(Basis.IDENTITY, Vector3(1.0, 0.0, -1.0)), deg_to_rad(45.0), 1e-6)
	assert_almost_eq(PilotSteering.angle_to(Basis.IDENTITY, Vector3.BACK), PI, 1e-6)


# --- seek ----------------------------------------------------------------------------------------------------------


func test_a_small_velocity_error_coasts() -> void:
	var r: Dictionary = PilotSteering.seek(Vector3(10.0, 0.0, 0.0), Vector3(10.4, 0.0, 0.0), Basis.IDENTITY, _cap())
	assert_eq(r["main"], 0.0)
	assert_eq(r["retro"], 0.0)
	assert_eq(r["strafe"], Vector2.ZERO)


func test_an_error_along_the_nose_uses_the_mains_in_proportion() -> void:
	var r: Dictionary = PilotSteering.seek(Vector3.ZERO, Vector3(0.0, 0.0, -10.0), Basis.IDENTITY, _cap())
	assert_almost_eq(float(r["main"]), 10.0 / 20.0, TOL, "10 m/s of a = 20 m/s^2 over 1 s")
	assert_eq(r["retro"], 0.0)
	var big: Dictionary = PilotSteering.seek(Vector3.ZERO, Vector3(0.0, 0.0, -100.0), Basis.IDENTITY, _cap())
	assert_eq(big["main"], 1.0, "clamped")


func test_an_error_astern_uses_the_retros() -> void:
	var r: Dictionary = PilotSteering.seek(Vector3(0.0, 0.0, -40.0), Vector3.ZERO, Basis.IDENTITY, _cap())
	assert_eq(r["main"], 0.0)
	assert_almost_eq(float(r["retro"]), 1.0, TOL, "40 m/s against 8 m/s^2: full retros")
	var gentle: Dictionary = PilotSteering.seek(Vector3(0.0, 0.0, -4.0), Vector3.ZERO, Basis.IDENTITY, _cap())
	assert_almost_eq(float(gentle["retro"]), 0.5, TOL)


func test_a_sideways_error_uses_the_rcs_only() -> void:
	var r: Dictionary = PilotSteering.seek(Vector3.ZERO, Vector3(5.0, -3.0, 0.0), Basis.IDENTITY, _cap())
	assert_eq(r["main"], 0.0)
	assert_eq(r["retro"], 0.0)
	var strafe: Vector2 = r["strafe"]
	assert_almost_eq(strafe.x, 0.5, TOL, "sway right 5 m/s of 10")
	assert_almost_eq(strafe.y, -0.5, TOL, "heave down 3 m/s of 6")


func test_an_oblique_error_between_the_cones_uses_neither_mains_nor_retros() -> void:
	var r: Dictionary = PilotSteering.seek(Vector3.ZERO, Vector3(10.0, 0.0, -10.0), Basis.IDENTITY, _cap())
	assert_eq(r["main"], 0.0, "45 degrees off the nose: turn first")
	assert_eq(r["retro"], 0.0)
	assert_gt(float((r["strafe"] as Vector2).x), 0.0, "meanwhile the RCS starts on the sideways part")


func test_seek_works_in_the_ships_frame() -> void:
	var turned := Basis(Vector3.UP, deg_to_rad(90.0))  # nose along world -X
	var r: Dictionary = PilotSteering.seek(Vector3.ZERO, Vector3(-10.0, 0.0, 0.0), turned, _cap())
	assert_almost_eq(float(r["main"]), 0.5, TOL)


func test_apply_seek_drives_both_nacelles_equally() -> void:
	var flight := FlightCommand.new()
	PilotSteering.apply_seek(flight, {"main": 0.6, "retro": 0.0, "strafe": Vector2(0.1, -0.2)})
	assert_eq(flight.main_left, 0.6)
	assert_eq(flight.main_right, 0.6)
	assert_eq(flight.retro_left, 0.0)
	assert_eq(flight.strafe, Vector2(0.1, -0.2))
	PilotSteering.apply_seek(flight, {"main": 0.0, "retro": 0.3, "strafe": Vector2.ZERO})
	assert_eq([flight.retro_left, flight.retro_right], [0.3, 0.3])


# --- capability ------------------------------------------------------------------------------------------------------


func test_capability_comes_from_the_spec_and_the_layout() -> void:
	var spec := load("res://assets/ships/raider_delta_v.tres") as ShipSpec
	var layout: ThrusterLayout = ThrusterLayout.load_file("res://tests/fixtures/hardpoints_raider_nominal.json")
	var cap: ShipCapability = ShipCapability.from_spec(spec, layout)
	assert_almost_eq(cap.a_main, 2.0 * spec.pod_main_thrust / spec.mass, 1e-6, "two nacelles")
	assert_almost_eq(cap.a_retro, 2.0 * spec.pod_retro_thrust / spec.mass, 1e-6)
	assert_almost_eq(cap.a_rcs.x, spec.rcs_force_max.x / spec.mass, 1e-6)
	assert_eq(cap.rate_max_rad, spec.rate_max_rad())
