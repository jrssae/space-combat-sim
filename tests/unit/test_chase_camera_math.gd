extends GutTest
## ChaseCameraMath: the rigid chase pose and the optional orientation lag (architecture §8). Pure, so exact numbers
## can be checked.

const TOL: float = 1e-4

var cfg: ChaseCameraConfig


func before_each() -> void:
	cfg = ChaseCameraConfig.new()


func _ship(yaw_deg: float = 0.0, pitch_deg: float = 0.0, at: Vector3 = Vector3.ZERO) -> Transform3D:
	var basis: Basis = Basis(Vector3.UP, deg_to_rad(yaw_deg)) * Basis(Vector3.RIGHT, deg_to_rad(pitch_deg))
	return Transform3D(basis, at)


## A camera pose that is far from any goal, in both position and orientation.
func _stale_pose() -> Transform3D:
	return Transform3D(Basis(Vector3(1.0, 2.0, 3.0).normalized(), deg_to_rad(110.0)), Vector3(30.0, -12.0, 80.0))


func _pose_error(a: Transform3D, b: Transform3D) -> float:
	return a.origin.distance_to(b.origin) + a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion())


func _assert_poses_equal(a: Transform3D, b: Transform3D, tol: float, what: String) -> void:
	assert_almost_eq(a.origin, b.origin, Vector3(tol, tol, tol), what + " (origin)")
	assert_almost_eq(a.basis.x, b.basis.x, Vector3(tol, tol, tol), what + " (basis x)")
	assert_almost_eq(a.basis.y, b.basis.y, Vector3(tol, tol, tol), what + " (basis y)")
	assert_almost_eq(a.basis.z, b.basis.z, Vector3(tol, tol, tol), what + " (basis z)")


func _v(tol: float) -> Vector3:
	return Vector3(tol, tol, tol)


## The rigid pose of the camera for `ship`: a start pose whose orientation differs from the goal of another attitude.
func _pose_for(ship: Transform3D) -> Transform3D:
	return ChaseCameraMath.target_pose(ship, cfg)


# --- goal pose -----------------------------------------------------------------------------------------------


func test_default_config_matches_the_design_numbers() -> void:
	assert_eq(cfg.offset_local, Vector3(0.0, 2.5, 9.0))
	assert_eq(cfg.look_ahead_m, 40.0)
	assert_eq(cfg.smoothing_s, 0.0, "rigid by default")


func test_goal_is_behind_and_above_a_ship_at_rest_orientation() -> void:
	var goal: Transform3D = ChaseCameraMath.target_pose(Transform3D.IDENTITY, cfg)
	assert_eq(goal.origin, Vector3(0.0, 2.5, 9.0))
	# Looks forward (-Z) and slightly down, at the point 40 m ahead of the ship.
	var forward: Vector3 = -goal.basis.z
	assert_lt(forward.z, -0.99, "looks ahead of the ship")
	assert_lt(forward.y, 0.0, "tilts down toward the aim point")
	assert_almost_eq(forward, (Vector3(0.0, 0.0, -40.0) - goal.origin).normalized(), Vector3(TOL, TOL, TOL))
	assert_almost_eq(goal.basis.y.dot(Vector3.UP), 1.0, 0.01, "no roll for a level ship")


func test_goal_follows_ship_position_and_orientation() -> void:
	var ship: Transform3D = _ship(90.0, 0.0, Vector3(100.0, 5.0, -20.0))
	var goal: Transform3D = ChaseCameraMath.target_pose(ship, cfg)
	# Yawed +90 degrees about Y: ship-local +Z (behind) points along world +X, forward (-Z) along world -X.
	assert_almost_eq(goal.origin, Vector3(109.0, 7.5, -20.0), Vector3(TOL, TOL, TOL))
	assert_gt((goal.origin - ship.origin).dot(ship.basis.z), 8.9, "behind the ship along its own axis")
	assert_gt((goal.origin - ship.origin).dot(ship.basis.y), 2.4, "above the ship along its own up axis")
	assert_gt((-goal.basis.z).dot(-ship.basis.z), 0.99, "camera heading follows the ship heading")


func test_goal_rolls_with_the_ship() -> void:
	var ship := Transform3D(Basis(Vector3.FORWARD, deg_to_rad(60.0)), Vector3.ZERO)
	var goal: Transform3D = ChaseCameraMath.target_pose(ship, cfg)
	assert_almost_eq(goal.basis.y.dot(ship.basis.y), 1.0, 0.01, "camera up stays the ship's up")


func test_goal_ignores_ship_scale() -> void:
	var scaled := Transform3D(Basis.IDENTITY.scaled(Vector3(3.0, 3.0, 3.0)), Vector3.ZERO)
	var goal: Transform3D = ChaseCameraMath.target_pose(scaled, cfg)
	assert_eq(goal.origin, Vector3(0.0, 2.5, 9.0), "offset is in metres, not scaled with the ship")
	assert_almost_eq(goal.basis.x.length(), 1.0, TOL)


func test_degenerate_geometry_keeps_the_ship_heading_instead_of_erroring() -> void:
	# Camera sitting on its own look-at point, and a camera straight above the aim point (direction parallel to up).
	for geometry: Array in [[Vector3(0.0, 0.0, -40.0), 40.0], [Vector3(0.0, 10.0, 0.0), 0.0]]:
		cfg.offset_local = geometry[0]
		cfg.look_ahead_m = geometry[1]
		var ship: Transform3D = _ship(33.0, 12.0, Vector3(5.0, 6.0, 7.0))
		var goal: Transform3D = ChaseCameraMath.target_pose(ship, cfg)
		assert_true(goal.is_finite(), "finite pose for offset %s" % geometry[0])
		_assert_poses_equal(Transform3D(goal.basis, Vector3.ZERO), Transform3D(ship.basis, Vector3.ZERO), TOL,
				"falls back to the ship's heading for offset %s" % geometry[0])


# --- rigid mount ---------------------------------------------------------------------------------------------


func test_target_pose_is_the_ship_pose_times_the_fixed_local_pose() -> void:
	var local: Transform3D = ChaseCameraMath.local_pose(cfg)
	assert_eq(local.origin, cfg.offset_local)
	for ship: Transform3D in [_ship(), _ship(90.0, 0.0, Vector3(100.0, 5.0, -20.0)), _ship(-130.0, 40.0, Vector3(-3.0, 8.0, 12.0)),
			Transform3D(Basis(Vector3(0.3, -0.5, 0.8).normalized(), deg_to_rad(200.0)), Vector3(30.0, -60.0, 20.0))]:
		var goal: Transform3D = ChaseCameraMath.target_pose(ship, cfg)
		_assert_poses_equal(ship.orthonormalized().affine_inverse() * goal, local, TOL, "fixed in ship space")
	# Single precision: far from the origin the poses themselves are only good to a few ulps (a metre at 1e7 m).
	var far := Transform3D(Basis(Vector3(0.3, -0.5, 0.8).normalized(), deg_to_rad(200.0)), Vector3(1e3, -2e3, 5e2))
	_assert_poses_equal(far.orthonormalized().affine_inverse() * ChaseCameraMath.target_pose(far, cfg), local, 2e-3, "far away")


func test_local_pose_looks_at_the_point_ahead_with_the_ship_up_as_up() -> void:
	var local: Transform3D = ChaseCameraMath.local_pose(cfg)
	assert_almost_eq(-local.basis.z, (Vector3(0.0, 0.0, -cfg.look_ahead_m) - cfg.offset_local).normalized(), _v(TOL))
	assert_almost_eq(local.basis.x.y, 0.0, TOL, "no roll against the ship's up axis")


func test_rigid_step_ignores_the_previous_pose_and_dt() -> void:
	var ship: Transform3D = _ship(40.0, -15.0, Vector3(10.0, 20.0, -30.0))
	var goal: Transform3D = ChaseCameraMath.target_pose(ship, cfg)
	for dt: float in [0.0, 1.0 / 240.0, 1.0 / 60.0, 0.5, 10.0]:
		_assert_poses_equal(ChaseCameraMath.step(_stale_pose(), ship, dt, cfg), goal, 0.0, "dt = %s" % dt)


func test_rigid_camera_stays_at_the_offset_while_the_ship_yaws_reverses_and_rolls() -> void:
	# A made-up manoeuvre: yaw, then reverse thrust (the ship decelerates, stops and moves backwards along its own
	# axis), then roll, then all three at once. Frame by frame the camera is where the offset says, in ship space.
	var ship: Transform3D = _ship(0.0, 0.0, Vector3(0.0, 0.0, 0.0))
	var camera: Transform3D = ChaseCameraMath.step(_stale_pose(), ship, 1.0 / 60.0, cfg)
	var speed: float = 60.0  # m/s along the nose; the ship stays within ~150 m of the origin, where float32 is good to 1e-5
	for frame: int in 300:
		var dt: float = 1.0 / 60.0
		var yaw: float = deg_to_rad(90.0) * dt if frame < 100 or frame >= 200 else 0.0
		var roll: float = deg_to_rad(120.0) * dt if frame >= 150 else 0.0
		if frame >= 100:
			speed -= 40.0 * dt  # reverse thrust: through zero to backwards
		var basis: Basis = ship.basis * Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, roll)
		ship = Transform3D(basis.orthonormalized(), ship.origin + (-basis.z) * speed * dt)
		camera = ChaseCameraMath.step(camera, ship, dt, cfg)
		var in_ship_space: Transform3D = ship.affine_inverse() * camera
		assert_almost_eq(in_ship_space.origin, cfg.offset_local, _v(TOL), "frame %d: at the chase offset" % frame)
		assert_almost_eq(in_ship_space.basis.z, ChaseCameraMath.local_pose(cfg).basis.z, _v(TOL), "frame %d: same look" % frame)
	assert_lt(speed, 0.0, "the manoeuvre did reverse the ship")


func test_rigid_camera_ignores_ship_velocity_and_follows_only_orientation() -> void:
	var heading: Basis = Basis(Vector3.UP, deg_to_rad(20.0))
	var near_goal: Transform3D = ChaseCameraMath.target_pose(Transform3D(heading, Vector3.ZERO), cfg)
	var far_goal: Transform3D = ChaseCameraMath.target_pose(Transform3D(heading, Vector3(900.0, 0.0, 900.0)), cfg)
	_assert_poses_equal(Transform3D(near_goal.basis, Vector3.ZERO), Transform3D(far_goal.basis, Vector3.ZERO), TOL,
			"same orientation wherever the ship is")


# --- optional orientation lag -------------------------------------------------------------------------------------


func test_blend_is_zero_without_time_and_one_without_smoothing() -> void:
	assert_eq(ChaseCameraMath.blend(0.0, 0.1), 0.0)
	assert_eq(ChaseCameraMath.blend(-1.0, 0.1), 0.0)
	assert_eq(ChaseCameraMath.blend(0.016, 0.0), 1.0)
	assert_almost_eq(ChaseCameraMath.blend(0.1, 0.1), 1.0 - exp(-1.0), 1e-9, "one time constant closes 63 %")


func test_two_half_steps_equal_one_full_step() -> void:
	cfg.smoothing_s = 0.2
	var ship: Transform3D = _ship(40.0, -15.0, Vector3(10.0, 20.0, -30.0))
	var current: Transform3D = _pose_for(_ship(-50.0, 10.0, Vector3(10.0, 20.0, -30.0)))
	var dt: float = 1.0 / 60.0
	var one: Transform3D = ChaseCameraMath.step(current, ship, dt, cfg)
	var two: Transform3D = ChaseCameraMath.step(ChaseCameraMath.step(current, ship, dt / 2.0, cfg), ship, dt / 2.0, cfg)
	_assert_poses_equal(two, one, TOL, "2 x 1/120 s equals 1 x 1/60 s")
	assert_gt(_pose_error(one, current), 0.01, "the step actually moved the camera")


func test_many_small_steps_equal_one_big_step() -> void:
	cfg.smoothing_s = 0.3
	var ship: Transform3D = _ship(-70.0, 25.0, Vector3(-3.0, 4.0, 50.0))
	var current: Transform3D = _pose_for(_ship(60.0, -20.0, Vector3(-3.0, 4.0, 50.0)))
	var stepped: Transform3D = current
	for i: int in 240:
		stepped = ChaseCameraMath.step(stepped, ship, 1.0 / 240.0, cfg)
	_assert_poses_equal(stepped, ChaseCameraMath.step(current, ship, 1.0, cfg), TOL, "240 x 1/240 s equals 1 x 1 s")


func test_one_time_constant_closes_63_percent_of_the_rotation_error() -> void:
	cfg.smoothing_s = 0.25
	var ship: Transform3D = _ship(0.0, 0.0, Vector3.ZERO)
	var goal: Transform3D = ChaseCameraMath.target_pose(ship, cfg)
	var current: Transform3D = _pose_for(_ship(100.0, 20.0, Vector3.ZERO))
	var error: float = current.basis.get_rotation_quaternion().angle_to(goal.basis.get_rotation_quaternion())
	var after: Transform3D = ChaseCameraMath.step(current, ship, cfg.smoothing_s, cfg)
	assert_almost_eq(after.basis.get_rotation_quaternion().angle_to(goal.basis.get_rotation_quaternion()),
			error * exp(-1.0), 1e-4)


func test_smoothing_lags_only_the_orientation_the_camera_never_leaves_the_offset_distance() -> void:
	cfg.smoothing_s = 0.4
	var camera: Transform3D = ChaseCameraMath.target_pose(_ship(), cfg)
	var distance: float = cfg.offset_local.length()
	var ship: Transform3D = _ship()
	for frame: int in 120:
		ship = Transform3D(ship.basis * Basis(Vector3.UP, deg_to_rad(3.0)), ship.origin + Vector3(0.0, 0.0, 3.0))
		camera = ChaseCameraMath.step(camera, ship, 1.0 / 60.0, cfg)
		assert_almost_eq(camera.origin.distance_to(ship.origin), distance, TOL, "frame %d: distance to the ship" % frame)
	var rigid: Transform3D = ChaseCameraMath.target_pose(ship, cfg)
	assert_gt(camera.basis.get_rotation_quaternion().angle_to(rigid.basis.get_rotation_quaternion()), 0.05,
			"the orientation really does trail")


func test_converges_to_the_rigid_pose() -> void:
	cfg.smoothing_s = 0.1
	var ship: Transform3D = _ship(120.0, 30.0, Vector3(-500.0, 40.0, 900.0))
	var goal: Transform3D = ChaseCameraMath.target_pose(ship, cfg)
	var current: Transform3D = _stale_pose()
	for i: int in 300:
		current = ChaseCameraMath.step(current, ship, 1.0 / 60.0, cfg)
	_assert_poses_equal(current, goal, 1e-3, "after 5 s")


func test_lagging_rotation_never_overshoots() -> void:
	cfg.smoothing_s = 0.15
	var ship: Transform3D = _ship()
	var goal: Transform3D = ChaseCameraMath.target_pose(ship, cfg)
	var current: Transform3D = _pose_for(_ship(150.0, 0.0, Vector3.ZERO))
	var last_error: float = INF
	for i: int in 20:  # stops well before the error reaches float precision (angle_to is only good to ~3e-4)
		current = ChaseCameraMath.step(current, ship, 1.0 / 30.0, cfg)
		var error: float = current.basis.get_rotation_quaternion().angle_to(goal.basis.get_rotation_quaternion())
		assert_lt(error, last_error, "rotation error shrinks every step")
		last_error = error


func test_zero_dt_leaves_the_orientation_alone_when_smoothing() -> void:
	cfg.smoothing_s = 0.2
	var ship: Transform3D = _ship(10.0, 5.0, Vector3(1.0, 2.0, 3.0))
	var current: Transform3D = _pose_for(_ship(80.0, 0.0, Vector3(1.0, 2.0, 3.0)))
	_assert_poses_equal(ChaseCameraMath.step(current, ship, 0.0, cfg), current, TOL, "dt = 0")


func test_output_basis_is_orthonormal() -> void:
	cfg.smoothing_s = 0.2
	var ship: Transform3D = _ship(75.0, 20.0, Vector3(4.0, 5.0, 6.0))
	var current: Transform3D = _stale_pose()
	for i: int in 20:
		current = ChaseCameraMath.step(current, ship, 1.0 / 60.0, cfg)
	assert_almost_eq(current.basis.x.length(), 1.0, TOL)
	assert_almost_eq(current.basis.y.length(), 1.0, TOL)
	assert_almost_eq(current.basis.z.length(), 1.0, TOL)
	assert_almost_eq(current.basis.x.dot(current.basis.y), 0.0, TOL)
	assert_almost_eq(current.basis.determinant(), 1.0, TOL)
