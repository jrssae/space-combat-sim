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
## - **Ties** (a dead-centre course, or the same position): the side comes from the kernel's tie direction, seeded and odd in `w`,
##   so two ships meeting head-on dodge apart whatever their two seeds.
## - **Rocks and mines** (`BodyKind.is_static`, M4-T09) are obstacles like any contact, with their radius. Their horizon is
##   at least the time a sideways RCS burn takes to clear their reach, plus `URGENT_SETTLE_S`, so a 200 m rock is seen
##   early enough to go round; ship-sized contacts keep the horizon above.
## - `urgent`: a threat closer in time than a 90 degree turn plus `URGENT_SETTLE_S`, or a contact inside the margin that
##   closes: the driver then seeks harder, so the RCS strafe does the dodge before any turn could.
##
## The maths runs in the native pilot kernels (M4-T16, architecture §17.13; `kernels::pilot::avoid`): over the core's rows
## when the perception is on them (`Perception.on_rows`), else over its own lists loaded as rows (`PilotRows`). The GDScript
## loop it matched bit for bit went in M4-T42; its answers are recorded in `tests/fixtures/parity/pilot_kernels.json`. The
## constants named above are the kernel's (`native/src/kernels.rs`, `pub mod pilot`).

## Clearance kept beyond the two bounding radii, m (the kernel's `MARGIN_M`).
const MARGIN_M: float = 15.0
## A tie's side: within this many degrees of "right of the relative velocity, world up" (the kernel's `TIE_SPREAD_DEG`).
const TIE_SPREAD_DEG: float = 40.0


## The desired velocity with every threat's dodge added: `{"v_des": Vector3, "urgent": bool}`. `v_des` comes back
## unchanged (the same value) when nothing threatens. `own_vel` is the current velocity (it only lengthens the horizon);
## `seed_value` breaks ties.
static func filter(own_pos: Vector3, own_vel: Vector3, own_radius: float, contacts: Array[Contact], v_des: Vector3,
		capability: ShipCapability, seed_value: int) -> Dictionary:
	var kernels: Object = PilotRows.kernels_of(contacts)
	if kernels == null:
		return {"v_des": v_des, "urgent": false}
	return _avoid(kernels, PilotRows.span(0, contacts.size()), PackedInt32Array(), 0, own_pos, own_vel, own_radius, v_des,
			capability, hash(seed_value))


## `filter` for a perception: its contacts but `exempt_id` (a committed rammer's target, M3-T13; 0 for none), then its
## statics (rocks and mines, M4-T09), from its own position and velocity, with `hash(seed_value)` as the tie-break.
static func filter_seen(p: Perception, own_radius: float, v_des: Vector3, exempt_id: int, seed_value: int) -> Dictionary:
	if p.on_rows():
		return _avoid(p.kernels, p.contact_rows, p.static_rows, exempt_id, p.position, p.velocity, own_radius, v_des,
				p.capability, hash(seed_value))
	var listed: Array[Contact] = []
	listed.append_array(p.contacts)
	listed.append_array(p.statics)
	var kernels: Object = PilotRows.kernels_of(listed)
	if kernels == null:
		return {"v_des": v_des, "urgent": false}
	return _avoid(kernels, PilotRows.span(0, p.contacts.size()), PilotRows.span(p.contacts.size(), p.statics.size()),
			exempt_id, p.position, p.velocity, own_radius, v_des, p.capability, hash(seed_value))


# One ship's avoidance through `kernels` over the given rows: `{"v_des": Vector3, "urgent": bool}`.
static func _avoid(kernels: Object, contact_rows: PackedInt32Array, static_rows: PackedInt32Array, exempt_id: int,
		own_pos: Vector3, own_vel: Vector3, own_radius: float, v_des: Vector3, capability: ShipCapability,
		tie_hash: int) -> Dictionary:
	var out: Vector4 = kernels.avoid(contact_rows, static_rows, exempt_id, own_pos, own_vel, own_radius, v_des,
			capability.a_retro, capability.rate_max_rad, capability.a_rcs, tie_hash)
	return {"v_des": Vector3(out.x, out.y, out.z), "urgent": out.w > 0.5}


## Distance between two bodies at their closest approach within `horizon_s` from now, given the relative position and
## velocity of one with respect to the other (now, when they are opening or not moving apart at all).
static func closest_approach(rel_pos: Vector3, rel_vel: Vector3, horizon_s: float) -> float:
	var speed_sq: float = rel_vel.length_squared()
	if speed_sq < 1e-12:
		return rel_pos.length()
	var t: float = clampf(-rel_pos.dot(rel_vel) / speed_sq, 0.0, horizon_s)
	return (rel_pos + rel_vel * t).length()
