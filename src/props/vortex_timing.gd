class_name VortexTiming
extends RefCounted
## When a jumpgate's vortex glows, flashes, grows, stays open and closes (M6-T14, D69), on the reference video's timing
## (`docs/design-references.md`, "Jumpgate (M6)"): the inner tips glow, their glows merge in a flash at the centre, a spark
## grows into the funnel, it stays open while ships pass, then shrinks back to a spark. Pure: every answer is a function of the
## age (sim seconds since the opening began), so a pause freezes it and a test can ask any instant.
##
## One opening has one direction. `extend` keeps it open longer while a ship is still on its way; `close_now` starts the close as
## soon as the vortex is fully open (a gate is not shut down quickly).

enum Phase { GLOW, FLASH, GROW, OPEN, CLOSING, CLOSED }
const PHASE_NAMES: Array[String] = ["glow", "flash", "grow", "open", "closing", "closed"]

## The tips glow for about a second, the flash takes about a second, the funnel grows in 1 to 2 s (the reference's frames).
const GLOW_S: float = 1.0
const FLASH_S: float = 1.0
const GROW_S: float = 1.5
## It is gone within about a second of starting to close.
const CLOSE_S: float = 1.0
## Open long enough for a ship that is already lined up to pass (3 to 4 s in the clips).
const DEFAULT_HOLD_S: float = 4.0

## Age at which the funnel is fully open.
const OPEN_AT_S: float = GLOW_S + FLASH_S + GROW_S

## Age at which the close starts.
var close_from_s: float = OPEN_AT_S + DEFAULT_HOLD_S


func _init(hold_s: float = DEFAULT_HOLD_S) -> void:
	close_from_s = OPEN_AT_S + maxf(hold_s, 0.0)


## Which part of the opening `age_s` falls in.
func phase(age_s: float) -> Phase:
	if age_s < 0.0:
		return Phase.CLOSED
	if age_s < GLOW_S:
		return Phase.GLOW
	if age_s < GLOW_S + FLASH_S:
		return Phase.FLASH
	if age_s < OPEN_AT_S:
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


## Seconds until it is fully open (0 once open or after).
func open_in_s(age_s: float) -> float:
	return maxf(OPEN_AT_S - age_s, 0.0)


## Keeps it open at least `hold_s` past `age_s`, while it has not begun to close.
func extend(age_s: float, hold_s: float) -> void:
	if age_s < close_from_s:
		close_from_s = maxf(close_from_s, maxf(age_s, OPEN_AT_S) + hold_s)


## Starts the close now, or as soon as the funnel is fully open.
func close_now(age_s: float) -> void:
	if age_s < close_from_s:
		close_from_s = maxf(age_s, OPEN_AT_S)


## The funnel's size, 0..1 of its full radius: nothing until the flash ends, an eased growth, full while open, an eased shrink.
func radius_scale(age_s: float) -> float:
	var grow_from: float = GLOW_S + FLASH_S
	if age_s < grow_from or is_done(age_s):
		return 0.0
	if age_s < OPEN_AT_S:
		return smoothstep(0.0, 1.0, (age_s - grow_from) / GROW_S)
	if age_s < close_from_s:
		return 1.0
	return 1.0 - smoothstep(0.0, 1.0, (age_s - close_from_s) / CLOSE_S)


## The inner tips' glow, 0..1: rising through the glow, peaking as the flash starts, gone once the funnel is half grown.
func tip_glow(age_s: float) -> float:
	if age_s < 0.0:
		return 0.0
	if age_s < GLOW_S:
		return smoothstep(0.0, 1.0, age_s / GLOW_S)
	var fade_until: float = GLOW_S + FLASH_S + GROW_S * 0.5
	if age_s < fade_until:
		return 1.0 - smoothstep(0.0, 1.0, (age_s - GLOW_S) / (fade_until - GLOW_S))
	return 0.0


## The flash at the centre, 0..1: up fast through the first third of the flash, back down by the time the funnel is a third grown.
func flash(age_s: float) -> float:
	var start: float = GLOW_S
	var peak: float = GLOW_S + FLASH_S / 3.0
	var end: float = GLOW_S + FLASH_S + GROW_S / 3.0
	if age_s < start or age_s >= end:
		return 0.0
	if age_s < peak:
		return (age_s - start) / (peak - start)
	return 1.0 - (age_s - peak) / (end - peak)
