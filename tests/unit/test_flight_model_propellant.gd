extends GutTest
## FlightModel with an empty tank (architecture §5.2, M2-T14): `has_propellant = false` cuts every pod nozzle and every
## RCS translation force to zero through the flag alone, in every mode, while attitude control (RCS torque) keeps
## working; with propellant (the default) nothing changes. Expected values come from the ShipSpec and the hardpoints
## fixture.

const SPEC_PATH: String = "res://assets/ships/starfury_aurora.tres"
const FIXTURE: String = "res://tests/fixtures/hardpoints_nominal.json"
const DT: float = 1.0 / 60.0
const SUM_TOL: float = 2.0  # float32 force sums of ~1e6

var spec: ShipSpec
var layout: ThrusterLayout
var model: FlightModel


func before_each() -> void:
	spec = load(SPEC_PATH) as ShipSpec
	layout = ThrusterLayout.load_file(FIXTURE)
	assert_true(layout.valid, layout.error)
	model = FlightModel.new(spec, layout)


func _full_demand() -> FlightCommand:
	var cmd := FlightCommand.new()
	cmd.main_left = 1.0
	cmd.main_right = 1.0
	cmd.retro_left = 0.5
	cmd.retro_right = 0.5
	cmd.strafe = Vector2(1.0, -1.0)
	return cmd


func _run(cmd: FlightCommand, assist_on: bool, has_propellant: bool, v_b: Vector3 = Vector3.ZERO,
		w_b: Vector3 = Vector3.ZERO) -> FlightOutput:
	return model.compute(cmd, v_b, w_b, Vector3.ZERO, assist_on, DT, has_propellant)


func _assert_no_thrust(out: FlightOutput, label: String) -> void:
	assert_eq(out.pod_force_b, Vector3.ZERO, "%s: no pod force" % label)
	assert_eq(out.rcs_force_b, Vector3.ZERO, "%s: no RCS force" % label)
	assert_eq(out.force_b, Vector3.ZERO, "%s: no total force" % label)
	assert_eq(out.pod_torque_b, Vector3.ZERO, "%s: no pod torque" % label)
	assert_eq(out.mass_flow_kg_s, 0.0, "%s: nothing burns, so nothing flows" % label)
	assert_eq(out.trim, 0.0, "%s: nothing to trim" % label)
	assert_true(out.propellant_empty, "%s: the output says why" % label)
	for nozzle: Dictionary in out.nozzle_forces:
		assert_eq(nozzle["force"], Vector3.ZERO, "%s: nozzle %s silent" % [label, nozzle["name"]])
		assert_eq(nozzle["level"], 0.0, "%s: nozzle %s level 0" % [label, nozzle["name"]])
	for level: float in out.group_levels:
		assert_eq(level, 0.0, "%s: group levels 0" % label)
	for level: float in out.main_levels:
		assert_eq(level, 0.0, "%s: main levels 0 (the glow goes out)" % label)
	for level: float in out.retro_levels:
		assert_eq(level, 0.0, "%s: retro levels 0" % label)
	assert_eq(out.rcs_force_level, Vector3.ZERO, "%s: RCS translation level 0" % label)


func test_with_propellant_is_the_default_and_changes_nothing() -> void:
	var cmd: FlightCommand = _full_demand()
	var by_default: FlightOutput = model.compute(cmd, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, true, DT)
	var explicit: FlightOutput = _run(cmd, true, true)
	assert_false(by_default.propellant_empty)
	assert_false(explicit.propellant_empty)
	assert_eq(by_default.force_b, explicit.force_b)
	assert_eq(by_default.torque_b, explicit.torque_b)
	assert_eq(by_default.mass_flow_kg_s, explicit.mass_flow_kg_s)
	assert_gt(by_default.force_b.length(), 1.0e6, "and the demand really does thrust")


func test_an_empty_tank_cuts_all_thrust_with_assist_on_and_off() -> void:
	for assist_on: bool in [true, false]:
		var label: String = "assist on" if assist_on else "assist off"
		_assert_no_thrust(_run(_full_demand(), assist_on, false), label)


func test_an_empty_tank_cuts_one_sided_thrust_and_leaves_no_trim() -> void:
	var right_only := FlightCommand.new()
	right_only.main_right = 1.0
	for assist_on: bool in [true, false]:
		var out: FlightOutput = _run(right_only, assist_on, false)
		_assert_no_thrust(out, "right trigger, assist %s" % assist_on)
	var settled: FlightOutput = null
	for i: int in 120:  # the pod-yaw command converges while the model keeps cutting the pods
		settled = _run(right_only, true, false)
	_assert_no_thrust(settled, "after 2 s of holding RT")


func test_an_empty_tank_cuts_the_brake_thrust_too() -> void:
	var brake := FlightCommand.new()
	brake.brake = true
	var out: FlightOutput = _run(brake, true, false, Vector3(3.0, -2.0, -80.0))
	_assert_no_thrust(out, "brake at speed")
	assert_true(out.braking, "the brake is still commanded")
	var with_fuel: FlightOutput = _run(brake, true, true, Vector3(3.0, -2.0, -80.0))
	assert_gt(with_fuel.force_b.length(), 1.0e5, "with fuel the same brake does thrust")


func test_attitude_control_survives_an_empty_tank() -> void:
	# RCS torque never drew reaction mass in this model (mass_flow counts forces only), so the ship can still turn.
	var pitch_up := FlightCommand.new()
	pitch_up.rot = Vector3(1.0, 0.0, 0.0)
	var raw: FlightOutput = _run(pitch_up, false, false)
	assert_almost_eq(raw.torque_b, Vector3(spec.rcs_torque_max.x, 0.0, 0.0), Vector3.ONE * SUM_TOL, "raw stick = full RCS torque")
	assert_eq(raw.force_b, Vector3.ZERO)
	var assisted: FlightOutput = _run(pitch_up, true, false)
	assert_gt(assisted.torque_b.x, 0.0, "assist on: the rate controller still commands torque")
	assert_eq(assisted.force_b, Vector3.ZERO)


func test_the_brake_still_stops_a_spin_with_an_empty_tank() -> void:
	var brake := FlightCommand.new()
	brake.brake = true
	var spin := Vector3(0.0, 0.0, 1.0)  # rad/s about body +Z
	var out: FlightOutput = _run(brake, true, false, Vector3.ZERO, spin)
	assert_lt(out.torque_b.z, 0.0, "torque opposes the spin")
	assert_eq(out.force_b, Vector3.ZERO)


func test_pod_torque_is_not_fed_forward_when_the_pods_are_dead() -> void:
	# Assist on, a yaw command: with fuel the pods' torque is part of the answer; without it RCS supplies all of it.
	var yaw := FlightCommand.new()
	yaw.rot = Vector3(0.0, 1.0, 0.0)
	var out: FlightOutput = _run(yaw, true, false)
	assert_eq(out.pod_torque_b, Vector3.ZERO)
	assert_almost_eq(out.torque_b, out.rcs_torque_b, Vector3.ONE * SUM_TOL, "all of it is RCS torque")
	assert_ne(out.torque_b.y, 0.0, "and it is not zero")


func test_random_commands_never_thrust_without_propellant() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 14
	for i: int in 200:
		var cmd := FlightCommand.new()
		cmd.main_left = rng.randf()
		cmd.main_right = rng.randf()
		cmd.retro_left = rng.randf()
		cmd.retro_right = rng.randf()
		cmd.strafe = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
		cmd.rot = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
		cmd.brake = rng.randf() < 0.3
		var v_b := Vector3(rng.randf_range(-50.0, 50.0), rng.randf_range(-50.0, 50.0), rng.randf_range(-200.0, 200.0))
		var w_b := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
		var out: FlightOutput = _run(cmd, rng.randf() < 0.5, false, v_b, w_b)
		assert_eq(out.force_b, Vector3.ZERO, "case %d" % i)
		assert_eq(out.mass_flow_kg_s, 0.0, "case %d" % i)
		if out.force_b != Vector3.ZERO:
			return  # one failure is enough to report
