class_name Manoeuvres
extends RefCounted
## The five demo moves (architecture §16 D37, M3-T09, maintainer Q5) as `Manoeuvre` state machines, and `create(name)`.
## Each flies the real flight model (assist on, as every AI ship) and ends on its measured goal:
##
## - **roll**: a full 360 degrees to the right at the roll rate limit. The angle is the integrated measured roll rate; the
##   rate command runs at the limit, then falls as `min(K * left, sqrt(2 a left))` (a = half the RCS's roll acceleration),
##   so it stops on the circle. Done within `DONE_DEG` and under `DONE_DPS`. Result `roll_deg`.
## - **flip_and_burn**: face the retrograde of the starting velocity (no thrust), then both mains (a seek to rest with RCS on
##   the sideways rest) until the velocity is reversed or under 2 m/s. Result `speed0_mps`, `speed_mps`, `along_mps` (the
##   velocity along the starting direction), `reversed`, `flip_s`, `burn_s`.
## - **strafe_box**: RCS only, the attitude held on the starting nose: legs right, up, left and down of `LEG_M`, each a seek
##   toward the next corner of a square that moves with the starting velocity (so a box flown at cruise is a box around the
##   flight path). Each leg opens with a full-strafe push of about 1.5 s up to `LEG_SPEED_MPS` and brakes onto the corner; a
##   leg ends at the corner (within `ARRIVE_M`, under `SETTLE_MPS` relative). Result `legs_m` (each leg's measured length),
##   `legs_done`, `closure_m` (distance from the moving start at the end).
## - **pod_turn**: the left main alone, no stick: its torque swings the nose right (the assist turns the pod difference into
##   a yaw rate) until the heading is over 30 degrees right of the start. Result `yaw_deg` (+ = right).
## - **all_stop**: the brake until under 0.5 m/s and 1 degree/s. Result `speed_mps`, `rate_dps`.
##
## The numbers are tuned on the Starfury in Jolt (`tests/integration/test_manoeuvres_jolt.gd`, recorded in the M3 as-built
## notes).

const NAMES: Array[StringName] = [&"roll", &"flip_and_burn", &"strafe_box", &"pod_turn", &"all_stop"]


## A fresh move by name (`NAMES`), or null.
static func create(demo: StringName) -> Manoeuvre:
	match demo:
		&"roll":
			return Roll.new()
		&"flip_and_burn":
			return FlipAndBurn.new()
		&"strafe_box":
			return StrafeBox.new()
		&"pod_turn":
			return PodTurn.new()
		&"all_stop":
			return AllStop.new()
	return null


## The HUD's word for a demo: `FLIP AND BURN`.
static func display_name(demo: StringName) -> String:
	return String(demo).replace("_", " ").to_upper()


class Roll extends Manoeuvre:
	const TURN_RAD: float = TAU
	const DONE_DEG: float = 1.0
	const DONE_DPS: float = 5.0
	## Share of the RCS's roll acceleration the stop is planned with (the rest covers the assist's lag).
	const DECEL_FRACTION: float = 0.5

	var rolled_rad: float = 0.0
	var _last_rate: float = 0.0

	func _init() -> void:
		id = &"roll"

	func state_name() -> String:
		if done:
			return "done"
		return "rolling" if TURN_RAD - rolled_rad > deg_to_rad(90.0) else "stopping"

	func _begin(p: Perception) -> void:
		_last_rate = Manoeuvre.roll_rate(p)

	func _step(p: Perception, dt: float) -> FlightCommand:
		var rate: float = Manoeuvre.roll_rate(p)
		if elapsed_s > 0.0:
			rolled_rad += 0.5 * (rate + _last_rate) * dt
		_last_rate = rate
		var left: float = TURN_RAD - rolled_rad
		var cmd := FlightCommand.new()
		if absf(left) < deg_to_rad(DONE_DEG) and absf(rate) < deg_to_rad(DONE_DPS):
			done = true
			return cmd
		var cap: ShipCapability = p.capability
		var limit: float = cap.rate_max_rad.z
		var stop: float = sqrt(2.0 * DECEL_FRACTION * cap.alpha_max_rad.z * absf(left))
		var w: float = signf(left) * minf(limit, minf(PilotSteering.K_FACE * absf(left), stop))
		cmd.rot = Vector3(0.0, 0.0, clampf(w / limit, -1.0, 1.0))
		return cmd

	func _result() -> Dictionary:
		return {"roll_deg": snappedf(rad_to_deg(rolled_rad), 0.01)}


class FlipAndBurn extends Manoeuvre:
	const STOP_MPS: float = 2.0
	## The burn starts when the nose is this close to the retrograde.
	const ALIGNED_DEG: float = 3.0
	## The burn's seek horizon, s: full mains until the last metre per second or so.
	const BURN_HORIZON_S: float = 0.2

	var burning: bool = false
	var speed0_mps: float = 0.0
	var flip_s: float = 0.0
	var burn_s: float = 0.0
	var _retro: Vector3 = Vector3.BACK
	var _velocity: Vector3 = Vector3.ZERO

	func _init() -> void:
		id = &"flip_and_burn"

	func needs_speed() -> bool:
		return true

	func state_name() -> String:
		if done:
			return "done"
		return "burn" if burning else "flip"

	func _begin(p: Perception) -> void:
		_velocity = p.velocity
		speed0_mps = p.velocity.length()
		if speed0_mps < STOP_MPS:
			done = true
			return
		_retro = -p.velocity / speed0_mps

	func _step(p: Perception, _dt: float) -> FlightCommand:
		_velocity = p.velocity
		var cmd := FlightCommand.new()
		if burning and (p.velocity.length() < STOP_MPS or p.velocity.dot(-_retro) < 0.0):
			done = true
			return cmd
		cmd.rot = PilotSteering.face(p.basis, _retro, p.capability.rate_max_rad)
		if not burning:
			flip_s = elapsed_s
			if rad_to_deg(PilotSteering.angle_to(p.basis, _retro)) >= ALIGNED_DEG:
				return cmd
			burning = true
		burn_s = elapsed_s - flip_s
		_seek(cmd, p, Vector3.ZERO, BURN_HORIZON_S)
		return cmd

	func _result() -> Dictionary:
		var along: float = _velocity.dot(-_retro) if speed0_mps >= STOP_MPS else _velocity.length()
		return {"speed0_mps": snappedf(speed0_mps, 0.001), "speed_mps": snappedf(_velocity.length(), 0.001),
				"along_mps": snappedf(along, 0.001), "reversed": along < 0.0, "flip_s": snappedf(flip_s, 0.01),
				"burn_s": snappedf(burn_s, 0.01)}


class StrafeBox extends Manoeuvre:
	const LEG_M: float = 50.0
	const LEG_SPEED_MPS: float = 15.0
	const ARRIVE_M: float = 2.0
	const SETTLE_MPS: float = 1.0
	## Share of the RCS acceleration the approach to a corner is planned with.
	const DECEL_FRACTION: float = 0.8
	## The seek horizon, s: full strafe until the last 1.5 m/s of each change, so each push lasts about 1.5 s.
	const SEEK_HORIZON_S: float = 0.15
	const LEG_NAMES: Array[String] = ["right", "up", "left", "down"]

	var legs_m: Array[float] = []
	var closure_m: float = -1.0
	var _start: UniversePos = null
	var _t0: float = 0.0
	var _v0: Vector3 = Vector3.ZERO
	var _forward: Vector3 = Vector3.FORWARD
	var _corners: Array[Vector3] = []
	var _last_corner: Vector3 = Vector3.ZERO

	func _init() -> void:
		id = &"strafe_box"

	func state_name() -> String:
		return "done" if done else LEG_NAMES[legs_m.size()]

	func _begin(p: Perception) -> void:
		_start = p.frame_origin.plus_local(p.position)
		_t0 = p.now_s
		_v0 = p.velocity
		_forward = -p.basis.z
		var right: Vector3 = p.basis.x * LEG_M
		var up: Vector3 = p.basis.y * LEG_M
		_corners = [right, right + up, up, Vector3.ZERO]

	## Where the ship is against the start point moving on at the starting velocity, World frame, m.
	func offset(p: Perception) -> Vector3:
		return p.position - p.to_local(_start) - _v0 * (p.now_s - _t0)

	func _step(p: Perception, _dt: float) -> FlightCommand:
		var rel: Vector3 = offset(p)
		var cmd := FlightCommand.new()
		var leg: int = legs_m.size()
		var to: Vector3 = _corners[leg] - rel
		if to.length() < ARRIVE_M and (p.velocity - _v0).length() < SETTLE_MPS:
			legs_m.append((rel - _last_corner).length())
			_last_corner = rel
			if legs_m.size() == _corners.size():
				done = true
				closure_m = rel.length()
				return cmd
			to = _corners[legs_m.size()] - rel
		var d: float = to.length()
		var cap: ShipCapability = p.capability
		var speed: float = minf(LEG_SPEED_MPS, sqrt(2.0 * DECEL_FRACTION * minf(cap.a_rcs.x, cap.a_rcs.y) * d))
		var v_rel: Vector3 = to / d * speed if d > 1e-6 else Vector3.ZERO
		cmd.rot = PilotSteering.face(p.basis, _forward, cap.rate_max_rad)
		_seek(cmd, p, _v0 + v_rel, SEEK_HORIZON_S)
		return cmd

	func _result() -> Dictionary:
		var legs: Array[float] = []
		for leg: float in legs_m:
			legs.append(snappedf(leg, 0.01))
		return {"legs_m": legs, "legs_done": legs_m.size(), "closure_m": snappedf(closure_m, 0.01)}


class PodTurn extends Manoeuvre:
	const TURN_DEG: float = 30.0

	var yaw_deg: float = 0.0
	var _forward0: Vector3 = Vector3.FORWARD
	var _right0: Vector3 = Vector3.RIGHT

	func _init() -> void:
		id = &"pod_turn"

	func state_name() -> String:
		return "done" if done else "left main"

	func _begin(p: Perception) -> void:
		_forward0 = -p.basis.z
		_right0 = p.basis.x

	func _step(p: Perception, _dt: float) -> FlightCommand:
		var nose: Vector3 = -p.basis.z
		yaw_deg = rad_to_deg(atan2(nose.dot(_right0), nose.dot(_forward0)))
		var cmd := FlightCommand.new()
		if yaw_deg > TURN_DEG:
			done = true
			return cmd
		cmd.main_left = 1.0
		return cmd

	func _result() -> Dictionary:
		return {"yaw_deg": snappedf(yaw_deg, 0.01)}


class AllStop extends Manoeuvre:
	const STOP_MPS: float = 0.5
	const STOP_DPS: float = 1.0

	var speed_mps: float = -1.0
	var rate_dps: float = -1.0

	func _init() -> void:
		id = &"all_stop"

	func needs_speed() -> bool:
		return true

	func state_name() -> String:
		return "done" if done else "brake"

	func _step(p: Perception, _dt: float) -> FlightCommand:
		speed_mps = p.velocity.length()
		rate_dps = rad_to_deg(p.angular_velocity.length())
		var cmd := FlightCommand.new()
		if speed_mps < STOP_MPS and rate_dps < STOP_DPS:
			done = true
			return cmd
		cmd.brake = true
		return cmd

	func _result() -> Dictionary:
		return {"speed_mps": snappedf(speed_mps, 0.001), "rate_dps": snappedf(rate_dps, 0.001)}
