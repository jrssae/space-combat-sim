class_name GateJumpPrompt
extends RefCounted
## When the player may ask a gate for a jump (M6-T14, the maintainer's "The player's jump"): within about 10 km of the gate,
## with the gate targeted, alive, with the controls in hand and no jump under way. Only then does the HUD show the prompt and
## X (the auto-track action) mean "request jump"; everywhere else X stays auto-track. Pure.

## "Within about 10 km" (maintainer, 2026-11-11): close enough that the run-in is a short flight, far enough to ask from a
## patrol.
const RANGE_M: float = 10000.0
const TEXT: String = "X: REQUEST JUMP"


## Whether the prompt shows and X requests the jump.
static func offered(range_m: float, gate_targeted: bool, alive: bool, controls_free: bool, jump_idle: bool) -> bool:
	return gate_targeted and alive and controls_free and jump_idle and range_m <= RANGE_M


## The HUD's prompt line for the same facts: the text, or "" when it is not offered.
static func line(range_m: float, gate_targeted: bool, alive: bool, controls_free: bool, jump_idle: bool) -> String:
	return TEXT if offered(range_m, gate_targeted, alive, controls_free, jump_idle) else ""
