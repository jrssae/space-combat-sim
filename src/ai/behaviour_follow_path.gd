class_name BehaviourFollowPath
extends AiBehaviour
## Lead a route, paced to the player, and show a demo move at a waypoint (architecture §16 D37, M3-T09, maintainer Q5):
## the instructor's behaviour. The route is the context's (`AiContext.route`, set by `attach`); the progress is kept here.
##
## States (`state_name`, the console's `route.state`):
## - `lead`: toward the waypoint at the route's paced speed (`Route.pace_speed` of the lag), nose along. A waypoint within
##   `Route.ARRIVAL_M` is reached: its demo comes next, else its hold, else the next waypoint. With the pace ship beyond
##   `Route.WAIT_BEYOND_M` it waits.
## - `wait`: the brake, with the pace ship selected so the brake turns the nose onto it (`target_id`), until it is within
##   `Route.RESUME_WITHIN_M`. A demo also waits for that: the player should be close enough to see it.
## - `run_up`: a move that takes speed away (`Manoeuvre.needs_speed`) is shown from cruise: below `RUN_UP_FRACTION` of it the
##   ship first speeds up toward the next waypoint.
## - `demo`: the `Manoeuvre` flies the ship until its goal is met; the result goes into `results`.
## - `hold`: the brake for the waypoint's `hold_s`.
## - `done`: the end of a route that does not loop; the score drops to 0 and the pilot idles (the instructor holds).
## Pacing never interrupts a move that has started. Losing control to another behaviour restarts a running move on return.

const SCORE: float = 0.5
## A speed-taking demo starts from at least this share of the route's cruise.
const RUN_UP_FRACTION: float = 0.9

enum Phase { LEAD, WAIT, RUN_UP, DEMO, HOLD, DONE }
const PHASE_NAMES: Array[String] = ["lead", "wait", "run_up", "demo", "hold", "done"]

## The waypoint flown to (or shown at).
var index: int = 0
var phase: Phase = Phase.LEAD
## m: the distance to the pace ship last tick (INF out of sight, 0 without pacing).
var lag_m: float = 0.0
## The demo due or in progress (or the last one), null before the first waypoint with a demo.
var manoeuvre: Manoeuvre = null
## Waypoint indices in the order they were reached, and each finished demo's result plus `demo` and `index` (the tests).
var visited: PackedInt32Array = PackedInt32Array()
var results: Array[Dictionary] = []

var _route: Route = null
## The current waypoint's demo is due (it was reached; the move has not finished yet).
var _demo_due: bool = false
var _hold_left_s: float = 0.0


func _init() -> void:
	id = &"follow_path"


## Gives `pilot` the route to lead: sets `context.route` and adds this behaviour (once). Returns the behaviour.
static func attach(pilot: AiPilot, route: Route) -> BehaviourFollowPath:
	pilot.context.route = route
	var b := pilot.behaviour(&"follow_path") as BehaviourFollowPath
	if b == null:
		b = BehaviourFollowPath.new()
		pilot.add_behaviour(b)
	b._route = route  # readable (HUD, console) before its first tick
	return b


func score(ctx: AiContext) -> float:
	_route = ctx.route
	if _route == null or _route.count() == 0 or phase == Phase.DONE:
		return 0.0
	return SCORE


func enter() -> void:
	if phase == Phase.DEMO and manoeuvre != null:
		manoeuvre = Manoeuvres.create(manoeuvre.id)  # its measured start is stale: show it again from here


func think(ctx: AiContext, dt: float) -> PilotCommand:
	_route = ctx.route
	var cmd := PilotCommand.new()
	if _route == null or _route.count() == 0:
		return cmd
	var p: Perception = ctx.perception
	lag_m = _route.lag_to(p)
	_settle(p)
	match phase:
		Phase.LEAD:
			var to: Vector3 = p.to_local(_route.waypoint(index).position) - p.position
			_fly(cmd.flight, p, to, _route.pace_speed(lag_m))
		Phase.RUN_UP:
			_fly(cmd.flight, p, _run_up_direction(p), _route.cruise_mps)
		Phase.DEMO:
			cmd.flight = manoeuvre.step(p, dt)
			desired_velocity = manoeuvre.desired_velocity
			has_desired_velocity = manoeuvre.has_desired_velocity
			if manoeuvre.done:
				_finish_demo()
		Phase.HOLD:
			cmd.flight.brake = true
			_hold_left_s -= dt
		Phase.WAIT, Phase.DONE:
			cmd.flight.brake = true
	return cmd


## The pace ship while waiting (the brake faces the selected target), else none.
func target_id() -> int:
	if phase == Phase.WAIT and _route != null and _route.pace_id != 0:
		return _route.pace_id
	return PilotBrain.TARGET_NONE


func state_name() -> String:
	return PHASE_NAMES[phase]


## 1-based number of the waypoint flown to (the HUD's `NAV n`).
func nav_number() -> int:
	return index + 1


## Waypoints on the route (0 before the first tick with one).
func waypoint_count() -> int:
	return _route.count() if _route != null else 0


## The current waypoint's demo (`""` for none or after the end).
func demo_name() -> String:
	if _route == null or phase == Phase.DONE or index >= _route.count():
		return ""
	return String(_route.waypoint(index).demo)


## The HUD's label for the waypoint flown to, `NAV 2`.
func waypoint_label() -> String:
	return _route.label(index) if _route != null else ""


## The waypoint flown to as a universe position, or null after the end.
func waypoint_position() -> UniversePos:
	if _route == null or phase == Phase.DONE or index >= _route.count():
		return null
	return _route.waypoint(index).position


## The HUD's status line: `FOLLOW INSTRUCTOR — NAV 2/6 — NEXT: ROLL` (`leader_name` is the leader's callsign).
func status_line(leader_name: String) -> String:
	if _route == null:
		return ""
	if phase == Phase.DONE:
		return "FOLLOW %s — ROUTE COMPLETE" % leader_name
	var nav: String = "NAV %d/%d" % [nav_number(), _route.count()]
	var demo: String = demo_name()
	var demo_word: String = Manoeuvres.display_name(StringName(demo))
	var next: String = " — NEXT: " + demo_word if not demo.is_empty() else ""
	match phase:
		Phase.RUN_UP, Phase.DEMO:
			return "WATCH %s — %s — %s" % [leader_name, nav, demo_word]
		Phase.WAIT:
			return "CLOSE UP ON %s — %s%s" % [leader_name, nav, next]
		Phase.HOLD:
			return "FOLLOW %s — %s" % [leader_name, nav]  # its demo is over
	return "FOLLOW %s — %s%s" % [leader_name, nav, next]


## `state`, `nav` (`NAV 2/6`), `lag_m`, `demo` (the current waypoint's, or `none`) and, during a demo, its `step`.
func describe() -> Dictionary:
	var demo: String = demo_name()
	var out: Dictionary = {"state": state_name(),
			"nav": "NAV %d/%d" % [nav_number(), _route.count()] if _route != null else "none",
			"lag_m": snappedf(lag_m, 1.0) if lag_m < INF else -1.0,
			"demo": demo if not demo.is_empty() else "none"}
	if phase == Phase.DEMO and manoeuvre != null:
		out["step"] = manoeuvre.state_name()
	return out


func reset() -> void:
	index = 0
	phase = Phase.LEAD
	lag_m = 0.0
	manoeuvre = null
	visited.clear()
	results.clear()
	_demo_due = false
	_hold_left_s = 0.0


# --- internals -----------------------------------------------------------------------------------------------------


# Moves through the phases until one has something to fly this tick (each transition at most once per tick).
func _settle(p: Perception) -> void:
	for i: int in PHASE_NAMES.size():
		var before: Phase = phase
		match phase:
			Phase.LEAD:
				if Route.should_wait(lag_m, false):
					phase = Phase.WAIT
				elif (p.to_local(_route.waypoint(index).position) - p.position).length() < Route.ARRIVAL_M:
					_arrive()
			Phase.WAIT:
				if not Route.should_wait(lag_m, true):
					phase = Phase.RUN_UP if _demo_due else Phase.LEAD
			Phase.RUN_UP:
				if Route.should_wait(lag_m, true):
					phase = Phase.WAIT  # the player is not close enough to see it: wait first
				elif not manoeuvre.needs_speed() or p.velocity.length() >= RUN_UP_FRACTION * _route.cruise_mps:
					phase = Phase.DEMO
			Phase.HOLD:
				if _hold_left_s <= 0.0:
					_advance()
		if phase == before:
			return


func _arrive() -> void:
	visited.append(index)
	var w: Route.Waypoint = _route.waypoint(index)
	if w.demo != &"":
		_demo_due = true
		manoeuvre = Manoeuvres.create(w.demo)  # not started until the phase is DEMO
		phase = Phase.RUN_UP
	elif w.hold_s > 0.0:
		_hold_left_s = w.hold_s
		phase = Phase.HOLD
	else:
		_advance()


func _finish_demo() -> void:
	var out: Dictionary = manoeuvre.result()
	out["demo"] = String(manoeuvre.id)
	out["index"] = index
	results.append(out)
	_demo_due = false
	var hold: float = _route.waypoint(index).hold_s
	if hold > 0.0:
		_hold_left_s = hold
		phase = Phase.HOLD
	else:
		_advance()


func _advance() -> void:
	_demo_due = false
	var next: int = _route.next_index(index)
	if next < 0:
		phase = Phase.DONE
		return
	index = next
	phase = Phase.LEAD


# The run-up heads for the waypoint after this one (or straight on when there is none, or it is right here).
func _run_up_direction(p: Perception) -> Vector3:
	var next: int = _route.next_index(index)
	if next >= 0:
		var to: Vector3 = p.to_local(_route.waypoint(next).position) - p.position
		if to.length() > Route.ARRIVAL_M:
			return to
	return p.velocity if p.velocity.length() > 1.0 else p.forward()


# Nose along `to`, velocity toward `to` at `speed`.
func _fly(flight: FlightCommand, p: Perception, to: Vector3, speed: float) -> void:
	var d: float = to.length()
	var dir: Vector3 = to / d if d > 1e-6 else p.forward()
	flight.rot = PilotSteering.face(p.basis, dir, p.capability.rate_max_rad)
	seek_velocity(flight, p, dir * speed)
