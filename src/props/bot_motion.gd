class_name BotMotion
extends BotMover
## One maintenance bot's behaviour (M7-T11, Q11): it flies its loop slowly; when fighting starts near it, it follows the loop on
## to a hatch, slips into the hull there and stays hidden until the quiet has held, then comes out and goes on. Kinematic and
## smooth: it speeds up and slows down at a fixed acceleration and never leaves the loop except down its hatch's short leg.
## Pure: the bot's node reads `position`, `heading` and `visible()` each tick.
##
## Where it goes next never depends on where it is in the world, only on the loop, so the hull clearance the loop keeps
## (tested) holds for every phase.

enum Phase { PATROL, RETREAT, ENTER, HIDDEN, EXIT }

## Flying to a hatch, m/s; through the hatch's leg, m/s; how fast the speed may change, m/s^2.
const RETREAT_SPEED_MPS: float = 9.0
const LEG_SPEED_MPS: float = 4.0
const ACCEL_MPS2: float = 2.0
## A bot never stops dead, so it always has a heading.
const MIN_SPEED_MPS: float = 0.6
## A bot stays in at least this long whatever the quiet, s; and each waits its own delay after the quiet begins, so they do not
## all come out at once.
const MIN_HIDDEN_S: float = 8.0

var loop: BotLoop = null
## Each hatch: `name`, `s` (where on the loop its leg leaves it), `inside` (where the leg ends, sunk in the hull).
var hatches: Array[Dictionary] = []
var patrol_speed_mps: float = 3.0
var emerge_delay_s: float = 0.0

var phase: Phase = Phase.PATROL
## Metres along the loop (patrol, retreat) and how far down the hatch's leg (0 at the loop, 1 inside).
var s: float = 0.0
var leg: float = 0.0
## The hatch in use.
var hatch: int = 0
## Counts of times it went in and came out, for the console and tests.
var times_hidden: int = 0
var times_emerged: int = 0

var _retreat_left_m: float = 0.0
var _hidden_s: float = 0.0
var _quiet_s: float = 0.0


func setup(p_loop: BotLoop, p_hatches: Array[Dictionary], p_speed_mps: float, p_up: Vector3, start_s: float, p_emerge_delay_s: float) -> void:
	loop = p_loop
	hatches = p_hatches
	patrol_speed_mps = p_speed_mps
	up = p_up
	emerge_delay_s = p_emerge_delay_s
	s = fposmod(start_s, loop.length_m)
	speed_mps = p_speed_mps
	phase = Phase.PATROL
	_pose()


func is_visible() -> bool:
	return phase != Phase.HIDDEN


func phase_name() -> String:
	return String(Phase.keys()[phase]).to_lower()


func step(delta: float, alarm: bool) -> void:
	match phase:
		Phase.PATROL:
			if alarm:
				_begin_retreat()
			else:
				_fly(delta, patrol_speed_mps)
		Phase.RETREAT:
			_retreat_left_m -= _fly(delta, RETREAT_SPEED_MPS, _retreat_left_m)
			if _retreat_left_m <= 0.0:
				s = hatches[hatch]["s"]
				leg = 0.0
				phase = Phase.ENTER
		Phase.ENTER:
			_speed_toward(delta, LEG_SPEED_MPS)
			leg += speed_mps * delta / _leg_length()
			if leg >= 1.0:
				leg = 1.0
				phase = Phase.HIDDEN
				_hidden_s = 0.0
				_quiet_s = 0.0
				times_hidden += 1
		Phase.HIDDEN:
			_hidden_s += delta
			_quiet_s = 0.0 if alarm else _quiet_s + delta
			if _hidden_s >= MIN_HIDDEN_S and _quiet_s >= emerge_delay_s and not alarm:
				phase = Phase.EXIT
				speed_mps = MIN_SPEED_MPS
				times_emerged += 1
		Phase.EXIT:
			if alarm:
				phase = Phase.ENTER
			else:
				_speed_toward(delta, LEG_SPEED_MPS)
				leg -= speed_mps * delta / _leg_length()
				if leg <= 0.0:
					leg = 0.0
					s = hatches[hatch]["s"]
					phase = Phase.PATROL
	_pose()


## Where the nearest hatch ahead of `from_s` is, and how far: `[index, metres]`.
func nearest_hatch(from_s: float) -> Array:
	var best: int = 0
	var best_m: float = INF
	for i: int in hatches.size():
		var m: float = loop.ahead(from_s, hatches[i]["s"])
		if m < best_m:
			best_m = m
			best = i
	return [best, best_m]


func _begin_retreat() -> void:
	var pick: Array = nearest_hatch(s)
	hatch = pick[0]
	_retreat_left_m = pick[1]
	phase = Phase.RETREAT


## Flies along the loop at about `target` m/s, no further than `limit` metres; the metres moved.
func _fly(delta: float, target: float, limit: float = INF) -> float:
	_speed_toward(delta, target)
	var moved: float = minf(speed_mps * delta, limit)
	s = fposmod(s + moved, loop.length_m)
	return moved


func _speed_toward(delta: float, target: float) -> void:
	speed_mps = maxf(MIN_SPEED_MPS, move_toward(speed_mps, target, ACCEL_MPS2 * delta))


func _leg_length() -> float:
	var length: float = loop.point_at(hatches[hatch]["s"]).distance_to(hatches[hatch]["inside"])
	return maxf(length, 0.1)


func _pose() -> void:
	if phase == Phase.PATROL or phase == Phase.RETREAT:
		position = loop.point_at(s)
		heading = loop.direction_at(s)
		return
	var start: Vector3 = loop.point_at(hatches[hatch]["s"])
	var inside: Vector3 = hatches[hatch]["inside"]
	position = start.lerp(inside, leg)
	var way: Vector3 = (inside - start).normalized()
	heading = -way if phase == Phase.EXIT else way
