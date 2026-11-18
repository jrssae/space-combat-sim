class_name DockAutopilot
extends RefCounted
## The autopilot that brings the player's ship into the main docking bay (M8-T06, D82): to the lane from whatever speed the ship
## has, then along the lane's axis through the mouth and the inner doors to a stop in the void. Pure: World poses and the ship's
## velocity against the station in, one `FlightCommand` out, through `PilotSteering` as the gate's autopilot flies.
## The speeds come from `StoppingDistance`, which the approach cue shares (D84).

## The nose turns onto the velocity error while it is larger than this (a flip and burn); else onto the course.
const FACE_DV_MPS: float = 30.0
## How hard the lane pulls back onto its axis, 1/s, and the most it asks sideways, m/s.
const K_LATERAL: float = 0.5
const MAX_LATERAL_MPS: float = 25.0


## The speed to close on a point `distance` away: what the ship can still shed with a flip and its mains, no more than `cruise_mps`
## and no less than `arrive_mps` (the speed it may pass the point with; 0 stops on it).
static func approach_speed(distance: float, cruise_mps: float, arrive_mps: float, capability: ShipCapability) -> float:
	return minf(cruise_mps, maxf(arrive_mps, StoppingDistance.speed_for_mps(distance, capability.a_main)))


## The command toward `target` at `approach_speed`. `velocity` is against the station.
static func approach(position: Vector3, velocity: Vector3, basis: Basis, target: Vector3, cruise_mps: float, arrive_mps: float,
		capability: ShipCapability) -> FlightCommand:
	var to: Vector3 = target - position
	var dist: float = to.length()
	var v_des: Vector3 = to / dist * approach_speed(dist, cruise_mps, arrive_mps, capability) if dist > 1e-3 else Vector3.ZERO
	return _fly(velocity, v_des, basis, capability, v_des if dist > 1.0 else -basis.z)


## The speed along the lane with `to_stop_m` left to where the ship must stand still: what its retros can shed, at most `cap_mps`.
static func lane_speed(to_stop_m: float, cap_mps: float, capability: ShipCapability) -> float:
	return minf(cap_mps, StoppingDistance.speed_for_mps(to_stop_m, capability.a_retro))


## The command along the lane: `axis` (World, unit, into the bay) through `on_axis`, at `speed`, pulled onto the axis, nose in.
static func lane(position: Vector3, velocity: Vector3, basis: Basis, on_axis: Vector3, axis: Vector3, speed: float,
		capability: ShipCapability) -> FlightCommand:
	var rel: Vector3 = position - on_axis
	var lateral: Vector3 = rel - axis * rel.dot(axis)
	var v_des: Vector3 = axis * speed + (-lateral * K_LATERAL).limit_length(MAX_LATERAL_MPS)
	var cmd := FlightCommand.new()
	cmd.rot = PilotSteering.face(basis, axis, capability.rate_max_rad)
	# Every thruster, the nose held on the axis: the retros slow it, the side thrusters keep it in the tunnel.
	PilotSteering.apply_seek(cmd, PilotSteering.seek(velocity, v_des, basis, capability, PilotSteering.HORIZON_S, true))
	return cmd


## How far `point` lies from the lane's axis, metres.
static func off_axis_m(point: Vector3, on_axis: Vector3, axis: Vector3) -> float:
	var rel: Vector3 = point - on_axis
	return (rel - axis * rel.dot(axis)).length()


static func _fly(velocity: Vector3, v_des: Vector3, basis: Basis, capability: ShipCapability, course: Vector3) -> FlightCommand:
	var cmd := FlightCommand.new()
	var dv: Vector3 = v_des - velocity
	var nose: Vector3 = dv if dv.length() > FACE_DV_MPS else course
	if nose.length() > 1e-6:
		cmd.rot = PilotSteering.face(basis, nose, capability.rate_max_rad)
	PilotSteering.apply_seek(cmd, PilotSteering.seek(velocity, v_des, basis, capability))
	return cmd
