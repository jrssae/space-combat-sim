extends GutTest
## FlightModel: command to body-frame forces, exactly architecture §5.2. One test per row of the §5.2 "what the
## player must experience" table (assist off and on), the sign conventions, and the extras T08 lists. Expected
## values are derived from the ShipSpec resource and the hardpoints fixture, never hard-coded.

const SPEC_PATH: String = "res://assets/ships/starfury_aurora.tres"
const FIXTURE: String = "res://tests/fixtures/hardpoints_nominal.json"
const DT: float = 1.0 / 60.0
const EPS: float = 1e-6
## Absolute slack for float32 force/torque sums of ~1e6 (ulp 0.25).
const SUM_TOL: float = 2.0
const DEG_PER_S: float = PI / 180.0

var spec: ShipSpec
var layout: ThrusterLayout
var model: FlightModel

# Derived from spec + layout.
var main_t: float  # N per main nozzle
var retro_t: float  # N per retro nozzle
var yaw_lever: float  # Σ x_i over the right mains = torque_axis(R_MAIN).y, m
var rt_torque: float  # yaw torque of RT alone, N·m (nose left, +y)
var rb_torque: float  # yaw torque of RB alone, N·m (nose right, -y)


func before_each() -> void:
	spec = load(SPEC_PATH) as ShipSpec
	assert_not_null(spec, "ShipSpec resource loads")
	layout = ThrusterLayout.load_file(FIXTURE)
	assert_true(layout.valid, layout.error)
	model = FlightModel.new(spec, layout)
	main_t = spec.pod_main_thrust
	retro_t = spec.pod_retro_thrust
	yaw_lever = layout.torque_axis(ThrusterLayout.Group.R_MAIN).y
	rt_torque = main_t * yaw_lever
	rb_torque = retro_t * layout.torque_axis(ThrusterLayout.Group.R_RETRO).y


# --- ShipSpec resource -------------------------------------------------------------------------------------------


func test_ship_spec_resource_matches_the_section_5_1_defaults() -> void:
	var defaults := ShipSpec.new()
	assert_eq(spec.asset_id, "starfury_aurora")
	assert_eq(spec.hardpoints_path(), "res://assets/generated/starfury_aurora/hardpoints.json")
	assert_eq(spec.mass, 48000.0)
	assert_eq(spec.inertia, Vector3(6.0e5, 6.0e5, 5.0e5))
	assert_eq(spec.pod_main_thrust, 3.6e5)
	assert_eq(spec.pod_retro_thrust, 1.8e5)
	assert_eq(spec.rcs_force_max, Vector3(4.8e5, 4.8e5, 0.0))
	assert_eq(spec.rcs_torque_max, Vector3(9.4e5, 9.4e5, 1.57e6))
	assert_eq(spec.rate_max, Vector3(60.0, 60.0, 90.0))
	assert_eq(spec.assist_gain_k, 6.0)
	assert_eq(spec.pod_yaw_gain, 0.5)
	assert_eq(spec.pod_yaw_deadzone, 0.10)
	assert_eq(spec.pod_yaw_smoothing_s, 0.15)
	assert_eq(spec.brake_gain_k, 2.0)
	assert_eq(spec.exhaust_velocity, 30000.0)
	for property: Dictionary in defaults.get_property_list():
		var usage: int = property["usage"]
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 and property["name"] != "asset_id":
			assert_eq(spec.get(property["name"]), defaults.get(property["name"]), "resource agrees with the code default for %s" % property["name"])
	assert_almost_eq(spec.rate_max_rad(), Vector3(deg_to_rad(60.0), deg_to_rad(60.0), deg_to_rad(90.0)), Vector3.ONE * EPS)
	assert_almost_eq(model.main_total(), 4.0 * main_t, EPS)
	assert_almost_eq(model.retro_total(), 4.0 * retro_t, EPS)


# --- Sign conventions ---------------------------------------------------------------------------------------------


func test_axis_sign_maps_pilot_axes_to_body_axes_once() -> void:
	assert_eq(FlightModel.AXIS_SIGN, Vector3(1.0, -1.0, -1.0))
	var pitch_up: FlightOutput = _run(_rot(1.0, 0.0, 0.0), false)
	assert_almost_eq(pitch_up.torque_b, Vector3(spec.rcs_torque_max.x, 0.0, 0.0), Vector3.ONE * SUM_TOL, "pitch up = +x")
	var yaw_right: FlightOutput = _run(_rot(0.0, 1.0, 0.0), false)
	assert_almost_eq(yaw_right.torque_b, Vector3(0.0, -spec.rcs_torque_max.y, 0.0), Vector3.ONE * SUM_TOL, "yaw right = -y")
	var roll_right: FlightOutput = _run(_rot(0.0, 0.0, 1.0), false)
	assert_almost_eq(roll_right.torque_b, Vector3(0.0, 0.0, -spec.rcs_torque_max.z), Vector3.ONE * SUM_TOL, "roll right = -z")
	# Assist on from rest: the rate target carries the same signs and the controller saturates toward it.
	var on_pitch: FlightOutput = _run(_rot(1.0, 0.0, 0.0), true)
	assert_almost_eq(on_pitch.rate_target_b, Vector3(spec.rate_max_rad().x, 0.0, 0.0), Vector3.ONE * EPS)
	assert_almost_eq(on_pitch.torque_b, Vector3(spec.rcs_torque_max.x, 0.0, 0.0), Vector3.ONE * SUM_TOL)
	var on_yaw: FlightOutput = _run(_rot(0.0, 1.0, 0.0), true)
	assert_almost_eq(on_yaw.rate_target_b, Vector3(0.0, -spec.rate_max_rad().y, 0.0), Vector3.ONE * EPS)
	assert_almost_eq(on_yaw.torque_b, Vector3(0.0, -spec.rcs_torque_max.y, 0.0), Vector3.ONE * SUM_TOL)
	var on_roll: FlightOutput = _run(_rot(0.0, 0.0, 1.0), true)
	assert_almost_eq(on_roll.rate_target_b, Vector3(0.0, 0.0, -spec.rate_max_rad().z), Vector3.ONE * EPS)
	assert_almost_eq(on_roll.torque_b, Vector3(0.0, 0.0, -spec.rcs_torque_max.z), Vector3.ONE * SUM_TOL)


# --- §5.2 table, one test per row ---------------------------------------------------------------------------------


func test_rt_plus_lt_equal_fly_straight() -> void:
	var cmd: FlightCommand = _triggers(0.5, 0.5)
	for assist_on: bool in [false, true]:
		var out: FlightOutput = _run(cmd, assist_on)
		assert_almost_eq(out.force_b, Vector3(0.0, 0.0, -0.5 * 4.0 * main_t), Vector3.ONE * SUM_TOL, _mode(assist_on))
		assert_almost_eq(out.force_b.z / spec.mass, -0.5 * 4.0 * main_t / spec.mass, EPS, "AC5a acceleration")
		assert_eq(out.torque_b, Vector3.ZERO, "zero net torque " + _mode(assist_on))
		assert_eq(out.rcs_torque_b, Vector3.ZERO, _mode(assist_on))
		assert_eq(out.trim, 0.0, _mode(assist_on))
		assert_eq(out.group_levels, PackedFloat64Array([0.5, 0.5, 0.0, 0.0]), _mode(assist_on))
		assert_eq(out.pod_yaw_cmd, 0.0, _mode(assist_on))


func test_rt_with_lt_inside_the_deadzone_flies_straight_only_with_assist() -> void:
	var cmd: FlightCommand = _triggers(0.95, 1.0)
	var imbalance: float = 0.05 * rt_torque
	var off: FlightOutput = _run(cmd, false)
	assert_almost_eq(off.torque_b.y, imbalance, SUM_TOL, "assist off: the imbalance yaws the nose left")
	assert_eq(off.rcs_torque_b, Vector3.ZERO)
	var on: FlightOutput = _run(cmd, true)
	assert_almost_eq(on.torque_b.y, 0.0, SUM_TOL, "assist on: RCS cancels the small imbalance")
	assert_almost_eq(on.rcs_torque_b.y, -imbalance, SUM_TOL)
	assert_eq(on.rate_target_b, Vector3.ZERO, "inside the deadzone there is no yaw command")
	assert_eq(on.trim, 0.0, "no trim needed")
	assert_eq(on.group_levels, PackedFloat64Array([1.0, 0.95, 0.0, 0.0]), "levels untouched")


func test_rt_alone_assist_off_yaws_nose_left_and_the_spin_keeps_building() -> void:
	var cmd: FlightCommand = _triggers(0.0, 1.0)
	for tick: int in 30:
		var w := Vector3(0.0, 0.1 * tick, 0.0)  # whatever the spin already is
		var out: FlightOutput = model.compute(cmd, Vector3.ZERO, w, Vector3.ZERO, false, DT)
		assert_almost_eq(out.torque_b, Vector3(0.0, rt_torque, 0.0), Vector3.ONE * SUM_TOL, "r x F of the right mains, nothing else")
		assert_almost_eq(out.torque_b.y / spec.inertia.y, rt_torque / spec.inertia.y, EPS, "AC5b yaw acceleration = Σ x_i · T / I_y")
		assert_almost_eq(out.force_b, Vector3(0.0, 0.0, -2.0 * main_t), Vector3.ONE * SUM_TOL)
		assert_eq(out.rcs_torque_b, Vector3.ZERO)
		assert_eq(out.trim, 0.0)
		assert_eq(out.pod_yaw_cmd, 0.0)
		assert_eq(out.group_levels, PackedFloat64Array([1.0, 0.0, 0.0, 0.0]))
	assert_gt(rt_torque, 0.0, "nose left is +y")


func test_rt_alone_assist_on_turns_nose_left_at_a_steady_trimmed_rate() -> void:
	var cmd: FlightCommand = _triggers(0.0, 1.0)
	var first: FlightOutput = _run(cmd, true)
	assert_gte(first.torque_b.y, 0.0, "turn-in starts nose left")
	assert_gt(first.trim, 0.0, "the right side is trimmed from the first tick")
	var out: FlightOutput = _settle(cmd, true)
	var rate: float = spec.pod_yaw_gain * spec.rate_max_rad().y
	assert_almost_eq(out.rate_target_b, Vector3(0.0, rate, 0.0), Vector3.ONE * EPS, "steady 30 deg/s nose left")
	assert_almost_eq(out.pod_yaw_cmd, -spec.pod_yaw_gain, EPS, "pilot terms: yaw left")
	assert_almost_eq(out.torque_b.y, 0.0, SUM_TOL, "holding the rate needs zero net torque")
	assert_almost_eq(out.rcs_torque_b.y, -spec.rcs_torque_max.y, SUM_TOL, "RCS cancels all it can")
	var lam: float = spec.rcs_torque_max.y / rt_torque
	assert_almost_eq(out.trim, 1.0 - lam, 1e-5, "POD TRIM")
	assert_almost_eq(out.group_levels[ThrusterLayout.Group.R_MAIN], lam, 1e-5)
	assert_eq(out.group_levels[ThrusterLayout.Group.L_MAIN], 0.0)
	_assert_levels_almost(out.main_levels, [lam, lam, 0.0, 0.0], 1e-5, "the right side is trimmed")
	assert_eq(out.retro_levels, PackedFloat64Array([0.0, 0.0, 0.0, 0.0]))
	assert_almost_eq(out.force_b, Vector3(0.0, 0.0, -2.0 * main_t * lam), Vector3.ONE * SUM_TOL, "still accelerating at the trimmed level")
	_assert_levels_within_pilot(out, cmd)


func test_lt_alone_mirrors_rt() -> void:
	var cmd: FlightCommand = _triggers(1.0, 0.0)
	var off: FlightOutput = _run(cmd, false)
	assert_almost_eq(off.torque_b, Vector3(0.0, -rt_torque, 0.0), Vector3.ONE * SUM_TOL, "nose right")
	assert_almost_eq(off.force_b, Vector3(0.0, 0.0, -2.0 * main_t), Vector3.ONE * SUM_TOL)
	var on: FlightOutput = _settle(cmd, true)
	var rate: float = spec.pod_yaw_gain * spec.rate_max_rad().y
	assert_almost_eq(on.rate_target_b, Vector3(0.0, -rate, 0.0), Vector3.ONE * EPS)
	assert_almost_eq(on.pod_yaw_cmd, spec.pod_yaw_gain, EPS)
	assert_almost_eq(on.torque_b.y, 0.0, SUM_TOL)
	var lam: float = spec.rcs_torque_max.y / rt_torque
	assert_almost_eq(on.trim, 1.0 - lam, 1e-5)
	_assert_levels_almost(on.main_levels, [0.0, 0.0, lam, lam], 1e-5, "the left side is trimmed")
	_assert_levels_within_pilot(on, cmd)


func test_rb_plus_lb_decelerate_straight() -> void:
	var cmd: FlightCommand = _bumpers(1.0, 1.0)
	for assist_on: bool in [false, true]:
		var out: FlightOutput = _run(cmd, assist_on)
		assert_almost_eq(out.force_b, Vector3(0.0, 0.0, 4.0 * retro_t), Vector3.ONE * SUM_TOL, "AC5c: aft " + _mode(assist_on))
		assert_eq(out.torque_b, Vector3.ZERO, _mode(assist_on))
		assert_eq(out.trim, 0.0, _mode(assist_on))
		assert_eq(out.retro_levels, PackedFloat64Array([1.0, 1.0, 1.0, 1.0]), _mode(assist_on))


func test_rb_alone_decelerates_and_yaws_nose_right() -> void:
	var cmd: FlightCommand = _bumpers(0.0, 1.0)
	assert_lt(rb_torque, 0.0, "right retros push the nose right (-y)")
	var off: FlightOutput = _run(cmd, false)
	assert_almost_eq(off.torque_b, Vector3(0.0, rb_torque, 0.0), Vector3.ONE * SUM_TOL)
	assert_almost_eq(off.force_b, Vector3(0.0, 0.0, 2.0 * retro_t), Vector3.ONE * SUM_TOL)
	var first: FlightOutput = _run(cmd, true)
	assert_lt(first.rate_target_b.y, 0.0, "assist: RB commands yaw right")
	assert_lt(first.torque_b.y, 0.0)
	var on: FlightOutput = _settle(cmd, true)
	var rate: float = spec.pod_yaw_gain * spec.rate_max_rad().y
	assert_almost_eq(on.rate_target_b, Vector3(0.0, -rate, 0.0), Vector3.ONE * EPS, "steady 30 deg/s nose right")
	assert_almost_eq(on.torque_b.y, 0.0, SUM_TOL)
	var lam: float = spec.rcs_torque_max.y / absf(rb_torque)
	assert_almost_eq(on.trim, 1.0 - lam, 1e-5, "the right retros are trimmed")
	_assert_levels_almost(on.retro_levels, [lam, lam, 0.0, 0.0], 1e-5, "the right retros are trimmed")
	assert_gt(on.force_b.z, 0.0, "still decelerating")
	_assert_levels_within_pilot(on, cmd)


func test_dpad_right_plus_lt_adds_and_caps_at_rate_max() -> void:
	var cmd: FlightCommand = _triggers(1.0, 0.0)
	cmd.rot = Vector3(0.0, 1.0, 0.0)
	var off: FlightOutput = _run(cmd, false)
	assert_almost_eq(off.torque_b.y, -spec.rcs_torque_max.y - rt_torque, SUM_TOL, "raw torque plus pod yaw")
	var first: FlightOutput = _run(cmd, true)
	assert_lt(first.torque_b.y, -spec.rcs_torque_max.y, "left-pod torque speeds the turn-in beyond RCS alone")
	assert_eq(first.trim, 0.0, "nothing to trim while the pods help")
	var on: FlightOutput = _settle(cmd, true)
	assert_almost_eq(on.rate_target_b, Vector3(0.0, -spec.rate_max_rad().y, 0.0), Vector3.ONE * EPS, "capped at rate_max")
	assert_almost_eq(on.torque_b.y, 0.0, SUM_TOL)
	assert_gt(on.trim, 0.0)
	_assert_levels_within_pilot(on, cmd)


func test_right_stick_back_pitches_up_and_dpad_right_yaws_right() -> void:
	for assist_on: bool in [false, true]:
		var up: FlightOutput = _run(_rot(1.0, 0.0, 0.0), assist_on)
		assert_almost_eq(up.torque_b, Vector3(spec.rcs_torque_max.x, 0.0, 0.0), Vector3.ONE * SUM_TOL, "nose up " + _mode(assist_on))
		var down: FlightOutput = _run(_rot(-0.5, 0.0, 0.0), assist_on)
		assert_lt(down.torque_b.x, 0.0, "nose down " + _mode(assist_on))
		var right: FlightOutput = _run(_rot(0.0, 1.0, 0.0), assist_on)
		assert_almost_eq(right.torque_b, Vector3(0.0, -spec.rcs_torque_max.y, 0.0), Vector3.ONE * SUM_TOL, "nose right " + _mode(assist_on))
		assert_eq(right.force_b, Vector3.ZERO, "no translation " + _mode(assist_on))
	# Assist on: a rate, so it stops when centred and the rate is reached.
	var reached: FlightOutput = model.compute(_rot(1.0, 0.0, 0.0), Vector3.ZERO, Vector3(spec.rate_max_rad().x, 0.0, 0.0), Vector3.ZERO, true, DT)
	assert_eq(reached.torque_b, Vector3.ZERO, "at the commanded rate the controller is quiet")
	var half: FlightOutput = model.compute(_rot(0.5, 0.0, 0.0), Vector3.ZERO, Vector3(0.5 * spec.rate_max_rad().x, 0.0, 0.0), Vector3.ZERO, true, DT)
	assert_almost_eq(half.torque_b, Vector3.ZERO, Vector3.ONE * SUM_TOL, "half deflection = half rate")


func test_right_stick_right_rolls_right() -> void:
	for assist_on: bool in [false, true]:
		var out: FlightOutput = _run(_rot(0.0, 0.0, 1.0), assist_on)
		assert_almost_eq(out.torque_b, Vector3(0.0, 0.0, -spec.rcs_torque_max.z), Vector3.ONE * SUM_TOL, "roll right = -z " + _mode(assist_on))
		var left: FlightOutput = _run(_rot(0.0, 0.0, -1.0), assist_on)
		assert_almost_eq(left.torque_b, Vector3(0.0, 0.0, spec.rcs_torque_max.z), Vector3.ONE * SUM_TOL, "roll left = +z " + _mode(assist_on))
	var on: FlightOutput = _run(_rot(0.0, 0.0, 1.0), true)
	assert_almost_eq(on.rate_target_b, Vector3(0.0, 0.0, -spec.rate_max_rad().z), Vector3.ONE * EPS)


func test_left_stick_translates_without_turning() -> void:
	for assist_on: bool in [false, true]:
		var right: FlightOutput = _run(_strafe(1.0, 0.0), assist_on)
		assert_almost_eq(right.force_b, Vector3(spec.rcs_force_max.x, 0.0, 0.0), Vector3.ONE * SUM_TOL, "sway right = +x " + _mode(assist_on))
		assert_eq(right.torque_b, Vector3.ZERO, "nose does not turn " + _mode(assist_on))
		var up: FlightOutput = _run(_strafe(0.0, 1.0), assist_on)
		assert_almost_eq(up.force_b, Vector3(0.0, spec.rcs_force_max.y, 0.0), Vector3.ONE * SUM_TOL, "heave up = +y " + _mode(assist_on))
		assert_eq(up.torque_b, Vector3.ZERO, _mode(assist_on))
		var diagonal: FlightOutput = _run(_strafe(0.5, -0.5), assist_on)
		assert_almost_eq(diagonal.force_b, Vector3(0.5 * spec.rcs_force_max.x, -0.5 * spec.rcs_force_max.y, 0.0), Vector3.ONE * SUM_TOL, _mode(assist_on))
		assert_eq(diagonal.pod_force_b, Vector3.ZERO, "pods stay cold " + _mode(assist_on))
		assert_eq(diagonal.rcs_force_b.z, 0.0, "no axial RCS " + _mode(assist_on))


func test_release_everything_keeps_velocity_and_only_assist_stops_the_spin() -> void:
	var w := Vector3(0.3, 1.0, -0.2)
	var off: FlightOutput = model.compute(_cmd(), Vector3(10.0, -5.0, -80.0), w, Vector3.ZERO, false, DT)
	assert_eq(off.force_b, Vector3.ZERO, "velocity unchanged")
	assert_eq(off.torque_b, Vector3.ZERO, "spin unchanged")
	assert_eq(off.mass_flow_kg_s, 0.0)
	var on: FlightOutput = model.compute(_cmd(), Vector3(10.0, -5.0, -80.0), w, Vector3.ZERO, true, DT)
	assert_eq(on.force_b, Vector3.ZERO, "velocity unchanged")
	var expected: Vector3 = (-(spec.inertia * (spec.assist_gain_k * w))).clamp(-spec.rcs_torque_max, spec.rcs_torque_max)
	assert_almost_eq(on.torque_b, expected, Vector3.ONE * SUM_TOL, "rate controller nulls the spin within RCS authority")
	assert_lt(on.torque_b.x, 0.0)
	assert_lt(on.torque_b.y, 0.0)
	assert_gt(on.torque_b.z, 0.0)
	# AC5e: a 60 deg/s yaw spin is countered with everything RCS has.
	var spin: FlightOutput = model.compute(_cmd(), Vector3.ZERO, Vector3(0.0, 60.0 * DEG_PER_S, 0.0), Vector3.ZERO, true, DT)
	assert_almost_eq(spin.torque_b, Vector3(0.0, -spec.rcs_torque_max.y, 0.0), Vector3.ONE * SUM_TOL)


func test_x_held_brakes_to_an_all_stop_in_both_modes() -> void:
	var v := Vector3(10.0, -5.0, -80.0)
	var w := Vector3(0.3, 1.0, -0.2)
	var cmd: FlightCommand = _cmd()
	cmd.brake = true
	var a_des: Vector3 = -spec.brake_gain_k * v
	var expected_rcs: Vector3 = (spec.mass * Vector3(a_des.x, a_des.y, 0.0)).clamp(-spec.rcs_force_max, spec.rcs_force_max)
	var expected_torque: Vector3 = (-(spec.inertia * (spec.assist_gain_k * w))).clamp(-spec.rcs_torque_max, spec.rcs_torque_max)
	var stick: FlightCommand = _rot(1.0, -1.0, 0.5)
	stick.brake = true
	for assist_on: bool in [false, true]:
		var out: FlightOutput = model.compute(cmd, v, w, Vector3.ZERO, assist_on, DT)
		assert_true(out.braking, _mode(assist_on))
		assert_eq(out.main_levels[0], out.main_levels[2], "mains symmetric across sides " + _mode(assist_on))
		assert_eq(out.retro_levels[0], out.retro_levels[2], "retros symmetric across sides " + _mode(assist_on))
		assert_eq(out.group_levels[ThrusterLayout.Group.R_RETRO], out.group_levels[ThrusterLayout.Group.L_RETRO], _mode(assist_on))
		assert_eq(out.pod_torque_b, Vector3.ZERO, "symmetric sides => zero pod torque " + _mode(assist_on))
		assert_almost_eq(out.rcs_force_b, expected_rcs, Vector3.ONE * SUM_TOL, "RCS sway/heave against v " + _mode(assist_on))
		assert_lt(out.force_b.x, 0.0, _mode(assist_on))
		assert_gt(out.force_b.y, 0.0, _mode(assist_on))
		assert_gt(out.force_b.z, 0.0, "retros against forward velocity " + _mode(assist_on))
		assert_eq(out.group_levels[ThrusterLayout.Group.R_MAIN], 0.0, "mains cold while moving forward " + _mode(assist_on))
		assert_eq(out.pod_yaw_cmd, 0.0, "no pod yaw while braking " + _mode(assist_on))
		# Rotation: all stop as well, in both modes.
		assert_eq(out.rate_target_b, Vector3.ZERO, "rate target zero " + _mode(assist_on))
		assert_almost_eq(out.torque_b, expected_torque, Vector3.ONE * SUM_TOL, "the spin is nulled within RCS authority " + _mode(assist_on))
		assert_eq(out.trim, 0.0, _mode(assist_on))
		assert_false(out.facing, "no target, no facing " + _mode(assist_on))
		# Sticks and D-pad are ignored while braking: same torque, same symmetric levels, nothing trimmed.
		var with_stick: FlightOutput = model.compute(stick, v, w, Vector3.ZERO, assist_on, DT)
		assert_eq(with_stick.torque_b, out.torque_b, "rotation demand ignored " + _mode(assist_on))
		assert_eq(with_stick.group_levels, out.group_levels, "no trim " + _mode(assist_on))
		assert_eq(with_stick.rate_target_b, Vector3.ZERO, _mode(assist_on))
		var still: FlightOutput = model.compute(stick, v, Vector3.ZERO, Vector3.ZERO, assist_on, DT)
		assert_eq(still.rcs_torque_b, Vector3.ZERO, "not rotating: RCS torque stays quiet " + _mode(assist_on))
	# AC5e-style: a 60 deg/s spin under the brake gets everything RCS has, assist off too.
	var spin: FlightOutput = model.compute(cmd, Vector3.ZERO, Vector3(0.0, 60.0 * DEG_PER_S, 0.0), Vector3.ZERO, false, DT)
	assert_almost_eq(spin.torque_b, Vector3(0.0, -spec.rcs_torque_max.y, 0.0), Vector3.ONE * SUM_TOL)


func test_brake_with_a_target_turns_the_nose_onto_it_without_roll() -> void:
	var cmd: FlightCommand = _cmd()
	cmd.brake = true
	for assist_on: bool in [false, true]:
		cmd.face_dir_b = Vector3(800.0, 0.0, 0.0)  # 90 deg right of the nose
		var right: FlightOutput = _run(cmd, assist_on)
		assert_true(right.facing, _mode(assist_on))
		assert_almost_eq(right.face_error_rad, PI / 2.0, EPS, _mode(assist_on))
		assert_almost_eq(right.rate_target_b, model.assist.face_rate_target(cmd.face_dir_b), Vector3.ONE * EPS, _mode(assist_on))
		assert_almost_eq(right.rate_target_b, Vector3(0.0, -spec.rate_max_rad().y, 0.0), Vector3.ONE * EPS, "yaw right (-y) at rate_max " + _mode(assist_on))
		assert_almost_eq(right.torque_b, Vector3(0.0, -spec.rcs_torque_max.y, 0.0), Vector3.ONE * SUM_TOL, "full RCS yaw right from rest " + _mode(assist_on))
		assert_eq(right.force_b, Vector3.ZERO, "at rest the brake has nothing to null " + _mode(assist_on))
		cmd.face_dir_b = Vector3(0.0, 30.0, -30.0)  # 45 deg above the nose
		var up: FlightOutput = _run(cmd, assist_on)
		assert_gt(up.rate_target_b.x, 0.0, "pitch up (+x) " + _mode(assist_on))
		assert_almost_eq(up.rate_target_b.y, 0.0, EPS, _mode(assist_on))
		assert_gt(up.torque_b.x, 0.0, _mode(assist_on))
		# Facing has no roll requirement: the roll target is zero, so a roll rate is nulled on the way.
		var rolling: FlightOutput = model.compute(cmd, Vector3.ZERO, Vector3(0.0, 0.0, 0.5), Vector3.ZERO, assist_on, DT)
		assert_eq(rolling.rate_target_b.z, 0.0, _mode(assist_on))
		assert_lt(rolling.torque_b.z, 0.0, "roll rate nulled " + _mode(assist_on))
		cmd.face_dir_b = Vector3(0.0, 0.0, -1.0)
		var on_target: FlightOutput = _run(cmd, assist_on)
		assert_eq(on_target.torque_b, Vector3.ZERO, "on target and still: quiet " + _mode(assist_on))
		assert_eq(on_target.face_error_rad, 0.0, _mode(assist_on))
	# Without the brake the direction is ignored: the pilot flies.
	var free: FlightCommand = _cmd()
	free.face_dir_b = Vector3(1.0, 0.0, 0.0)
	for assist_on: bool in [false, true]:
		var out: FlightOutput = _run(free, assist_on)
		assert_false(out.facing, _mode(assist_on))
		assert_eq(out.rate_target_b, Vector3.ZERO, _mode(assist_on))
		assert_eq(out.torque_b, Vector3.ZERO, _mode(assist_on))


# --- Extras listed in M1-T08 ---------------------------------------------------------------------------------------


func test_pod_torque_has_no_pitch_or_roll_for_random_demands() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5a7f
	for trial: int in 60:
		var cmd: FlightCommand = _random_cmd(rng)
		var w := Vector3(rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0))
		var assist_on: bool = trial % 2 == 0
		var out: FlightOutput = model.compute(cmd, Vector3.ZERO, w, Vector3.ZERO, assist_on, DT)
		assert_lt(absf(out.pod_torque_b.x), EPS, "no pitch from pods, trial %d" % trial)
		assert_lt(absf(out.pod_torque_b.z), EPS, "no roll from pods, trial %d" % trial)
		assert_eq(out.torque_b.x, out.rcs_torque_b.x, "pitch is RCS only, trial %d" % trial)
		assert_eq(out.torque_b.z, out.rcs_torque_b.z, "roll is RCS only, trial %d" % trial)


func test_trim_lam_equals_the_closed_form_for_rt_at_the_steady_rate() -> void:
	var cmd: FlightCommand = _triggers(0.0, 1.0)
	for _tick: int in 180:
		model.compute(cmd, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, true, DT)
	var rate := Vector3(0.0, spec.pod_yaw_gain * spec.rate_max_rad().y, 0.0)
	var out: FlightOutput = model.compute(cmd, Vector3.ZERO, rate, Vector3.ZERO, true, DT)
	# tau_des = 0, residual = -tau_pods, overflow = rcs_max - tau_pods, lam = 1 - overflow / tau_pods.
	var lam: float = 1.0 - (rt_torque - spec.rcs_torque_max.y) / rt_torque
	assert_almost_eq(1.0 - out.trim, lam, 1e-5)
	assert_almost_eq(out.group_levels[ThrusterLayout.Group.R_MAIN] * rt_torque, spec.rcs_torque_max.y, SUM_TOL, "trimmed pod torque equals RCS authority")
	assert_almost_eq(out.pod_torque_b.y + out.rcs_torque_b.y, 0.0, SUM_TOL)


func test_assist_at_the_target_rate_with_equal_triggers_gives_zero_rcs_torque() -> void:
	var cmd: FlightCommand = _triggers(0.7, 0.7)
	cmd.rot = Vector3(0.3, -0.2, 0.6)
	var probe: FlightOutput = _run(cmd, true)
	var out: FlightOutput = model.compute(cmd, Vector3.ZERO, probe.rate_target_b, Vector3.ZERO, true, DT)
	assert_eq(out.rcs_torque_b, Vector3.ZERO)
	assert_eq(out.torque_b, Vector3.ZERO)
	assert_eq(out.trim, 0.0)
	assert_almost_eq(out.force_b, Vector3(0.0, 0.0, -0.7 * 4.0 * main_t), Vector3.ONE * SUM_TOL)


func test_assist_never_raises_a_level_above_the_pilot() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xf1a9
	for trial: int in 80:
		var cmd: FlightCommand = _random_cmd(rng)
		cmd.brake = false
		var w := Vector3(rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0))
		var out: FlightOutput = model.compute(cmd, Vector3.ZERO, w, Vector3.ZERO, true, DT)
		_assert_levels_within_pilot(out, cmd, "trial %d" % trial)
		assert_between(out.trim, 0.0, 1.0, "trial %d" % trial)
		assert_eq(out.rcs_torque_b.clamp(-spec.rcs_torque_max, spec.rcs_torque_max), out.rcs_torque_b, "RCS within authority, trial %d" % trial)


func test_assist_off_ignores_the_pod_yaw_command() -> void:
	var cmd: FlightCommand = _triggers(0.0, 1.0)
	for _tick: int in 60:
		var out: FlightOutput = model.compute(cmd, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, false, DT)
		assert_eq(out.pod_yaw_cmd, 0.0)
		assert_eq(out.rate_target_b, Vector3.ZERO)
		assert_eq(out.rcs_torque_b, Vector3.ZERO)
		assert_almost_eq(out.torque_b.y, rt_torque, SUM_TOL)
	assert_eq(model.assist.pod_yaw_smoothed, 0.0, "the smoothing state does not even advance")


func test_brake_with_forward_velocity_uses_retros_only_and_never_exceeds_retro_total() -> void:
	var cmd: FlightCommand = _cmd()
	cmd.brake = true
	var fast: FlightOutput = model.compute(cmd, Vector3(0.0, 0.0, -80.0), Vector3.ZERO, Vector3.ZERO, false, DT)
	assert_eq(fast.group_levels, PackedFloat64Array([0.0, 0.0, 1.0, 1.0]), "retros saturate, mains cold")
	assert_almost_eq(fast.force_b, Vector3(0.0, 0.0, model.retro_total()), Vector3.ONE * SUM_TOL)
	assert_lte(fast.force_b.z, model.retro_total() + SUM_TOL)
	var slow: FlightOutput = model.compute(cmd, Vector3(0.0, 0.0, -1.0), Vector3.ZERO, Vector3.ZERO, true, DT)
	var wanted: float = spec.mass * spec.brake_gain_k * 1.0
	assert_almost_eq(slow.force_b, Vector3(0.0, 0.0, wanted), Vector3.ONE * SUM_TOL, "P brake below saturation")
	assert_almost_eq(slow.group_levels[ThrusterLayout.Group.R_RETRO], wanted / model.retro_total(), EPS)
	assert_eq(slow.group_levels[ThrusterLayout.Group.R_MAIN], 0.0)
	var backwards: FlightOutput = model.compute(cmd, Vector3(0.0, 0.0, 20.0), Vector3.ZERO, Vector3.ZERO, false, DT)
	assert_eq(backwards.group_levels, PackedFloat64Array([1.0, 1.0, 0.0, 0.0]), "moving aft: mains saturate")
	assert_almost_eq(backwards.force_b, Vector3(0.0, 0.0, -model.main_total()), Vector3.ONE * SUM_TOL)


func test_brake_feed_forward_from_the_environment_acceleration() -> void:
	var cmd: FlightCommand = _cmd()
	cmd.brake = true
	for assist_on: bool in [false, true]:
		var out: FlightOutput = model.compute(cmd, Vector3.ZERO, Vector3.ZERO, Vector3(0.0, 0.0, -1.0), assist_on, DT)
		assert_almost_eq(out.force_b, Vector3(0.0, 0.0, spec.mass), Vector3.ONE * SUM_TOL, "+mass N on z " + _mode(assist_on))
		assert_eq(out.pod_torque_b, Vector3.ZERO, _mode(assist_on))
	var sideways: FlightOutput = model.compute(cmd, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.0, 0.0), false, DT)
	assert_almost_eq(sideways.force_b, Vector3(-spec.mass, 0.0, 0.0), Vector3.ONE * SUM_TOL, "RCS holds against a side pull")
	var strong: FlightOutput = model.compute(cmd, Vector3.ZERO, Vector3.ZERO, Vector3(0.0, 20.0, 0.0), false, DT)
	assert_almost_eq(strong.force_b, Vector3(0.0, -spec.rcs_force_max.y, 0.0), Vector3.ONE * SUM_TOL, "clamped to RCS authority")


func test_brake_ignores_triggers_bumpers_and_the_left_stick() -> void:
	var cmd: FlightCommand = _triggers(1.0, 0.3)
	cmd.retro_left = 1.0
	cmd.strafe = Vector2(1.0, -1.0)
	cmd.brake = true
	for assist_on: bool in [false, true]:
		var out: FlightOutput = model.compute(cmd, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, assist_on, DT)
		assert_eq(out.force_b, Vector3.ZERO, "at rest: nothing fires " + _mode(assist_on))
		assert_eq(out.torque_b, Vector3.ZERO, _mode(assist_on))
		assert_eq(out.group_levels, PackedFloat64Array([0.0, 0.0, 0.0, 0.0]), _mode(assist_on))
		assert_eq(out.pod_yaw_cmd, 0.0, _mode(assist_on))
		assert_eq(out.rate_target_b, Vector3.ZERO, _mode(assist_on))


func test_mass_flow_is_total_thrust_over_exhaust_velocity() -> void:
	var cmd: FlightCommand = _triggers(0.5, 0.5)
	cmd.strafe = Vector2(1.0, 0.0)
	var out: FlightOutput = _run(cmd, false)
	assert_almost_eq(out.mass_flow_kg_s, (4.0 * 0.5 * main_t + spec.rcs_force_max.x) / spec.exhaust_velocity, EPS)
	var retro: FlightOutput = _run(_bumpers(1.0, 1.0), true)
	assert_almost_eq(retro.mass_flow_kg_s, 4.0 * retro_t / spec.exhaust_velocity, EPS)
	assert_eq(_run(_cmd(), true).mass_flow_kg_s, 0.0)


func test_nozzle_forces_are_the_physics_behind_the_totals() -> void:
	var cmd: FlightCommand = _triggers(0.3, 0.8)
	cmd.retro_left = 0.5
	cmd.retro_right = 1.0
	cmd.strafe = Vector2(0.2, 0.0)
	var out: FlightOutput = _run(cmd, false)
	assert_eq(out.nozzle_forces.size(), layout.nozzle_count())
	var pilot_levels: PackedFloat64Array = [cmd.main_right, cmd.main_left, cmd.retro_right, cmd.retro_left]
	var force_sum := Vector3.ZERO
	var torque_sum := Vector3.ZERO
	for i: int in out.nozzle_forces.size():
		var entry: Dictionary = out.nozzle_forces[i]
		var group: int = entry["group"]
		assert_eq(entry["name"], layout.nozzle_names[i])
		assert_eq(group, layout.nozzle_groups[i])
		assert_eq(entry["position"], layout.nozzle_positions[i], "forces are applied at the nozzle, not the CoM")
		assert_eq(entry["level"], pilot_levels[group])
		var thrust: float = main_t if ThrusterLayout.is_main_group(group) else retro_t
		var force: Vector3 = entry["force"]
		assert_almost_eq(force, -layout.nozzle_exhausts[i] * (pilot_levels[group] * thrust), Vector3.ONE * SUM_TOL, layout.nozzle_names[i])
		force_sum += force
		torque_sum += layout.nozzle_arms[i].cross(force)
	assert_almost_eq(out.pod_force_b, force_sum, Vector3.ONE * SUM_TOL)
	assert_almost_eq(out.pod_torque_b, torque_sum, Vector3.ONE * SUM_TOL, "Σ r_i × F_i")
	assert_almost_eq(out.force_b, out.pod_force_b + out.rcs_force_b, Vector3.ONE * SUM_TOL)
	assert_almost_eq(out.torque_b, out.pod_torque_b + out.rcs_torque_b, Vector3.ONE * SUM_TOL)


func test_reset_assist_clears_the_pod_yaw_state() -> void:
	var cmd: FlightCommand = _triggers(0.0, 1.0)
	for _tick: int in 60:
		model.compute(cmd, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, true, DT)
	assert_lt(model.assist.pod_yaw_smoothed, -0.5)
	model.reset_assist()
	assert_eq(model.assist.pod_yaw_smoothed, 0.0)
	var out: FlightOutput = _run(_triggers(0.5, 0.5), true)
	assert_eq(out.pod_yaw_cmd, 0.0)
	assert_eq(out.rate_target_b, Vector3.ZERO)


func test_rcs_levels_report_the_fraction_of_authority() -> void:
	var cmd: FlightCommand = _strafe(0.5, -0.25)
	cmd.rot = Vector3(0.5, 0.25, -1.0)
	var out: FlightOutput = _run(cmd, false)
	assert_almost_eq(out.rcs_force_level, Vector3(0.5, -0.25, 0.0), Vector3.ONE * EPS)
	assert_almost_eq(out.rcs_torque_level, Vector3(0.5, -0.25, 1.0), Vector3.ONE * EPS, "rot × AXIS_SIGN")
	assert_false(out.assist_on)
	assert_false(out.braking)


# --- Pure-model simulations of the AC5 shapes (Euler, yaw only; the Jolt versions are T10) -----------------------


func test_pod_steering_simulation_settles_and_stops() -> void:
	var rate: float = spec.pod_yaw_gain * spec.rate_max_rad().y
	var turn: Dictionary = _simulate_yaw(_triggers(0.0, 1.0), 1.5, 0.0, true)
	assert_almost_eq(turn["w"] as float, rate, 0.05 * rate, "AC5d: RT alone settles at pod_yaw_gain × rate_max.y within 1.5 s")
	assert_gt((turn["last"] as FlightOutput).trim, 0.0, "trimmed at the steady rate")
	assert_eq(turn["violations"], 0, "no nozzle level ever exceeds its trigger")
	var stop: Dictionary = _simulate_yaw(_cmd(), 1.5, turn["w"], true)
	assert_lt(absf(stop["w"] as float), 1.0 * DEG_PER_S, "the turn stops within 1.5 s of release")
	model.reset_assist()
	var mirror: Dictionary = _simulate_yaw(_triggers(1.0, 0.0), 1.5, 0.0, true)
	assert_almost_eq(mirror["w"] as float, -rate, 0.05 * rate, "LT alone mirrors it")
	model.reset_assist()
	var straight: Dictionary = _simulate_yaw(_triggers(0.95, 1.0), 2.0, 0.0, true)
	assert_lt(absf(straight["w"] as float), 1.0 * DEG_PER_S, "inside the deadzone the ship flies straight")
	assert_lt(absf(straight["heading"] as float), 2.0 * DEG_PER_S, "heading change under 2 deg over 2 s")


func test_spin_stops_with_assist_and_persists_without() -> void:
	var spin: float = 60.0 * DEG_PER_S
	var stopped: Dictionary = _simulate_yaw(_cmd(), 1.5, spin, true)
	assert_lt(absf(stopped["w"] as float), 1.0 * DEG_PER_S, "AC5e: assist on, 60 deg/s stops within 1.5 s")
	var raw: Dictionary = _simulate_yaw(_cmd(), 2.0, spin, false)
	assert_almost_eq(raw["w"] as float, spin, 0.005 * spin, "assist off: nothing damps the spin")
	var building: Dictionary = _simulate_yaw(_triggers(0.0, 1.0), 0.5, 0.0, false)
	assert_almost_eq(building["w"] as float, rt_torque / spec.inertia.y * 0.5, 0.02 * absf(building["w"] as float), "AC5b: Σ x_i · T / I_y · 0.5 s")


func test_brake_simulation_stops_a_tumble_in_both_modes() -> void:
	var w0: Vector3 = Vector3(0.6, -0.5, 0.62).normalized() * 60.0 * DEG_PER_S  # 60 deg/s about an oblique axis
	var cmd: FlightCommand = _rot(1.0, 1.0, -1.0)  # full stick and D-pad, ignored
	cmd.brake = true
	for assist_on: bool in [false, true]:
		model.reset_assist()
		var r: Dictionary = _simulate_attitude(cmd, Vector3.ZERO, w0, assist_on, 2.0)
		assert_lt((r["w"] as Vector3).length(), 0.5 * DEG_PER_S, "tumble < 0.5 deg/s within 2 s " + _mode(assist_on))
		assert_gt(r["stopped_at"] as float, 0.0, _mode(assist_on))
		gut.p("brake sim %s: tumble < 0.5 deg/s after %.2f s" % [_mode(assist_on), r["stopped_at"]])


func test_brake_simulation_faces_a_target_critically_damped() -> void:
	var cmd: FlightCommand = _cmd()
	cmd.brake = true
	# World directions to face from an identity start, plus a start spin: right, high and behind, low left.
	var cases: Array[Dictionary] = [
		{"name": "90 deg right", "dir": Vector3(1.0, 0.0, 0.0), "w0": Vector3.ZERO, "within": 3.5},
		{"name": "150 deg off, up and behind", "dir": Vector3(0.3, 0.4, 0.866), "w0": Vector3.ZERO, "within": 5.0},
		{"name": "low left, spinning away and rolling", "dir": Vector3(-0.5, -0.3, -0.81), "w0": Vector3(0.0, -0.6, 0.4), "within": 4.0},
	]
	for assist_on: bool in [false, true]:
		for c: Dictionary in cases:
			model.reset_assist()
			var r: Dictionary = _simulate_attitude(cmd, c["dir"], c["w0"], assist_on, 7.0)
			var label: String = "%s %s" % [c["name"], _mode(assist_on)]
			gut.p("face sim %s: within 2 deg after %.2f s, overshoot %.4f deg, final %.4f deg, |w| %.4f deg/s"
					% [label, r["aligned_at"], rad_to_deg(r["rebound"]), rad_to_deg(r["error"]),
					(r["w"] as Vector3).length() / DEG_PER_S])
			assert_gt(r["aligned_at"] as float, 0.0, label)
			assert_lt(r["aligned_at"] as float, c["within"] as float, "nose within 2 deg in time: " + label)
			assert_lt(r["worst_after"] as float, 2.0 * DEG_PER_S, "and it stays within 2 deg: " + label)
			assert_lt(r["rebound"] as float, 0.05 * DEG_PER_S, "critically damped, no overshoot: " + label)
			assert_lt(r["error"] as float, 0.05 * DEG_PER_S, "settles on the target: " + label)
			assert_lt((r["w"] as Vector3).length(), 0.05 * DEG_PER_S, "and stops there: " + label)
			assert_lt(absf((r["w"] as Vector3).z), 0.05 * DEG_PER_S, "no roll left over: " + label)


# --- helpers ---------------------------------------------------------------------------------------------------------


func _cmd() -> FlightCommand:
	return FlightCommand.new()


func _triggers(left: float, right: float) -> FlightCommand:
	var cmd := FlightCommand.new()
	cmd.main_left = left
	cmd.main_right = right
	return cmd


func _bumpers(left: float, right: float) -> FlightCommand:
	var cmd := FlightCommand.new()
	cmd.retro_left = left
	cmd.retro_right = right
	return cmd


func _rot(x: float, y: float, z: float) -> FlightCommand:
	var cmd := FlightCommand.new()
	cmd.rot = Vector3(x, y, z)
	return cmd


func _strafe(x: float, y: float) -> FlightCommand:
	var cmd := FlightCommand.new()
	cmd.strafe = Vector2(x, y)
	return cmd


func _random_cmd(rng: RandomNumberGenerator) -> FlightCommand:
	var cmd := FlightCommand.new()
	cmd.main_left = rng.randf()
	cmd.main_right = rng.randf()
	cmd.retro_left = rng.randf()
	cmd.retro_right = rng.randf()
	cmd.strafe = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
	cmd.rot = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
	cmd.brake = rng.randf() < 0.2
	return cmd


func _mode(assist_on: bool) -> String:
	return "(assist on)" if assist_on else "(assist off)"


## One tick from rest with no environment.
func _run(cmd: FlightCommand, assist_on: bool) -> FlightOutput:
	return model.compute(cmd, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, assist_on, DT)


## Lets the pod-yaw smoothing converge with the body already at the commanded rate, then returns one more tick
## at exactly that rate (so `tau_des` is zero and only feed-forward and trim remain).
func _settle(cmd: FlightCommand, assist_on: bool, seconds: float = 3.0) -> FlightOutput:
	var w := Vector3.ZERO
	for _tick: int in int(round(seconds / DT)):
		var out: FlightOutput = model.compute(cmd, Vector3.ZERO, w, Vector3.ZERO, assist_on, DT)
		w = out.rate_target_b
	return model.compute(cmd, Vector3.ZERO, w, Vector3.ZERO, assist_on, DT)


## Semi-implicit Euler on the yaw axis only: `w += torque_b / inertia * dt`. Returns the final body rate `w`
## (float, y), the integrated `heading` (rad), the `last` output and how many ticks broke the pilot's ceiling.
func _simulate_yaw(cmd: FlightCommand, seconds: float, w_y: float, assist_on: bool) -> Dictionary:
	var w := Vector3(0.0, w_y, 0.0)
	var heading: float = 0.0
	var violations: int = 0
	var last: FlightOutput = null
	var pilot_levels: PackedFloat64Array = [cmd.main_right, cmd.main_left, cmd.retro_right, cmd.retro_left]
	for _tick: int in int(round(seconds / DT)):
		last = model.compute(cmd, Vector3.ZERO, w, Vector3.ZERO, assist_on, DT)
		for group: int in ThrusterLayout.GROUP_COUNT:
			if last.group_levels[group] > pilot_levels[group] + 1e-9:
				violations += 1
		w += last.torque_b / spec.inertia * DT
		heading += w.y * DT
	return {"w": w.y, "heading": heading, "last": last, "violations": violations}


## Semi-implicit Euler on all three axes with attitude: `w += torque_b / inertia * dt`, then the body turns by
## `w * dt` (body frame, so `B = B * R`). `face_world` (World frame, zero = none) is converted to the body frame each
## tick, as the Ship does. Returns the final body rate `w`, the final nose error (rad), when the nose first came within
## 2 deg (`aligned_at`, s, -1 if never), from then on the worst error (`worst_after`) and how far the error ever grew
## back from its smallest value (`rebound`, rad: overshoot), and when |w| first fell below 0.5 deg/s (`stopped_at`).
func _simulate_attitude(cmd: FlightCommand, face_world: Vector3, w0: Vector3, assist_on: bool, seconds: float) -> Dictionary:
	var b := Basis.IDENTITY
	var w: Vector3 = w0
	var aligned_at: float = -1.0
	var stopped_at: float = -1.0
	var worst_after: float = 0.0
	var error: float = 0.0
	var closest: float = INF
	var rebound: float = 0.0
	for tick: int in int(round(seconds / DT)):
		cmd.face_dir_b = b.transposed() * face_world
		var out: FlightOutput = model.compute(cmd, Vector3.ZERO, w, Vector3.ZERO, assist_on, DT)
		w += out.torque_b / spec.inertia * DT
		if not w.is_zero_approx():
			b = (b * Basis(w.normalized(), w.length() * DT)).orthonormalized()
		var t: float = float(tick + 1) * DT
		if not face_world.is_zero_approx():
			error = (-b.z).angle_to(face_world)
			if aligned_at < 0.0 and error < 2.0 * DEG_PER_S:
				aligned_at = t
			if aligned_at >= 0.0:
				worst_after = maxf(worst_after, error)
				closest = minf(closest, error)
				rebound = maxf(rebound, error - closest)
		if stopped_at < 0.0 and w.length() < 0.5 * DEG_PER_S:
			stopped_at = t
	return {"w": w, "error": error, "aligned_at": aligned_at, "worst_after": worst_after, "stopped_at": stopped_at,
			"rebound": rebound}


func _assert_levels_almost(got: PackedFloat64Array, expected: Array[float], tolerance: float, text: String) -> void:
	assert_eq(got.size(), expected.size(), text)
	for i: int in mini(got.size(), expected.size()):
		assert_almost_eq(got[i], expected[i], tolerance, "%s [%d]" % [text, i])


func _assert_levels_within_pilot(out: FlightOutput, cmd: FlightCommand, text: String = "") -> void:
	var pilot_levels: PackedFloat64Array = [cmd.main_right, cmd.main_left, cmd.retro_right, cmd.retro_left]
	for group: int in ThrusterLayout.GROUP_COUNT:
		assert_lte(out.group_levels[group], pilot_levels[group] + 1e-9, "%s stays at or below the pilot's level %s" % [ThrusterLayout.group_name(group), text])
		assert_gte(out.group_levels[group], 0.0, "%s never negative %s" % [ThrusterLayout.group_name(group), text])
	for entry: Dictionary in out.nozzle_forces:
		var group: int = entry["group"]
		assert_lte(entry["level"] as float, pilot_levels[group] + 1e-9, "%s nozzle level within its trigger %s" % [entry["name"], text])
