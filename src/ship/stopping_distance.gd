class_name StoppingDistance
extends RefCounted
## How far a ship needs to stop, and how fast it may go and still stop in time (M8-T06, D84). Pure: speeds are against whatever
## the caller measures them to (a bay's or a gate's rest), the braking is the thruster's acceleration at the ship's mass
## (`ShipCapability`). The docking autopilot paces its lane with it; the approach cue (M8-T18) reads the same numbers.

## The share of the ideal braking speed an autopilot plans with, so it never arrives with the brakes at their limit.
const PLAN_MARGIN: float = 0.7
const MIN_DECEL: float = 0.01


## Metres covered from `speed_mps` to rest at `decel_mps2`, after `reaction_s` flown at full speed first (a turn to the burn).
static func distance_m(speed_mps: float, decel_mps2: float, reaction_s: float = 0.0) -> float:
	var speed: float = absf(speed_mps)
	return speed * maxf(reaction_s, 0.0) + speed * speed / (2.0 * maxf(decel_mps2, MIN_DECEL))


## Seconds from `speed_mps` to rest, the reaction included.
static func time_s(speed_mps: float, decel_mps2: float, reaction_s: float = 0.0) -> float:
	return maxf(reaction_s, 0.0) + absf(speed_mps) / maxf(decel_mps2, MIN_DECEL)


## The fastest a ship may close on a point `distance_m` away and still stop there, times `margin`.
static func speed_for_mps(distance: float, decel_mps2: float, margin: float = PLAN_MARGIN) -> float:
	return sqrt(2.0 * maxf(decel_mps2, MIN_DECEL) * maxf(distance, 0.0)) * margin


## The braking a stop within `distance` from `speed_mps` takes, m/s^2 (INF with no room left).
static func decel_needed(speed_mps: float, distance: float) -> float:
	if distance <= 0.0:
		return INF if absf(speed_mps) > 0.0 else 0.0
	return speed_mps * speed_mps / (2.0 * distance)


## Whether a ship closing at `speed_mps` can still stop within `distance` (the cue's OVERSHOOT is the opposite).
static func can_stop(speed_mps: float, distance: float, decel_mps2: float, reaction_s: float = 0.0) -> bool:
	return distance_m(speed_mps, decel_mps2, reaction_s) <= distance
