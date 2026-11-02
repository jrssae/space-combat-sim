class_name PilotSteering
extends RefCounted
## Closed-loop steering through the real flight model, in pilot terms (architecture §15.8). Pure statics: given a pose, a
## velocity and what the ship can do, they produce the `FlightCommand` fields a pilot would. They sit outside the flight
## assist's own loop, so their gains are well below it.
##
## - **face**: a P loop on the angle between the nose and a direction, clamped to the rate limits. Roll is never commanded.
##   Dead astern, the nose pitches up.
## - **align_roll**: the roll alone, so formation flying can roll with its leader (M3-T07).
## - **seek**: the velocity error is met with the mains when within `MAINS_CONE_DEG` of the nose, the retros when within
##   `180 - RETRO_CONE_DEG` of the tail, and the RCS for its sideways part, each scaled by what the thrusters give in
##   `HORIZON_S` (the driver's urgent dodge seeks harder). Nothing is commanded under `COAST_BELOW_MPS`. A ship whose nose is
##   held elsewhere (formation keeping, M3-T07) seeks with `all_axes`: mains or retros along the nose, RCS for the rest.

## s^-1. The face loop's gain; the assist's own rate gain (`ShipSpec.assist_gain_k`) is 6, so the cascade is stable.
const K_FACE: float = 2.5
const COAST_BELOW_MPS: float = 1.0
const MAINS_CONE_DEG: float = 12.0
const RETRO_CONE_DEG: float = 150.0
## The velocity error is met in about this long at full thrust.
const HORIZON_S: float = 1.0


## Angle in radians between the nose and `direction_world` (0 when the direction is zero).
static func angle_to(basis: Basis, direction_world: Vector3) -> float:
	if direction_world.length_squared() < 1e-12:
		return 0.0
	var d_b: Vector3 = basis.transposed() * direction_world.normalized()
	return atan2(Vector3(d_b.y, -d_b.x, 0.0).length(), -d_b.z)


## Pilot `rot` (x pitch up, y yaw right, z roll right, each -1..1) that turns the nose toward `direction_world`.
static func face(basis: Basis, direction_world: Vector3, rate_max_rad: Vector3, gain: float = K_FACE) -> Vector3:
	if direction_world.length_squared() < 1e-12:
		return Vector3.ZERO
	var d_b: Vector3 = basis.transposed() * direction_world.normalized()
	# The body-frame axis that takes the nose onto d.
	var axis := Vector3(d_b.y, -d_b.x, 0.0)
	var sin_angle: float = axis.length()
	var angle: float = atan2(sin_angle, -d_b.z)
	if sin_angle < 1e-6:
		if -d_b.z > 0.0:
			return Vector3.ZERO  # already pointing there
		axis = Vector3(1.0, 0.0, 0.0)  # dead astern: pitch up
	else:
		axis /= sin_angle
	var w_b: Vector3 = axis * (gain * angle)
	var rot: Vector3 = w_b * FlightModel.AXIS_SIGN / rate_max_rad
	return Vector3(clampf(rot.x, -1.0, 1.0), clampf(rot.y, -1.0, 1.0), 0.0)


## `face` with the direction's own turn rate `omega_world` (rad/s, World frame) fed forward (M3-T18), so a turning lead in a
## slashing pass is tracked instead of trailed.
static func face_tracking(basis: Basis, direction_world: Vector3, omega_world: Vector3, rate_max_rad: Vector3,
		gain: float = K_FACE) -> Vector3:
	var rot: Vector3 = face(basis, direction_world, rate_max_rad, gain)
	var w_ff: Vector3 = basis.transposed() * omega_world
	var ff: Vector3 = Vector3(w_ff.x, w_ff.y, 0.0) * FlightModel.AXIS_SIGN / rate_max_rad
	return Vector3(clampf(rot.x + ff.x, -1.0, 1.0), clampf(rot.y + ff.y, -1.0, 1.0), 0.0)


## Pilot roll (`rot.z`, + = roll right, -1..1) that turns the ship's top toward `up_world`. Only the part square to the nose
## counts; 0 when it vanishes or the ship is already level.
static func align_roll(basis: Basis, up_world: Vector3, rate_max_rad: Vector3, gain: float = K_FACE) -> float:
	var u_b: Vector3 = basis.transposed() * up_world
	if Vector2(u_b.x, u_b.y).length_squared() < 1e-12:
		return 0.0
	# Positive when the target leans right, which a roll right reaches.
	var angle: float = atan2(u_b.x, u_b.y)
	if absf(angle) < 1e-9:
		return 0.0
	var w_bz: float = -gain * angle
	return clampf(w_bz * FlightModel.AXIS_SIGN.z / rate_max_rad.z, -1.0, 1.0)


## The thrust levels that move the velocity from `velocity` toward `v_des`: `{"main": 0..1, "retro": 0..1, "strafe": Vector2}`.
## `all_axes`: the mains or retros on the part along the nose whatever the angle (a ship whose nose is held elsewhere).
static func seek(velocity: Vector3, v_des: Vector3, basis: Basis, capability: ShipCapability,
		horizon_s: float = HORIZON_S, all_axes: bool = false) -> Dictionary:
	var out: Dictionary = {"main": 0.0, "retro": 0.0, "strafe": Vector2.ZERO}
	var dv: Vector3 = v_des - velocity
	var dv_len: float = dv.length()
	if dv_len < COAST_BELOW_MPS:
		return out
	var dv_b: Vector3 = basis.transposed() * dv
	var angle_deg: float = 0.0 if all_axes else rad_to_deg(atan2(Vector3(dv_b.x, dv_b.y, 0.0).length(), -dv_b.z))
	if all_axes or angle_deg < MAINS_CONE_DEG:
		out["main"] = clampf(-dv_b.z / (capability.a_main * horizon_s), 0.0, 1.0)
	if all_axes or angle_deg > RETRO_CONE_DEG:
		out["retro"] = clampf(dv_b.z / (capability.a_retro * horizon_s), 0.0, 1.0)
	out["strafe"] = Vector2(clampf(dv_b.x / (capability.a_rcs.x * horizon_s), -1.0, 1.0),
			clampf(dv_b.y / (capability.a_rcs.y * horizon_s), -1.0, 1.0))
	return out


## The nose direction nearest `base` (unit) from which the RCS (at most `a_side` m/s^2 square to the nose) and the mains or
## retros together give `accel` (World frame). `base` itself while the RCS can cope; else `base` leant by the least angle
## that lets it, at most `max_lean_rad`. A ship flying another's attitude leans this way when the RCS alone cannot keep up
## (formation keeping, M3-T07).
static func lean_toward(base: Vector3, accel: Vector3, a_side: float, max_lean_rad: float) -> Vector3:
	var along: float = accel.dot(base)
	var side: Vector3 = accel - base * along
	var side_len: float = side.length()
	if side_len <= a_side or side_len < 1e-9:
		return base
	# Square part after leaning by t: side_len cos t - |along| sin t = A cos(t + phi).
	var amplitude: float = sqrt(side_len * side_len + along * along)
	var lean: float = acos(clampf(a_side / amplitude, 0.0, 1.0)) - atan2(absf(along), side_len)
	lean = clampf(lean, 0.0, max_lean_rad)
	var toward: Vector3 = side / side_len if along >= 0.0 else -side / side_len
	return (base * cos(lean) + toward * sin(lean)).normalized()


## Writes a `seek` result into `flight`, both pods together so they add no yaw.
static func apply_seek(flight: FlightCommand, result: Dictionary) -> void:
	var main_level: float = result["main"]
	var retro_level: float = result["retro"]
	flight.main_left = main_level
	flight.main_right = main_level
	flight.retro_left = retro_level
	flight.retro_right = retro_level
	flight.strafe = result["strafe"]
