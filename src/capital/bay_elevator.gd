class_name BayElevator
extends RefCounted
## A bay's hidden lift (M10-T17, Q71, Q73: the Nova's): flush with the hall's floor when idle, it sinks empty to the hangar deck
## to take a trip of craft up for a launch, and takes craft drawn into the bay down. Pure: `CapitalHangar` runs it in step with
## the dock's rows (the same ease and time as `ScsDockRows`' lift), `BayElevatorNode` draws it.

enum State { UP, SINKING, DOWN, RISING, LOWERING, RETURNING }

const STATE_NAMES: PackedStringArray = ["up", "sinking", "down", "rising", "lowering", "returning"]

## How long it takes over its travel, s (the dock kernel's `LIFT_S`).
var travel_s: float = 4.0
var state: State = State.UP
## Its time in the current move, s.
var age_s: float = 0.0
## Trips up with craft, and trips down with craft (readouts).
var trips_up: int = 0
var trips_down: int = 0


## How far up its travel it is (1 at the floor, 0 on the hangar deck), with the kernel's ease.
func height() -> float:
	var t: float = clampf(age_s / maxf(travel_s, 1e-3), 0.0, 1.0)
	var eased: float = t * t * (3.0 - 2.0 * t)
	match state:
		State.UP:
			return 1.0
		State.DOWN:
			return 0.0
		State.SINKING, State.LOWERING:
			return 1.0 - eased
		_:
			return eased


## Whether it is at the floor with nothing to do: a launch trip or a capture may use it.
func is_free() -> bool:
	return state == State.UP


## Sinks empty to fetch a trip (from the floor only). False when it is busy.
func fetch() -> bool:
	if state != State.UP:
		return false
	_go(State.SINKING)
	return true


## Down on the deck with a trip aboard: it rises with it (the craft's rows start their lift the same tick).
func rise() -> bool:
	if state != State.DOWN:
		return false
	trips_up += 1
	_go(State.RISING)
	return true


## Craft drawn in wait on it at the floor: it takes them down (their rows start lowering the same tick).
func lower() -> bool:
	if state != State.UP:
		return false
	trips_down += 1
	_go(State.LOWERING)
	return true


## One tick: a move ends at its far end. Returns the state it ended in this tick (-1 none): DOWN after sinking, UP after
## rising, and after lowering it returns up empty.
func advance(delta: float) -> int:
	if state == State.UP or state == State.DOWN:
		return -1
	age_s += delta
	if age_s < travel_s:
		return -1
	match state:
		State.SINKING:
			_go(State.DOWN)
			return State.DOWN
		State.LOWERING:
			_go(State.RETURNING)
			return -1
		_:
			_go(State.UP)
			return State.UP


func state_name() -> StringName:
	return StringName(STATE_NAMES[state])


func _go(next: State) -> void:
	state = next
	age_s = 0.0
