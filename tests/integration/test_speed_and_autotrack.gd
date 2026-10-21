extends GutTest
## The speed ceilings (assist's 5000 m/s safe speed, the 9999 m/s hard limit with thrust fading toward it) and the X-button
## auto-track (the nose follows the lead point of the selected target, the velocity untouched).

var main: Main
var source: FakeInputSource


func before_each() -> void:
	get_tree().paused = false
	DebugConsole.flags.invulnerable = true
	source = FakeInputSource.new()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	main.waves_auto_start = false
	add_child_autofree(main)
	await _ticks(2)


func after_each() -> void:
	DebugConsole.flags.invulnerable = false
	get_tree().paused = false


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func test_the_limits_are_in_the_ship_spec() -> void:
	assert_eq(main.ship.spec.assist_speed_max_mps, 5000.0)
	assert_eq(main.ship.spec.speed_limit_mps, 9999.0)
	assert_gte(float(ProjectSettings.get_setting("physics/jolt_physics_3d/limits/max_linear_velocity")), 9999.0,
			"Jolt must not clamp below the ship's own limit")


func test_the_bolts_leave_at_1000_m_s_relative_to_the_ship() -> void:
	assert_eq(main.cannon.weapon.muzzle_speed_mps, 1000.0)


func test_assist_stops_accelerating_at_the_safe_speed() -> void:
	main.ship.linear_velocity = main.ship.forward() * 4900.0
	source.hold(InputAdapter.MAIN_LEFT)
	source.hold(InputAdapter.MAIN_RIGHT)
	await _ticks(300)
	var speed: float = main.ship.linear_velocity.length()
	assert_gt(speed, 4900.0, "it did accelerate toward the cap")
	assert_lt(speed, main.ship.spec.assist_speed_max_mps + 2.0, "and stopped there")


func test_assist_does_not_brake_a_ship_that_is_already_faster() -> void:
	main.ship.set_assist(false)
	main.ship.linear_velocity = main.ship.forward() * 7000.0
	main.ship.set_assist(true)
	await _ticks(120)
	assert_almost_eq(main.ship.linear_velocity.length(), 7000.0, 1.0, "coasting above the cap is left alone")


func test_without_assist_thrust_fades_toward_the_hard_limit() -> void:
	main.ship.set_assist(false)
	main.ship.linear_velocity = main.ship.forward() * 9500.0
	source.hold(InputAdapter.MAIN_LEFT)
	source.hold(InputAdapter.MAIN_RIGHT)
	await _ticks(600)
	var speed: float = main.ship.linear_velocity.length()
	assert_gt(speed, 9500.0, "still gaining")
	assert_lte(speed, main.ship.spec.speed_limit_mps, "never past the limit")
	# At 9500 m/s the gain is sqrt(1 - (9500/9999)^2), about 0.31, so ten seconds of full mains add well under their rest value.
	var at_rest_gain: float = (main.ship.get_flight_output().pod_force_b.length() / main.ship.mass) * 10.0
	assert_lt(speed - 9500.0, at_rest_gain * 0.6, "the same thrust gives much less acceleration up there")


func test_a_rest_burst_accelerates_at_full_thrust() -> void:
	source.hold(InputAdapter.MAIN_LEFT)
	source.hold(InputAdapter.MAIN_RIGHT)
	await _ticks(60)
	var expected: float = main.ship.get_flight_output().pod_force_b.length() / main.ship.mass  # m/s² at the rest gain
	assert_almost_eq(main.ship.linear_velocity.length(), expected * 1.0, expected * 0.15, "about one second of full thrust")


func test_autotrack_swings_the_nose_onto_the_target_and_keeps_the_velocity() -> void:
	DebugConsole.registry.execute("spawn raider idle 1500 0 0")  # dead ahead of the nose
	await _ticks(4)
	assert_true(main.ship.targeting.select_by_name("RAIDER 1"), "a target to track")
	main.ship.global_basis = Basis(Vector3.UP, deg_to_rad(40.0)) * Basis(Vector3.RIGHT, deg_to_rad(-15.0))  # nose swung away
	await _ticks(2)
	main.ship.linear_velocity = Vector3(3.0, 2.0, -100.0)
	var velocity_before: Vector3 = main.ship.linear_velocity
	var angle_before: float = _nose_error_deg()
	assert_gt(angle_before, 20.0, "starts well off the target")
	source.hold(InputAdapter.AUTOTRACK)
	await _ticks(360)
	assert_lt(_nose_error_deg(), 2.0, "the nose is on the lead point")
	assert_lt(main.ship.linear_velocity.distance_to(velocity_before), 1.0, "the velocity was not touched")
	assert_true(main.ship.get_flight_output().tracking)
	source.release(InputAdapter.AUTOTRACK)
	await _ticks(2)
	assert_false(main.ship.get_flight_output().tracking, "let go, the pilot has the stick again")


func test_autotrack_with_no_target_does_nothing() -> void:
	main.ship.targeting.clear_selection()
	source.hold(InputAdapter.AUTOTRACK)
	await _ticks(30)
	assert_false(main.ship.get_flight_output().tracking)


func test_brake_still_stops_the_ship_on_its_own_button() -> void:
	main.ship.linear_velocity = main.ship.forward() * 100.0
	source.hold(InputAdapter.BRAKE)
	await _ticks(600)
	assert_lt(main.ship.linear_velocity.length(), 3.0, "all stop")


func _nose_error_deg() -> float:
	var readout: TargetReadout = main.ship.targeting.selected_readout()
	var to_target: Vector3 = (readout.position - main.ship.global_position).normalized()
	return rad_to_deg(main.ship.forward().angle_to(to_target))
