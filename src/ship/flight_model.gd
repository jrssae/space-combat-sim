class_name FlightModel
extends RefCounted
## From a `FlightCommand` to body-frame forces and torques, exactly architecture §5.2. Pure: no scene tree, no
## `Input`, no clock; the Ship calls `compute` once per physics tick and applies the `FlightOutput`.
##
## Sign conventions (§5.2), the one place they are applied:
## - Body frame is Godot's: right-handed, +X right, +Y up, -Z forward. Nozzle exhaust directions and positions
##   come from hardpoints in this frame; thrust acts along `-exhaust`, so a main nozzle (exhaust +Z) pushes
##   forward and a retro nozzle (exhaust -Z) pushes aft.
## - `FlightCommand.rot` is in pilot terms: x pitch up, y yaw right, z roll right (clockwise as seen by the
##   pilot). A positive body rotation about +X pitches the nose up, about +Y yaws it left, about +Z rolls it left,
##   so pilot axes map to body axes through `AXIS_SIGN = (+1, -1, -1)`: `w_body = rot * AXIS_SIGN * rate`.
## - Pod torque is physics, not a yaw term: `tau = Σ r_i × F_i` about the centre of mass. The right mains
##   (x > 0, thrust -Z) give `tau.y = +Σ x_i T > 0`, nose LEFT; the left mains give nose RIGHT; the retros the
##   reverse. The pod-yaw command of the assist (LT or RB => yaw right, RT or LB => yaw left) points the same
##   way as that torque, so the flight computer only ever cancels or trims pod thrust, never adds to it.
## - `FlightCommand.strafe` is (sway right, heave up) = body (+X, +Y). Brake and RCS forces are central.
## - `FlightCommand.face_dir_b` is already a body-frame direction (no `AXIS_SIGN`): while braking, the attitude
##   controller turns the nose (-Z) onto it about an axis in the body XY plane, so with no roll.

## Pilot axes (pitch up, yaw right, roll right) to body axes (+X, +Y, +Z) for rotations.
const AXIS_SIGN: Vector3 = Vector3(1.0, -1.0, -1.0)

var spec: ShipSpec
var layout: ThrusterLayout
## The assist's only state is its smoothed pod-yaw command; see `reset_assist`.
var assist: FlightAssist

var _main_total: float = 0.0
var _retro_total: float = 0.0
var _group_counts: PackedInt32Array = [0, 0, 0, 0]


func _init(p_spec: ShipSpec, p_layout: ThrusterLayout) -> void:
	spec = p_spec
	layout = p_layout
	assist = FlightAssist.new(spec)
	for group: int in layout.nozzle_groups:
		_group_counts[group] += 1
	_main_total = spec.pod_main_thrust * (_group_counts[ThrusterLayout.Group.R_MAIN] + _group_counts[ThrusterLayout.Group.L_MAIN])
	_retro_total = spec.pod_retro_thrust * (_group_counts[ThrusterLayout.Group.R_RETRO] + _group_counts[ThrusterLayout.Group.L_RETRO])


## Clears the assist's smoothed pod-yaw command. The Ship calls this when assist is toggled and on `reset_to`.
func reset_assist() -> void:
	assist.reset()


## Total forward thrust with every main nozzle at level 1, N.
func main_total() -> float:
	return _main_total


## Total aft thrust with every retro nozzle at level 1, N.
func retro_total() -> float:
	return _retro_total


## One tick of §5.2. `v_b`, `w_b` are the body-frame linear and angular velocity; `env_accel_b` is the
## environment's acceleration in the body frame (gravity hook, zero in M1), used only as brake feed-forward;
## `dt` drives the pod-yaw smoothing when assist is on. `has_propellant` is false when the `FuelTank` is empty: no
## pod nozzle and no RCS translation can fire, so the output carries zero force (`propellant_empty` is set). Attitude
## control (RCS torque) stays, because `mass_flow` never counted it, so an empty ship can still turn but not thrust.
func compute(cmd: FlightCommand, v_b: Vector3, w_b: Vector3, env_accel_b: Vector3, assist_on: bool, dt: float,
		has_propellant: bool = true) -> FlightOutput:
	var out := FlightOutput.new()
	out.assist_on = assist_on
	out.braking = cmd.brake
	out.propellant_empty = not has_propellant

	# 1. Pilot demand per nozzle group and RCS translation.
	var levels: PackedFloat64Array = [cmd.main_right, cmd.main_left, cmd.retro_right, cmd.retro_left]
	var rcs_force := Vector3(cmd.strafe.x * spec.rcs_force_max.x, cmd.strafe.y * spec.rcs_force_max.y, 0.0)

	# 2. Brake overrides all translational demand, assist on or off: symmetric sides, so zero pod torque. (Its
	# rotation half is 4c.)
	if cmd.brake:
		var a_des: Vector3 = -spec.brake_gain_k * v_b - env_accel_b
		var f_z: float = clampf(spec.mass * a_des.z, -_main_total, _retro_total)
		var main_level: float = -f_z / _main_total if f_z < 0.0 and _main_total > 0.0 else 0.0
		var retro_level: float = f_z / _retro_total if f_z > 0.0 and _retro_total > 0.0 else 0.0
		levels[ThrusterLayout.Group.R_MAIN] = main_level
		levels[ThrusterLayout.Group.L_MAIN] = main_level
		levels[ThrusterLayout.Group.R_RETRO] = retro_level
		levels[ThrusterLayout.Group.L_RETRO] = retro_level
		rcs_force = (spec.mass * Vector3(a_des.x, a_des.y, 0.0)).clamp(-spec.rcs_force_max, spec.rcs_force_max)

	# 2b. No reaction mass: nothing that burns it can fire. Cutting the demand here, before the pod torque, means the
	# rotation logic below sees the pods dead (no feed-forward, nothing to trim) and RCS torque supplies all of it.
	if not has_propellant:
		levels.fill(0.0)
		rcs_force = Vector3.ZERO

	# 3. Pod torque about the centre of mass at the demanded levels: physics, not a yaw term.
	var group_torque_y: PackedFloat64Array = [0.0, 0.0, 0.0, 0.0]
	var tau_pods: Vector3 = _pod_torque(levels, group_torque_y)

	# 4. Rotation. Auto-track: the pilot holds the nose on the lead point of the selected target; only the attitude
	# controller changes, the velocity is left alone.
	var tracking: bool = cmd.autotrack and not cmd.brake and not cmd.track_dir_b.is_zero_approx()
	var tau_rcs: Vector3
	var lam: float = 1.0
	if assist_on:
		# 4a. Pod steering: the side difference becomes a yaw-rate command (pilot terms), smoothed and capped. While
		# braking the difference reads zero, so the command decays and is not applied.
		assist.update_pod_yaw(cmd, dt)
	if cmd.brake:
		# 4c. Brake = all stop, assist on or off: the flight computer owns rotation too. The sticks are ignored and the
		# rate target is zero, or with `face_dir_b` set the attitude controller's rate that swings the nose onto it.
		# The pods are symmetric (step 2), so RCS supplies the whole rate-controller torque; nothing is trimmed.
		var w_face: Vector3 = assist.face_rate_target(cmd.face_dir_b)
		tau_rcs = (assist.rate_torque(w_face, w_b) - tau_pods).clamp(-spec.rcs_torque_max, spec.rcs_torque_max)
		out.rate_target_b = w_face
		out.facing = not cmd.face_dir_b.is_zero_approx()
		out.face_error_rad = FlightAssist.face_error_vector(cmd.face_dir_b).length()
	elif assist_on or tracking:
		var w_target: Vector3
		if tracking:
			# Pitch and yaw go to the nose-onto-lead controller; roll stays with the pilot.
			w_target = assist.track_rate_target(cmd.track_dir_b, cmd.track_rate_b)
			w_target.z = cmd.rot.z * AXIS_SIGN.z * spec.rate_max_rad().z
			out.facing = true
			out.face_error_rad = FlightAssist.face_error_vector(cmd.track_dir_b).length()
		else:
			var rot: Vector3 = assist.rotation_demand(cmd)
			w_target = rot * AXIS_SIGN * spec.rate_max_rad()
		# 4b. Rate controller with the pods' torque as feed-forward; RCS supplies the residual, and when more yaw
		# is needed than RCS has, the groups fighting it are trimmed (only ever reduced, never raised). With no
		# group fighting (stick alone, or the pods already helping) the controller simply saturates.
		var tau_des: Vector3 = assist.rate_torque(w_target, w_b)
		var residual: Vector3 = tau_des - tau_pods
		var overflow: Vector3 = residual - residual.clamp(-spec.rcs_torque_max, spec.rcs_torque_max)
		if overflow.y != 0.0:
			lam = assist.yaw_trim_factor(overflow.y, group_torque_y)
			if lam < 1.0:
				for group: int in ThrusterLayout.GROUP_COUNT:
					if FlightAssist.is_trim_cause(group_torque_y[group], overflow.y):
						levels[group] *= lam
				tau_pods = _pod_torque(levels, group_torque_y)
				residual = tau_des - tau_pods
		tau_rcs = residual.clamp(-spec.rcs_torque_max, spec.rcs_torque_max)
		out.rate_target_b = w_target
		out.tracking = tracking
		out.pod_yaw_cmd = assist.pod_yaw_command() if assist_on else 0.0
	else:
		# Raw: stick and D-pad command RCS torque directly; pod torque acts in full and nothing damps rotation.
		tau_rcs = cmd.rot * AXIS_SIGN * spec.rcs_torque_max

	# 5. Outputs, body frame.
	var pod_force := Vector3.ZERO
	var thrust_sum: float = 0.0
	for i: int in layout.nozzle_count():
		var group: int = layout.nozzle_groups[i]
		var level: float = levels[group]
		var magnitude: float = level * _group_thrust(group)
		var force: Vector3 = -layout.nozzle_exhausts[i] * magnitude
		pod_force += force
		thrust_sum += absf(magnitude)
		out.nozzle_forces.append({
			"name": layout.nozzle_names[i],
			"position": layout.nozzle_positions[i],
			"force": force,
			"group": group,
			"level": level,
		})
	out.group_levels = levels
	out.main_levels.resize(layout.pod_count())
	out.retro_levels.resize(layout.pod_count())
	for pod: int in layout.pod_count():
		var right: bool = layout.pod_is_right[pod] != 0
		out.main_levels[pod] = levels[ThrusterLayout.Group.R_MAIN if right else ThrusterLayout.Group.L_MAIN]
		out.retro_levels[pod] = levels[ThrusterLayout.Group.R_RETRO if right else ThrusterLayout.Group.L_RETRO]
	out.pod_force_b = pod_force
	out.pod_torque_b = tau_pods
	out.rcs_force_b = rcs_force
	out.rcs_torque_b = tau_rcs
	out.force_b = pod_force + rcs_force
	out.torque_b = tau_pods + tau_rcs
	out.trim = 1.0 - lam
	out.rcs_force_level = _level_of(rcs_force, spec.rcs_force_max)
	out.rcs_torque_level = _level_of(tau_rcs, spec.rcs_torque_max)
	if spec.exhaust_velocity > 0.0:
		out.mass_flow_kg_s = (thrust_sum + rcs_force.length()) / spec.exhaust_velocity
	return out


## Per-nozzle thrust of a group at level 1, N.
func _group_thrust(group: int) -> float:
	return spec.pod_main_thrust if ThrusterLayout.is_main_group(group) else spec.pod_retro_thrust


# `Σ_g level_g × thrust_g × torque_axis(g)`, the pod torque about the centre of mass; fills `group_torque_y`
# with each group's yaw torque for the trim.
func _pod_torque(levels: PackedFloat64Array, group_torque_y: PackedFloat64Array) -> Vector3:
	var total := Vector3.ZERO
	for group: int in ThrusterLayout.GROUP_COUNT:
		var tau_g: Vector3 = layout.torque_axis(group) * (levels[group] * _group_thrust(group))
		group_torque_y[group] = tau_g.y
		total += tau_g
	return total


static func _level_of(value: Vector3, limit: Vector3) -> Vector3:
	return Vector3(
		value.x / limit.x if limit.x > 0.0 else 0.0,
		value.y / limit.y if limit.y > 0.0 else 0.0,
		value.z / limit.z if limit.z > 0.0 else 0.0,
	)
