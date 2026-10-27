class_name Route
extends RefCounted
## A waypoint route a ship leads another along (architecture §16 D37, M3-T09, maintainer Q5): the instructor's lesson.
## Pure data and the pacing rule; `BehaviourFollowPath` flies it and keeps the progress.
##
## - Waypoints are `UniversePos` (rebase-proof), each with an optional `demo` (a `Manoeuvres.NAMES` move shown on arrival)
##   and `hold_s` (seconds held there with the brake, after the demo if there is one).
## - `cruise_mps` (60) is the leading speed; `loop` starts over after the last waypoint, else the route ends there.
## - `pace` is who sets the pace (`player` or `none`, the scenario's word); `pace_id` is that ship's `Contact.id` (its
##   `Targetable`'s instance id), set by whoever spawns the leader, 0 for no pacing.
## - Pacing: the lag is the distance to the pace ship. Full cruise under `FULL_PACE_M`, linear to zero at `STOP_PACE_M`;
##   beyond `WAIT_BEYOND_M` the leader brakes, faces the pace ship and waits until it is within `RESUME_WITHIN_M`.
##   A waypoint counts as reached within `ARRIVAL_M`.
## Scenario files describe routes as `routes[]` (`ScenarioLoader`).

const DEFAULT_CRUISE_MPS: float = 60.0
const FULL_PACE_M: float = 600.0
const STOP_PACE_M: float = 1500.0
const WAIT_BEYOND_M: float = 1600.0
const RESUME_WITHIN_M: float = 800.0
const ARRIVAL_M: float = 150.0
## The scenario words for `pace`.
const PACE_PLAYER: StringName = &"player"
const PACE_NONE: StringName = &"none"
const PACE_WORDS: Array[StringName] = [PACE_PLAYER, PACE_NONE]


## One point of the route.
class Waypoint extends RefCounted:
	var position: UniversePos = UniversePos.new()
	## A `Manoeuvres.NAMES` move shown on arrival, or `&""`.
	var demo: StringName = &""
	## Seconds held at the waypoint with the brake (after its demo).
	var hold_s: float = 0.0


var name: String = ""
var waypoints: Array[Waypoint] = []
var cruise_mps: float = DEFAULT_CRUISE_MPS
var pace: StringName = PACE_PLAYER
## The pace ship's `Contact.id`, 0 for none (no pacing).
var pace_id: int = 0
var loop: bool = false


## Appends a waypoint.
func add(position: UniversePos, demo: StringName = &"", hold_s: float = 0.0) -> void:
	var w := Waypoint.new()
	w.position = position
	w.demo = demo
	w.hold_s = hold_s
	waypoints.append(w)


func count() -> int:
	return waypoints.size()


func waypoint(index: int) -> Waypoint:
	return waypoints[index]


## The waypoint after `index`: the first again on a loop, -1 after the last of a route that does not loop.
func next_index(index: int) -> int:
	if index + 1 < waypoints.size():
		return index + 1
	return 0 if loop and not waypoints.is_empty() else -1


## What the HUD calls a waypoint: `NAV 2` for index 1.
func label(index: int) -> String:
	return "NAV %d" % (index + 1)


## 0..1: the share of cruise to lead at, by the lag (1 under `FULL_PACE_M`, 0 from `STOP_PACE_M`).
static func pace_factor(lag_m: float) -> float:
	return clampf((STOP_PACE_M - lag_m) / (STOP_PACE_M - FULL_PACE_M), 0.0, 1.0)


## m/s: the speed to lead at with the pace ship `lag_m` away.
func pace_speed(lag_m: float) -> float:
	return cruise_mps * pace_factor(lag_m)


## Whether the leader waits for the pace ship: beyond `WAIT_BEYOND_M` when it is not waiting yet, and once it waits, until
## the pace ship is within `RESUME_WITHIN_M`.
static func should_wait(lag_m: float, waiting: bool) -> bool:
	return lag_m >= RESUME_WITHIN_M if waiting else lag_m > WAIT_BEYOND_M


## m: the distance from the perceiving ship to the pace ship this tick; INF when the pace ship is not in sight (out of
## sensor range, destroyed, parked), 0 when the route has none.
func lag_to(p: Perception) -> float:
	if pace_id == 0:
		return 0.0
	for c: Contact in p.contacts:
		if c.id == pace_id:
			return p.position.distance_to(c.position)
	return INF
