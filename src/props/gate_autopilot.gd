class_name GateAutopilot
extends RefCounted
## The autopilot of the player's jump (M6-T14): lines the ship up with the gate's departure point, then accelerates it along the
## gate's axis into the vortex. It takes the ship as it comes (M8-T18, D84): from any speed it brakes on the way to the departure
## point, and a ship already lined up with the mouth carries its speed down to the run-in's without stopping there. Pure: World-frame poses in, one `FlightCommand` out, through `PilotSteering` as the AI flies, so
## it obeys the same flight model and assist. It never runs the ship into the plane before the vortex can take it.

## The fastest the line-up flies: a ship that asked at speed and overshot comes back from 100 km or more in a couple of minutes;
## near the point the braking speed rules (from 2 km about 240 m/s).
const APPROACH_MPS: float = 1500.0
## The speed it arrives at the departure point with, and the floor of the approach near it.
const LINE_UP_MPS: float = 80.0
## The run-in's speed through the vortex.
const RUN_IN_MPS: float = 250.0
## s^-1 and m/s: how hard the run-in pulls back onto the axis, and the most it asks sideways.
const K_LATERAL: float = 0.4
const MAX_LATERAL_MPS: float = 60.0
## With the vortex not yet opening, the run-in creeps to this far from the plane and waits.
const WAIT_SHORT_M: float = 600.0
## A ship beside or behind the gate, out among the arms (800 m from the axis above and below, 1 240 m at the sides, their fins
## reaching about 140 m to either side), first moves out to a diagonal between two arms at least this far from the axis (about
## 1 km clear of every fin), then flies round to the front.
const DETOUR_RADIUS_M: float = 1600.0
## Inside this distance from the axis a ship is within the four arms (the nearer pair is about 760 m out), where a straight line
## to the front meets none of them.
const INSIDE_ARMS_M: float = 650.0
## The nose turns onto the velocity error while it is larger than this (a flip and burn); else onto the course.
const FACE_DV_MPS: float = 30.0
## Lined up with the mouth (M8-T18): out in front of the departure point, within this of the axis, heading in within this angle.
const LINED_UP_RADIUS_M: float = 150.0
const LINED_UP_DEG: float = 15.0
## The departure shot closes in on the ship this long before it is predicted at the mouth, and is never shorter than this.
const SHOT_CLOSE_LEAD_S: float = 2.0
const SHOT_MIN_CLOSE_S: float = 1.0
## The departure shot holds its last frame this long past the predicted arrival: the funnel, the ring and the fade fit inside.
const SHOT_HOLD_AFTER_S: float = 54.0
## The arrival's prediction steps the run-in this finely, s, and gives up past this (the run-in's own timeout).
const PREDICT_STEP_S: float = 1.0 / 30.0
const PREDICT_LIMIT_S: float = 45.0
## A ship no wider than this share of the mouth's smaller half axis fits through any way up, and keeps its roll (M7-T28).
const FITS_ANY_WAY_UP: float = 0.5


## The line-up's command: to `target` (World) at a speed that it can shed on the way down to `arrive_mps` (the run-in's for a
## ship lined up with the mouth, `line_up_arrival`), nose on the velocity error.
static func line_up(position: Vector3, velocity: Vector3, basis: Basis, target: Vector3, capability: ShipCapability,
		arrive_mps: float = LINE_UP_MPS) -> FlightCommand:
	var to: Vector3 = target - position
	var dist: float = to.length()
	var brake_mps: float = StoppingDistance.speed_for_mps(dist, capability.a_main)
	var speed: float = minf(APPROACH_MPS, maxf(arrive_mps, brake_mps))
	var v_des: Vector3 = to / dist * speed if dist > 1e-3 else Vector3.ZERO
	return _fly(velocity, v_des, basis, capability, v_des)


## Whether a ship at `local` moving at `local_velocity` (both gate-local, against the gate's rest) is lined up with the mouth: out
## in front of the departure point, near the axis through it along `forward` (the way departures fly), heading in along it.
static func lined_up(local: Vector3, local_velocity: Vector3, departure: Vector3, forward: Vector3) -> bool:
	var rel: Vector3 = local - departure
	var along: float = rel.dot(forward)
	if along > 0.0 or (rel - forward * along).length() > LINED_UP_RADIUS_M:
		return false
	var speed: float = local_velocity.length()
	return speed > LINE_UP_MPS and local_velocity.dot(forward) >= speed * cos(deg_to_rad(LINED_UP_DEG))


## The speed the line-up arrives at the departure point with: the run-in's for a lined-up ship (no stop on the way), else the
## slow line-up speed it turns onto the axis at.
static func line_up_arrival(local: Vector3, local_velocity: Vector3, departure: Vector3, forward: Vector3) -> float:
	return RUN_IN_MPS if lined_up(local, local_velocity, departure, forward) else LINE_UP_MPS


## Seconds from the run-in's start until the ship is at the mouth `to_plane_m` ahead, the vortex open in `open_in_s`: the run-in
## flies at its own speed and no sooner than the vortex can take it. Given the ship's `speed_mps` along the axis and its
## `capability`, the run-in's own pacing is followed from that speed (a ship that came back slowly first gathers speed).
static func predicted_arrival_s(to_plane_m: float, open_in_s: float, speed_mps: float = RUN_IN_MPS,
		capability: ShipCapability = null) -> float:
	if capability == null:
		var flying: float = maxf(to_plane_m, 0.0) / RUN_IN_MPS
		return maxf(flying, open_in_s) if is_finite(open_in_s) else flying
	# The run-in's command along the axis, flown in one dimension as `PilotSteering.seek` paces it.
	var left: float = to_plane_m
	var speed: float = speed_mps
	var t: float = 0.0
	while left > 0.0 and t < PREDICT_LIMIT_S:
		var wanted: float = RUN_IN_MPS
		var opens: float = open_in_s - t if is_finite(open_in_s) else INF
		if opens == INF:
			wanted = minf(wanted, maxf(left - WAIT_SHORT_M, 0.0) * 0.25)
		elif opens > 0.0:
			wanted = minf(wanted, left / opens)
		var dv: float = wanted - speed
		var accel: float = 0.0
		if absf(dv) >= PilotSteering.COAST_BELOW_MPS:
			accel = clampf(dv / PilotSteering.HORIZON_S, -capability.a_retro, capability.a_main)
		speed += accel * PREDICT_STEP_S
		left -= speed * PREDICT_STEP_S
		t += PREDICT_STEP_S
	return t


## The departure shot's keys for a ship predicted at the mouth in `arrival_s` (M8-T18): beside and behind it as it lines up,
## then in close behind it shortly before the mouth and all the way down the funnel to the ring (M6-T22).
static func departure_shot_keys(arrival_s: float) -> Array:
	var close_s: float = maxf(arrival_s - SHOT_CLOSE_LEAD_S, SHOT_MIN_CLOSE_S)
	var near: Dictionary = {"position": {"actor": "player", "offset": [22, 9, 62]}, "look_at": {"actor": "player", "offset": [0, 0, -40]},
			"fov": 55}
	return [
		{"t": 0.0, "position": {"actor": "player", "offset": [45, 18, 95]}, "look_at": {"actor": "player", "offset": [0, 0, -300]}, "fov": 62},
		near.merged({"t": close_s}),
		near.merged({"t": maxf(arrival_s, close_s) + SHOT_HOLD_AFTER_S}),
	]


## The way up a ship of `ship_radius_m` must be turned to pass a mouth whose smaller half axis is `mouth_radius_m`: `up` for one
## too wide to fit any way up, zero (keep its roll) for the rest. A fighter never rolls for a gate (M7-T28).
static func roll_up(up: Vector3, mouth_radius_m: float, ship_radius_m: float) -> Vector3:
	return up if ship_radius_m > mouth_radius_m * FITS_ANY_WAY_UP else Vector3.ZERO


## The run-in's command: along the gate's `axis` (World, unit, the way departures fly) through `centre`, pulled onto the axis,
## at a speed that reaches the plane no sooner than the vortex opens (`open_in_s`, INF while it is not opening). `up` as
## `follow_axis`.
static func run_in(position: Vector3, velocity: Vector3, basis: Basis, centre: Vector3, axis: Vector3, up: Vector3,
		open_in_s: float, capability: ShipCapability) -> FlightCommand:
	var to_plane: float = -(position - centre).dot(axis)
	var speed: float = RUN_IN_MPS
	if open_in_s == INF:
		speed = minf(speed, maxf(to_plane - WAIT_SHORT_M, 0.0) * 0.25)
	elif open_in_s > 0.0 and to_plane > 0.0:
		speed = minf(speed, to_plane / open_in_s)
	return follow_axis(position, velocity, basis, centre, axis, up, speed, capability)


## Along `axis` (World, unit) through `centre` at `speed`, pulled onto the axis, nose on the axis: the run-in, and a departing
## ship flying down a jump vortex's funnel to its base (M6-T22). Rolled to `up` only when one is given (`roll_up`); with zero the
## ship keeps the roll it has. `velocity` is against the frame's rest.
static func follow_axis(position: Vector3, velocity: Vector3, basis: Basis, centre: Vector3, axis: Vector3, up: Vector3,
		speed: float, capability: ShipCapability) -> FlightCommand:
	var rel: Vector3 = position - centre
	var lateral: Vector3 = rel - axis * rel.dot(axis)
	var correction: Vector3 = (-lateral * K_LATERAL).limit_length(MAX_LATERAL_MPS)
	var v_des: Vector3 = axis * speed + correction
	var cmd: FlightCommand = _fly(velocity, v_des, basis, capability, axis)
	if not up.is_zero_approx():
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
