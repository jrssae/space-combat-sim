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
	source.hold(InputAdapter.AUTOTRACK)  # one press switches it on
	await _ticks(2)
	source.release(InputAdapter.AUTOTRACK)
	await _ticks(358)
	assert_lt(_nose_error_deg(), 2.0, "the nose is on the lead point")
	assert_lt(main.ship.linear_velocity.distance_to(velocity_before), 1.0, "the velocity was not touched")
	assert_true(main.ship.get_flight_output().tracking, "and it stays on after the button is let go")
	source.hold(InputAdapter.AUTOTRACK)  # the next press switches it off
	await _ticks(2)
	source.release(InputAdapter.AUTOTRACK)
	await _ticks(2)
	assert_false(main.ship.get_flight_output().tracking, "off: the pilot has the stick again")


func test_autotrack_with_no_target_in_range_switches_itself_off() -> void:
	main.ship.targeting.clear_selection()
	source.hold(InputAdapter.AUTOTRACK)
	await _ticks(30)
	assert_false(main.ship.get_flight_output().tracking)
	assert_false(main.adapter.autotrack_on, "no hostile to take, so it is off again")


func test_autotrack_with_no_selection_takes_the_nearest_hostile() -> void:
	DebugConsole.registry.execute("spawn raider idle 1200 0 0")
	await _ticks(4)
	main.ship.targeting.clear_selection()
	source.hold(InputAdapter.AUTOTRACK)
	await _ticks(10)
	assert_true(main.ship.targeting.system.has_selection(), "a target was picked")
	assert_true(main.adapter.autotrack_on)


func test_autotrack_puts_the_nose_on_the_lead_of_a_crossing_target() -> void:
	# A raider crossing at 200 m/s, 1500 m ahead: its lead point sweeps at ~7 degrees per second. A controller that only chases
	# the position trails by that rate over its gain (about 5 degrees); with the rate fed forward the nose sits on the lead.
	DebugConsole.registry.execute("spawn raider idle 1500 0 0")
	await _ticks(4)
	var raider: Combatant = main.ships.alive(ShipPool.DEFAULT_TYPE)[0]
	raider.ship.linear_velocity = main.ship.global_basis.x * 200.0
	assert_true(main.ship.targeting.select_by_name("RAIDER 1"))
	source.hold(InputAdapter.AUTOTRACK)
	await _ticks(2)
	source.release(InputAdapter.AUTOTRACK)
	await _ticks(480)
	var readout: TargetReadout = main.ship.targeting.selected_readout()
	var weapon: WeaponSpec = main.ship.spec.weapon
	var lead: Dictionary = InterceptMath.solve(main.ship.global_position, main.ship.linear_velocity, readout.position,
			readout.velocity, weapon.muzzle_speed_mps, weapon.lifetime_s)
	assert_true(lead["ok"], "there is a lead solution")
	var off_deg: float = rad_to_deg(main.ship.forward().angle_to(lead["aim_dir"]))
	assert_lt(off_deg, 0.7, "the nose is on the aim line (%.2f deg off)" % off_deg)


func test_brake_still_stops_the_ship_on_its_own_button() -> void:
	main.ship.linear_velocity = main.ship.forward() * 100.0
	source.hold(InputAdapter.BRAKE)
	await _ticks(600)
	assert_lt(main.ship.linear_velocity.length(), 3.0, "all stop")


func _nose_error_deg() -> float:
	var readout: TargetReadout = main.ship.targeting.selected_readout()
	var to_target: Vector3 = (readout.position - main.ship.global_position).normalized()
	return rad_to_deg(main.ship.forward().angle_to(to_target))


func test_turning_the_ship_around_never_changes_its_velocity() -> void:
	# Newtonian: the velocity is a vector in space. Auto-track swings the nose through 180 degrees onto a target behind, and
	# the velocity does not move at all, because no nozzle fires; it only changes when the engines or the brake do.
	DebugConsole.registry.execute("spawn raider idle 1200 0 0")
	await _ticks(4)
	assert_true(main.ship.targeting.select_by_name("RAIDER 1"))
	main.ship.global_basis = Basis(Vector3.UP, PI)  # the raider is now dead astern
	main.ship.linear_velocity = Vector3(5.0, -3.0, 250.0)  # and the ship is moving
	var before: Vector3 = main.ship.linear_velocity
	await _ticks(2)
	source.hold(InputAdapter.AUTOTRACK)
	await _ticks(2)
	source.release(InputAdapter.AUTOTRACK)
	assert_gt(_nose_error_deg(), 150.0, "starting facing away from the target")
	var worst: float = 0.0
	for i: int in 420:
		await _ticks(1)
		worst = maxf(worst, main.ship.linear_velocity.distance_to(before))
	assert_lt(_nose_error_deg(), 2.0, "the nose came all the way round")
	assert_lt(worst, 0.01, "and the velocity never moved (worst change %.5f m/s)" % worst)
	assert_gt(main.ship.linear_velocity.length(), 200.0, "the ship is still travelling the same way")


func test_with_assist_off_turning_with_the_sticks_does_not_change_the_velocity_either() -> void:
	main.ship.set_assist(false)
	main.ship.linear_velocity = Vector3(0.0, 0.0, -400.0)
	var before: Vector3 = main.ship.linear_velocity
	source.hold(InputAdapter.ROLL_RIGHT, 1.0)
	source.hold(InputAdapter.PITCH_UP, 0.8)
	source.hold(InputAdapter.YAW_LEFT)
	await _ticks(180)
	assert_gt(main.ship.angular_velocity.length(), 0.1, "it is spinning")
	assert_lt(main.ship.linear_velocity.distance_to(before), 0.01, "but not going anywhere new")


func test_with_assist_on_turning_with_the_sticks_does_not_change_the_velocity() -> void:
	assert_true(main.ship.assist_on, "assist is on by default")
	main.ship.linear_velocity = Vector3(10.0, -4.0, -400.0)
	var before: Vector3 = main.ship.linear_velocity
	source.hold(InputAdapter.ROLL_RIGHT, 1.0)
	source.hold(InputAdapter.PITCH_UP, 0.8)
	source.hold(InputAdapter.YAW_LEFT)
	var worst: float = 0.0
	var peak_rate: float = 0.0
	for i: int in 240:
		await _ticks(1)
		worst = maxf(worst, main.ship.linear_velocity.distance_to(before))
		peak_rate = maxf(peak_rate, main.ship.angular_velocity.length())
	assert_gt(peak_rate, 0.5, "the assist spun the ship (%.2f rad/s)" % peak_rate)
	assert_lt(worst, 0.01, "and the velocity never moved (worst change %.5f m/s)" % worst)
	# Letting go: the flight computer stops the spin, again with no push on the ship.
	source.release_all()
	await _ticks(180)
	assert_lt(main.ship.angular_velocity.length(), 0.05, "the spin was damped by torque")
	assert_lt(main.ship.linear_velocity.distance_to(before), 0.01, "still not a metre per second different")


func test_the_canopy_glass_is_cleared_in_the_cockpit_and_back_outside() -> void:
	var mesh: Mesh = main.ship.hull_mesh_fallback.mesh
	assert_not_null(mesh)
	var glass: int = -1
	for i: int in mesh.get_surface_count():
		if String(mesh.surface_get_material(i).resource_name).contains("glass"):
			glass = i
	assert_gte(glass, 0, "the hull mesh has a glass surface")
	main.camera_rig.mode = CameraRig.Mode.COCKPIT
	await _ticks(2)
	assert_not_null(main.ship.hull_mesh_fallback.get_surface_override_material(glass), "cockpit: the glass draws nothing")
	main.camera_rig.mode = CameraRig.Mode.CHASE
	await _ticks(2)
	assert_null(main.ship.hull_mesh_fallback.get_surface_override_material(glass), "chase: the real glass again")
