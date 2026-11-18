class_name DockVisit
extends RefCounted
## One ship's visit to the main docking bay (M8-T06, D82), as a state: on its way to the lane, on the lane, through the inner
## doors, under repair, waiting for a Cobra bay, launching, away again. Pure: `DockingDirector` moves it on from what it sees
## of the ship, the doors and the launch.

enum State { APPROACH, LANE, INSIDE, REPAIR, RELAUNCH, LAUNCHING, DONE, CANCELLED }
const STATE_NAMES: Array[String] = ["approach", "lane", "inside", "repair", "relaunch", "launching", "done", "cancelled"]

## Why the visit began: the player's hold, the wing order, a wingman's own call below the hull threshold, the console.
const WHY_HOLD: StringName = &"hold"
const WHY_ORDER: StringName = &"order"
const WHY_HULL: StringName = &"hull"
const WHY_CONSOLE: StringName = &"console"

var ship_name: String = ""
var is_player: bool = false
var why: StringName = WHY_HOLD
var state: State = State.APPROACH
## Seconds in the current state, and in the visit.
var state_s: float = 0.0
var total_s: float = 0.0
## The repair: how long it takes and how much is left, and the hull the ship came in with (0..1).
var repair_s: float = 0.0
var repair_left_s: float = 0.0
var hull_before: float = 1.0
## The ship jumped ahead (a skipped cinematic, a timeout) instead of flying the whole way in.
var skipped: bool = false
var cancel_reason: String = ""


func _init(p_name: String = "", p_is_player: bool = false, p_why: StringName = WHY_HOLD) -> void:
	ship_name = p_name
	is_player = p_is_player
	why = p_why


func state_name() -> String:
	return STATE_NAMES[state]


func advance(delta: float) -> void:
	state_s += delta
	total_s += delta


func enter(next: State) -> void:
	state = next
	state_s = 0.0


## The ship is still outside the inner doors: the visit can be called off and the ship flies on.
func can_cancel() -> bool:
	return state == State.APPROACH or state == State.LANE


## The ship is out of play: inside the station or on a Cobra bay's rack.
func is_away() -> bool:
	return state == State.REPAIR or state == State.RELAUNCH or state == State.LAUNCHING


func is_over() -> bool:
	return state == State.DONE or state == State.CANCELLED


## Starts the repair clock.
func begin_repair(seconds: float, hull_fraction: float) -> void:
	repair_s = maxf(seconds, 0.0)
	repair_left_s = repair_s
	hull_before = hull_fraction
	enter(State.REPAIR)


## Runs the repair clock; true once the ship is ready.
func repair_tick(delta: float) -> bool:
	repair_left_s = maxf(repair_left_s - delta, 0.0)
	return repair_left_s <= 0.0


## 0..1 of the repair done.
func repair_progress() -> float:
	return 1.0 if repair_s <= 0.0 else clampf(1.0 - repair_left_s / repair_s, 0.0, 1.0)


func cancel(reason: String) -> void:
	cancel_reason = reason
	enter(State.CANCELLED)


func describe() -> String:
	var text: String = "%s %s" % [ship_name, state_name()]
	if state == State.REPAIR:
		text += " %.0f s left" % repair_left_s
	if skipped:
		text += " (skipped)"
	return text
