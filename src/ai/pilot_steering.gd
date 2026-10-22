class_name PilotSteering
extends RefCounted
## Closed-loop steering through the real flight model, in pilot terms (architecture §15.8). Pure statics: given a pose, a
## velocity and what the ship can do, they produce the `FlightCommand` fields a pilot would. Everything goes through the
## flight assist (which tracks a commanded turn rate), so these are outer loops with gains well below the assist's own.
##
## - **face**: a P loop on the angle between the nose and a direction. The rate command is `K_FACE * angle` about the axis
##   that carries the nose onto the direction, clamped to the ship's rate limits, converted to pilot terms with
##   `FlightModel.AXIS_SIGN` and the rate limits. Roll is never commanded. With the direction dead astern the nose pitches up.
## - **seek**: the velocity error `v_des - v` is met with the mains when it is within `MAINS_CONE_DEG` of the nose, the
##   retros when it is within `180 - RETRO_CONE_DEG` of the tail, and the RCS for its sideways part. Each level is the error
##   divided by what the thrusters give in `HORIZON_S`, clamped to 0..1, so a small error gets a gentle push; under
##   `COAST_BELOW_MPS` nothing is commanded.

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
	# f x d with f = (0, 0, -1): the rotation axis (body frame) that takes the nose onto d.
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


## The thrust levels that move the velocity from `velocity` toward `v_des`: `{"main": 0..1, "retro": 0..1, "strafe": Vector2}`.
static func seek(velocity: Vector3, v_des: Vector3, basis: Basis, capability: ShipCapability) -> Dictionary:
	var out: Dictionary = {"main": 0.0, "retro": 0.0, "strafe": Vector2.ZERO}
	var dv: Vector3 = v_des - velocity
	var dv_len: float = dv.length()
	if dv_len < COAST_BELOW_MPS:
		return out
	var dv_b: Vector3 = basis.transposed() * dv
	var angle_deg: float = rad_to_deg(atan2(Vector3(dv_b.x, dv_b.y, 0.0).length(), -dv_b.z))
	if angle_deg < MAINS_CONE_DEG:
		out["main"] = clampf(-dv_b.z / (capability.a_main * HORIZON_S), 0.0, 1.0)
	elif angle_deg > RETRO_CONE_DEG:
		out["retro"] = clampf(dv_b.z / (capability.a_retro * HORIZON_S), 0.0, 1.0)
	out["strafe"] = Vector2(clampf(dv_b.x / (capability.a_rcs.x * HORIZON_S), -1.0, 1.0),
			clampf(dv_b.y / (capability.a_rcs.y * HORIZON_S), -1.0, 1.0))
	return out


## Writes a `seek` result into `flight` (both mains and both retros together: no differential yaw from the pods).
static func apply_seek(flight: FlightCommand, result: Dictionary) -> void:
	var main_level: float = result["main"]
	var retro_level: float = result["retro"]
	flight.main_left = main_level
	flight.main_right = main_level
	flight.retro_left = retro_level
	flight.retro_right = retro_level
	flight.strafe = result["strafe"]
