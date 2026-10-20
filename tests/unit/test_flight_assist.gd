extends GutTest
## FlightAssist: the pod-yaw command (sign, deadzone, rescaling, cap, smoothing, brake, reset), the P rate
## controller and the yaw trim factor (architecture §5.2 step 4, §5.5). Expected values come from the ShipSpec
## defaults, never literals.

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


func _cmd(main_left: float = 0.0, main_right: float = 0.0, retro_left: float = 0.0, retro_right: float = 0.0) -> FlightCommand:
	var cmd := FlightCommand.new()
	cmd.main_left = main_left
	cmd.main_right = main_right
	cmd.retro_left = retro_left
	cmd.retro_right = retro_right
	return cmd
