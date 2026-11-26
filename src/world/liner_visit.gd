class_name LinerVisit
extends RefCounted
## One Asimov liner calling at Babylon 5 (M10-T53, Q85): where it is in its visit and what its two shuttles are doing.
## `LinerTraffic` flies it; this is its record, and its line for the console.

## The visit's phases, in order: asked of the gate, flying in, holding at its standoff spot, flying out, gone.
const GATE: StringName = &"gate"
const INBOUND: StringName = &"inbound"
const HOLDING: StringName = &"holding"
const OUTBOUND: StringName = &"outbound"
const GONE: StringName = &"gone"

## A shuttle's legs: aboard, leaving the liner's bay, on its way into the station's docking bay, inside the station, coming
## out and flying back, being taken into the liner's bay, finished (both trips flown) or lost.
const ABOARD: StringName = &"aboard"
const LAUNCHING: StringName = &"launching"
const TO_STATION: StringName = &"to_station"
const INSIDE: StringName = &"inside"
const FROM_STATION: StringName = &"from_station"
const HOME: StringName = &"home"
const BERTHING: StringName = &"berthing"
const DONE: StringName = &"done"
const LOST: StringName = &"lost"
## What each trip is for.
const TRIPS: PackedStringArray = ["unload", "load"]

var name: String = ""
var phase: StringName = GATE
## Which standoff spot it holds (a second liner takes the next).
var slot: int = 0
## How long it stays at its spot, and how long it has held there, s.
var stay_s: float = 0.0
var held_s: float = 0.0
var ship: CapitalShip = null
## Whether its arrival has been asked of the gate (one liner at a time comes out).
var asked: bool = false
## Whether its hangar has been given its craft (it is placed empty: `LinerTraffic._place`).
var stocked: bool = false
## Which leg of its way out it flies (the line-up point, then through the gate).
var out_leg: int = 0
## One per shuttle: {type, leg, trip, wait_s, combatant, brain, entry}.
var shuttles: Array[Dictionary] = []


## Seconds of its stay left (0 once it waits only for its shuttles).
func time_left_s() -> float:
	return maxf(stay_s - held_s, 0.0)


## Whether it is still in play.
func in_play() -> bool:
	return phase != GONE


## Whether it is at the station or on its way there (a visit under way; a liner flying out is not).
func visiting() -> bool:
	return phase == GATE or phase == INBOUND or phase == HOLDING


## Whether no shuttle is out or about to be: all aboard, finished or lost.
func shuttles_home() -> bool:
	for s: Dictionary in shuttles:
		if s["leg"] != ABOARD and s["leg"] != DONE and s["leg"] != LOST:
			return false
	return true


## Whether every shuttle has flown its trips (or was lost).
func trips_done() -> bool:
	for s: Dictionary in shuttles:
		if s["leg"] != DONE and s["leg"] != LOST:
			return false
	return true


## The visit in a line: the liner's phase and time left, then each shuttle's leg and trip.
func text() -> String:
	var parts := PackedStringArray()
	for s: Dictionary in shuttles:
		var trip: int = int(s["trip"])
		var leg: StringName = s["leg"]
		var what: String = String(leg)
		if leg != DONE and leg != LOST and trip < TRIPS.size():
			what = "%s (trip %d of %d, to %s)" % [leg, trip + 1, TRIPS.size(), TRIPS[trip]]
		parts.append("%s %s" % [s["type"], what])
	var left: String = ", %.0f s left" % time_left_s() if phase == HOLDING else ""
	return "%s %s%s [%s]" % [name, phase, left, "; ".join(parts)]
