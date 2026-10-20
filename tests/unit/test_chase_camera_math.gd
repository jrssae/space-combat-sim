extends GutTest
## ChaseCameraMath: goal pose and half-life smoothing (architecture §8). Pure, so exact numbers can be checked.

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


# --- goal pose -----------------------------------------------------------------------------------------------


func test_default_config_matches_the_design_numbers() -> void:
	assert_eq(cfg.offset_local, Vector3(0.0, 2.5, 9.0))
	assert_eq(cfg.look_ahead_m, 40.0)
	assert_eq(cfg.position_half_life_s, 0.08)
	assert_eq(cfg.rotation_half_life_s, 0.12)


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


# --- smoothing -----------------------------------------------------------------------------------------------


func test_blend_is_zero_without_time_and_one_without_smoothing() -> void:
	assert_eq(ChaseCameraMath.blend(0.0, 0.1), 0.0)
	assert_eq(ChaseCameraMath.blend(-1.0, 0.1), 0.0)
	assert_eq(ChaseCameraMath.blend(0.016, 0.0), 1.0)
	assert_almost_eq(ChaseCameraMath.blend(0.1, 0.1), 0.5, 1e-9, "one half-life closes half the error")


func test_two_half_steps_equal_one_full_step() -> void:
	var ship: Transform3D = _ship(40.0, -15.0, Vector3(10.0, 20.0, -30.0))
	var current: Transform3D = _stale_pose()
	var dt: float = 1.0 / 60.0
	var one: Transform3D = ChaseCameraMath.step(current, ship, dt, cfg)
	var two: Transform3D = ChaseCameraMath.step(ChaseCameraMath.step(current, ship, dt / 2.0, cfg), ship, dt / 2.0, cfg)
	_assert_poses_equal(two, one, TOL, "2 x 1/120 s equals 1 x 1/60 s")
	assert_gt(_pose_error(one, current), 0.01, "the step actually moved the camera")


func test_many_small_steps_equal_one_big_step() -> void:
	var ship: Transform3D = _ship(-70.0, 25.0, Vector3(-3.0, 4.0, 50.0))
	var current: Transform3D = _stale_pose()
	var stepped: Transform3D = current
	for i: int in 240:
		stepped = ChaseCameraMath.step(stepped, ship, 1.0 / 240.0, cfg)
	_assert_poses_equal(stepped, ChaseCameraMath.step(current, ship, 1.0, cfg), TOL, "240 x 1/240 s equals 1 x 1 s")


func test_one_half_life_halves_the_position_and_rotation_error() -> void:
	var ship: Transform3D = _ship(0.0, 0.0, Vector3.ZERO)
	var goal: Transform3D = ChaseCameraMath.target_pose(ship, cfg)
	var current: Transform3D = _stale_pose()
	var pos_error: float = current.origin.distance_to(goal.origin)
	var rot_error: float = current.basis.get_rotation_quaternion().angle_to(goal.basis.get_rotation_quaternion())

	var after_pos: Transform3D = ChaseCameraMath.step(current, ship, cfg.position_half_life_s, cfg)
	assert_almost_eq(after_pos.origin.distance_to(goal.origin), pos_error * 0.5, 1e-4, "position half-life")
	var after_rot: Transform3D = ChaseCameraMath.step(current, ship, cfg.rotation_half_life_s, cfg)
	assert_almost_eq(after_rot.basis.get_rotation_quaternion().angle_to(goal.basis.get_rotation_quaternion()),
			rot_error * 0.5, 1e-4, "rotation half-life")


func test_rotation_is_slower_than_position() -> void:
	var ship: Transform3D = _ship()
	var goal: Transform3D = ChaseCameraMath.target_pose(ship, cfg)
	var current: Transform3D = _stale_pose()
	var after: Transform3D = ChaseCameraMath.step(current, ship, 0.1, cfg)
	var pos_fraction: float = after.origin.distance_to(goal.origin) / current.origin.distance_to(goal.origin)
	var rot_fraction: float = after.basis.get_rotation_quaternion().angle_to(goal.basis.get_rotation_quaternion()) \
			/ current.basis.get_rotation_quaternion().angle_to(goal.basis.get_rotation_quaternion())
	assert_gt(rot_fraction, pos_fraction, "0.12 s rotation half-life leaves more error than the 0.08 s position one")


func test_converges_to_the_goal() -> void:
	var ship: Transform3D = _ship(120.0, 30.0, Vector3(-500.0, 40.0, 900.0))
	var goal: Transform3D = ChaseCameraMath.target_pose(ship, cfg)
	var current: Transform3D = _stale_pose()
	for i: int in 300:
		current = ChaseCameraMath.step(current, ship, 1.0 / 60.0, cfg)
	_assert_poses_equal(current, goal, 1e-3, "after 5 s")


func test_never_overshoots() -> void:
	var ship: Transform3D = _ship(0.0, 0.0, Vector3(0.0, 0.0, 0.0))
	var goal: Transform3D = ChaseCameraMath.target_pose(ship, cfg)
	var current: Transform3D = _stale_pose()
	var last_error: float = INF
	for i: int in 40:  # stops well before the error reaches float precision
		current = ChaseCameraMath.step(current, ship, 1.0 / 30.0, cfg)
		var error: float = current.origin.distance_to(goal.origin)
		assert_lt(error, last_error, "position error shrinks every step")
		last_error = error


func test_zero_dt_leaves_the_pose_alone_and_zero_half_life_snaps() -> void:
	var ship: Transform3D = _ship(10.0, 5.0, Vector3(1.0, 2.0, 3.0))
	var current: Transform3D = _stale_pose()
	_assert_poses_equal(ChaseCameraMath.step(current, ship, 0.0, cfg), current, TOL, "dt = 0")
	cfg.position_half_life_s = 0.0
	cfg.rotation_half_life_s = 0.0
	_assert_poses_equal(ChaseCameraMath.step(current, ship, 1.0 / 60.0, cfg), ChaseCameraMath.target_pose(ship, cfg),
			TOL, "half-life 0 snaps")


func test_output_basis_is_orthonormal() -> void:
	var ship: Transform3D = _ship(75.0, 20.0, Vector3(4.0, 5.0, 6.0))
	var current: Transform3D = _stale_pose()
	for i: int in 20:
		current = ChaseCameraMath.step(current, ship, 1.0 / 60.0, cfg)
	assert_almost_eq(current.basis.x.length(), 1.0, TOL)
	assert_almost_eq(current.basis.y.length(), 1.0, TOL)
	assert_almost_eq(current.basis.z.length(), 1.0, TOL)
	assert_almost_eq(current.basis.x.dot(current.basis.y), 0.0, TOL)
	assert_almost_eq(current.basis.determinant(), 1.0, TOL)


func test_follows_orientation_not_velocity() -> void:
	# The step reads only the ship's transform, so sideways drift (velocity is not an input) cannot swing the camera:
	# a ship that keeps its heading keeps the same camera orientation wherever it is.
	var heading: Basis = Basis(Vector3.UP, deg_to_rad(20.0))
	var near_goal: Transform3D = ChaseCameraMath.target_pose(Transform3D(heading, Vector3.ZERO), cfg)
	var far_goal: Transform3D = ChaseCameraMath.target_pose(Transform3D(heading, Vector3(900.0, 0.0, 900.0)), cfg)
	_assert_poses_equal(Transform3D(near_goal.basis, Vector3.ZERO), Transform3D(far_goal.basis, Vector3.ZERO), TOL,
			"same orientation")
