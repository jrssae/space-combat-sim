class_name BotFerryMotion
extends BotMover
## One ferry bot's trip (M7-T11, Q11): it comes out of the cargo bay's back wall, flies the route out to a freighter's cargo pods,
## waits there a few seconds, flies back along its own return lane and slips into the bay's wall, where it is hidden for a
## little before the next trip. Kinematic: it speeds up and slows down at a fixed acceleration, stops at the pods and slows to a
## crawl as it enters the bay.
##
## When fighting starts near it, a bot on its way out turns round on the same route and goes back to the bay at once, one at the
## pods leaves for the bay, one on its way back hurries; every bot ends inside, stays there until the quiet has held, and goes on.
## Pure: the node reads `position`, `heading` and `is_visible()`.

enum Phase { HIDDEN, OUT, WAIT, BACK, FLEE }

const CRUISE_MPS: float = 20.0
## In a hurry (fighting near), m/s; how fast the speed may change, m/s^2; and the speed a bot enters the bay's wall at.
const HURRY_MPS: float = 30.0
const ACCEL_MPS2: float = 4.0
const ENTER_MPS: float = 4.0
const MIN_SPEED_MPS: float = 0.8
## At the pods, and hidden in the bay between trips (s); a bot also waits its own stagger after the quiet begins.
const WAIT_AT_PODS_S: float = 6.0
const HIDDEN_S: float = 6.0

var out_route: BotRoute = null
var back_route: BotRoute = null
var phase: Phase = Phase.HIDDEN
## Metres along the route in use (`out_route` for OUT and FLEE, `back_route` for BACK).
var s: float = 0.0
var trips: int = 0
var times_hidden: int = 0
var stagger_s: float = 0.0

var _timer_s: float = 0.0
var _quiet_s: float = 0.0


func setup(p_out: BotRoute, p_back: BotRoute, p_up: Vector3, p_stagger_s: float) -> void:
	out_route = p_out
	back_route = p_back
	up = p_up
	stagger_s = p_stagger_s
	_enter_hidden()
	times_hidden = 0
	_pose()


func is_visible() -> bool:
	return phase != Phase.HIDDEN


func phase_name() -> String:
	return String(Phase.keys()[phase]).to_lower()


func step(delta: float, alarm: bool) -> void:
	match phase:
		Phase.HIDDEN:
			_timer_s += delta
			_quiet_s = 0.0 if alarm else _quiet_s + delta
			if _timer_s >= HIDDEN_S and _quiet_s >= stagger_s and not alarm:
				phase = Phase.OUT
				s = 0.0
				speed_mps = MIN_SPEED_MPS
		Phase.OUT:
			if alarm:
				phase = Phase.FLEE
			else:
				_advance(out_route, delta, CRUISE_MPS, 0.0, 1.0)
				if s >= out_route.length_m:
					phase = Phase.WAIT
					_timer_s = 0.0
					speed_mps = 0.0
		Phase.WAIT:
			_timer_s += delta
			if alarm or _timer_s >= WAIT_AT_PODS_S:
				phase = Phase.BACK
				s = 0.0
				speed_mps = MIN_SPEED_MPS
		Phase.BACK:
			_advance(back_route, delta, HURRY_MPS if alarm else CRUISE_MPS, ENTER_MPS, 1.0)
			if s >= back_route.length_m:
				trips += 1
				_enter_hidden()
		Phase.FLEE:
			_advance(out_route, delta, HURRY_MPS, ENTER_MPS, -1.0)
			if s <= 0.0:
				_enter_hidden()
	_pose()


## Where on its out route the bot is, 0 to 1 (for the stagger and the console).
func progress() -> float:
	var route: BotRoute = back_route if phase == Phase.BACK else out_route
	return s / route.length_m if route != null and route.valid() else 0.0


# Moves along the route `way` (+1 or -1) at about `target` m/s, slowing so it arrives at `end_mps` where the route ends.
func _advance(route: BotRoute, delta: float, target: float, end_mps: float, way: float) -> void:
	var remaining: float = route.length_m - s if way > 0.0 else s
	var limit: float = sqrt(maxf(end_mps * end_mps + 2.0 * ACCEL_MPS2 * remaining, 0.0))
	speed_mps = maxf(MIN_SPEED_MPS, move_toward(speed_mps, minf(target, limit), ACCEL_MPS2 * delta))
	var moved: float = minf(speed_mps * delta, remaining)
	s += moved * way
	if remaining - moved <= 0.0:
		s = route.length_m if way > 0.0 else 0.0


func _enter_hidden() -> void:
	phase = Phase.HIDDEN
	_timer_s = 0.0
	_quiet_s = 0.0
	speed_mps = 0.0
	s = 0.0
	times_hidden += 1


func _pose() -> void:
	match phase:
		Phase.HIDDEN:
			position = out_route.point_at(0.0)
			heading = out_route.direction_at(0.0)
		Phase.OUT, Phase.WAIT:
			position = out_route.point_at(s)
			heading = out_route.direction_at(s)
		Phase.FLEE:
			position = out_route.point_at(s)
			heading = -out_route.direction_at(s)
		Phase.BACK:
			position = back_route.point_at(s)
			heading = back_route.direction_at(s)
