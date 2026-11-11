class_name GateAutopilot
extends RefCounted
## The autopilot of the player's jump (M6-T14): lines the ship up with the gate's departure point, then accelerates it along the
## gate's axis into the vortex. Pure: World-frame poses in, one `FlightCommand` out, through `PilotSteering` as the AI flies, so
## it obeys the same flight model and assist. It never runs the ship into the plane before the vortex can take it.

## Fast enough to cross 10 km in about half a minute.
const APPROACH_MPS: float = 300.0
## The speed it arrives at the departure point with, and the floor of the approach near it.
const LINE_UP_MPS: float = 80.0
## The run-in's speed through the vortex.
const RUN_IN_MPS: float = 250.0
## s^-1 and m/s: how hard the run-in pulls back onto the axis, and the most it asks sideways.
const K_LATERAL: float = 0.4
const MAX_LATERAL_MPS: float = 60.0
## With the vortex not yet opening, the run-in creeps to this far from the plane and waits.
const WAIT_SHORT_M: float = 600.0
## A ship beside or behind the gate, out among the arms (800 m from the axis, their fins to about 950 m), first moves out to a
## diagonal between two arms at least this far from the axis, then flies round to the front.
const DETOUR_RADIUS_M: float = 1600.0
## Inside this distance from the axis a ship is within the four arms, where a straight line to the front meets none of them.
const INSIDE_ARMS_M: float = 650.0
## The nose turns onto the velocity error while it is larger than this (a flip and burn); else onto the course.
const FACE_DV_MPS: float = 30.0


## The line-up's command: to `target` (World) at a speed that it can shed on the way, nose on the velocity error.
static func line_up(position: Vector3, velocity: Vector3, basis: Basis, target: Vector3, capability: ShipCapability) -> FlightCommand:
	var to: Vector3 = target - position
	var dist: float = to.length()
	var brake_mps: float = sqrt(2.0 * maxf(capability.a_main, 0.1) * dist) * 0.7
	var speed: float = minf(APPROACH_MPS, maxf(LINE_UP_MPS, brake_mps))
	var v_des: Vector3 = to / dist * speed if dist > 1e-3 else Vector3.ZERO
	return _fly(velocity, v_des, basis, capability, v_des)


## The run-in's command: along the gate's `axis` (World, unit, the way departures fly) through `centre`, pulled onto the axis,
## at a speed that reaches the plane no sooner than the vortex opens (`open_in_s`, INF while it is not opening).
static func run_in(position: Vector3, velocity: Vector3, basis: Basis, centre: Vector3, axis: Vector3, up: Vector3,
		open_in_s: float, capability: ShipCapability) -> FlightCommand:
	var rel: Vector3 = position - centre
	var to_plane: float = -rel.dot(axis)
	var lateral: Vector3 = rel + axis * to_plane
	var speed: float = RUN_IN_MPS
	if open_in_s == INF:
		speed = minf(speed, maxf(to_plane - WAIT_SHORT_M, 0.0) * 0.25)
	elif open_in_s > 0.0 and to_plane > 0.0:
		speed = minf(speed, to_plane / open_in_s)
	var correction: Vector3 = (-lateral * K_LATERAL).limit_length(MAX_LATERAL_MPS)
	var v_des: Vector3 = axis * speed + correction
	var cmd: FlightCommand = _fly(velocity, v_des, basis, capability, axis)
	cmd.rot.z = PilotSteering.align_roll(basis, up, capability.rate_max_rad)
	return cmd


## Where the line-up flies to now: the departure point, or first a point on a diagonal between two arms when the ship is beside
## or behind the gate out among the arms (the arms run parallel to the axis, so a straight line to the front could meet one).
## `local` is the ship in the gate's frame; the answer is gate-local too.
static func line_up_target(local: Vector3, departure: Vector3) -> Vector3:
	var radial := Vector2(local.x, local.y)
	if local.z <= 0.0 or radial.length() < INSIDE_ARMS_M or _between_arms(radial):
		return departure
	# Out on the diagonal nearest the ship (the arms lie on x and y), so the way round to the front misses them.
	var angle: float = radial.angle() if radial.length() > 1.0 else PI / 4.0
	var diagonal: float = PI / 4.0 + roundf((angle - PI / 4.0) / (PI / 2.0)) * (PI / 2.0)
	var side: Vector2 = Vector2.from_angle(diagonal) * maxf(DETOUR_RADIUS_M, radial.length())
	return Vector3(side.x, side.y, local.z)


static func _fly(velocity: Vector3, v_des: Vector3, basis: Basis, capability: ShipCapability, course: Vector3) -> FlightCommand:
	var cmd := FlightCommand.new()
	var dv: Vector3 = v_des - velocity
	var nose: Vector3 = dv if dv.length() > FACE_DV_MPS else course
	if nose.length() > 1e-6:
		cmd.rot = PilotSteering.face(basis, nose, capability.rate_max_rad)
	PilotSteering.apply_seek(cmd, PilotSteering.seek(velocity, v_des, basis, capability))
	return cmd


# Close enough to a diagonal that a straight line to the front passes between two arms.
static func _between_arms(radial: Vector2) -> bool:
	var off: float = fposmod(radial.angle() - PI / 4.0, PI / 2.0)
	return minf(off, PI / 2.0 - off) <= deg_to_rad(20.0)
