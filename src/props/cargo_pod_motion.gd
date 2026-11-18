class_name CargoPodMotion
extends BotMover
## One cargo pod's flight (M7-T11, Q11; M7-T34: the craft is a cargo pod, T30 flew maintenance bots): it launches from the cargo
## bay's back wall, flies the route out to a freighter's cargo, waits there a few seconds, flies back along its own return lane and
## lands in the bay's wall, where it is hidden for a little before the next trip. Kinematic: it speeds up and slows down at a fixed
## acceleration, stops at the cargo and slows to a crawl as it enters the bay.
##
## When fighting starts near it, a pod on its way out turns round on the same route and goes back to the bay at once, one at the
## cargo leaves for the bay, one on its way back hurries; every pod ends inside, stays there until the quiet has held, and goes on.
##
## **Carrying (M7-T30).** Given a `FerryPod` (the freighter's block, `carry`), the craft is one of its crew: unloading, it flies out
## to its hold on the block, holds it there while the block moves (front or back, at a fixed place), and goes into the wall with it;
## loading, it brings the block out of the wall, lets go at its grab point (or on the hull) and flies home empty. If fighting starts
## while it holds the block away from the bay it lets go and goes home (the far end's pod over the block), and after the quiet comes
## back to the block where it lies.
##
## **The arms (M7-T34).** It reaches out with its jaws open over the last metres to its hold, shuts them once it holds, keeps them
## shut while carrying, and when it lets go it opens them standing still a moment, then folds its arms as it flies off (at once in a
## fight). Pure: the node reads `position`, `heading`, `up`, `is_visible()`, `extend` and `jaw_open`.

enum Phase { HIDDEN, OUT, WAIT, BACK, FLEE, CARRY }

const CRUISE_MPS: float = 20.0
## In a hurry (fighting near), m/s; how fast the speed may change, m/s^2; and the speed a pod enters the bay's wall at.
const HURRY_MPS: float = 30.0
const ACCEL_MPS2: float = 4.0
const ENTER_MPS: float = 4.0
const MIN_SPEED_MPS: float = 0.8
## At the cargo, and hidden in the bay between trips (s); a pod also waits its own stagger after the quiet begins.
const WAIT_AT_PODS_S: float = 6.0
const HIDDEN_S: float = 6.0
## The arms: how far from the end of its way out it reaches, how fast the reach and the jaws move (a whole stroke a second times
## the rate), and how long it stands still opening its jaws when it lets go.
const REACH_FROM_M: float = 20.0
const EXTEND_RATE: float = 0.5
const JAW_RATE: float = 0.8
const HURRY_RATE: float = 3.0
const RELEASE_S: float = 1.25
## While it holds a block, the craft counts as hidden once its centre is this far behind the bay's back wall (its nose and hands
## pass the wall last).
const HIDE_PAST_WALL_M: float = 4.0

var out_route: BotRoute = null
var back_route: BotRoute = null
var phase: Phase = Phase.HIDDEN
## Metres along the route in use (`out_route` for OUT and FLEE, `back_route` for BACK).
var s: float = 0.0
var trips: int = 0
var times_hidden: int = 0
var stagger_s: float = 0.0
## Carrying: the freighter's block (`FerryPod`), which of its crew this is, and the times it let go in a fight.
var pod: FerryPod = null
var crew_index: int = 0
var drops: int = 0
## A crew pod with no block this trip stays inside the wall.
var idle: bool = false
## The arms' pose (`CargoPodRig.set_pose`): the reach 0..1 and the jaws, 1 open to 0 shut.
var extend: float = 0.0
var jaw_open: float = 1.0

var _timer_s: float = 0.0
var _quiet_s: float = 0.0
# The route the current phase flies, a hurry home, and the craft's own clock (it steps its block).
var _route: BotRoute = null
var _hurry: bool = false
var _clock_s: float = 0.0
# After letting go of a pod in a fight: the way back to it, and where along its trip the pod lay.
var _return_route: BotRoute = null
var _return_s: float = -1.0
# The block's drops when this craft took hold (a later one is a new fight).
var _held_drops: int = 0
# Time left standing still with the jaws opening after letting go.
var _release_s: float = 0.0


func setup(p_out: BotRoute, p_back: BotRoute, p_up: Vector3, p_stagger_s: float) -> void:
	out_route = p_out
	back_route = p_back
	up = p_up
	stagger_s = p_stagger_s
	_route = out_route
	_enter_hidden()
	times_hidden = 0
	_pose()


## Makes the craft crew `k` of the block `p_pod`, out `p_stagger_s` after the quiet; it must be hidden. Null takes it off any block.
func carry(p_pod: FerryPod, k: int, p_stagger_s: float = 0.0) -> void:
	pod = p_pod
	crew_index = k
	stagger_s = p_stagger_s
	up = Vector3.UP
	idle = pod == null
	_return_route = null
	_return_s = -1.0
	if pod != null:
		out_route = pod.trip.out_routes[k]
		_route = out_route
	_enter_hidden()
	_timer_s = HIDDEN_S
	if out_route != null:
		_pose()


## The same block planned again: the craft keeps its phase and its place along the route out.
func retarget(p_pod: FerryPod) -> void:
	pod = p_pod
	out_route = pod.trip.out_routes[crew_index]
	if phase == Phase.OUT or phase == Phase.WAIT or phase == Phase.HIDDEN:
		_route = out_route
		s = minf(s, out_route.length_m)
	_pose()


func is_visible() -> bool:
	if phase == Phase.CARRY:
		return position.z - HIDE_PAST_WALL_M < pod.trip.wall_z
	return phase != Phase.HIDDEN


func phase_name() -> String:
	return String(Phase.keys()[phase]).to_lower()


func step(delta: float, alarm: bool) -> void:
	if idle:
		return
	if pod != null:
		_clock_s += delta
		pod.advance_to(_clock_s, alarm)
		_step_carrying(delta, alarm)
		_pose()
		_move_arms(delta)
		return
	match phase:
		Phase.HIDDEN:
			_timer_s += delta
			_quiet_s = 0.0 if alarm else _quiet_s + delta
			if _timer_s >= HIDDEN_S and _quiet_s >= stagger_s and not alarm:
				phase = Phase.OUT
				_route = out_route
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
				_route = back_route
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
	_move_arms(delta)


## Where on its out route the craft is, 0 to 1 (for the stagger and the console).
func progress() -> float:
	var route: BotRoute = _route if _route != null else out_route
	return s / route.length_m if route != null and route.valid() else 0.0


# One tick of a crew pod (after its block has stepped).
func _step_carrying(delta: float, alarm: bool) -> void:
	var k: int = crew_index
	match phase:
		Phase.HIDDEN:
			_timer_s += delta
			_quiet_s = 0.0 if alarm else _quiet_s + delta
			var go: bool = _timer_s >= HIDDEN_S and _quiet_s >= stagger_s and not alarm
			if not go or pod.done():
				return
			if pod.loading and pod.s >= pod.trip.carry.length_m - FerryPod.EPS_M and pod.needs(k):
				_hold()  # it takes the pod behind the wall
			elif pod.needs(k) or (not pod.loading and pod.trip.grab_s[k] > pod.s):
				_route = _return_route if _return_route != null and absf(_return_s - pod.s) <= FerryPod.EPS_M else out_route
				phase = Phase.OUT
				s = 0.0
				speed_mps = MIN_SPEED_MPS
		Phase.OUT:
			if alarm:
				phase = Phase.FLEE
			else:
				_advance(_route, delta, CRUISE_MPS, 0.0, 1.0)
				if s >= _route.length_m:
					phase = Phase.WAIT
					speed_mps = 0.0
		Phase.WAIT:
			if alarm:
				phase = Phase.FLEE
			elif pod.needs(k) and pod.state != FerryPod.State.MOVING and (pod.at_grab(k) or _route == _return_route):
				_hold()
		Phase.CARRY:
			if pod.state == FerryPod.State.DROPPED and pod.drops > _held_drops:
				_let_go_in_a_fight()
			elif pod.done() and not pod.loading:
				pod.holding[k] = 0
				trips += 1
				_enter_hidden()
			elif not pod.needs(k) and pod.state != FerryPod.State.MOVING:
				pod.holding[k] = 0
				_route = pod.trip.out_routes[k].reversed()
				phase = Phase.BACK
				s = 0.0
				speed_mps = 0.0
				_hurry = false
				_release_s = RELEASE_S
		Phase.BACK:
			if _release_s > 0.0 and not alarm:
				_release_s -= delta
				return
			_release_s = 0.0
			_advance(_route, delta, HURRY_MPS if alarm or _hurry else CRUISE_MPS, ENTER_MPS, 1.0)
			if s >= _route.length_m:
				trips += 1 if not _hurry else 0
				_enter_hidden()
		Phase.FLEE:
			_advance(_route, delta, HURRY_MPS, ENTER_MPS, -1.0)
			if s <= 0.0:
				_enter_hidden()


func _hold() -> void:
	if phase == Phase.HIDDEN:
		extend = 1.0  # loading: it takes the block behind the wall, already gripping
		jaw_open = 0.0
	pod.holding[crew_index] = 1
	_held_drops = pod.drops
	phase = Phase.CARRY
	speed_mps = 0.0
	_return_route = null
	_return_s = -1.0


# Lets go of the pod where it is and hurries home; the way back to it is kept for after the quiet.
func _let_go_in_a_fight() -> void:
	pod.holding[crew_index] = 0
	drops += 1
	var home: BotRoute = BotRoute.from_points(pod.trip.escape_points(crew_index, pod.s))
	_return_route = home.reversed()
	_return_s = pod.s
	_route = home
	phase = Phase.BACK
	_hurry = true
	s = 0.0
	speed_mps = MIN_SPEED_MPS


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
	_release_s = 0.0
	extend = 0.0
	jaw_open = 1.0
	_timer_s = 0.0
	_quiet_s = 0.0
	speed_mps = 0.0
	s = 0.0
	_hurry = false
	times_hidden += 1


func _pose() -> void:
	match phase:
		Phase.HIDDEN:
			position = out_route.point_at(0.0)
			heading = out_route.direction_at(0.0)
		Phase.OUT, Phase.WAIT:
			position = _route.point_at(s)
			heading = _route.direction_at(s)
		Phase.BACK:
			position = _route.point_at(s)
			# Backing off the block it held, nose still toward it, then turning for home.
			heading = -_route.direction_at(s) if pod != null and not _hurry and s < CargoFerryPlan.APPROACH_IN_M else _route.direction_at(s)
		Phase.FLEE:
			position = _route.point_at(s)
			heading = -_route.direction_at(s)
		Phase.CARRY:
			position = pod.trip.bot_position(crew_index, pod.s)
			heading = pod.trip.bot_heading(crew_index)
			up = pod.trip.bot_up(pod.s)
			speed_mps = pod.speed_mps
	if phase != Phase.CARRY:
		up = Vector3.UP


# The arms follow the phase: out and open near the end of the way out and at the hold, shut while holding, opened then folded
# after letting go, stowed otherwise.
func _move_arms(delta: float) -> void:
	var reach: float = 0.0
	var open: float = 1.0
	var rate: float = 1.0
	match phase:
		Phase.OUT:
			reach = 1.0 if _route != null and _route.length_m - s <= REACH_FROM_M else 0.0
		Phase.WAIT:
			reach = 1.0
		Phase.CARRY:
			reach = 1.0
			open = 0.0
		Phase.BACK:
			reach = 1.0 if _release_s > 0.0 else 0.0
			rate = HURRY_RATE if _hurry else 1.0
		Phase.FLEE:
			rate = HURRY_RATE
	jaw_open = move_toward(jaw_open, open, JAW_RATE * rate * delta)
	# The arms fold only once the jaws are open.
	if reach < extend and jaw_open < 1.0 - 1e-6:
		return
	extend = move_toward(extend, reach, EXTEND_RATE * rate * delta)
