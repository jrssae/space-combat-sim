class_name SpeedGovernor
extends RefCounted
## The ship's speed ceilings, pure (architecture §5.6). Relativity does not exist here, but one idea from it does: inertia
## grows with speed, so the same thrust gives less acceleration the faster the ship goes. The effective mass is
## `m / sqrt(1 - (v / v_max)²)` (the Lorentz factor with `v_max` in place of c), so the thrust a nozzle delivers is
## scaled by `sqrt(1 - (v / v_max)²)` and reaches zero at `v_max`. On top of that, flight assist keeps the ship under a
## "maximum safe speed": thrust that would push the speed past it is cancelled (coasting above it is left alone).
##
## `Ship` applies both to the force of each tick; neither touches torque.


## Share of the commanded thrust that reaches the hull at `speed_mps`: 1 at rest, 0 at `limit_mps`. A non-positive limit
## switches the effect off (1).
static func thrust_gain(speed_mps: float, limit_mps: float) -> float:
	if limit_mps <= 0.0:
		return 1.0
	var ratio: float = clampf(speed_mps / limit_mps, 0.0, 1.0)
	return sqrt(1.0 - ratio * ratio)


## The effective mass multiplier at `speed_mps` (1 at rest, rising without bound as the speed nears `limit_mps`).
static func mass_factor(speed_mps: float, limit_mps: float) -> float:
	var gain: float = thrust_gain(speed_mps, limit_mps)
	return INF if gain <= 0.0 else 1.0 / gain


## The force to add so that `force` cannot raise the speed past `cap_mps`: the part of `force` along the velocity, negated,
## once the ship is at or above the cap and the force would speed it up; zero otherwise. Sideways thrust is untouched, so
## the ship can still turn its velocity. A non-positive cap switches the governor off.
static func assist_cap_correction(force: Vector3, velocity: Vector3, cap_mps: float) -> Vector3:
	if cap_mps <= 0.0:
		return Vector3.ZERO
	var speed: float = velocity.length()
	if speed < cap_mps:
		return Vector3.ZERO
	var heading: Vector3 = velocity / speed
	var along: float = force.dot(heading)
	if along <= 0.0:
		return Vector3.ZERO
	return -heading * along


## `velocity` brought down to `limit_mps` if it is faster (the hard ceiling); unchanged otherwise.
static func clamp_velocity(velocity: Vector3, limit_mps: float) -> Vector3:
	if limit_mps > 0.0 and velocity.length() > limit_mps:
		return velocity.normalized() * limit_mps
	return velocity
