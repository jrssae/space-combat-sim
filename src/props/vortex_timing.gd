class_name VortexTiming
extends RefCounted
## When a jump vortex flashes, unfolds, stays open and closes (M6-T14, T19, D69), on the reference video's timing
## (`docs/design-references.md`, "Jumpgate (M6)"): an optional lead-in that belongs to whoever opens it (a jumpgate's arm
## sequence, `GateActivation`; none for a ship-made point), then the flash at the centre, the funnel unfolding from that point
## to its rim, open while ships pass, then folding back to the point. Pure: every answer is a function of the age (sim seconds
## since the opening began), so a pause freezes it and a test can ask any instant.
##
## One opening has one direction. `extend` keeps it open longer while a ship is still on its way; `close_now` starts the close as
## soon as the vortex is fully open (a gate is not shut down quickly).

enum Phase { ACTIVATE, FLASH, GROW, OPEN, CLOSING, CLOSED }
const PHASE_NAMES: Array[String] = ["activate", "flash", "grow", "open", "closing", "closed"]

## The flash takes about a second, the funnel unfolds in 1 to 2 s (the reference's frames).
const FLASH_S: float = 1.0
const GROW_S: float = 1.5
## It is gone within about a second of starting to close.
const CLOSE_S: float = 1.0
## Open long enough for a ship that is already lined up to pass (3 to 4 s in the clips).
const DEFAULT_HOLD_S: float = 4.0

## The opener's lead-in before the flash (0 for a ship-made point).
var lead_s: float = 0.0
## Age at which the funnel is fully open.
var open_at_s: float = FLASH_S + GROW_S
## Age at which the close starts.
var close_from_s: float = open_at_s + DEFAULT_HOLD_S


func _init(hold_s: float = DEFAULT_HOLD_S, p_lead_s: float = 0.0) -> void:
	lead_s = maxf(p_lead_s, 0.0)
	open_at_s = lead_s + FLASH_S + GROW_S
	close_from_s = open_at_s + maxf(hold_s, 0.0)


## Which part of the opening `age_s` falls in.
func phase(age_s: float) -> Phase:
	if age_s < 0.0:
		return Phase.CLOSED
	if age_s < lead_s:
		return Phase.ACTIVATE
	if age_s < lead_s + FLASH_S:
		return Phase.FLASH
	if age_s < open_at_s:
		return Phase.GROW
	if age_s < close_from_s:
		return Phase.OPEN
	if age_s < close_from_s + CLOSE_S:
		return Phase.CLOSING
	return Phase.CLOSED


func phase_name(age_s: float) -> String:
	return PHASE_NAMES[phase(age_s)]


## Whether ships may pass now: fully open and not closing.
func is_open(age_s: float) -> bool:
	return phase(age_s) == Phase.OPEN


## Whether the opening is over.
func is_done(age_s: float) -> bool:
	return age_s >= close_from_s + CLOSE_S


## The age at which the opening is over.
func done_at_s() -> float:
	return close_from_s + CLOSE_S


## Seconds until it is fully open (0 once open or after).
func open_in_s(age_s: float) -> float:
	return maxf(open_at_s - age_s, 0.0)


## Keeps it open at least `hold_s` past `age_s`, while it has not begun to close.
func extend(age_s: float, hold_s: float) -> void:
	if age_s < close_from_s:
		close_from_s = maxf(close_from_s, maxf(age_s, open_at_s) + hold_s)


## Starts the close now, or as soon as the funnel is fully open.
func close_now(age_s: float) -> void:
	if age_s < close_from_s:
		close_from_s = maxf(age_s, open_at_s)


## How far the funnel has unfolded from its centre toward the rim, 0..1: nothing until the flash ends, an eased unfolding, full
## while open, folding back while it closes.
func growth(age_s: float) -> float:
	var grow_from: float = lead_s + FLASH_S
	if age_s < grow_from or is_done(age_s):
		return 0.0
	if age_s < open_at_s:
		return smoothstep(0.0, 1.0, (age_s - grow_from) / GROW_S)
	if age_s < close_from_s:
		return 1.0
	return 1.0 - smoothstep(0.0, 1.0, (age_s - close_from_s) / CLOSE_S)


## The flash at the centre, 0..1: up fast through the first third of the flash, back down by the time the funnel is a third grown.
func flash(age_s: float) -> float:
	var start: float = lead_s
	var peak: float = lead_s + FLASH_S / 3.0
	var end: float = lead_s + FLASH_S + GROW_S / 3.0
	if age_s < start or age_s >= end:
		return 0.0
	if age_s < peak:
		return (age_s - start) / (peak - start)
	return 1.0 - (age_s - peak) / (end - peak)
