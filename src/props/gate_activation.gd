class_name GateActivation
extends RefCounted
## A jumpgate's activation before its vortex flashes (M6-T19, maintainer 2026-11-11): the lamps at the fin stations flash one
## after another along all four arms together, from the arms' front ends to their back ends, then the emitters on the back
## ends glow into the vortex's centre flash, and the jump point forms inside the arms. Only a gate does this; it runs as the
## lead-in of the vortex's `VortexTiming` (`lead_s = DURATION_S`). Pure: levels are functions of the age (sim seconds since the
## opening began); a lamp's station is its place along the arm, 0 at the front.

## Seconds and levels from `data/jump/vortex_look.json` (M7-T23, the maintainer's GIF). The whole lead-in.
static var DURATION_S: float = VortexLook.number("gate", "lead_s", 2.0)
## The chase takes this long from the front station to the back one.
static var CHASE_S: float = VortexLook.number("gate", "chase_s", 1.2)
## A lamp's flash: up in a blink, then down to a steady glow over this long.
static var RISE_S: float = VortexLook.number("gate", "lamp_rise_s", 0.05)
static var PULSE_S: float = VortexLook.number("gate", "lamp_pulse_s", 0.3)
## Lit lamps keep this share of their flash until the vortex's flash is over.
static var HOLD_LEVEL: float = VortexLook.number("gate", "lamp_hold_level", 0.3)
## Between openings the lamps burn steadily at this level: the amber points that show a gate in shadow (the stills).
static var STEADY_LEVEL: float = VortexLook.number("gate", "lamp_steady_level", 0.12)
## The back ends throb this many times as they build to the flash, dipping by this share between throbs.
static var TIP_PULSES: float = VortexLook.number("gate", "tip_pulses", 2.0)
static var TIP_PULSE_DEPTH: float = VortexLook.number("gate", "tip_pulse_depth", 0.35)
## Two lamps this close along the arm (metres) belong to the same station.
const SAME_STATION_M: float = 2.0


## Each lamp's station, 0 the front, from its place along the arm (`along`: metres toward the back, gate-local z); the four arms
## share ranks.
static func station_ranks(along: PackedFloat32Array) -> PackedInt32Array:
	var levels: Array[float] = []
	for z: float in along:
		var known: bool = false
		for level: float in levels:
			known = known or absf(level - z) <= SAME_STATION_M
		if not known:
			levels.append(z)
	levels.sort()
	var ranks := PackedInt32Array()
	for z: float in along:
		var rank: int = 0
		for i: int in levels.size():
			if absf(levels[i] - z) <= SAME_STATION_M:
				rank = i
				break
		ranks.append(rank)
	return ranks


## When station `rank` (of `stations`) flashes, seconds into the opening: the front first, the back last.
static func flash_at_s(rank: int, stations: int) -> float:
	if stations <= 1:
		return 0.0
	return CHASE_S * float(rank) / float(stations - 1)


## A lamp's level, 0..1, `age_s` into the opening: its steady burn, a flash in its turn, a brighter glow until the vortex's flash
## is over, then its steady burn again.
static func lamp_level(rank: int, stations: int, age_s: float) -> float:
	var t: float = age_s - flash_at_s(rank, stations)
	if t < 0.0 or age_s >= DURATION_S + VortexTiming.FLASH_S:
		return STEADY_LEVEL
	if t < RISE_S:
		return lerpf(STEADY_LEVEL, 1.0, t / RISE_S)
	var settle: float = clampf((t - RISE_S) / PULSE_S, 0.0, 1.0)
	var level: float = lerpf(1.0, HOLD_LEVEL, settle)
	var fade_from: float = DURATION_S + VortexTiming.FLASH_S * 0.5
	if age_s > fade_from:
		level = lerpf(level, STEADY_LEVEL, (age_s - fade_from) / (VortexTiming.FLASH_S * 0.5))
	return maxf(level, STEADY_LEVEL)


## The back ends' glow, 0..1: rising in throbs once the chase reaches them, peaking as the vortex flashes, gone half way through the flash.
static func tip_level(age_s: float) -> float:
	if age_s < CHASE_S or age_s >= DURATION_S + VortexTiming.FLASH_S * 0.5:
		return 0.0
	if age_s < DURATION_S:
		var build: float = (age_s - CHASE_S) / (DURATION_S - CHASE_S)
		var throb: float = 1.0 - TIP_PULSE_DEPTH * 0.5 * (1.0 - cos(TAU * TIP_PULSES * build))
		return smoothstep(0.0, 1.0, build) * throb
	return 1.0 - smoothstep(0.0, 1.0, (age_s - DURATION_S) / (VortexTiming.FLASH_S * 0.5))


## Whether anything of the activation still shows.
static func is_showing(age_s: float) -> bool:
	return age_s >= 0.0 and age_s < DURATION_S + VortexTiming.FLASH_S
