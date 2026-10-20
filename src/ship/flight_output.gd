class_name FlightOutput
extends RefCounted
## What `FlightModel.compute` produces for one physics tick (architecture §5.2, step 5): the forces the Ship
## applies, plus predicted totals and levels for tests and the HUD overlay. Everything is in the body frame; the
## Ship rotates by its basis `B` before `apply_force(B * force, B * position)`, `apply_central_force(B *
## rcs_force_b)` and `apply_torque(B * rcs_torque_b)`.

## One entry per pod nozzle, in `ThrusterLayout` nozzle order: `name` (String), `position` (Vector3, body origin
## frame), `force` (Vector3, N), `group` (int, `ThrusterLayout.Group`), `level` (float, 0..1 after trim).
var nozzle_forces: Array[Dictionary] = []
## RCS translation force, N (sway x, heave y; z is always 0).
var rcs_force_b: Vector3 = Vector3.ZERO
## RCS torque, N·m.
var rcs_torque_b: Vector3 = Vector3.ZERO
## Sum of the pod nozzle forces, N.
var pod_force_b: Vector3 = Vector3.ZERO
## Sum of `r_i × F_i` over the pod nozzles about the centre of mass, N·m (after trim).
var pod_torque_b: Vector3 = Vector3.ZERO
## Predicted total force `pod_force_b + rcs_force_b`, N.
var force_b: Vector3 = Vector3.ZERO
## Predicted total torque `pod_torque_b + rcs_torque_b`, N·m.
var torque_b: Vector3 = Vector3.ZERO
## 0..1: how much the flight computer reduced the trimmed nozzle groups (`1 - lam`); 0 when nothing was trimmed.
var trim: float = 0.0
## -1..1, pilot terms (+ = yaw right): `pod_yaw_gain × d_s`, the smoothed pod-steering yaw command (0 when assist
## is off).
var pod_yaw_cmd: float = 0.0
## Rate target handed to the rate controller, rad/s, body frame; zero when assist is off and not braking.
var rate_target_b: Vector3 = Vector3.ZERO
## Levels per nozzle group after trim, indexed by `ThrusterLayout.Group`.
var group_levels: PackedFloat64Array = [0.0, 0.0, 0.0, 0.0]
## Main nozzle level per pod after trim, indexed like `ThrusterLayout.pod_names`.
var main_levels: PackedFloat64Array = []
## Retro nozzle level per pod after trim, indexed like `ThrusterLayout.pod_names`.
var retro_levels: PackedFloat64Array = []
## RCS translation level per axis, -1..1 (`rcs_force_b / rcs_force_max`; 0 where the maximum is 0).
var rcs_force_level: Vector3 = Vector3.ZERO
## RCS torque level per axis, -1..1 (`rcs_torque_b / rcs_torque_max`; 0 where the maximum is 0).
var rcs_torque_level: Vector3 = Vector3.ZERO
## Reaction-mass seam: `(Σ |F_i| + |rcs_force_b|) / exhaust_velocity`, kg/s. Not consumed in M1.
var mass_flow_kg_s: float = 0.0
## Echo of the mode the output was computed in, for the overlay.
var assist_on: bool = false
## True when the brake took over this tick: translation and rotation (all stop, or facing `face_dir_b`).
var braking: bool = false
## True while braking with a `FlightCommand.face_dir_b`: the rate target turns the nose onto that direction.
var facing: bool = false
## Angle between the nose and `face_dir_b` this tick, rad; 0 when not `facing`.
var face_error_rad: float = 0.0
