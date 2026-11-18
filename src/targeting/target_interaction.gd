class_name TargetInteraction
extends RefCounted
## What a target lets the player do to it with a long hold of the auto-track button (M7-T27): jump through a gate now; dock in a
## bay and load or unload cargo when missions fill them in. A `Targetable` carries one in `interaction`; `InteractionHost` offers
## it while the target is selected. One with no action is a placeholder that answers "not available".

const NOT_AVAILABLE: String = "not available"

## What it is (`&"jump"`, `&"dock"`, `&"cargo"`), for missions and the console.
var kind: StringName = &""
## What the prompt calls it (`HOLD X: JUMP`).
var label: String = ""
## How close the ship must be to the target for the hold to be offered, m (maintainer: no button prompt out of range). INF = any.
var range_m: float = INF
## Whether it is offered now, its reach aside (the jump's state): `func() -> bool`. Unset = whenever the target is selected.
var offered: Callable = Callable()
## Runs it: `func() -> String`, "" or why it could not. Unset = a placeholder.
var action: Callable = Callable()


func _init(p_kind: StringName = &"", p_label: String = "", p_action: Callable = Callable(), p_offered: Callable = Callable(),
		p_range_m: float = INF) -> void:
	kind = p_kind
	label = p_label
	action = p_action
	offered = p_offered
	range_m = p_range_m


## Whether the hold may run it now.
func is_offered() -> bool:
	return not offered.is_valid() or bool(offered.call())


## Whether a ship `distance_m` from the target is close enough to hold for it.
func in_reach(distance_m: float) -> bool:
	return distance_m <= range_m


## Whether it does anything yet (false for the bays' placeholders).
func is_available() -> bool:
	return action.is_valid()


## Runs it: "" when it ran, else why not (`NOT_AVAILABLE` for a placeholder).
func run() -> String:
	if not action.is_valid():
		return NOT_AVAILABLE
	return String(action.call())
