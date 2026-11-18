class_name BotCrewMotion
extends BotMover
## One maintenance bot of the station's crew (M7-T35): docked and hidden in the cargo bay until it is given a `BotTrip`, then
## flown through the trip's steps and home again. Kinematic and smooth: it speeds up and slows to a stop at a fixed acceleration on
## each flight, rides the drum turning with it and meets the jumpgate where it is now. Everything it reports is in the station's
## frame; the moving frames come from the shared `BotFrames`. Pure: the bot's node reads `position`, `heading` and `is_visible()`.

## A bot never crawls slower than this on a flight, so it always arrives, m/s.
const MIN_SPEED_MPS: float = 0.5
## How fast a bot backs off its work spot while fighting is near it, m/s.
const DUCK_SPEED_MPS: float = 4.0

var frames: BotFrames = null
## Where a docked bot waits, hidden, in the station's frame.
var dock: Vector3 = Vector3.ZERO
## How fast a flight's speed may change, m/s^2, and how long getting on or off the drum takes, s.
var accel_mps2: float = 4.0
var spin_s: float = 20.0

var trip: BotTrip = null
var index: int = 0
## Metres along the current flight, or seconds into a hold or a spin.
var progress: float = 0.0
## The drum angle this bot rides at, rad (set when it lands on the drum).
var psi: float = 0.0
## How far it has backed off its work spot (0 at it) and how far it may (the crew's duck), m.
var duck_m: float = 0.0
var duck_goal_m: float = 0.0
## Trips flown, for the console.
var trips_flown: int = 0

var _homeward: bool = false
var _abort_after_spin: bool = false
var _waiting: bool = false
var _wait_prev: float = -1.0
var _psi_from: float = 0.0
var _psi_delta: float = 0.0
## Where the bot was left by its last step: the frame and the point in it.
var _anchor_frame: BotTrip.Frame = BotTrip.Frame.STATION
var _anchor: Vector3 = Vector3.ZERO
var _duck_dir: Vector3 = Vector3.ZERO
var _transit_len: float = 0.0


func setup(p_frames: BotFrames, p_dock: Vector3, p_accel: float, p_spin_s: float) -> void:
	frames = p_frames
	dock = p_dock
	accel_mps2 = p_accel
	spin_s = p_spin_s
	position = dock
	heading = Vector3.FORWARD


func is_visible() -> bool:
	return trip != null


func is_docked() -> bool:
	return trip == null


## Sends the docked bot out on `p_trip`.
func start(p_trip: BotTrip) -> void:
	trip = p_trip
	index = 0
	_homeward = false
	_abort_after_spin = false
	duck_m = 0.0
	duck_goal_m = 0.0
	trips_flown += 1
	_begin_step()


## Calls the bot home: it turns round where it is (or finishes getting on the drum first) and flies back to the bay.
func recall() -> void:
	if trip == null or _homeward:
		return
	var step: Dictionary = trip.steps[index]
	if int(step["kind"]) == BotTrip.Kind.SPIN_UP and not _waiting:
		_abort_after_spin = true
		_homeward = true
		return
	_homeward = true
	var next: int = trip.home_step(index)
	if next < 0:
		return
	if int(step["kind"]) == BotTrip.Kind.SPIN_UP:
		next += 1  # still waiting under the drum: never got on, so no getting off
	var mirrored_progress: float = -1.0
	match int(step["kind"]):
		BotTrip.Kind.FLY:
			mirrored_progress = (step["route"] as BotRoute).length_m - progress
		BotTrip.Kind.TRANSIT:
			mirrored_progress = _transit_len - progress
	index = next
	if index >= trip.steps.size():
		_finish()
		return
	_begin_step()
	if mirrored_progress >= 0.0:
		progress = maxf(mirrored_progress, 0.0)
		speed_mps = minf(speed_mps, 2.0)


func homeward() -> bool:
	return _homeward or (trip != null and index > trip.middle)


## The step it is on now, or an empty one when docked.
func current() -> Dictionary:
	return trip.steps[index] if trip != null else {}


## True while it is at its work spot (not backed off), working.
func at_work() -> bool:
	return trip != null and int(trip.steps[index]["kind"]) == BotTrip.Kind.WORK and duck_m <= 0.01


## The crew's word that the work is done: it goes on home.
func work_done() -> void:
	if trip != null and int(trip.steps[index]["kind"]) == BotTrip.Kind.WORK:
		_next_step()


func phase_name() -> String:
	if trip == null:
		return "docked"
	var kind: String = String(BotTrip.Kind.keys()[int(trip.steps[index]["kind"])]).to_lower()
	if _waiting:
		kind += " (waiting for the drum)"
	return "%s %s%s" % [trip.label, kind, " home" if homeward() else ""]


func step(delta: float, _alarm: bool) -> void:
	if trip == null:
		position = dock
		return
	var s: Dictionary = trip.steps[index]
	match int(s["kind"]):
		BotTrip.Kind.FLY:
			_fly(delta, s)
		BotTrip.Kind.TRANSIT:
			_transit(delta, s)
		BotTrip.Kind.SPIN_UP:
			_spin(delta, s, true)
		BotTrip.Kind.SPIN_DOWN:
			_spin(delta, s, false)
		BotTrip.Kind.HOLD:
			progress += delta
			_hold_pose(delta)
			if progress >= float(s["seconds"]):
				_next_step()
		BotTrip.Kind.WORK:
			duck_m = move_toward(duck_m, duck_goal_m, DUCK_SPEED_MPS * delta)
			_hold_pose(delta)


func _begin_step() -> void:
	progress = 0.0
	_waiting = false
	_wait_prev = -1.0
	var s: Dictionary = trip.steps[index]
	match int(s["kind"]):
		BotTrip.Kind.FLY, BotTrip.Kind.TRANSIT:
			speed_mps = MIN_SPEED_MPS
		BotTrip.Kind.SPIN_UP, BotTrip.Kind.SPIN_DOWN:
			_waiting = true
		BotTrip.Kind.WORK:
			duck_m = 0.0
			duck_goal_m = 0.0


func _next_step() -> void:
	if _abort_after_spin:
		_abort_after_spin = false
		var mirror: int = trip.steps.size() - 1 - index
		index = mirror
	else:
		index += 1
	if index >= trip.steps.size():
		_finish()
		return
	_begin_step()


func _finish() -> void:
	trip = null
	index = 0
	speed_mps = 0.0
	position = dock


func _fly(delta: float, s: Dictionary) -> void:
	var route: BotRoute = s["route"]
	var frame: BotTrip.Frame = s["frame"]
	var left: float = route.length_m - progress
	_speed_on(delta, float(s["speed"]), accel_mps2, left)
	progress = minf(progress + speed_mps * delta, route.length_m)
	var local: Vector3 = route.point_at(progress)
	position = frames.to_station(local, frame, psi)
	heading = frames.dir_to_station(route.direction_at(progress), frame, psi)
	up = _up_in(frame, s, local)
	if progress >= route.length_m:
		_anchor_frame = frame
		_anchor = local
		_duck_dir = -route.direction_at(route.length_m)
		_next_step()


func _transit(delta: float, s: Dictionary) -> void:
	var from: Vector3 = frames.to_station(s["from"], s["from_frame"])
	var to: Vector3 = frames.to_station(s["to"], s["to_frame"])
	_transit_len = maxf(from.distance_to(to), 0.01)
	_speed_on(delta, float(s["speed"]), float(s["accel"]), _transit_len - progress)
	progress = minf(progress + speed_mps * delta, _transit_len)
	position = from.lerp(to, progress / _transit_len)
	heading = (to - from).normalized()
	up = Vector3.UP
	if progress >= _transit_len:
		_anchor_frame = s["to_frame"]
		_anchor = s["to"]
		_duck_dir = Vector3.ZERO
		_next_step()


# Getting on the drum (`on`) or off it: the bot's angle about the axis eases from the hold point's to the drum angle `psi` it
# rides at, so its turn rate goes from still to the drum's (and back). With the drum turning it first waits for the moment that
# makes the ramp land exactly where it should, so it never swings round against the drum.
func _spin(delta: float, s: Dictionary, on: bool) -> void:
	var radius: float = float(s["radius"])
	var z: float = float(s["z"])
	var omega: float = frames.spin_rate
	var half_sweep: float = omega * spin_s * 0.5
	var beta: float = frames.hold_angle
	if _waiting:
		var target_psi: float = float(s["psi"]) if on else psi
		var free: bool = on and is_nan(target_psi)
		if absf(omega) > 1e-4 and not free:
			# The drum angle at which to start: on, the ramp lands at `psi`; off, it ends at the hold point.
			var start_at: float = (beta - half_sweep - target_psi) if on else (beta - target_psi - half_sweep)
			var d: float = fposmod(frames.drum_angle - start_at, TAU)
			var crossed: bool = _wait_prev >= 0.0 and (d < _wait_prev if omega > 0.0 else d > _wait_prev)
			_wait_prev = d
			if not crossed:
				_pose_spin(radius, z, (beta if on else frames.drum_angle + psi), on, 0.0)
				return
		_waiting = false
		progress = 0.0
		if on:
			_psi_from = beta - frames.drum_angle
			var want: float = (_psi_from - half_sweep) if free else target_psi
			_psi_delta = wrapf(want - _psi_from + half_sweep, -PI, PI) - half_sweep
		else:
			_psi_from = psi
			# Where the drum will be when the ramp ends; the bot must then stand at the hold point.
			var end_angle: float = frames.drum_angle + omega * spin_s
			_psi_delta = wrapf(beta - end_angle - psi + half_sweep, -PI, PI) - half_sweep
	progress += delta
	var u: float = clampf(progress / maxf(spin_s, 1e-3), 0.0, 1.0)
	var ease: float = (2.0 * u - u * u) if on else (u * u)
	var rel: float = _psi_from + _psi_delta * ease
	_pose_spin(radius, z, frames.drum_angle + rel, on, u)
	if u >= 1.0:
		if on:
			psi = _psi_from + _psi_delta
			_anchor_frame = BotTrip.Frame.DRUM
			_anchor = Vector3(radius, 0.0, z - frames.pivot.z)
		else:
			_anchor_frame = BotTrip.Frame.STATION
			_anchor = frames.on_circle(radius, z, beta)
			position = _anchor
		_duck_dir = Vector3.ZERO
		_next_step()


func _pose_spin(radius: float, z: float, phi: float, _on: bool, _u: float) -> void:
	position = frames.on_circle(radius, z, phi)
	var radial := Vector3(cos(phi), sin(phi), 0.0)
	up = radial
	var tangent := Vector3(-sin(phi), cos(phi), 0.0)
	heading = tangent if frames.spin_rate >= 0.0 else -tangent


func _hold_pose(_delta: float) -> void:
	var local: Vector3 = _anchor
	if duck_m > 0.0 and _duck_dir != Vector3.ZERO:
		local += _duck_dir * duck_m
	position = frames.to_station(local, _anchor_frame, psi)
	if _anchor_frame == BotTrip.Frame.DRUM:
		up = frames.dir_to_station(Vector3(local.x, local.y, 0.0).normalized(), BotTrip.Frame.DRUM, psi)
		heading = frames.dir_to_station(Vector3(0.0, 1.0, 0.0), BotTrip.Frame.DRUM, psi)


## Whether a duck (backing off the work spot) is possible here: only on a flight's end in the station's frame.
func can_duck() -> bool:
	return _anchor_frame == BotTrip.Frame.STATION and _duck_dir != Vector3.ZERO


func _speed_on(delta: float, cruise: float, accel: float, left_m: float) -> void:
	var cap: float = sqrt(maxf(2.0 * accel * maxf(left_m, 0.0), 0.0))
	speed_mps = maxf(MIN_SPEED_MPS, move_toward(speed_mps, minf(cruise, cap), accel * delta))


func _up_in(frame: BotTrip.Frame, s: Dictionary, local: Vector3) -> Vector3:
	if frame == BotTrip.Frame.DRUM:
		return frames.dir_to_station(Vector3(local.x, local.y, 0.0).normalized(), frame, psi)
	return frames.dir_to_station(s.get("up", Vector3.UP), frame, psi)
