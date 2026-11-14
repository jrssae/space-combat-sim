class_name FerryPod
extends RefCounted
## One cargo pod being carried by maintenance bots (M7-T30): where it is along its `CargoTrip`, and whether it waits for its bots,
## moves, lies where they let it go, or is done. Unloading carries it from the hull into the bay's back wall, loading the other
## way. It only moves while every bot it needs there holds it; its bots (`BotFerryMotion`) read it and step it.
##
## Fighting near: away from the bay its bots let go and it waits where it is; nearer the bay they carry on inside (unloading) or
## back inside (loading), and the trip starts again after the quiet. Pure.

enum State { WAITING, MOVING, DROPPED, DONE }

const CRUISE_MPS: float = 20.0
const HURRY_MPS: float = 30.0
const ACCEL_MPS2: float = 2.0
## The speed it slides into the wall at, and the least speed while moving, m/s.
const ENTER_MPS: float = 4.0
const MIN_SPEED_MPS: float = 0.5
## How long its bots hold it before it moves, and hold still before letting go, s.
const GRAB_S: float = 3.0
const EPS_M: float = 0.01

var trip: CargoTrip = null
var loading: bool = false
var state: State = State.WAITING
## Metres along the trip's path (0 on the hull), the speed along it and which way it goes now (+1 toward the bay).
var s: float = 0.0
var speed_mps: float = 0.0
var dir: float = 1.0
## Which of its bots hold it now (one flag a bot, the trip's order).
var holding := PackedByteArray()
## Whether the freighter is at its hold point: until then the pod waits (its bots may already be on their way).
var berthed: bool = true
## Times its bots let it go in a fight, and times it went back inside instead.
var drops: int = 0
var retreats: int = 0

var _clock_s: float = 0.0
var _pending_alarm: bool = false
var _held_s: float = 0.0


func _init(p_trip: CargoTrip, p_loading: bool) -> void:
	trip = p_trip
	loading = p_loading
	holding.resize(trip.bot_count())
	s = trip.carry.length_m if loading else 0.0
	dir = -1.0 if loading else 1.0


## Carries on from `old` (the same pod, planned again from where the freighter stopped): its clock and who holds it.
func take_over(old: FerryPod) -> void:
	_clock_s = old._clock_s
	holding = old.holding.duplicate()


func pose() -> Transform3D:
	return trip.pose_at(s)


func done() -> bool:
	return state == State.DONE


## Whether bot `k` is needed to hold the pod for its next move from here.
func needs(k: int) -> bool:
	if state == State.DONE:
		return false
	var from: float = trip.grab_s[k]
	return s > from + EPS_M if dir < 0.0 else s >= from - EPS_M


## Whether the pod sits where bot `k` takes hold or lets go (its grab point), still.
func at_grab(k: int) -> bool:
	return state != State.MOVING and absf(s - trip.grab_s[k]) <= EPS_M


## Whether it is inside the bay's back wall (not drawn): its face toward the freighter is past the wall.
func inside_wall() -> bool:
	return pose().origin.z - trip.size.z * 0.5 > trip.wall_z


## Called by each of its bots every tick with that bot's own clock: the first one this tick moves the pod.
func advance_to(clock_s: float, alarm: bool) -> void:
	if clock_s <= _clock_s:
		_pending_alarm = _pending_alarm or alarm
		return
	var dt: float = clock_s - _clock_s
	_clock_s = clock_s
	var any_alarm: bool = alarm or _pending_alarm
	_pending_alarm = false
	_step(dt, any_alarm)


func _step(dt: float, alarm: bool) -> void:
	match state:
		State.WAITING, State.DROPPED:
			# Held still away from the bay when fighting starts: its bots let go there too.
			if alarm and state == State.WAITING and s <= trip.commit_s and holding.has(1):
				state = State.DROPPED
				drops += 1
			if not alarm and berthed and _crew_ready():
				_held_s += dt
				if _held_s >= GRAB_S:
					state = State.MOVING
					_held_s = 0.0
					speed_mps = MIN_SPEED_MPS
			else:
				_held_s = 0.0
		State.MOVING:
			if alarm and dir * (-1.0 if loading else 1.0) > 0.0:
				if s <= trip.commit_s:
					state = State.DROPPED
					speed_mps = 0.0
					drops += 1
					return
				if loading:
					dir = 1.0  # back inside the wall
					retreats += 1
			_move(dt, alarm)


# Every bot needed for the next move holds it and no other does.
func _crew_ready() -> bool:
	for k: int in holding.size():
		if (holding[k] != 0) != needs(k):
			return false
	return true


# Moves toward the next stop (a bot's grab point, the wall, the hull), slowing to arrive there.
func _move(dt: float, alarm: bool) -> void:
	var stop: float = _next_stop()
	var remaining: float = absf(stop - s)
	var end_mps: float = ENTER_MPS if stop >= trip.carry.length_m else 0.0
	var limit: float = sqrt(maxf(end_mps * end_mps + 2.0 * ACCEL_MPS2 * remaining, 0.0))
	var target: float = HURRY_MPS if alarm else CRUISE_MPS
	speed_mps = maxf(MIN_SPEED_MPS, move_toward(speed_mps, minf(target, limit), ACCEL_MPS2 * dt))
	var moved: float = minf(speed_mps * dt, remaining)
	s += moved * dir
	# Within the stop's own band it has arrived (the next stop is looked for past half of it).
	if remaining - moved > EPS_M:
		return
	s = stop
	speed_mps = 0.0
	if stop >= trip.carry.length_m and not loading:
		state = State.DONE
	elif stop <= 0.0 and loading:
		state = State.DONE
	elif stop >= trip.carry.length_m:
		dir = -1.0  # went back in: it waits for the quiet with its bots
		state = State.WAITING
	else:
		state = State.WAITING


# The next place it stops: a corner of its way off the hull, a bot's grab point, or the end.
func _next_stop() -> float:
	if dir > 0.0:
		var stop: float = trip.carry.length_m
		for corner: float in trip.stops:
			if corner > s + EPS_M * 0.5:
				stop = minf(stop, corner)
		if not loading:
			for k: int in holding.size():
				if holding[k] == 0 and trip.grab_s[k] > s + EPS_M * 0.5:
					stop = minf(stop, trip.grab_s[k])
		return stop
	var low: float = 0.0
	for corner: float in trip.stops:
		if corner < s - EPS_M * 0.5:
			low = maxf(low, corner)
	for k: int in holding.size():
		if holding[k] != 0 and trip.grab_s[k] > EPS_M and trip.grab_s[k] < s - EPS_M * 0.5:
			low = maxf(low, trip.grab_s[k])
	return low
