extends GutTest
## FlightAssist: the pod-yaw command (sign, deadzone, rescaling, cap, smoothing, brake, reset), the P rate
## controller, the yaw trim factor and the brake's face-target attitude controller (architecture §5.2 step 4, §5.5).
## Expected values come from the ShipSpec defaults, never literals.

const EPS: float = 1e-6
const DT_60: float = 1.0 / 60.0

var spec: ShipSpec
var assist: FlightAssist


func before_each() -> void:
	spec = ShipSpec.new()
	assist = FlightAssist.new(spec)


func test_pod_yaw_raw_sign_lt_or_rb_is_right_rt_or_lb_is_left() -> void:
	assert_eq(FlightAssist.pod_yaw_raw(_cmd(1.0, 0.0)), 1.0, "LT alone => yaw right")
	assert_eq(FlightAssist.pod_yaw_raw(_cmd(0.0, 0.0, 0.0, 1.0)), 1.0, "RB alone => yaw right")
	assert_eq(FlightAssist.pod_yaw_raw(_cmd(0.0, 1.0)), -1.0, "RT alone => yaw left")
	assert_eq(FlightAssist.pod_yaw_raw(_cmd(0.0, 0.0, 1.0, 0.0)), -1.0, "LB alone => yaw left")
	assert_eq(FlightAssist.pod_yaw_raw(_cmd(0.7, 0.7, 1.0, 1.0)), 0.0, "even sides => straight")
	assert_eq(FlightAssist.pod_yaw_raw(_cmd(1.0, 0.0, 0.0, 1.0)), 2.0, "trigger and bumper differences add")


func test_deadzone_small_differences_give_zero() -> void:
	assert_eq(assist.pod_yaw_shaped(0.05), 0.0)
	assert_eq(assist.pod_yaw_shaped(-0.05), 0.0)
	assert_eq(assist.pod_yaw_shaped(spec.pod_yaw_deadzone), 0.0, "exactly at the deadzone is still zero")
	assert_eq(assist.pod_yaw_shaped(0.0), 0.0)
	assert_eq(assist.pod_yaw_shaped(FlightAssist.pod_yaw_raw(_cmd(0.95, 1.0))), 0.0, "RT = 1, LT = 0.95 flies straight")


func test_rescaling_a_full_difference_still_gives_one() -> void:
	assert_almost_eq(assist.pod_yaw_shaped(1.0), 1.0, EPS)
	assert_almost_eq(assist.pod_yaw_shaped(-1.0), -1.0, EPS)
	var mid: float = (0.55 - spec.pod_yaw_deadzone) / (1.0 - spec.pod_yaw_deadzone)
	assert_almost_eq(assist.pod_yaw_shaped(0.55), mid, EPS, "linear above the deadzone")
	assert_almost_eq(assist.pod_yaw_shaped(-0.55), -mid, EPS)
	assert_almost_eq(assist.pod_yaw_shaped(2.0), 1.0, EPS, "trigger plus bumper is clamped to one")
	assert_almost_eq(assist.pod_yaw_shaped(-2.0), -1.0, EPS)


func test_rotation_demand_adds_the_pod_yaw_and_caps_at_one() -> void:
	assist.pod_yaw_smoothed = -1.0  # RT alone, settled: yaw left
	var cmd := _cmd()
	cmd.rot = Vector3(0.3, 0.8, -0.4)
	var rot: Vector3 = assist.rotation_demand(cmd)
	assert_almost_eq(rot.y, 0.8 - spec.pod_yaw_gain, EPS, "stick and pod yaw add")
	assert_eq(rot.x, cmd.rot.x, "pitch passes through")
	assert_eq(rot.z, cmd.rot.z, "roll passes through")
	assist.pod_yaw_smoothed = 1.0  # LT alone: yaw right
	cmd.rot = Vector3(0.0, 1.0, 0.0)
	assert_eq(assist.rotation_demand(cmd).y, 1.0, "capped at +1")
	assist.pod_yaw_smoothed = -1.0
	cmd.rot = Vector3(0.0, -1.0, 0.0)
	assert_eq(assist.rotation_demand(cmd).y, -1.0, "capped at -1")
	assist.pod_yaw_smoothed = 1.0
	cmd.rot = Vector3.ZERO
	assert_almost_eq(assist.rotation_demand(cmd).y, spec.pod_yaw_gain, EPS, "sticks centred: the pod yaw alone")


func test_pod_yaw_command_is_gain_times_smoothed() -> void:
	assist.pod_yaw_smoothed = -0.6
	assert_almost_eq(assist.pod_yaw_command(), -0.6 * spec.pod_yaw_gain, EPS)


func test_smoothing_is_frame_rate_independent() -> void:
	var other := FlightAssist.new(spec)
	var cmd := _cmd(0.0, 1.0)  # RT alone
	for _step: int in 30:
		assist.update_pod_yaw(cmd, DT_60)
		other.update_pod_yaw(cmd, DT_60 / 2.0)
		other.update_pod_yaw(cmd, DT_60 / 2.0)
		assert_almost_eq(other.pod_yaw_smoothed, assist.pod_yaw_smoothed, EPS)
	var expected: float = -(1.0 - exp(-30.0 * DT_60 / spec.pod_yaw_smoothing_s))
	assert_almost_eq(assist.pod_yaw_smoothed, expected, EPS, "first-order response to a step")


func test_smoothing_converges_and_stays_within_bounds() -> void:
	var cmd := _cmd(1.0, 0.0)  # LT alone: yaw right
	for _step: int in 180:
		var value: float = assist.update_pod_yaw(cmd, DT_60)
		assert_between(value, 0.0, 1.0)
	assert_almost_eq(assist.pod_yaw_smoothed, 1.0, EPS, "settled after 3 s")
	for _step: int in 180:
		assist.update_pod_yaw(_cmd(), DT_60)
	assert_almost_eq(assist.pod_yaw_smoothed, 0.0, EPS, "and back to zero after release")


func test_smoothing_edge_cases() -> void:
	assist.update_pod_yaw(_cmd(0.0, 1.0), 0.0)
	assert_eq(assist.pod_yaw_smoothed, 0.0, "dt = 0 leaves the state alone")
	spec.pod_yaw_smoothing_s = 0.0
	assist.update_pod_yaw(_cmd(0.0, 1.0), DT_60)
	assert_eq(assist.pod_yaw_smoothed, -1.0, "no time constant: instant")


func test_zero_while_braking() -> void:
	var braking := _cmd(0.0, 1.0)
	braking.brake = true
	assert_eq(FlightAssist.pod_yaw_raw(braking), 0.0)
	assist.pod_yaw_smoothed = -0.8
	for _step: int in 180:
		assist.update_pod_yaw(braking, DT_60)
	assert_almost_eq(assist.pod_yaw_smoothed, 0.0, EPS, "a held brake lets the pod yaw decay to zero")


func test_reset_clears_the_smoothed_command() -> void:
	for _step: int in 30:
		assist.update_pod_yaw(_cmd(0.0, 1.0), DT_60)
	assert_almost_ne(assist.pod_yaw_smoothed, 0.0, 0.1)
	assist.reset()
	assert_eq(assist.pod_yaw_smoothed, 0.0)
	assert_eq(assist.pod_yaw_command(), 0.0)


func test_rate_torque_is_inertia_times_gain_times_rate_error() -> void:
	var w_target := Vector3(0.2, -0.5, 1.0)
	var w := Vector3(0.1, 0.1, 0.4)
	var expected: Vector3 = spec.inertia * (spec.assist_gain_k * (w_target - w))
	assert_almost_eq(assist.rate_torque(w_target, w), expected, Vector3.ONE * 1.0)
	assert_eq(assist.rate_torque(w, w), Vector3.ZERO, "no error, no torque")


func test_yaw_trim_factor_closed_form() -> void:
	# RT alone at the target rate: tau_des = 0, residual.y = -tau_pods.y, overflow.y = residual.y + rcs_max.y.
	var tau_right: float = 2.291e6
	var torques: PackedFloat64Array = [tau_right, 0.0, 0.0, 0.0]
	var overflow_y: float = -tau_right + spec.rcs_torque_max.y
	var lam: float = assist.yaw_trim_factor(overflow_y, torques)
	assert_almost_eq(lam, spec.rcs_torque_max.y / tau_right, EPS, "lam = rcs_max / pod torque")
	assert_almost_eq(lam * tau_right, spec.rcs_torque_max.y, 1.0, "trimmed torque equals what RCS can cancel")
	assert_eq(assist.yaw_trim_factor(0.0, torques), 1.0, "no overflow, no trim")
	assert_eq(assist.yaw_trim_factor(-1.0e5, [0.0, 0.0, 0.0, 0.0]), 1.0, "no group causes it: saturation, not trim")
	assert_eq(assist.yaw_trim_factor(-1.0e5, [-5.0e5, 0.0, 0.0, 0.0]), 1.0, "a group pushing with the overflow is not a cause")
	assert_eq(assist.yaw_trim_factor(-9.0e6, torques), 0.0, "never below zero")
	# Left-side case: negative pod torque, positive overflow, the negative group is trimmed.
	assert_almost_eq(assist.yaw_trim_factor(4.0e5, [0.0, -1.0e6, 0.0, 0.0]), 0.6, EPS)
	# Two causing groups share the trim in proportion to their torque.
	assert_almost_eq(assist.yaw_trim_factor(-5.0e5, [1.0e6, -3.0e5, 0.0, 1.0e6]), 0.75, EPS)


func test_is_trim_cause() -> void:
	assert_true(FlightAssist.is_trim_cause(1.0e6, -1.0e5))
	assert_true(FlightAssist.is_trim_cause(-1.0e6, 1.0e5))
	assert_false(FlightAssist.is_trim_cause(1.0e6, 1.0e5))
	assert_false(FlightAssist.is_trim_cause(0.0, 1.0e5))
	assert_false(FlightAssist.is_trim_cause(1.0e6, 0.0))


# --- brake attitude controller (face target) ----------------------------------------------------------------------


func test_face_error_vector_axes_and_signs() -> void:
	assert_eq(FlightAssist.face_error_vector(Vector3.ZERO), Vector3.ZERO, "no direction, no error")
	assert_eq(FlightAssist.face_error_vector(Vector3(0.0, 0.0, -5.0)), Vector3.ZERO, "dead ahead")
	assert_almost_eq(FlightAssist.face_error_vector(Vector3(3.0, 0.0, 0.0)), Vector3(0.0, -PI / 2.0, 0.0), Vector3.ONE * EPS,
			"target right: yaw right is -y")
	assert_almost_eq(FlightAssist.face_error_vector(Vector3(-1.0, 0.0, -1.0)), Vector3(0.0, PI / 4.0, 0.0), Vector3.ONE * EPS,
			"45 deg left: +y")
	assert_almost_eq(FlightAssist.face_error_vector(Vector3(0.0, 2.0, 0.0)), Vector3(PI / 2.0, 0.0, 0.0), Vector3.ONE * EPS,
			"target above: pitch up is +x")
	assert_almost_eq(FlightAssist.face_error_vector(Vector3(0.0, 0.0, 4.0)), Vector3(PI, 0.0, 0.0), Vector3.ONE * EPS,
			"dead astern: pitch up through it")


func test_face_error_vector_never_rolls_and_its_length_is_the_angle() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xface
	for trial: int in 50:
		var d := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * rng.randf_range(0.1, 5000.0)
		var e: Vector3 = FlightAssist.face_error_vector(d)
		assert_eq(e.z, 0.0, "no roll, trial %d" % trial)
		assert_almost_eq(e.length(), Vector3.FORWARD.angle_to(d), 1e-5, "length = angle off the nose, trial %d" % trial)
		# Turning the nose by e lands it on d.
		if e.length() > 1e-6:
			var nose: Vector3 = Basis(e.normalized(), e.length()) * Vector3.FORWARD
			assert_almost_eq(nose.angle_to(d), 0.0, 1e-4, "the rotation lands on the target, trial %d" % trial)


func test_face_gain_is_critical_damping_for_the_rate_loop() -> void:
	assert_almost_eq(assist.face_gain(), spec.assist_gain_k / 4.0, EPS, "K = k / 4: double pole at -k / 2")
	assert_almost_eq(assist.turn_accel_max(), minf(spec.rcs_torque_max.x / spec.inertia.x, spec.rcs_torque_max.y / spec.inertia.y), EPS)


func test_face_rate_target_small_errors_are_linear_and_large_ones_capped() -> void:
	assert_eq(assist.face_rate_target(Vector3.ZERO), Vector3.ZERO, "no target: all stop")
	assert_eq(assist.face_rate_target(Vector3.FORWARD), Vector3.ZERO, "on target: stop")
	# 5 deg right: the linear, critically damped law.
	var small := Vector3(sin(deg_to_rad(5.0)), 0.0, -cos(deg_to_rad(5.0)))
	assert_almost_eq(assist.face_rate_target(small), Vector3(0.0, -assist.face_gain() * deg_to_rad(5.0), 0.0), Vector3.ONE * EPS)
	# 90 deg right: capped at rate_max yaw.
	assert_almost_eq(assist.face_rate_target(Vector3.RIGHT), Vector3(0.0, -spec.rate_max_rad().y, 0.0), Vector3.ONE * EPS)
	# Diagonal: the whole vector is scaled, so it still points straight at the target and never exceeds rate_max.
	var diagonal := Vector3(1.0, 1.0, 0.0)
	var w: Vector3 = assist.face_rate_target(diagonal)
	var axis: Vector3 = FlightAssist.face_error_vector(diagonal).normalized()
	assert_almost_eq(w.normalized(), axis, Vector3.ONE * EPS, "direction preserved")
	assert_lte(absf(w.x), spec.rate_max_rad().x + EPS)
	assert_lte(absf(w.y), spec.rate_max_rad().y + EPS)
	assert_eq(w.z, 0.0, "never a roll target")


func test_face_rate_target_can_always_stop_in_time() -> void:
	# A slow turner: the sqrt(2 a θ) profile takes over from the linear law so RCS can still stop the turn.
	spec.rcs_torque_max = Vector3(1.0e5, 1.0e5, 1.0e5)
	var decel: float = FlightAssist.FACE_DECEL_FRACTION * assist.turn_accel_max()
	for deg: float in [1.0, 10.0, 30.0, 60.0, 120.0]:
		var theta: float = deg_to_rad(deg)
		var rate: float = assist.face_rate_target(Vector3(sin(theta), 0.0, -cos(theta))).length()
		assert_lte(rate, sqrt(2.0 * decel * theta) + EPS, "%d deg: stoppable within RCS" % deg)
		assert_lte(rate, assist.face_gain() * theta + EPS, "%d deg: never above the linear law" % deg)


func test_face_loop_simulation_has_no_overshoot() -> void:
	# One axis, the cascade as FlightModel runs it: outer face_rate_target, inner P rate loop clamped to RCS.
	var theta: float = deg_to_rad(30.0)  # target 30 deg right, nose turning toward it
	var w: float = 0.0  # rate toward the target, rad/s
	var min_theta: float = theta
	var aligned_at: float = -1.0
	for tick: int in 300:
		var target := Vector3(sin(theta), 0.0, -cos(theta))
		var w_cmd: float = -assist.face_rate_target(target).y  # toward the target
		var accel: float = clampf(spec.assist_gain_k * (w_cmd - w), -spec.rcs_torque_max.y / spec.inertia.y,
				spec.rcs_torque_max.y / spec.inertia.y)
		w += accel * DT_60
		theta -= w * DT_60
		min_theta = minf(min_theta, theta)
		if aligned_at < 0.0 and theta < deg_to_rad(2.0):
			aligned_at = float(tick + 1) * DT_60
	assert_gt(min_theta, -deg_to_rad(0.05), "critically damped: no meaningful overshoot (min %.4f deg)" % rad_to_deg(min_theta))
	assert_between(aligned_at, 0.0, 2.0, "30 deg closes to 2 deg within 2 s")
	assert_lt(absf(theta), deg_to_rad(0.01), "settled after 5 s")


func _cmd(main_left: float = 0.0, main_right: float = 0.0, retro_left: float = 0.0, retro_right: float = 0.0) -> FlightCommand:
	var cmd := FlightCommand.new()
	cmd.main_left = main_left
	cmd.main_right = main_right
	cmd.retro_left = retro_left
	cmd.retro_right = retro_right
	return cmd


func test_track_rate_target_adds_the_direction_rate_to_the_correction() -> void:
	var dir := Vector3(0.0, 0.0, -1.0)  # dead ahead: no correction needed
	var rate := Vector3(0.02, -0.03, 0.5)
	var w: Vector3 = assist.track_rate_target(dir, rate)
	assert_almost_eq(w.x, 0.02, 1e-9, "pitch follows the direction's pitch rate")
	assert_almost_eq(w.y, -0.03, 1e-9, "yaw follows its yaw rate")
	assert_eq(w.z, 0.0, "roll is not part of tracking")


func test_track_rate_target_keeps_each_axis_inside_the_rate_limit() -> void:
	var cap: Vector3 = spec.rate_max_rad()
	var w: Vector3 = assist.track_rate_target(Vector3(0.0, 0.0, -1.0), Vector3(10.0, -10.0, 0.0))
	assert_almost_eq(w.x, cap.x, 1e-9)
	assert_almost_eq(w.y, -cap.y, 1e-9)


func test_track_rate_target_without_a_rate_is_the_face_rate() -> void:
	var dir := Vector3(0.3, 0.2, -1.0)
	assert_eq(assist.track_rate_target(dir, Vector3.ZERO), assist.face_rate_target(dir))
