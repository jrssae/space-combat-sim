class_name FlightAssist
extends RefCounted
## The flight computer's rotation logic for assist on (architecture §5.2 step 4, §5.5): pod steering turned into
## a yaw-rate command, the P rate controller, and the yaw trim that keeps pod torque within what RCS can cancel.
## Pure and body-frame; `FlightModel` owns one instance and is the only caller. The only state is the smoothed
## pod-yaw command `pod_yaw_smoothed` (`d_s` in §5.2), which `reset()` clears on assist toggle and ship reset.
##
## Pilot terms here: a positive pod-yaw command means yaw right, like `FlightCommand.rot.y`. The conversion to
## body axes (`AXIS_SIGN`) happens in `FlightModel`, not here.
##
## It also holds the brake's attitude controller (§5.5), used in both assist modes: `face_rate_target` turns a
## body-frame direction into a body-frame rate target for the same P rate controller. That outer loop is stateless.

## Share of the RCS angular acceleration the face-target controller plans to decelerate with; the rest covers the
## rate loop's lag and nulling any rate across the turn axis at the same time.
const FACE_DECEL_FRACTION: float = 0.5

var spec: ShipSpec
## `d_s`: the first-order-smoothed, deadzoned pod-yaw command, -1..1, pilot terms (+ = yaw right).
var pod_yaw_smoothed: float = 0.0


func _init(p_spec: ShipSpec) -> void:
	spec = p_spec


## Clears the smoothed pod-yaw command. Called when assist is toggled and when the ship is reset.
func reset() -> void:
	pod_yaw_smoothed = 0.0


## The raw side difference of triggers and bumpers as a yaw command in pilot terms (+ = yaw right): LT or RB
## push the nose right, RT or LB push it left. Zero while braking, since the brake owns the pods then.
static func pod_yaw_raw(cmd: FlightCommand) -> float:
	if cmd.brake:
		return 0.0
	return (cmd.main_left - cmd.main_right) + (cmd.retro_right - cmd.retro_left)


## Deadzone and rescale: differences below `pod_yaw_deadzone` give 0, the rest maps linearly so a full
## one-sided trigger (difference 1) still gives 1. Clamped to ±1.
func pod_yaw_shaped(raw: float) -> float:
	var deadzone: float = clampf(spec.pod_yaw_deadzone, 0.0, 0.999)
	var shaped: float = signf(raw) * maxf(0.0, absf(raw) - deadzone) / (1.0 - deadzone)
	return clampf(shaped, -1.0, 1.0)


## Advances the smoothed pod-yaw command by one tick of `dt` seconds toward the shaped command for `cmd` and
## returns it. First-order: `d_s += (target - d_s) * (1 - exp(-dt / tau))`, so two half steps equal one step.
func update_pod_yaw(cmd: FlightCommand, dt: float) -> float:
	var target: float = pod_yaw_shaped(pod_yaw_raw(cmd))
	var tau: float = spec.pod_yaw_smoothing_s
	var alpha: float = 1.0
	if tau > 0.0 and dt > 0.0:
		alpha = 1.0 - exp(-dt / tau)
	elif dt <= 0.0:
		alpha = 0.0
	pod_yaw_smoothed += (target - pod_yaw_smoothed) * alpha
	return pod_yaw_smoothed


## The pod-yaw command as the overlay shows it: `pod_yaw_gain × d_s`, pilot terms.
func pod_yaw_command() -> float:
	return spec.pod_yaw_gain * pod_yaw_smoothed


## The rotation demand in pilot terms (-1..1 per axis) with the pod-yaw command folded into yaw and the sum
## capped, so stick plus trigger reach full rate but never more.
func rotation_demand(cmd: FlightCommand) -> Vector3:
	return Vector3(cmd.rot.x, clampf(cmd.rot.y + pod_yaw_command(), -1.0, 1.0), cmd.rot.z)


## P rate controller: the body-frame torque that would close the rate error in `1 / assist_gain_k` seconds,
## `tau_des = inertia * k * (w_target - w_b)` per axis (diagonal inertia). Unclamped; the caller splits it
## between pod feed-forward, RCS and trim.
func rate_torque(w_target_b: Vector3, w_b: Vector3) -> Vector3:
	return spec.inertia * (spec.assist_gain_k * (w_target_b - w_b))


## Gain of the face-target loop on the nose error, s⁻¹. With the P rate loop (gain `k = assist_gain_k`) inside it
## the small-angle error obeys `θ'' + k θ' + k K θ = 0`, critically damped at `K = k / 4` (double pole at `-k / 2`).
func face_gain() -> float:
	return spec.assist_gain_k / 4.0


## Angular acceleration RCS can give about any axis in the body XY plane, rad/s²: the weaker of pitch and yaw
## (`rcs_torque_max / inertia`), a bound that holds whatever the mix of the two.
func turn_accel_max() -> float:
	var pitch: float = spec.rcs_torque_max.x / spec.inertia.x if spec.inertia.x > 0.0 else 0.0
	var yaw: float = spec.rcs_torque_max.y / spec.inertia.y if spec.inertia.y > 0.0 else 0.0
	return maxf(0.0, minf(pitch, yaw))


## The brake's rate target, body frame, rad/s: zero (all stop) for a zero `dir_b`, else the rate that swings the
## nose (-Z) onto `dir_b` along the shortest arc. Its size is `min(face_gain · θ, sqrt(2 · a · θ))` with
## `a = FACE_DECEL_FRACTION · turn_accel_max()`, so the turn can always be stopped within RCS authority, then the
## whole vector is scaled down to fit `rate_max` per axis (the nose still swings straight at the target). The roll
## target is always zero: facing a point has no roll requirement.
func face_rate_target(dir_b: Vector3) -> Vector3:
	var error: Vector3 = face_error_vector(dir_b)
	var angle: float = error.length()
	if angle == 0.0:
		return Vector3.ZERO
	var decel: float = FACE_DECEL_FRACTION * turn_accel_max()
	var rate: float = minf(face_gain() * angle, sqrt(2.0 * decel * angle))
	var w: Vector3 = error / angle * rate
	var cap: Vector3 = spec.rate_max_rad()
	var scale: float = 1.0
	if absf(w.x) > cap.x:
		scale = minf(scale, cap.x / absf(w.x))
	if absf(w.y) > cap.y:
		scale = minf(scale, cap.y / absf(w.y))
	return w * scale


## The rotation vector, body frame, rad, that turns the nose (-Z) onto `dir_b` by the shortest arc: about
## `FORWARD × d = (d.y, -d.x, 0)`, so pitch and yaw only, never roll; its length is the angle off the nose. Zero for a
## zero direction or one dead ahead; dead astern it pitches up (+X) through the target.
static func face_error_vector(dir_b: Vector3) -> Vector3:
	if dir_b.is_zero_approx():
		return Vector3.ZERO
	var d: Vector3 = dir_b.normalized()
	var axis := Vector3(d.y, -d.x, 0.0)
	var sine: float = axis.length()
	var angle: float = atan2(sine, -d.z)
	if angle == 0.0:
		return Vector3.ZERO
	if sine < 1e-9:
		return Vector3(angle, 0.0, 0.0)
	return axis * (angle / sine)


## Yaw trim factor `lam` (0..1) for the groups that cause an RCS overflow. `overflow_y` is the part of the yaw
## residual (`tau_des - tau_pods`) beyond `rcs_torque_max.y`; `group_torque_y` is each group's current yaw
## torque. The causing groups are those pushing against the overflow (`sign(tau_g.y) == -sign(overflow_y)`);
## scaling them by `lam = 1 - |overflow_y| / Σ|tau_g.y|` removes exactly the excess. Returns 1 when there is no
## overflow or no group causes it (then the stick alone asks for more than RCS has, which is plain saturation).
func yaw_trim_factor(overflow_y: float, group_torque_y: PackedFloat64Array) -> float:
	if overflow_y == 0.0:
		return 1.0
	var cause_total: float = 0.0
	for group: int in group_torque_y.size():
		if is_trim_cause(group_torque_y[group], overflow_y):
			cause_total += absf(group_torque_y[group])
	if cause_total <= 0.0:
		return 1.0
	return maxf(0.0, 1.0 - absf(overflow_y) / cause_total)


## Whether a group with yaw torque `torque_y` is one the trim must reduce for this overflow.
static func is_trim_cause(torque_y: float, overflow_y: float) -> bool:
	return overflow_y != 0.0 and torque_y != 0.0 and signf(torque_y) == -signf(overflow_y)
