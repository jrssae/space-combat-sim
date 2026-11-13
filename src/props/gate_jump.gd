class_name GateJump
extends RefCounted
## The player's jump through a gate (M6-T14, the maintainer's "The player's jump"), as a state machine. Pure: the host feeds it
## each tick's facts (where the ship is in the gate's frame, whether it is alive, whether the gate saw it go through or placed
## it back) and carries out the events it returns; the screen's flash and fade are functions of its state and clock.
##
## The flow: `LINE_UP` (controls locked, the autopilot flies to the departure point), `RUN_IN` (it accelerates along the gate's
## axis, the orange vortex opens, the cinematic follows it in and down the funnel as it shrinks, M6-T22), `FLASH` (through the
## black ring: the shot holds on the ring's white flash, then fades to black, the shot's last frame), `AWAY` (black, "in
## hyperspace"; M11 puts hyperspace here), `ARRIVING` (the fade lifts on the blue vortex opening; the gate brings the ship out of
## its ring), `CLEARING` (the ship flies out of the funnel, growing, and on clear of the mouth), then `IDLE` with the controls
## back. Losing the ship, or a stage that takes too long, ends it early (`ended_why`). The screen shows no flash of its own: the
## flash is the ring's, in the world.

enum State { IDLE, LINE_UP, RUN_IN, FLASH, AWAY, ARRIVING, CLEARING }
const STATE_NAMES: Array[String] = ["idle", "line_up", "run_in", "flash", "away", "arriving", "clearing"]

## Events for the host, at most a few per tick, in order.
const EV_START: StringName = &"start"  # lock the controls, assist on
const EV_RUN_IN: StringName = &"run_in"  # tell the gate a departure is coming, start the departure shot
const EV_THROUGH: StringName = &"through"  # hide the ship, close the departure
const EV_ASK_ARRIVAL: StringName = &"ask_arrival"  # ask the gate for an arrival that places the ship
const EV_ARRIVED: StringName = &"arrived"  # the ship is back in sight: the arrival shot follows it out
const EV_DONE: StringName = &"done"  # controls back, shot stopped
const EV_ABORT: StringName = &"abort"  # the same, early (`ended_why` says why)

## Within this of the departure point the line-up is done and the run-in starts.
const LINE_UP_DONE_M: float = 200.0
## From 10 km at the autopilot's 300 m/s the line-up takes well under a minute; past this something is in the way.
const LINE_UP_TIMEOUT_S: float = 120.0
## The run-in is 1 440 m to the mouth and 1 200 m on down the funnel; at the slowest it waits for the vortex and then flies it in
## about 20 s.
const RUN_IN_TIMEOUT_S: float = 45.0
## Through the ring the shot holds on its flash this long, then the picture fades to black.
const RING_HOLD_S: float = 0.8
const FADE_OUT_S: float = 0.9
## Black while "in hyperspace": long enough to read as a passage, short enough not to bore (M11 replaces it).
const AWAY_S: float = 2.0
## The fade lifts while the blue vortex's tips glow, so the opening is seen from its start.
const FADE_IN_S: float = 1.2
## The vortex takes 3.5 s to open; past this the arrival is stuck.
const ARRIVING_TIMEOUT_S: float = 20.0
## Out of the arrival: clear once this far in front of the mouth, or this long after leaving it (M6-T22: the ship first flies out
## of the funnel from its ring, about 6 s at a gate).
const CLEAR_M: float = 500.0
const CLEAR_S: float = 3.0
## Coming out of the funnel takes no longer than this; past it the controls come back wherever the ship is.
const CLEARING_TIMEOUT_S: float = 30.0

var state: State = State.IDLE
## Seconds in the current state.
var state_s: float = 0.0
## Why the last jump ended early ("" when it finished or none ran).
var ended_why: String = ""
## Jumps finished and ended early (console, tests).
var completed: int = 0
var aborted: int = 0
## The flash's peak and the black, 0..1, for this tick (`screen`).
var flash_level: float = 0.0
var black_level: float = 0.0

## Gate-local z of the mouth (CLEARING measures from it).
var arrival_z: float = 0.0

var _out_s: float = 0.0  # seconds since the ship left the mouth, while clearing


func state_name() -> String:
	return STATE_NAMES[state]


func is_active() -> bool:
	return state != State.IDLE


## Starts a jump. False when one is under way.
func start() -> PackedStringArray:
	var out := PackedStringArray()
	if state != State.IDLE:
		return out
	ended_why = ""
	_enter(State.LINE_UP)
	out.append(EV_START)
	return out


## One tick: `dt` seconds, the ship's gate-local position `local`, its departure point `departure` (gate-local), whether it is
## `alive`, and the gate's two reports this tick: `went_through` (the departure handed it back) and `placed` (the arrival put
## it back). Returns the events to carry out.
func step(dt: float, local: Vector3, departure: Vector3, alive: bool, went_through: bool, placed: bool) -> PackedStringArray:
	var out := PackedStringArray()
	if state == State.IDLE:
		return out
	state_s += dt
	if not alive:
		return _abort("the ship was lost")
	match state:
		State.LINE_UP:
			if went_through:
				return _abort("went through before lining up")
			if local.distance_to(departure) <= LINE_UP_DONE_M:
				_enter(State.RUN_IN)
				out.append(EV_RUN_IN)
			elif state_s > LINE_UP_TIMEOUT_S:
				return _abort("could not line up in %.0f s" % LINE_UP_TIMEOUT_S)
		State.RUN_IN:
			if went_through:
				_enter(State.FLASH)
				out.append(EV_THROUGH)
			elif state_s > RUN_IN_TIMEOUT_S:
				return _abort("did not reach the vortex in %.0f s" % RUN_IN_TIMEOUT_S)
		State.FLASH:
			if state_s >= RING_HOLD_S + FADE_OUT_S:
				_enter(State.AWAY)
		State.AWAY:
			if state_s >= AWAY_S:
				_enter(State.ARRIVING)
				out.append(EV_ASK_ARRIVAL)
		State.ARRIVING:
			if placed:
				_enter(State.CLEARING)
				out.append(EV_ARRIVED)
			elif state_s > ARRIVING_TIMEOUT_S:
				return _abort("the arrival did not open in %.0f s" % ARRIVING_TIMEOUT_S)
		State.CLEARING:
			_out_s = _out_s + dt if local.z < arrival_z else 0.0
			if local.z <= arrival_z - CLEAR_M or _out_s >= CLEAR_S or state_s >= CLEARING_TIMEOUT_S:
				_enter(State.IDLE)
				completed += 1
				out.append(EV_DONE)
	_update_screen()
	return out


## Ends a jump under way now (the console, a scene change). Returns the abort event, or nothing when none runs.
func cancel(why: String = "cancelled") -> PackedStringArray:
	if state == State.IDLE:
		return PackedStringArray()
	return _abort(why)


## The ship should be out of sight (between going through and coming back).
func ship_hidden() -> bool:
	return state == State.FLASH or state == State.AWAY or state == State.ARRIVING


## The autopilot flies the ship (line-up and run-in); otherwise it coasts.
func autopilot_on() -> bool:
	return state == State.LINE_UP or state == State.RUN_IN


## The flash and the black for a state and its clock, each 0..1. Static so the curve can be tested on its own.
static func screen_at(p_state: State, t: float) -> Vector2:
	match p_state:
		State.FLASH:
			return Vector2(0.0, clampf((t - RING_HOLD_S) / FADE_OUT_S, 0.0, 1.0))
		State.AWAY:
			return Vector2(0.0, 1.0)
		State.ARRIVING:
			return Vector2(0.0, 1.0 - clampf(t / FADE_IN_S, 0.0, 1.0))
	return Vector2.ZERO


func _update_screen() -> void:
	var levels: Vector2 = screen_at(state, state_s)
	flash_level = levels.x
	black_level = levels.y


func _enter(p_state: State) -> void:
	state = p_state
	state_s = 0.0
	_out_s = 0.0
	_update_screen()


func _abort(why: String) -> PackedStringArray:
	ended_why = why
	aborted += 1
	_enter(State.IDLE)
	return PackedStringArray([EV_ABORT])
