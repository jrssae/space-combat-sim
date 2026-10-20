class_name FlightAssist
extends RefCounted
## The flight computer's rotation logic for assist on (architecture §5.2 step 4, §5.5): pod steering turned into
## a yaw-rate command, the P rate controller, and the yaw trim that keeps pod torque within what RCS can cancel.
## Pure and body-frame; `FlightModel` owns one instance and is the only caller. The only state is the smoothed
## pod-yaw command `pod_yaw_smoothed` (`d_s` in §5.2), which `reset()` clears on assist toggle and ship reset.
##
## Pilot terms here: a positive pod-yaw command means yaw right, like `FlightCommand.rot.y`. The conversion to
## body axes (`AXIS_SIGN`) happens in `FlightModel`, not here.

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
