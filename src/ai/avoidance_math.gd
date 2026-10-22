class_name AvoidanceMath
extends RefCounted
## Collision avoidance as a filter on a brain's desired velocity (architecture §16 D33). Pure statics; `AiPilotDriver` runs
## every brain's wish through `filter` before the seek, so every AI ship avoids whatever it is doing.
##
## Per contact, in the contact's frame: the own ship sits at `s = own_pos - contact.position` and, at the velocity it
## wants, moves at `w = v_des - contact.velocity` (props report zero or their drift). The closest approach comes after
## `t* = -s.w / |w|^2` at distance `m = |s + w t*|`. It is a threat when `0 < t* < horizon` and `m` is under the sum of the
## radii plus `MARGIN_M`; the horizon is the time to stop that relative speed on the retros (the larger of the wished and
## the current one), at least `HORIZON_MIN_S`. A threat adds a sideways velocity (perpendicular to `w`, away from the
## closest-approach offset) of exactly the size that makes the straight line at the filtered velocity clear the margin
## (plus `AIM_PAST_M`): the nearer and sooner the miss, the larger the dodge. Several threats add up.
##
## Predicting with the wish, not the current velocity, keeps the closed loop calm: the dodge shrinks only as the ship's
## position moves off the line (m grows), not as its velocity swings, so it does not chatter against the seek.
##
## - **Matched velocities** (relative speed under `MATCHED_MPS`, formation flight) never predict: they push apart only when
##   already inside the margin.
## - **Inside the margin**: straight away from the contact at `(reach - d) / PUSH_S`, plus whatever speed closes on it.
## - **Ties** (a dead-centre course, or the same position): the side comes from `tie_direction`, seeded and odd in `w`,
##   so two ships meeting head-on dodge apart whatever their two seeds.
## - `urgent`: a threat closer in time than a 90 degree turn plus `URGENT_SETTLE_S`, or a contact inside the margin that
##   closes: the driver then seeks harder, so the RCS strafe does the dodge before any turn could.

## Clearance kept beyond the two bounding radii, m.
const MARGIN_M: float = 15.0
const HORIZON_MIN_S: float = 4.0
## Relative speeds under this are flying together (formation): no prediction, only the margin.
const MATCHED_MPS: float = 3.0
## Inside the margin the overlap is pushed out in about this long.
const PUSH_S: float = 2.0
## The dodge aims this much past the margin, so the filtered line clears it rather than grazing it.
const AIM_PAST_M: float = 1.0
## Closest-approach offsets under this are ties (dead centre): the side is seeded.
const TIE_M: float = 0.1
## A tie's side: within this many degrees of "right of the relative velocity, world up". Under 45, so two seeded dodges
## never cancel.
const TIE_SPREAD_DEG: float = 40.0
## Added to the time a 90 degree turn takes to decide what is urgent.
const URGENT_SETTLE_S: float = 1.0
## A dodge never asks for less time than this (alongside, closest approach a fraction of a second away).
const MIN_TIME_S: float = 0.25


## The desired velocity with every threat's dodge added: `{"v_des": Vector3, "urgent": bool}`. `v_des` comes back
## unchanged (the same value) when nothing threatens. `own_vel` is the current velocity (it only lengthens the horizon);
## `seed_value` breaks ties.
static func filter(own_pos: Vector3, own_vel: Vector3, own_radius: float, contacts: Array[Contact], v_des: Vector3,
		capability: ShipCapability, seed_value: int) -> Dictionary:
	var dodge := Vector3.ZERO
	var urgent: bool = false
	var a_stop: float = maxf(capability.a_retro, 0.01)
	var turn_rate: float = maxf(minf(capability.rate_max_rad.x, capability.rate_max_rad.y), 0.01)
	var urgent_s: float = 0.5 * PI / turn_rate + URGENT_SETTLE_S
	for c: Contact in contacts:
		var reach: float = own_radius + c.bounding_radius + MARGIN_M
		var s: Vector3 = own_pos - c.position
		var w: Vector3 = v_des - c.velocity
		var d: float = s.length()
		if d < reach:
			var out_dir: Vector3 = s / d if d > TIE_M else tie_direction(w, seed_value)
			var closing: float = -w.dot(out_dir)
			dodge += out_dir * ((reach - d) / PUSH_S + maxf(closing, 0.0))
			urgent = urgent or closing > MATCHED_MPS
			continue
		var speed_sq: float = w.length_squared()
		if speed_sq < MATCHED_MPS * MATCHED_MPS:
			continue
		var t_star: float = -s.dot(w) / speed_sq
		if t_star <= 0.0:
			continue  # opening
		var speed: float = sqrt(speed_sq)
		var horizon: float = maxf(HORIZON_MIN_S, maxf(speed, (own_vel - c.velocity).length()) / a_stop)
		if t_star > horizon:
			continue
		var offset: Vector3 = s + w * t_star
		var miss: float = offset.length()
		if miss >= reach:
			continue
		var side: Vector3 = offset / miss if miss > TIE_M else tie_direction(w, seed_value)
		dodge += side * _sideways_speed(miss, speed * t_star, reach + AIM_PAST_M, speed, t_star)
		urgent = urgent or t_star < urgent_s
	return {"v_des": v_des + dodge, "urgent": urgent}


## Distance between two bodies at their closest approach within `horizon_s` from now, given the relative position and
## velocity of one with respect to the other (now, when they are opening or not moving apart at all).
static func closest_approach(rel_pos: Vector3, rel_vel: Vector3, horizon_s: float) -> float:
	var speed_sq: float = rel_vel.length_squared()
	if speed_sq < 1e-12:
		return rel_pos.length()
	var t: float = clampf(-rel_pos.dot(rel_vel) / speed_sq, 0.0, horizon_s)
	return (rel_pos + rel_vel * t).length()


## A unit vector perpendicular to `rel_vel` for a dead-centre tie: "right" of it with world up (world right when it is
## nearly vertical), turned about it by a seeded angle within `TIE_SPREAD_DEG`. Odd in `rel_vel` (the other ship sees
## `-rel_vel` and gets the opposite base), so two ships on a collision course dodge apart for any pair of seeds.
static func tie_direction(rel_vel: Vector3, seed_value: int) -> Vector3:
	var axis: Vector3 = rel_vel.normalized() if rel_vel.length_squared() > 1e-12 else Vector3.FORWARD
	var reference: Vector3 = Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var base: Vector3 = axis.cross(reference).normalized()
	var unit: float = float(posmod(hash(seed_value), 65536)) / 65535.0
	return base.rotated(axis, deg_to_rad(TIE_SPREAD_DEG) * (2.0 * unit - 1.0))


# The sideways speed (perpendicular to the relative velocity) that lifts the straight-line miss from `miss` to `target`.
# With `along` = the distance to the closest approach along the line and `speed` = |w|, adding `x` sideways makes the miss
# (miss * speed + along * x) / sqrt(speed^2 + x^2); setting that to `target` is a quadratic in x. When the closest approach
# is nearer along the line than `target` (alongside), no sideways speed alone gets there: as much as the time left asks.
# Never more than `speed` (45 degrees off the relative velocity).
static func _sideways_speed(miss: float, along: float, target: float, speed: float, t_star: float) -> float:
	var x: float
	if along > target + 1e-3:
		var distance_sq: float = along * along + miss * miss
		x = speed * (target * sqrt(distance_sq - target * target) - miss * along) / (along * along - target * target)
	else:
		x = (target - miss) / maxf(t_star, MIN_TIME_S)
	return clampf(x, 0.0, speed)
