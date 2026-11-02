extends GutTest
## Demo manoeuvres (M3-T09, AC10, architecture §16 D37): pure state machines on the measured state. A small kinematic
## model of an assisted ship (`Sim`, below: the assist tracks the commanded rates within the RCS's angular acceleration,
## thrust is the capability's accelerations, the brake is the flight model's law) flies each one, and the test measures
## the goal itself from the model's motion, not from the manoeuvre's own report. Jolt runs are in
## `tests/integration/test_manoeuvres_jolt.gd`.

const DT: float = 1.0 / 60.0
const CRUISE_MPS: float = 60.0


## An ideal assisted Starfury: rates follow the command with the assist's gain, capped by the RCS's angular
## acceleration; pods, retros and RCS give the capability's accelerations; the brake is `-brake_gain * v` within them.
## Positions are universe metres (`universe`); the perception sees them World-local against `origin`, so a test can
## rebase mid-manoeuvre.
class Sim:
	const ASSIST_GAIN: float = 6.0
	const BRAKE_GAIN: float = 2.0
	const POD_YAW_GAIN: float = 0.5

	var cap: ShipCapability
	var universe: Vector3 = Vector3.ZERO
	var origin: Vector3 = Vector3.ZERO
	var velocity: Vector3 = Vector3.ZERO
	var basis: Basis = Basis.IDENTITY
	var w_body: Vector3 = Vector3.ZERO
	var now_s: float = 0.0
	## False: the ship cannot roll (a test of "measured, not timed").
	var can_roll: bool = true
	var can_yaw: bool = true

	func _init(p_cap: ShipCapability, p_velocity: Vector3 = Vector3.ZERO) -> void:
		cap = p_cap
		velocity = p_velocity

	func perception() -> Perception:
		var p := Perception.new()
		p.now_s = now_s
		p.position = universe - origin
		p.basis = basis
		p.velocity = velocity
		p.angular_velocity = basis * w_body
		p.capability = cap
		p.frame_origin = UniversePos.new(origin.x, origin.y, origin.z)
		return p

	func step(cmd: FlightCommand, dt: float) -> void:
		var target := Vector3.ZERO
		if not cmd.brake:
			var pod_yaw: float = POD_YAW_GAIN * ((cmd.main_left - cmd.main_right) + (cmd.retro_right - cmd.retro_left))
			var pilot := Vector3(cmd.rot.x, clampf(cmd.rot.y + pod_yaw, -1.0, 1.0), cmd.rot.z)
			target = pilot * FlightModel.AXIS_SIGN * cap.rate_max_rad
		if not can_roll:
			target.z = 0.0
		if not can_yaw:
			target.y = 0.0
		var dw: Vector3 = ASSIST_GAIN * (target - w_body) * dt
		w_body += dw.clamp(-cap.alpha_max_rad * dt, cap.alpha_max_rad * dt)
		if w_body.length_squared() > 1e-18:
			basis = (basis * Basis(w_body.normalized(), w_body.length() * dt)).orthonormalized()
		var a_b: Vector3
		if cmd.brake:
			var v_b: Vector3 = basis.transposed() * velocity
			a_b = -BRAKE_GAIN * v_b
			a_b = Vector3(clampf(a_b.x, -cap.a_rcs.x, cap.a_rcs.x), clampf(a_b.y, -cap.a_rcs.y, cap.a_rcs.y),
					clampf(a_b.z, -cap.a_main, cap.a_retro))
		else:
			a_b = Vector3(cmd.strafe.x * cap.a_rcs.x, cmd.strafe.y * cap.a_rcs.y,
					-0.5 * (cmd.main_left + cmd.main_right) * cap.a_main + 0.5 * (cmd.retro_left + cmd.retro_right) * cap.a_retro)
		velocity += basis * a_b * dt
		universe += velocity * dt
		now_s += dt


func _capability() -> ShipCapability:
	# The Starfury's numbers (`starfury_aurora.tres`): mains 30 m/s^2, retros 15, RCS 10 sideways, 60 / 60 / 90 deg/s, RCS
	# angular acceleration 1.57 / 1.57 / 3.14 rad/s^2.
	var cap := ShipCapability.new()
	cap.a_main = 30.0
	cap.a_retro = 15.0
	cap.a_rcs = Vector2(10.0, 10.0)
	cap.rate_max_rad = Vector3(deg_to_rad(60.0), deg_to_rad(60.0), deg_to_rad(90.0))
	cap.alpha_max_rad = Vector3(940000.0 / 600000.0, 940000.0 / 600000.0, 1.57e6 / 500000.0)
	return cap


## Flies `m` in `sim` until it is done or `max_s` passes; `on_tick(sim, cmd)` sees every tick. Returns the seconds flown.
func _fly(m: Manoeuvre, sim: Sim, max_s: float = 60.0, on_tick: Callable = Callable()) -> float:
	var t: float = 0.0
	while not m.done and t < max_s:
		var cmd: FlightCommand = m.step(sim.perception(), DT)
		sim.step(cmd, DT)
		if on_tick.is_valid():
			on_tick.call(sim, cmd)
		t += DT
	return t


## Coasts with an empty command (the assist holding zero rates) for `seconds`.
func _settle(sim: Sim, seconds: float) -> void:
	for i: int in roundi(seconds / DT):
		sim.step(FlightCommand.new(), DT)


# --- the set -------------------------------------------------------------------------------------------------------


func test_the_five_demos_are_built_by_name() -> void:
	assert_eq(Manoeuvres.NAMES, [&"roll", &"flip_and_burn", &"strafe_box", &"pod_turn", &"all_stop"])
	for demo: StringName in Manoeuvres.NAMES:
		var m: Manoeuvre = Manoeuvres.create(demo)
		assert_not_null(m, String(demo))
		assert_eq(m.id, demo)
		assert_false(m.done)
		assert_true(m.describe().has("step"), "%s describes its step" % demo)
	assert_null(Manoeuvres.create(&"loop_the_loop"))


func test_the_moves_that_need_speed_are_the_ones_that_take_it_away() -> void:
	assert_true(Manoeuvres.create(&"flip_and_burn").needs_speed())
	assert_true(Manoeuvres.create(&"all_stop").needs_speed())
	assert_false(Manoeuvres.create(&"roll").needs_speed())
	assert_false(Manoeuvres.create(&"strafe_box").needs_speed())
	assert_false(Manoeuvres.create(&"pod_turn").needs_speed())


func test_the_display_words_are_upper_case_with_spaces() -> void:
	assert_eq(Manoeuvres.display_name(&"flip_and_burn"), "FLIP AND BURN")
	assert_eq(Manoeuvres.display_name(&"roll"), "ROLL")


# --- roll ----------------------------------------------------------------------------------------------------------


func test_roll_commands_the_full_roll_rate_and_nothing_else_at_first() -> void:
	var m: Manoeuvre = Manoeuvres.create(&"roll")
	var sim := Sim.new(_capability(), Vector3(0.0, 0.0, -CRUISE_MPS))
	var cmd: FlightCommand = m.step(sim.perception(), DT)
	assert_eq(cmd.rot, Vector3(0.0, 0.0, 1.0), "roll right at the rate limit")
	assert_eq(cmd.main_left + cmd.main_right + cmd.retro_left + cmd.retro_right, 0.0)
	assert_eq(cmd.strafe, Vector2.ZERO)
	assert_false(cmd.brake)


func test_roll_turns_a_full_circle_measured_from_the_ships_up_axis() -> void:
	var m: Manoeuvre = Manoeuvres.create(&"roll")
	var sim := Sim.new(_capability(), Vector3(0.0, 0.0, -CRUISE_MPS))
	var forward0: Vector3 = -sim.basis.z
	var turned: Array[float] = [0.0]
	var up_before: Array[Vector3] = [sim.basis.y]
	var peak_dps: Array[float] = [0.0]
	var watch := func(s: Sim, _cmd: FlightCommand) -> void:
		var up: Vector3 = s.basis.y
		turned[0] += atan2(up_before[0].cross(up).dot(-s.basis.z), up_before[0].dot(up))
		up_before[0] = up
		peak_dps[0] = maxf(peak_dps[0], absf(rad_to_deg(s.w_body.z)))
	var flown: float = _fly(m, sim, 20.0, watch)
	assert_true(m.done, "finished in %.1f s" % flown)
	var result: Dictionary = m.result()
	_settle(sim, 1.0)
	# Rolling right (clockwise seen from the pilot) turns the up axis positively about the nose.
	var measured_deg: float = rad_to_deg(turned[0])
	gut.p("roll: %.1f s, reported %.1f deg, up axis turned %.1f deg, peak %.1f deg/s" % [flown, result["roll_deg"],
			measured_deg, peak_dps[0]])
	assert_almost_eq(float(result["roll_deg"]), 360.0, 2.0, "it integrated a full circle")
	assert_almost_eq(measured_deg, 360.0, 3.0, "the up axis went once round, within the AC's 10 degrees")
	assert_almost_eq(peak_dps[0], 90.0, 1.0, "at the roll rate limit")
	assert_lt(rad_to_deg((-sim.basis.z).angle_to(forward0)), 1.0, "the nose stayed put")
	assert_almost_eq(sim.velocity, Vector3(0.0, 0.0, -CRUISE_MPS), Vector3.ONE * 1e-6, "no thrust")


func test_roll_counts_the_measured_rate_not_the_time() -> void:
	var m: Manoeuvre = Manoeuvres.create(&"roll")
	var sim := Sim.new(_capability())
	sim.can_roll = false
	_fly(m, sim, 10.0)
	assert_false(m.done, "a ship that does not roll never finishes the roll")
	assert_almost_eq(float(m.result()["roll_deg"]), 0.0, 1e-6)


func test_a_move_that_cannot_finish_gives_up_at_its_timeout() -> void:
	var m: Manoeuvre = Manoeuvres.create(&"roll")
	var sim := Sim.new(_capability())
	sim.can_roll = false
	var flown: float = _fly(m, sim, Manoeuvre.TIMEOUT_S + 5.0)
	assert_true(m.done)
	assert_true(m.timed_out)
	assert_true(bool(m.result()["timed_out"]))
	assert_almost_eq(flown, Manoeuvre.TIMEOUT_S, 2.0 * DT)


# --- flip and burn -------------------------------------------------------------------------------------------------


func test_flip_and_burn_turns_first_then_burns_the_mains_to_a_stop() -> void:
	var m: Manoeuvre = Manoeuvres.create(&"flip_and_burn")
	var v0 := Vector3(0.0, 0.0, -CRUISE_MPS)
	var sim := Sim.new(_capability(), v0)
	var first: FlightCommand = m.step(sim.perception(), DT)
	assert_ne(first.rot, Vector3.ZERO, "it turns")
	assert_eq(first.main_left + first.main_right, 0.0, "no thrust while it flips")
	assert_eq(m.describe()["step"], "flip")
	sim.step(first, DT)
	var burn_nose_dot: Array[float] = [1.0]
	var mains_used: Array[bool] = [false]
	var watch := func(s: Sim, cmd: FlightCommand) -> void:
		if cmd.main_left > 0.0 and cmd.main_right > 0.0:
			assert_almost_eq(cmd.main_left, cmd.main_right, 1e-9, "both mains alike: no pod yaw")
			mains_used[0] = true
			burn_nose_dot[0] = minf(burn_nose_dot[0], 1.0 - (-s.basis.z).dot(-v0.normalized()))
		assert_eq(cmd.retro_left + cmd.retro_right, 0.0, "the retros never fire")
	var flown: float = _fly(m, sim, 30.0, watch)
	assert_true(m.done, "finished in %.1f s" % flown)
	var result: Dictionary = m.result()
	var along: float = sim.velocity.dot(v0.normalized())
	gut.p("flip and burn: %.1f s, flip %.1f s, end speed %.2f m/s, along %.2f m/s" % [flown, result["flip_s"],
			sim.velocity.length(), along])
	assert_true(mains_used[0], "the mains did the braking")
	assert_lt(burn_nose_dot[0], 1.0 - cos(deg_to_rad(4.0)), "nose on retrograde during the burn")
	assert_true(along < 0.0 or sim.velocity.length() < 2.0, "velocity reversed or under 2 m/s")
	assert_almost_eq(float(result["speed0_mps"]), CRUISE_MPS, 1e-3)
	assert_almost_eq(float(result["speed_mps"]), sim.velocity.length(), 0.6, "the report is the measured speed")


func test_flip_and_burn_from_rest_has_nothing_to_do() -> void:
	var m: Manoeuvre = Manoeuvres.create(&"flip_and_burn")
	var sim := Sim.new(_capability(), Vector3(0.0, 0.0, -1.0))
	var cmd: FlightCommand = m.step(sim.perception(), DT)
	assert_true(m.done)
	assert_eq(cmd.rot, Vector3.ZERO)
	assert_almost_eq(float(m.result()["speed_mps"]), 1.0, 1e-6)


# --- strafe box ----------------------------------------------------------------------------------------------------


## Flies a strafe box in `sim` and returns, in the frame that moves with the starting velocity: the corner points where each
## leg ended, the closure, the first leg's full-strafe seconds and the nose drift.
func _fly_box(sim: Sim, rebase_at_s: float = -1.0, rebase_by: Vector3 = Vector3.ZERO) -> Dictionary:
	var m: Manoeuvre = Manoeuvres.create(&"strafe_box")
	var start: Vector3 = sim.universe
	var v0: Vector3 = sim.velocity
	var t0: float = sim.now_s
	var forward0: Vector3 = -sim.basis.z
	var corners: Array[Vector3] = []
	var last_leg: Array[int] = [0]
	var full_right_s: Array[float] = [0.0]
	var nose_drift_deg: Array[float] = [0.0]
	var rebased: Array[bool] = [false]
	var watch := func(s: Sim, cmd: FlightCommand) -> void:
		var rel: Vector3 = s.universe - start - v0 * (s.now_s - t0)
		var leg: int = int(m.describe()["legs_done"])
		if leg != last_leg[0] or m.done:
			corners.append(rel)
			last_leg[0] = leg
		if leg == 0 and cmd.strafe.x > 0.99:
			full_right_s[0] += DT
		nose_drift_deg[0] = maxf(nose_drift_deg[0], rad_to_deg((-s.basis.z).angle_to(forward0)))
		if rebase_at_s >= 0.0 and not rebased[0] and s.now_s - t0 >= rebase_at_s:
			s.origin += rebase_by
			rebased[0] = true
	var flown: float = _fly(m, sim, 60.0, watch)
	assert_true(m.done, "the box finished in %.1f s" % flown)
	return {"m": m, "corners": corners, "flown": flown, "full_right_s": full_right_s[0], "nose_drift_deg": nose_drift_deg[0],
			"right": sim.basis.x, "up": sim.basis.y}


func test_strafe_box_flies_right_up_left_down_and_closes() -> void:
	var sim := Sim.new(_capability(), Vector3(0.0, 0.0, -CRUISE_MPS))
	var right: Vector3 = sim.basis.x
	var up: Vector3 = sim.basis.y
	var box: Dictionary = _fly_box(sim)
	var corners: Array[Vector3] = box["corners"]
	assert_eq(corners.size(), 4, "four legs")
	var legs: Array[float] = []
	var previous := Vector3.ZERO
	var directions: Array[Vector3] = [right, up, -right, -up]
	for i: int in corners.size():
		var leg: Vector3 = corners[i] - previous
		legs.append(leg.length())
		assert_gt(leg.normalized().dot(directions[i]), 0.99, "leg %d goes %s" % [i + 1, ["right", "up", "left", "down"][i]])
		previous = corners[i]
	var result: Dictionary = (box["m"] as Manoeuvre).result()
	gut.p("strafe box: %.1f s, legs %s m, closure %.2f m, first push %.2f s at full strafe, nose drift %.2f deg" % [box["flown"],
			str(legs), corners[3].length(), box["full_right_s"], box["nose_drift_deg"]])
	for i: int in legs.size():
		assert_gt(legs[i], 40.0, "leg %d over 40 m" % (i + 1))
		assert_almost_eq(float((result["legs_m"] as Array)[i]), legs[i], 0.5, "leg %d as reported" % (i + 1))
	assert_lt(corners[3].length(), 30.0, "back within 30 m of the start (moving with the starting velocity)")
	assert_lt(corners[3].length(), 3.0, "in fact within a few metres")
	assert_almost_eq(float(box["full_right_s"]), 1.5, 0.35, "the first leg pushes at full strafe for about 1.5 s")
	assert_lt(float(box["nose_drift_deg"]), 0.5, "the attitude is held")


func test_strafe_box_survives_a_rebase_mid_leg() -> void:
	var sim := Sim.new(_capability(), Vector3(0.0, 0.0, -CRUISE_MPS))
	var box: Dictionary = _fly_box(sim, 3.0, Vector3(4000.0, -250.0, 9000.0))
	var corners: Array[Vector3] = box["corners"]
	assert_eq(corners.size(), 4)
	assert_lt(corners[3].length(), 3.0, "the World origin moved, the box did not")


# --- pod turn ------------------------------------------------------------------------------------------------------


func test_pod_turn_fires_the_left_main_alone_until_the_nose_is_30_degrees_right() -> void:
	var m: Manoeuvre = Manoeuvres.create(&"pod_turn")
	var sim := Sim.new(_capability(), Vector3(0.0, 0.0, -CRUISE_MPS))
	var forward0: Vector3 = -sim.basis.z
	var right0: Vector3 = sim.basis.x
	var watch := func(_s: Sim, cmd: FlightCommand) -> void:
		if m.done:
			return  # the tick that sees the goal met coasts
		assert_eq(cmd.main_left, 1.0, "left main")
		assert_eq(cmd.main_right, 0.0, "alone")
		assert_eq(cmd.rot, Vector3.ZERO, "no stick: the pod does the turning")
	var flown: float = _fly(m, sim, 10.0, watch)
	assert_true(m.done, "finished in %.1f s" % flown)
	var nose: Vector3 = -sim.basis.z
	var yaw_deg: float = rad_to_deg(atan2(nose.dot(right0), nose.dot(forward0)))
	gut.p("pod turn: %.2f s, nose %.1f deg right, reported %.1f" % [flown, yaw_deg, m.result()["yaw_deg"]])
	assert_gt(yaw_deg, 30.0, "nose right by over 30 degrees")
	assert_lt(yaw_deg, 40.0, "and it stopped soon after")
	assert_almost_eq(float(m.result()["yaw_deg"]), yaw_deg, 1.0)


func test_pod_turn_ends_on_the_measured_heading_not_the_time() -> void:
	var m: Manoeuvre = Manoeuvres.create(&"pod_turn")
	var sim := Sim.new(_capability())
	sim.can_yaw = false
	_fly(m, sim, 10.0)
	assert_false(m.done, "a ship that does not yaw never finishes the pod turn")


# --- all stop ------------------------------------------------------------------------------------------------------


func test_all_stop_holds_the_brake_until_still() -> void:
	var m: Manoeuvre = Manoeuvres.create(&"all_stop")
	var sim := Sim.new(_capability(), Vector3(12.0, -5.0, -CRUISE_MPS))
	sim.w_body = Vector3(0.2, -0.1, 0.3)
	var watch := func(_s: Sim, cmd: FlightCommand) -> void:
		if not m.done:
			assert_true(cmd.brake, "the brake, nothing else")
	var flown: float = _fly(m, sim, 30.0, watch)
	assert_true(m.done, "finished in %.1f s" % flown)
	var result: Dictionary = m.result()
	gut.p("all stop: %.1f s, %.3f m/s, %.3f deg/s" % [flown, result["speed_mps"], result["rate_dps"]])
	assert_lt(sim.velocity.length(), 0.5)
	assert_lt(rad_to_deg(sim.w_body.length()), 1.0)
	assert_lt(float(result["speed_mps"]), 0.5)
	assert_lt(float(result["rate_dps"]), 1.0)


func test_all_stop_is_not_done_while_still_turning() -> void:
	var m: Manoeuvre = Manoeuvres.create(&"all_stop")
	var p := Perception.new()
	p.capability = _capability()
	p.angular_velocity = Vector3(0.0, deg_to_rad(5.0), 0.0)
	m.step(p, DT)
	assert_false(m.done, "at rest but turning at 5 deg/s")
	p.angular_velocity = Vector3(0.0, deg_to_rad(0.5), 0.0)
	m.step(p, DT)
	assert_true(m.done)
