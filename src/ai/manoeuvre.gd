class_name Manoeuvre
extends RefCounted
## One demo move (architecture §16 D37, M3-T09): a state machine that flies the ship through the real flight model and
## decides from the ship's measured state, not from timers alone, when its goal is met. The instructor's follow-path
## behaviour runs one at a waypoint; the M7 tutorial can hold the player's flying against the same goals. The five moves
## are in `Manoeuvres`.
##
## Contract:
## - `step(p, dt)` every tick until `done`: returns this tick's `FlightCommand` (a fresh one). The first call records the
##   starting state (`_begin`). Places are kept as `UniversePos` and directions in the World frame, so a rebase
##   mid-move changes nothing.
## - `done`: the goal is met (or the move gave up after `TIMEOUT_S`, `timed_out`); after that `step` coasts.
## - `result()`: the measured outcome (`timed_out` plus each move's own numbers), for the tests and the console.
## - `needs_speed()`: the move takes speed away (flip and burn, all stop), so it is only worth showing from cruise.
## - `describe()`: `demo` and `step` (the state), for the console.
## - A move that steers toward a velocity records it in `desired_velocity` / `has_desired_velocity` (the `PilotBrain`
##   protocol, M3-T05), so the driver's avoidance filter sees the wish.
## Pure: no scene tree, no clock but the perception's, no randomness.

## Seconds after which a move that has not met its goal gives up, so a route never stalls on one.
const TIMEOUT_S: float = 45.0

var id: StringName = &""
var done: bool = false
var timed_out: bool = false
## Seconds since the first `step`.
var elapsed_s: float = 0.0
var desired_velocity: Vector3 = Vector3.ZERO
var has_desired_velocity: bool = false

var _started: bool = false


## One tick of the move. Coasts once it is done.
func step(p: Perception, dt: float) -> FlightCommand:
	has_desired_velocity = false
	if done:
		return FlightCommand.new()
	if not _started:
		_started = true
		_begin(p)
		if done:
			return FlightCommand.new()
	else:
		elapsed_s += dt
	if elapsed_s >= TIMEOUT_S:
		done = true
		timed_out = true
		return FlightCommand.new()
	return _step(p, dt)


## The measured outcome so far (complete once `done`).
func result() -> Dictionary:
	var out: Dictionary = _result()
	out["timed_out"] = timed_out
	return out


func needs_speed() -> bool:
	return false


func state_name() -> String:
	return "done" if done else "start"


func describe() -> Dictionary:
	var out: Dictionary = {"demo": String(id), "step": "timed out" if timed_out else state_name()}
	out.merge(_result())
	return out


# --- for the moves -----------------------------------------------------------------------------------------------


## Records the starting state from the first perception (may set `done` at once: nothing to do).
func _begin(_p: Perception) -> void:
	pass


func _step(_p: Perception, _dt: float) -> FlightCommand:
	return FlightCommand.new()


func _result() -> Dictionary:
	return {}


## Writes the thrust toward `v_des` (with the seek horizon given) into `flight` and records it as this tick's wish.
func _seek(flight: FlightCommand, p: Perception, v_des: Vector3, horizon_s: float) -> void:
	desired_velocity = v_des
	has_desired_velocity = true
	PilotSteering.apply_seek(flight, PilotSteering.seek(p.velocity, v_des, p.basis, p.capability, horizon_s))


## The roll rate in pilot terms (rad/s, + = rolling right), measured from the perception.
static func roll_rate(p: Perception) -> float:
	return (p.basis.transposed() * p.angular_velocity).z * FlightModel.AXIS_SIGN.z
