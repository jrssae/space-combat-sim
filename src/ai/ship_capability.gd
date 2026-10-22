class_name ShipCapability
extends RefCounted
## What a ship can do, in the terms a brain steers with (architecture §15.8): the accelerations the mains, retros and RCS
## can give at full level and the turn rates. Pure; built once per ship from its `ShipSpec` and thruster layout.

## m/s^2 at full level: both mains forward, both retros aft, the RCS sideways (x sway, y heave).
var a_main: float = 10.0
var a_retro: float = 5.0
var a_rcs: Vector2 = Vector2(5.0, 5.0)
## rad/s, body axes (x pitch, y yaw, z roll): the assist's rate target at full deflection.
var rate_max_rad: Vector3 = Vector3(1.0, 1.0, 1.0)


static func from_spec(spec: ShipSpec, layout: ThrusterLayout) -> ShipCapability:
	var cap := ShipCapability.new()
	var mains: int = layout.nozzles_in_group(ThrusterLayout.Group.R_MAIN).size() + layout.nozzles_in_group(ThrusterLayout.Group.L_MAIN).size()
	var retros: int = layout.nozzles_in_group(ThrusterLayout.Group.R_RETRO).size() + layout.nozzles_in_group(ThrusterLayout.Group.L_RETRO).size()
	var mass: float = maxf(spec.mass, 1.0)
	cap.a_main = maxf(float(mains) * spec.pod_main_thrust / mass, 0.01)
	cap.a_retro = maxf(float(retros) * spec.pod_retro_thrust / mass, 0.01)
	cap.a_rcs = Vector2(maxf(spec.rcs_force_max.x / mass, 0.01), maxf(spec.rcs_force_max.y / mass, 0.01))
	cap.rate_max_rad = spec.rate_max_rad()
	return cap
