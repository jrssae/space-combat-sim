class_name GateActivation
extends RefCounted
## A jumpgate's activation before its vortex flashes (M6-T19, maintainer 2026-11-11): the lamps at the fin stations flash one
## after another along all four arms together, then the arms' inner tips glow into the vortex's centre flash. Only a gate does
## this; it runs as the lead-in of the vortex's `VortexTiming` (`lead_s = DURATION_S`). Pure: levels are functions of the age
## (sim seconds since the opening began), the stations' order of the lamps' distances from the centre.

## The whole lead-in; the gate still opens in the 3.5 s of T14's timing (this replaces its 1 s tip glow).
const DURATION_S: float = 1.0
## The chase runs from the arms' outer ends in to the tips, so it leads into the centre flash (the show's stills). Flip to run
## it outward.
const CHASE_INWARD: bool = true
## The chase takes this long from the first station to the last.
const CHASE_S: float = 0.6
## A lamp's flash: up in a blink, then down to a steady glow over this long.
const RISE_S: float = 0.05
const PULSE_S: float = 0.3
## Lit lamps keep this share of their flash until the vortex's flash is over.
const HOLD_LEVEL: float = 0.3
## Two lamps this close in distance from the centre (metres) belong to the same station.
const SAME_STATION_M: float = 2.0


## Each lamp's station, 0 the innermost, from its distance to the gate's centre (`radials`, metres); the four arms share ranks.
static func station_ranks(radials: PackedFloat32Array) -> PackedInt32Array:
	var levels: Array[float] = []
	for r: float in radials:
		var known: bool = false
		for level: float in levels:
			known = known or absf(level - r) <= SAME_STATION_M
		if not known:
			levels.append(r)
	levels.sort()
	var ranks := PackedInt32Array()
	for r: float in radials:
		var rank: int = 0
		for i: int in levels.size():
			if absf(levels[i] - r) <= SAME_STATION_M:
				rank = i
				break
		ranks.append(rank)
	return ranks


## When station `rank` (of `stations`) flashes, seconds into the opening.
static func flash_at_s(rank: int, stations: int) -> float:
	if stations <= 1:
		return 0.0
	var order: int = (stations - 1 - rank) if CHASE_INWARD else rank
	return CHASE_S * float(order) / float(stations - 1)


## A lamp's level, 0..1, `age_s` into the opening: dark, a flash in its turn, a steady glow until the vortex's flash is over.
static func lamp_level(rank: int, stations: int, age_s: float) -> float:
	var t: float = age_s - flash_at_s(rank, stations)
	if t < 0.0 or age_s >= DURATION_S + VortexTiming.FLASH_S:
		return 0.0
	if t < RISE_S:
		return t / RISE_S
	var settle: float = clampf((t - RISE_S) / PULSE_S, 0.0, 1.0)
	var level: float = lerpf(1.0, HOLD_LEVEL, settle)
	var fade_from: float = DURATION_S + VortexTiming.FLASH_S * 0.5
	if age_s > fade_from:
		level *= 1.0 - (age_s - fade_from) / (VortexTiming.FLASH_S * 0.5)
	return level


## The inner tips' glow, 0..1: rising once the chase reaches them, peaking as the vortex flashes, gone half way through the flash.
static func tip_level(age_s: float) -> float:
	if age_s < CHASE_S or age_s >= DURATION_S + VortexTiming.FLASH_S * 0.5:
		return 0.0
	if age_s < DURATION_S:
		return smoothstep(0.0, 1.0, (age_s - CHASE_S) / (DURATION_S - CHASE_S))
	return 1.0 - smoothstep(0.0, 1.0, (age_s - DURATION_S) / (VortexTiming.FLASH_S * 0.5))


## Whether anything of the activation still shows.
static func is_showing(age_s: float) -> bool:
	return age_s >= 0.0 and age_s < DURATION_S + VortexTiming.FLASH_S
