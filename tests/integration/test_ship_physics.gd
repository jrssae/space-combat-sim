extends GutTest
## The Ship flying in Jolt, headless (architecture §5, AC5a-AC5g): straight-line thrust, pod differential yaw with
## assist off, retros, assist-on pod steering with trim and deadzone, spin stop, brake (all stop, and facing the
## selected target), one-tick model-vs-engine agreement, the damping guard (§5.4) and rebase safety (§14.1).
##
## Expected values come from the ShipSpec and the hardpoints (through the ship's ThrusterLayout), never literals.
##
## Timing: `physics_frame` fires at the start of a tick, before any node's `_physics_process` and after the previous
## step's state was synced. So after `_align()` a command set by the test is used in that same tick, and each further
## `await get_tree().physics_frame` observes one more completed step.

const SPEC_PATH: String = "res://assets/ships/starfury_aurora.tres"
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


func _spawn_ship(at: Vector3, basis: Basis = Basis.IDENTITY) -> Ship:
	var s: Ship = Ship.create(spec, world)
	world.spawn(s, world.to_universe(at), basis)
	assert_true(s.get_layout().valid, "ship has a valid thruster layout (%s)" % GEN_ASSETS_HINT)
	return s


func _dt() -> float:
	return 1.0 / float(Engine.physics_ticks_per_second)


func _ticks(seconds: float) -> int:
	return roundi(seconds * float(Engine.physics_ticks_per_second))


## Waits for the start of a physics tick: commands set now are applied in this tick.
func _align() -> void:
	await get_tree().physics_frame


## Waits for `n` physics steps to complete.
func _step(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _cmd(main_left: float = 0.0, main_right: float = 0.0, retro_left: float = 0.0, retro_right: float = 0.0,
		rot: Vector3 = Vector3.ZERO, brake: bool = false) -> FlightCommand:
	var cmd := FlightCommand.new()
	cmd.main_left = main_left
	cmd.main_right = main_right
	cmd.retro_left = retro_left
	cmd.retro_right = retro_right
	cmd.rot = rot
	cmd.brake = brake
	return cmd


## Compact scientific notation for log lines (GDScript's `%` has no `e` format).
static func _sci(x: float) -> String:
	if x == 0.0 or not is_finite(x):
		return str(x)
	var exponent: int = floori(log(absf(x)) / log(10.0))
	return "%.2fe%d" % [x / pow(10.0, exponent), exponent]


func _nozzle_count(group: int) -> int:
	return ship.get_layout().nozzles_in_group(group).size()


## Yaw rate (body +Y, nose left) after `seconds` of one group at full level from rest, assist off: `Σ x_i T / I_y t`.
func _pod_yaw_rate(group: int, seconds: float) -> float:
	var thrust: float = spec.pod_main_thrust if ThrusterLayout.is_main_group(group) else spec.pod_retro_thrust
	return ship.get_layout().torque_axis(group).y * thrust / spec.inertia.y * seconds


# --- AC5a: straight line -----------------------------------------------------------------------------------------


func test_ac5a_equal_triggers_accelerate_straight_and_then_coast() -> void:
	ship.assist_on = false
	var mains: int = _nozzle_count(ThrusterLayout.Group.R_MAIN) + _nozzle_count(ThrusterLayout.Group.L_MAIN)
	assert_eq(mains, 4, "four pod main nozzles")
	var burn: int = _ticks(2.0)
	var expected: float = 0.5 * mains * spec.pod_main_thrust / spec.mass * float(burn) * _dt()
	await _align()
	ship.set_flight_command(_cmd(0.5, 0.5))
	var max_w: float = 0.0
	for i: int in burn:
		await _step(1)
		max_w = maxf(max_w, ship.angular_velocity.length())
	var speed: float = ship.linear_velocity.length()
	gut.p("AC5a: speed after 2 s %.4f m/s, expected %.4f (%.3f %%), max |w| %s rad/s"
			% [speed, expected, 100.0 * (speed - expected) / expected, _sci(max_w)])
	assert_almost_eq(speed, expected, 0.01 * expected, "speed = 0.5 * 4 * T / m * 2 s within 1 %")
	assert_lt(max_w, 1e-3, "|w| < 1e-3 rad/s while burning")
	assert_almost_eq(ship.forward().dot(ship.linear_velocity.normalized()), 1.0, 1e-6, "straight ahead")

	ship.set_flight_command(_cmd())
	await _step(1)
	var released: float = ship.linear_velocity.length()
	var worst: float = 0.0
	for i: int in _ticks(3.0):
		await _step(1)
		worst = maxf(worst, absf(ship.linear_velocity.length() - released) / released)
		max_w = maxf(max_w, ship.angular_velocity.length())
	gut.p("AC5a: coast 3 s worst speed change %s (relative)" % _sci(worst))
	assert_lt(worst, 0.001, "speed unchanged within 0.1 % for 3 s after release")
	assert_lt(max_w, 1e-3, "|w| < 1e-3 rad/s while coasting")


# --- AC5b: pod differential yaw, assist off ----------------------------------------------------------------------


## Fires one side from rest (or from `v0`) for 0.5 s with assist off; returns the body rates at release and the
## worst relative change of the yaw rate over the next 2 s.
func _pod_kick(cmd: FlightCommand, v0: Vector3 = Vector3.ZERO) -> Dictionary:
	ship.assist_on = false
	await _align()
	ship.linear_velocity = v0
	ship.set_flight_command(cmd)
	await _step(_ticks(0.5))
	var w_release: Vector3 = ship.body_angular_velocity()
	var forward_speed: float = ship.linear_velocity.dot(v0.normalized()) if v0 != Vector3.ZERO else 0.0
	var body_v: Vector3 = ship.body_velocity()
	ship.set_flight_command(_cmd())
	await _step(1)
	var w_coast: float = ship.body_angular_velocity().y
	var worst: float = 0.0
	var max_cross: float = maxf(absf(w_release.x), absf(w_release.z))
	for i: int in _ticks(2.0):
		await _step(1)
		var w: Vector3 = ship.body_angular_velocity()
		worst = maxf(worst, absf(w.y - w_coast) / absf(w_coast))
		max_cross = maxf(max_cross, maxf(absf(w.x), absf(w.z)))
	return {"w": w_release, "persist": worst, "cross": max_cross, "forward_speed": forward_speed, "body_v": body_v}


func test_ac5b_right_trigger_alone_yaws_nose_left_at_the_lever_arm_rate() -> void:
	var expected: float = _pod_yaw_rate(ThrusterLayout.Group.R_MAIN, 0.5)
	var r: Dictionary = await _pod_kick(_cmd(0.0, 1.0))
	var w: Vector3 = r["w"]
	gut.p("AC5b RT: w_y %.4f rad/s, expected %.4f (%.3f %%); pitch/roll max %s rad/s; persistence %s"
			% [w.y, expected, 100.0 * (w.y - expected) / expected, _sci(r["cross"]), _sci(r["persist"])])
	assert_gt(expected, 0.0, "right mains push the nose left (+Y)")
	assert_gt(w.y, 0.0, "nose left")
	assert_almost_eq(w.y, expected, 0.02 * expected, "w_y = Σ x_i T / I_y * 0.5 s within 2 %")
	assert_lt(r["cross"], 1e-3, "pitch and roll rates < 1e-3 rad/s")
	assert_lt(r["persist"], 0.005, "the spin persists within 0.5 % for 2 s (assist off: nothing damps it)")


func test_ac5b_left_trigger_alone_mirrors_it() -> void:
	var expected: float = _pod_yaw_rate(ThrusterLayout.Group.L_MAIN, 0.5)
	var r: Dictionary = await _pod_kick(_cmd(1.0, 0.0))
	var w: Vector3 = r["w"]
	gut.p("AC5b LT: w_y %.4f rad/s, expected %.4f" % [w.y, expected])
	assert_lt(w.y, 0.0, "nose right")
	assert_almost_eq(w.y, expected, 0.02 * absf(expected), "mirror of RT within 2 %")
	assert_almost_eq(expected, -_pod_yaw_rate(ThrusterLayout.Group.R_MAIN, 0.5), 1e-9, "the layout is symmetric")
	assert_lt(r["cross"], 1e-3, "pitch and roll rates < 1e-3 rad/s")
	assert_lt(r["persist"], 0.005, "the spin persists")


func test_ac5b_right_bumper_alone_decelerates_and_yaws_nose_right() -> void:
	var v0: Vector3 = ship.forward() * 20.0
	var expected: float = _pod_yaw_rate(ThrusterLayout.Group.R_RETRO, 0.5)
	var r: Dictionary = await _pod_kick(_cmd(0.0, 0.0, 0.0, 1.0), v0)
	var w: Vector3 = r["w"]
	gut.p("AC5b RB: w_y %.4f rad/s, expected %.4f; forward speed 20 -> %.3f m/s" % [w.y, expected, r["forward_speed"]])
	assert_lt(w.y, 0.0, "nose right")
	assert_almost_eq(w.y, expected, 0.02 * absf(expected), "w_y = Σ x_i T_retro / I_y * 0.5 s within 2 %")
	assert_lt(r["forward_speed"], 20.0, "decelerates")
	assert_lt(r["cross"], 1e-3, "pitch and roll rates < 1e-3 rad/s")


# --- AC5c: retros ------------------------------------------------------------------------------------------------


func test_ac5c_both_bumpers_decelerate_straight() -> void:
	ship.assist_on = false
	var retros: int = _nozzle_count(ThrusterLayout.Group.R_RETRO) + _nozzle_count(ThrusterLayout.Group.L_RETRO)
	assert_eq(retros, 4, "four pod retro nozzles")
	var burn: int = _ticks(1.0)
	var expected_drop: float = retros * spec.pod_retro_thrust / spec.mass * float(burn) * _dt()
	await _align()
	ship.linear_velocity = ship.forward() * 50.0
	ship.set_flight_command(_cmd(0.0, 0.0, 1.0, 1.0))
	var max_w: float = 0.0
	for i: int in burn:
		await _step(1)
		max_w = maxf(max_w, ship.angular_velocity.length())
	var drop: float = 50.0 - ship.linear_velocity.dot(ship.forward())
	gut.p("AC5c: speed drop %.4f m/s, expected %.4f (%.3f %%), max |w| %s rad/s"
			% [drop, expected_drop, 100.0 * (drop - expected_drop) / expected_drop, _sci(max_w)])
	assert_almost_eq(drop, expected_drop, 0.01 * expected_drop, "drop = 4 * T_retro / m * 1 s within 1 %")
	assert_almost_eq(ship.linear_velocity.length(), 50.0 - expected_drop, 0.01 * expected_drop, "still straight")
	assert_lt(max_w, 1e-3, "|w| < 1e-3 rad/s")


# --- AC5d: assist on, pod steering -------------------------------------------------------------------------------


## Holds one trigger with assist on for 3 s, then releases for 1.5 s. Checks every tick that no nozzle group runs
## above its trigger and that pitch/roll stay under 1 deg/s.
func _assist_turn(cmd: FlightCommand) -> Dictionary:
	ship.assist_on = true
	var settle: int = _ticks(1.5)
	var hold: int = _ticks(3.0)
	var triggers: PackedFloat64Array = [cmd.main_right, cmd.main_left, cmd.retro_right, cmd.retro_left]
	var over_trigger: float = -INF
	var max_cross: float = 0.0
	var worst_after_settle: float = 0.0  # max |w_y| deviation from target after 1.5 s, relative
	var target: float = spec.pod_yaw_gain * deg_to_rad(spec.rate_max.y)
	var sign_y: float = 1.0 if cmd.main_right > cmd.main_left else -1.0
	await _align()
	ship.set_flight_command(cmd)
	for i: int in hold:
		await _step(1)
		var out: FlightOutput = ship.get_flight_output()
		for group: int in ThrusterLayout.GROUP_COUNT:
			over_trigger = maxf(over_trigger, out.group_levels[group] - triggers[group])
		var w: Vector3 = ship.body_angular_velocity()
		max_cross = maxf(max_cross, maxf(absf(w.x), absf(w.z)))
		if i + 1 >= settle:
			worst_after_settle = maxf(worst_after_settle, absf(w.y - sign_y * target) / target)
	var w_steady: float = ship.body_angular_velocity().y
	var trim: float = ship.get_flight_output().trim
	ship.set_flight_command(_cmd())
	await _step(_ticks(1.5))
	var w_stop: Vector3 = ship.body_angular_velocity()
	return {"target": sign_y * target, "w_steady": w_steady, "worst": worst_after_settle, "trim": trim,
			"over_trigger": over_trigger, "cross": max_cross, "w_stop": w_stop}


func test_ac5d_right_trigger_with_assist_turns_left_at_the_pod_yaw_rate_and_stops() -> void:
	var r: Dictionary = await _assist_turn(_cmd(0.0, 1.0))
	gut.p("AC5d RT: steady w_y %.2f deg/s, target %.2f; worst after 1.5 s %.3f %%; trim %.3f; pitch/roll max %.3f deg/s; after release %.3f deg/s"
			% [rad_to_deg(r["w_steady"]), rad_to_deg(r["target"]), 100.0 * r["worst"], r["trim"],
			rad_to_deg(r["cross"]), rad_to_deg((r["w_stop"] as Vector3).length())])
	assert_gt(r["w_steady"], 0.0, "nose left")
	assert_lt(r["worst"], 0.05, "settled at pod_yaw_gain * rate_max.y within 5 % by 1.5 s and stays there")
	assert_gt(r["trim"], 0.0, "the right pods are trimmed at steady state")
	assert_true(r["over_trigger"] <= 1e-9, "no nozzle level ever exceeds its trigger (max excess %s)" % _sci(r["over_trigger"]))
	assert_lt(r["cross"], ONE_DEG, "pitch and roll < 1 deg/s")
	assert_lt((r["w_stop"] as Vector3).length(), ONE_DEG, "rotation stops < 1 deg/s within 1.5 s of release")


func test_ac5d_left_trigger_with_assist_mirrors_it() -> void:
	var r: Dictionary = await _assist_turn(_cmd(1.0, 0.0))
	gut.p("AC5d LT: steady w_y %.2f deg/s, target %.2f; trim %.3f" % [rad_to_deg(r["w_steady"]),
			rad_to_deg(r["target"]), r["trim"]])
	assert_lt(r["w_steady"], 0.0, "nose right")
	assert_lt(r["worst"], 0.05, "settled within 5 % by 1.5 s and stays there")
	assert_gt(r["trim"], 0.0, "the left pods are trimmed at steady state")
	assert_true(r["over_trigger"] <= 1e-9, "no nozzle level ever exceeds its trigger")
	assert_lt(r["cross"], ONE_DEG, "pitch and roll < 1 deg/s")
	assert_lt((r["w_stop"] as Vector3).length(), ONE_DEG, "rotation stops within 1.5 s of release")


func test_ac5d_trigger_difference_inside_the_deadzone_flies_straight() -> void:
	ship.assist_on = true
	assert_lt(1.0 - 0.95, spec.pod_yaw_deadzone, "precondition: 5 % is inside the deadzone")
	await _align()
	var heading0: Vector3 = ship.forward()
	ship.set_flight_command(_cmd(0.95, 1.0))
	var max_wy: float = 0.0
	for i: int in _ticks(2.0):
		await _step(1)
		max_wy = maxf(max_wy, absf(ship.body_angular_velocity().y))
	var heading_change: float = rad_to_deg(heading0.angle_to(ship.forward()))
	gut.p("AC5d deadzone: max |w_y| %.3f deg/s, heading change %.3f deg" % [rad_to_deg(max_wy), heading_change])
	assert_lt(max_wy, ONE_DEG, "|w_y| < 1 deg/s")
	assert_lt(heading_change, 2.0, "heading change < 2 deg over 2 s")


# --- AC5e: spin stop ---------------------------------------------------------------------------------------------


func test_ac5e_assist_on_stops_a_60_dps_yaw_spin() -> void:
	ship.assist_on = true
	await _align()
	ship.angular_velocity = ship.global_basis * Vector3(0.0, deg_to_rad(60.0), 0.0)
	ship.set_flight_command(_cmd())
	var stopped_at: int = -1
	for i: int in _ticks(1.5):
		await _step(1)
		if stopped_at < 0 and ship.angular_velocity.length() < ONE_DEG:
			stopped_at = i + 1
	gut.p("AC5e assist on: < 1 deg/s after %.3f s; at 1.5 s %.4f deg/s" % [float(stopped_at) * _dt(),
			rad_to_deg(ship.angular_velocity.length())])
	assert_gt(stopped_at, 0, "stopped within 1.5 s")
	assert_lt(ship.angular_velocity.length(), ONE_DEG, "and still stopped at 1.5 s")


func test_ac5e_assist_off_does_not_damp_the_spin() -> void:
	ship.assist_on = false
	var spin: float = deg_to_rad(60.0)
	await _align()
	ship.angular_velocity = ship.global_basis * Vector3(0.0, spin, 0.0)
	ship.set_flight_command(_cmd())
	var worst: float = 0.0
	for i: int in _ticks(2.0):
		await _step(1)
		worst = maxf(worst, absf(ship.angular_velocity.length() - spin) / spin)
	gut.p("AC5e assist off: worst change over 2 s %s (relative)" % _sci(worst))
	assert_lt(worst, 0.005, "the spin does not decay (within 0.5 % over 2 s)")


# --- AC5f: brake -------------------------------------------------------------------------------------------------


func test_ac5f_brake_nulls_velocity_in_both_assist_modes() -> void:
	var other: Ship = _spawn_ship(Vector3(2000.0, 0.0, 0.0))  # far apart: both modes in one 7 s run
	ship.assist_on = true
	other.assist_on = false
	var v_body := Vector3(10.0, -5.0, -80.0)
	await _align()
	var ships: Array[Ship] = [ship, other]
	var stopped_at: Array[int] = [-1, -1]
	var max_w: Array[float] = [0.0, 0.0]
	for s: Ship in ships:
		s.linear_velocity = s.global_basis * v_body
		s.set_flight_command(_cmd(0.0, 0.0, 0.0, 0.0, Vector3.ZERO, true))
	for i: int in _ticks(7.0):
		await _step(1)
		for k: int in ships.size():
			max_w[k] = maxf(max_w[k], ships[k].angular_velocity.length())
			if stopped_at[k] < 0 and ships[k].linear_velocity.length() < 0.5:
				stopped_at[k] = i + 1
	for k: int in ships.size():
		var mode: String = "assist on" if ships[k].assist_on else "assist off"
		gut.p("AC5f %s: |v| < 0.5 m/s after %.3f s, |v| at 7 s %.4f m/s, max |w| %s deg/s" % [mode,
				float(stopped_at[k]) * _dt(), ships[k].linear_velocity.length(), _sci(rad_to_deg(max_w[k]))])
		assert_gt(stopped_at[k], 0, "%s: |v| < 0.5 m/s within 7 s" % mode)
		assert_lt(ships[k].linear_velocity.length(), 0.5, "%s: still below 0.5 m/s at 7 s" % mode)
		assert_lt(max_w[k], ONE_DEG, "%s: |w| < 1 deg/s throughout" % mode)


## A bare marker the targeting computer can select: a Node3D with a Targetable, spawned through World.
func _spawn_marker(display_name: String, at: Vector3) -> Node3D:
	var marker := Node3D.new()
	marker.name = display_name.to_pascal_case().validate_node_name()
	var targetable := Targetable.new()
	targetable.display_name = display_name
	marker.add_child(targetable)
	world.spawn(marker, world.to_universe(at))
	return marker


func test_ac5f_brake_stops_a_tumble_and_drift_in_both_modes() -> void:
	# All stop: a 60 deg/s tumble plus 50 m/s of drift, with the stick and D-pad deflected (ignored while braking).
	const LIMIT_S: float = 6.0  # measured: rate 0.87 s, speed 4.3 s (RCS sway/heave is the slow part)
	var other: Ship = _spawn_ship(Vector3(3000.0, 0.0, 0.0))
	ship.assist_on = true
	other.assist_on = false
	var ships: Array[Ship] = [ship, other]
	var w_body: Vector3 = Vector3(0.5, 0.7, -0.5).normalized() * deg_to_rad(60.0)
	var v_world: Vector3 = Vector3(30.0, -20.0, -34.6).normalized() * 50.0
	await _align()
	for s: Ship in ships:
		s.angular_velocity = s.global_basis * w_body
		s.linear_velocity = v_world
		s.set_flight_command(_cmd(0.0, 0.0, 0.0, 0.0, Vector3(1.0, -1.0, 1.0), true))
	var rate_stop: Array[int] = [-1, -1]
	var speed_stop: Array[int] = [-1, -1]
	var both_stop: Array[int] = [-1, -1]
	for i: int in _ticks(LIMIT_S):
		await _step(1)
		for k: int in ships.size():
			var w_ok: bool = ships[k].angular_velocity.length() < 0.5 * ONE_DEG
			var v_ok: bool = ships[k].linear_velocity.length() < 0.5
			if rate_stop[k] < 0 and w_ok:
				rate_stop[k] = i + 1
			if speed_stop[k] < 0 and v_ok:
				speed_stop[k] = i + 1
			if both_stop[k] < 0 and w_ok and v_ok:
				both_stop[k] = i + 1
	for k: int in ships.size():
		var mode: String = "assist on" if ships[k].assist_on else "assist off"
		var w_end: float = rad_to_deg(ships[k].angular_velocity.length())
		var v_end: float = ships[k].linear_velocity.length()
		gut.p("AC5f all stop %s: |w| < 0.5 deg/s after %.2f s, |v| < 0.5 m/s after %.2f s; at %.0f s |w| %.4f deg/s, |v| %.4f m/s"
				% [mode, float(rate_stop[k]) * _dt(), float(speed_stop[k]) * _dt(), LIMIT_S, w_end, v_end])
		assert_gt(both_stop[k], 0, "%s: speed < 0.5 m/s and rate < 0.5 deg/s within %.0f s" % [mode, LIMIT_S])
		assert_lt(v_end, 0.5, "%s: still stopped at %.0f s" % [mode, LIMIT_S])
		assert_lt(w_end, 0.5, "%s: still not rotating at %.0f s" % [mode, LIMIT_S])
		assert_true(ships[k].get_flight_output().braking, mode)
		assert_false(ships[k].get_flight_output().facing, "%s: no target selected" % mode)


func test_ac5f_brake_with_a_target_turns_the_nose_onto_it_and_holds() -> void:
	# Target 90 deg off the nose: right for the assist-on ship, straight up for the assist-off one.
	const ALIGN_LIMIT_S: float = 3.5  # measured: 2.6 s
	const HOLD_S: float = 2.0
	var other: Ship = _spawn_ship(Vector3(0.0, 0.0, 6000.0))
	ship.assist_on = true
	other.assist_on = false
	var ships: Array[Ship] = [ship, other]
	var names: Array[String] = ["FACE RIGHT", "FACE UP"]
	var markers: Array[Node3D] = [_spawn_marker(names[0], Vector3(1000.0, 0.0, 0.0)),
			_spawn_marker(names[1], Vector3(0.0, 1000.0, 6000.0))]
	await _align()
	for k: int in ships.size():
		assert_true(ships[k].targeting.select_by_name(names[k]), "%s selected" % names[k])
		assert_almost_eq(rad_to_deg(ships[k].forward().angle_to(markers[k].global_position - ships[k].global_position)),
				90.0, 1e-3, "starts 90 deg off the nose")
		ships[k].set_flight_command(_cmd(0.0, 0.0, 0.0, 0.0, Vector3.ZERO, true))
	var aligned_at: Array[int] = [-1, -1]
	var worst_after: Array[float] = [0.0, 0.0]
	var max_roll: Array[float] = [0.0, 0.0]
	var closest: Array[float] = [INF, INF]
	var rebound: Array[float] = [0.0, 0.0]  # once within 2 deg, how far the error grew back from its minimum: overshoot
	for i: int in _ticks(ALIGN_LIMIT_S + HOLD_S):
		await _step(1)
		for k: int in ships.size():
			var los: Vector3 = markers[k].global_position - ships[k].global_position
			var error: float = rad_to_deg(ships[k].forward().angle_to(los))
			max_roll[k] = maxf(max_roll[k], absf(ships[k].body_angular_velocity().z))
			if aligned_at[k] < 0 and error < 2.0:
				aligned_at[k] = i + 1
			if aligned_at[k] >= 0:
				worst_after[k] = maxf(worst_after[k], error)
				closest[k] = minf(closest[k], error)
				rebound[k] = maxf(rebound[k], error - closest[k])
	for k: int in ships.size():
		var mode: String = "assist on" if ships[k].assist_on else "assist off"
		var los: Vector3 = markers[k].global_position - ships[k].global_position
		var final_error: float = rad_to_deg(ships[k].forward().angle_to(los))
		var out: FlightOutput = ships[k].get_flight_output()
		gut.p("AC5f face %s: nose within 2 deg after %.2f s, overshoot %.4f deg, at %.1f s %.4f deg and %.4f deg/s; max roll rate %s deg/s"
				% [mode, float(aligned_at[k]) * _dt(), rebound[k], ALIGN_LIMIT_S + HOLD_S, final_error,
				rad_to_deg(ships[k].angular_velocity.length()), _sci(rad_to_deg(max_roll[k]))])
		assert_gt(aligned_at[k], 0, "%s: nose reached the target" % mode)
		assert_lte(float(aligned_at[k]) * _dt(), ALIGN_LIMIT_S, "%s: nose within 2 deg within %.0f s" % [mode, ALIGN_LIMIT_S])
		assert_lt(worst_after[k], 2.0, "%s: and it holds within 2 deg" % mode)
		assert_lt(rebound[k], 0.05, "%s: critically damped, no overshoot" % mode)
		assert_lt(final_error, 0.1, "%s: settled on the target" % mode)
		assert_lt(ships[k].angular_velocity.length(), 0.1 * ONE_DEG, "%s: and stopped there" % mode)
		assert_lt(max_roll[k], 0.1 * ONE_DEG, "%s: a pure pitch or yaw turn, no roll" % mode)
		assert_true(out.facing, mode)
		assert_almost_eq(rad_to_deg(out.face_error_rad), final_error, 0.05, "%s: the output reports the error" % mode)
	# Release the brake: the pilot has the ship back and facing stops.
	ship.set_flight_command(_cmd())
	await _step(1)
	assert_false(ship.get_flight_output().facing, "no brake, no facing")


# --- AC5g: model matches engine ----------------------------------------------------------------------------------


func test_ac5g_one_tick_angular_velocity_change_matches_the_model() -> void:
	# A tilted ship, so the body-to-world rotation of every force, position and torque is exercised.
	var tilt := Basis.from_euler(Vector3(0.3, -0.7, 0.2))
	var demands: Array[Dictionary] = [
		{"name": "RT alone, assist off", "assist": false, "cmd": _cmd(0.0, 1.0)},
		{"name": "LT 0.6 + RB, assist off", "assist": false, "cmd": _cmd(0.6, 0.0, 0.0, 1.0)},
		{"name": "raw stick pitch/yaw/roll, assist off", "assist": false, "cmd": _cmd(0.0, 0.0, 0.0, 0.0, Vector3(0.5, -0.8, 0.3))},
		{"name": "RT + pitch, assist on", "assist": true, "cmd": _cmd(0.0, 1.0, 0.0, 0.0, Vector3(0.4, 0.0, 0.0))},
		{"name": "brake + yaw spin + full stick (ignored), assist on", "assist": true,
				"v_body": Vector3(10.0, -5.0, -80.0), "w_body": Vector3(0.0, 0.5, 0.0),
				"cmd": _cmd(0.0, 0.0, 0.0, 0.0, Vector3(0.0, 1.0, -0.5), true)},
	]
	for demand: Dictionary in demands:
		ship.set_flight_command(_cmd())
		ship.assist_on = demand["assist"]
		ship.reset_to(Transform3D(tilt, Vector3.ZERO))
		await _align()
		var b: Basis = ship.global_basis
		ship.linear_velocity = b * (demand.get("v_body", Vector3.ZERO) as Vector3)
		ship.angular_velocity = b * (demand.get("w_body", Vector3.ZERO) as Vector3)  # one principal axis: no gyro term
		var w0: Vector3 = ship.angular_velocity
		var v0: Vector3 = ship.linear_velocity
		ship.set_flight_command(demand["cmd"])
		await _step(1)
		var out: FlightOutput = ship.get_flight_output()
		var dw_body: Vector3 = b.transposed() * (ship.angular_velocity - w0)
		var dv_body: Vector3 = b.transposed() * (ship.linear_velocity - v0)
		var dw_model: Vector3 = out.torque_b / spec.inertia * _dt()
		var dv_model: Vector3 = out.force_b / spec.mass * _dt()
		var err_w: float = (dw_body - dw_model).length() / dw_model.length()
		gut.p("AC5g %s: dw jolt %s, model %s, error %.3f %%" % [demand["name"], dw_body, dw_model, 100.0 * err_w])
		assert_gt(dw_model.length(), 1e-4, "%s: a real torque" % demand["name"])
		assert_lt(err_w, 0.01, "%s: one-tick dw matches torque_b / inertia * dt within 1 %%" % demand["name"])
		if dv_model.length() > 1e-6:
			var err_v: float = (dv_body - dv_model).length() / dv_model.length()
			assert_lt(err_v, 0.01, "%s: one-tick dv matches force_b / mass * dt within 1 %%" % demand["name"])


# --- damping guard (§5.4) ----------------------------------------------------------------------------------------


func test_damping_guard_project_and_body_settings() -> void:
	assert_eq(float(ProjectSettings.get_setting("physics/3d/default_gravity")), 0.0, "no default gravity")
	assert_eq(float(ProjectSettings.get_setting("physics/3d/default_linear_damp")), 0.0, "no default linear damp")
	assert_eq(float(ProjectSettings.get_setting("physics/3d/default_angular_damp")), 0.0, "no default angular damp")
	assert_eq(ship.gravity_scale, 0.0)
	assert_eq(ship.linear_damp_mode, RigidBody3D.DAMP_MODE_REPLACE, "body linear damp replaces the default")
	assert_eq(ship.angular_damp_mode, RigidBody3D.DAMP_MODE_REPLACE, "body angular damp replaces the default")
	assert_eq(ship.linear_damp, 0.0)
	assert_eq(ship.angular_damp, 0.0)
	assert_false(ship.can_sleep, "a coasting ship must never fall asleep")
	assert_false(ship.continuous_cd)


func test_damping_guard_measured_in_jolt() -> void:
	# A probe with the engine's default damping mode (COMBINE) sees the project defaults: with
	# default_linear_damp = 0.1 it loses ~10 %/s (measured 4.76 -> 4.32 m/s). The ship must not lose anything either.
	var probe := RigidBody3D.new()
	probe.can_sleep = false
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	probe.add_child(shape)
	world.spawn(probe, world.to_universe(Vector3(0.0, 500.0, 0.0)))
	ship.assist_on = false
	await _align()
	probe.linear_velocity = Vector3(10.0, 0.0, 0.0)
	probe.angular_velocity = Vector3(0.0, 1.0, 0.0)
	ship.linear_velocity = ship.forward() * 10.0
	ship.angular_velocity = Vector3(0.0, 1.0, 0.0)
	ship.set_flight_command(_cmd())
	await _step(_ticks(1.0))
	assert_almost_eq(probe.linear_velocity.length(), 10.0, 1e-4, "default-damped probe keeps its speed")
	assert_almost_eq(probe.angular_velocity.length(), 1.0, 1e-5, "default-damped probe keeps its spin")
	assert_almost_eq(ship.linear_velocity.length(), 10.0, 1e-4, "ship keeps its speed")
	assert_almost_eq(ship.angular_velocity.length(), 1.0, 1e-5, "ship keeps its spin")


# --- rebase safety (§14.1) ---------------------------------------------------------------------------------------


func test_rebase_mid_flight_keeps_velocity_and_the_trajectory() -> void:
	ship.assist_on = false
	var start: UniversePos = world.to_universe(ship.position)
	var accel: float = (_nozzle_count(ThrusterLayout.Group.R_MAIN) + _nozzle_count(ThrusterLayout.Group.L_MAIN)) * spec.pod_main_thrust / spec.mass
	var spin := Vector3(0.0, 0.0, 0.2)  # roll: keeps the thrust axis, so the speed stays easy to predict
	await _align()
	ship.angular_velocity = spin
	ship.set_flight_command(_cmd(1.0, 1.0))
	await _step(30)
	var v_before: Vector3 = ship.linear_velocity
	var w_before: Vector3 = ship.angular_velocity
	var u_before: UniversePos = world.to_universe(ship.position)
	world.rebase(Vector3(5000.0, -200.0, -3000.0))
	assert_almost_eq(ship.linear_velocity, v_before, Vector3.ONE * 1e-6, "velocity unchanged by the rebase")
	assert_almost_eq(ship.angular_velocity, w_before, Vector3.ONE * 1e-6, "spin unchanged by the rebase")
	assert_almost_eq(world.to_universe(ship.position).distance_to(u_before), 0.0, 1e-3, "no jump in universe terms")
	await _step(30)
	var n: int = 60
	var expected_speed: float = accel * float(n) * _dt()
	# Semi-implicit Euler from rest under constant acceleration: x_n = a dt² n (n + 1) / 2.
	var expected_distance: float = accel * _dt() * _dt() * float(n * (n + 1)) / 2.0
	var travelled: float = world.to_universe(ship.position).distance_to(start)
	gut.p("rebase: speed %.4f (expected %.4f), distance %.4f m (expected %.4f)" % [ship.linear_velocity.length(),
			expected_speed, travelled, expected_distance])
	assert_almost_eq(ship.linear_velocity.length(), expected_speed, 1e-3 * expected_speed, "kept accelerating")
	assert_almost_eq(travelled, expected_distance, 0.01, "on the same trajectory in universe terms")
	assert_almost_eq(ship.angular_velocity, w_before, Vector3.ONE * 1e-4, "still rolling at the same rate")
