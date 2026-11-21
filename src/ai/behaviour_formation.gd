class_name BehaviourFormation
extends AiBehaviour
## Fly in the wing's formation (architecture §16 D34, D36, M3-T07): hold the slot `AiContext.slot_offset` (in the leader's
## body frame) off the leader, and rejoin it from anywhere.
##
## Score: 0 without a slot, or without a leader (neither in sight nor on the wing's link). Otherwise `SCORE`, which beats
## idle by more than the stickiness, while the orders allow no attack on anything in sight (`AiContext.has_attackable`:
## FORM ON ME always; COVER ME while no hostile is near the leader or after it; ATTACK MY TARGET while the leader's target
## is not in sight), and `STAND_BY_SCORE` while they allow one, so any attack (0.3 or more) takes over. Evade and retreat
## outrank it either way (FORM ON ME gates the retreat itself).
##
## Station keeping, every tick: the slot is S = p_L + B_L * offset, from the leader's contact (position, nose and top as of
## this tick). The error looks `LEAD_S` ahead for both ships, e = (S - p) + LEAD_S * (v_L - v), so the lead damps the
## approach instead of parking the ship ahead of its slot. The wish is v_des = v_L + clamp(K_PER_S * e): the closure on the
## slot is capped at `NEAR_CLOSURE_MPS` within `FAR_RANGE_M` of it and at the profile's cruise + `FAR_EXTRA_MPS` beyond. With
## the seek's 1 s horizon that is a second-order loop with a damping ratio of about 0.95.
##
## Attitude: within `ALIGN_RANGE_M` of the slot the nose follows the leader's nose and the roll its top
## (`PilotSteering.align_roll`), so the mains push the way the leader's do, and the thrust works every axis at once
## (`seek_velocity` with `all_axes`): `seek`'s cones would wait for the nose to turn toward the error, and here it never does
## (in a turn the error stays mostly sideways and the slot runs away along the nose). When the sideways part of the
## acceleration the wish asks for is more than the RCS gives, the nose leans off the leader's toward it, by the least angle
## that lets the mains or retros carry the rest, at most `MAX_LEAN_DEG` (`PilotSteering.lean_toward`); in steady flight it
## is the leader's. Farther out the nose turns toward the velocity change it needs when that is over `FACE_DV_MPS` and not a
## slow-down along the way (the mains give twice the retros), otherwise it faces its desired velocity and the retros brake,
## and the thrust is `seek`'s.
##
## Out of sight (beyond sensor range) it flies to the leader's position on the wing's link (`AiContext.leader_link_position`)
## at the far closure, the slot offset ignored until the contact is back.
##
## Forming up (M7-T76, as the native brain flies it; this reference sees no big hull): a slot that lies across the leader (the
## leader turned about) is come round to over the leader's top from its left and under it from its right (`_swing`), the aim
## keeps off the line a leader burning back toward the ship comes along (`_clear_of_burn`), and every friendly ship is kept
## off the wish (`_kept_apart`).
##
## Shooting from the slot (M8-T19, D85): within `ALIGN_RANGE_M` of its slot a pilot that attacks (`gunner`, its attack
## behaviour; not a passive one) turns its nose on the nearest hostile ship inside its guns' range and within `FIRE_ARC_DEG`
## of the leader's nose, leads it as an attack does and holds the trigger on the attack's own gate (the lead inside the cone,
## no friend in the lane), while the thrusters keep the slot. A hold-fire order (`AiContext.holds_fire`) stops it.
##
## Hold position (M8-T19): under that order the behaviour scores with or without a leader and brakes, so the ship stops
## against the reference where it is and stays.

const SCORE: float = 0.25
const STAND_BY_SCORE: float = 0.1
## s^-1: the closure per metre of error.
const K_PER_S: float = 0.4
## s: how far ahead the error looks, for the slot and the ship alike.
const LEAD_S: float = 0.5
const NEAR_CLOSURE_MPS: float = 60.0
const FAR_RANGE_M: float = 1500.0
const FAR_EXTRA_MPS: float = 100.0
## Within this of the slot the ship takes the leader's attitude.
const ALIGN_RANGE_M: float = 150.0
## `describe` calls a ship this close to its slot "in slot".
const IN_SLOT_M: float = 25.0
const FACE_DV_MPS: float = 30.0
## The most the nose leans off the leader's toward the acceleration it needs (`PilotSteering.lean_toward`).
const MAX_LEAN_DEG: float = 40.0
## The flight path's turn rate fed forward is at most this (20 degrees/s), and fades in up to `FEED_FORWARD_FULL_MPS` of
## the leader's speed: at low speed v x a / |v|^2 is the leader's thrust, not a turn, and would fling the far slots.
const MAX_PATH_RATE_RAD_S: float = 0.35
const FEED_FORWARD_FULL_MPS: float = 30.0
## A friendly ship nearer than this is pushed off, m, at up to this speed, m/s; the moment a stop short of one takes to start, s.
const SEPARATION_M: float = 50.0
const SEPARATION_MPS: float = 40.0
const SETTLE_S: float = 1.0
## Coming round the leader: how far round the aim leads, where it is round, rad; how far out against the slot's distance it
## still comes round; how far off a burning leader's way it aims, m, and the burn that counts, m/s^2.
const SWING_STEP_RAD: float = 0.785
const SWING_DONE_RAD: float = 0.35
const SWING_REACH: float = 3.0
const SWING_CLEAR_M: float = 50.0
const SWING_BURN_MPS2: float = 8.0
## A ship in its slot turns its guns on a hostile this far off its leader's nose at most.
const FIRE_ARC_DEG: float = 40.0

## The closure cap beyond `FAR_RANGE_M`: the profile's cruise + `FAR_EXTRA_MPS`.
var far_closure_mps: float = 200.0
## Distance from the slot (from the leader on the link) at the last `think`, m; -1 before it.
var slot_error_m: float = -1.0

## The pilot's attack behaviour, whose fire gate and aim error a shot from the slot uses (`AiPilot.add_behaviour` sets it);
## null for a pilot that never attacks.
var gunner: BehaviourAttack = null
## Whether the trigger is held from the slot, and whether the ship is stopped under the order to hold position.
var firing: bool = false
var holding: bool = false

var _on_link: bool = false
# The hostile the nose follows from the slot (0 none).
var _fire_target_id: int = 0
# The axis the ship comes round its leader about, kept until it is round (`_swinging`).
var _swing_axis: Vector3 = Vector3.ZERO
var _swinging: bool = false
# The leader's velocity at the last `think` (and when, and whose), to estimate its acceleration on the next one.
var _last_leader_id: int = 0
var _last_leader_velocity: Vector3 = Vector3.ZERO
var _last_s: float = -INF
# A velocity change pointing within the retros' cone of the way the ship wants to go is a slow-down: the retros do it.
var _cos_slow_down: float = cos(deg_to_rad(180.0 - PilotSteering.RETRO_CONE_DEG))
var _max_lean_rad: float = deg_to_rad(MAX_LEAN_DEG)


func _init(profile: AiProfile) -> void:
	id = &"formation"
	far_closure_mps = profile.cruise_mps + FAR_EXTRA_MPS


func reset() -> void:
	slot_error_m = -1.0
	_on_link = false
	_last_leader_id = 0
	_last_s = -INF
	_swinging = false
	_fire_target_id = 0
	firing = false
	holding = false


func enter() -> void:
	_last_s = -INF  # the leader's acceleration needs two consecutive ticks


func score(ctx: AiContext) -> float:
	if ctx.order == AiContext.Order.HOLD_POSITION:
		return SCORE  # no leader needed: the ship stops where it is
	if not ctx.has_slot or (ctx.leader == null and ctx.leader_link_position == null):
		return 0.0
	return STAND_BY_SCORE if ctx.has_attackable() else SCORE


func think(ctx: AiContext, dt: float) -> PilotCommand:
	var p: Perception = ctx.perception
	var cmd := PilotCommand.new()
	var leader: Contact = ctx.leader
	var slot: Vector3
	var slot_velocity: Vector3
	var slot_accel := Vector3.ZERO
	var leader_accel := Vector3.ZERO
	_on_link = false
	_fire_target_id = 0
	firing = false
	holding = ctx.order == AiContext.Order.HOLD_POSITION
	if holding:
		cmd.flight.brake = true  # the brake stops the ship against the reference and keeps it there
		return cmd
	if leader != null:
		slot = Formation.slot_point(leader.position, leader.forward, leader.up, ctx.slot_offset)
		slot_velocity = leader.velocity
		# In a turn the slot swings round with the leader's flight path: the leader's acceleration (from its velocity a
		# tick ago) gives the path's turn rate w = v x a / |v|^2, and the slot moves at v + w x arm and accelerates at
		# a + w x (w x arm). Not the nose's spin: a nose swinging onto or off a lead over the flight path is a transient,
		# and chasing it overspeeds the member for the rest of the turn.
		var since: float = p.now_s - _last_s
		var speed_sq: float = leader.velocity.length_squared()
		if leader.id == _last_leader_id and dt > 0.0 and absf(since - dt) < 0.5 * dt and speed_sq > 1.0:
			leader_accel = (leader.velocity - _last_leader_velocity) / since
			var path_rate: Vector3 = (leader.velocity.cross(leader_accel) / speed_sq).limit_length(MAX_PATH_RATE_RAD_S)
			path_rate *= minf(1.0, sqrt(speed_sq) / FEED_FORWARD_FULL_MPS)
			var arm: Vector3 = slot - leader.position
			slot_velocity += path_rate.cross(arm)
			slot_accel = leader_accel + path_rate.cross(path_rate.cross(arm))
		_last_leader_id = leader.id
		_last_leader_velocity = leader.velocity
		_last_s = p.now_s
	elif ctx.leader_link_position != null:
		_on_link = true
		slot = p.to_local(ctx.leader_link_position)
		slot_velocity = ctx.leader_link_velocity
	else:
		return cmd  # nobody to fly with (it scored 0, so this is not reached in play)
	var to_slot: Vector3 = slot - p.position
	slot_error_m = to_slot.length()
	var aim: Vector3 = slot
	if leader != null:
		var swung: Variant = _swing(leader.position, leader.forward, leader.up, p.position, slot)
		aim = _clear_of_burn(leader.position, leader_accel, leader.up, swung if swung != null else slot)
	var error: Vector3 = (aim - p.position) + (slot_velocity - p.velocity) * LEAD_S
	var cap: float = NEAR_CLOSURE_MPS if slot_error_m <= FAR_RANGE_M else far_closure_mps
	var v_des: Vector3 = slot_velocity + (error * K_PER_S).limit_length(cap) + slot_accel * PilotSteering.HORIZON_S
	v_des = _kept_apart(p, v_des)
	var rate: Vector3 = p.capability.rate_max_rad
	if leader != null and slot_error_m <= ALIGN_RANGE_M:
		# The leader's nose, leant toward the acceleration the wish asks for when the RCS alone cannot give its sideways part.
		var a_need: Vector3 = (v_des - p.velocity) / PilotSteering.HORIZON_S
		var nose: Vector3 = PilotSteering.lean_toward(leader.forward, a_need, minf(p.capability.a_rcs.x, p.capability.a_rcs.y),
				_max_lean_rad)
		var shot: Variant = _shot(ctx, leader.forward)
		var rot: Vector3 = PilotSteering.face(p.basis, shot as Vector3 if shot != null else nose, rate)
		rot.z = PilotSteering.align_roll(p.basis, leader.up, rate)
		cmd.flight.rot = rot
		seek_velocity(cmd.flight, p, v_des, true)  # the nose is the leader's: every axis works at once
		cmd.combat.fire = firing
	else:
		cmd.flight.rot = PilotSteering.face(p.basis, _heading(p.velocity, v_des, leader), rate)
		seek_velocity(cmd.flight, p, v_des)
	return cmd


func target_id() -> int:
	return _fire_target_id if _fire_target_id != 0 else PilotBrain.TARGET_NONE


# Where the nose goes for a shot from the slot (see the class notes), or null with no hostile in reach and in the arc
# about the leader's nose `forward`; `firing` says whether the trigger is held.
func _shot(ctx: AiContext, forward: Vector3) -> Variant:
	if gunner == null or gunner._passive or ctx.holds_fire():
		return null
	var p: Perception = ctx.perception
	var tactics: RaiderTactics = gunner.brain.tactics
	var cos_arc: float = cos(deg_to_rad(FIRE_ARC_DEG))
	var best: int = -1
	var best_m: float = INF
	for i: int in ctx.hostiles.size():
		var range_m: float = ctx.hostile_ranges[i]
		if range_m < 1e-3 or range_m >= tactics.fire_range_m or range_m >= best_m:
			continue
		if ctx.hostile_offsets[i].dot(forward) < range_m * cos_arc:
			continue
		best = i
		best_m = range_m
	if best < 0:
		return null
	var c: Contact = ctx.hostiles[best]
	var lead: Dictionary = InterceptMath.solve(p.position + p.muzzle_offset, p.velocity, c.position, c.velocity,
			p.muzzle_speed_mps, p.weapon_lifetime_s)
	var lead_dir: Vector3 = (lead["aim_dir"] as Vector3) if bool(lead["ok"]) else ctx.hostile_offsets[best] / best_m
	var aim: Vector2 = gunner.aim_offset_at(p.now_s)
	if aim != Vector2.ZERO:
		var right: Vector3 = lead_dir.cross(Vector3.UP if absf(lead_dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
		lead_dir = (lead_dir + right * tan(aim.x) + right.cross(lead_dir) * tan(aim.y)).normalized()
	var cone_deg: float = minf(tactics.fire_cone_deg, rad_to_deg(atan(tactics.fire_miss_m / best_m)))
	_fire_target_id = c.id
	firing = rad_to_deg(PilotSteering.angle_to(p.basis, lead_dir)) < cone_deg and FireLane.clear_seen(p, p.forward(), best_m, c.id)
	return lead_dir


func describe() -> Dictionary:
	if holding:
		return {"state": "holding"}
	var state: String = "in slot"
	if slot_error_m < 0.0 or slot_error_m > ALIGN_RANGE_M:
		state = "joining"
	elif slot_error_m > IN_SLOT_M:
		state = "closing"
	if _on_link:
		state = "joining (link)"
	return {"state": state, "slot_error_m": snappedf(slot_error_m, 0.1)}


# The point to fly for instead of `slot` while it lies across the leader at `leader_at` (`forward`, `up` its nose and top),
# a step at a time round the leader at the ship's own distance; null when it is not across.
func _swing(leader_at: Vector3, forward: Vector3, up: Vector3, own: Vector3, slot: Vector3) -> Variant:
	var rel_own: Vector3 = own - leader_at
	var rel_slot: Vector3 = slot - leader_at
	var r_own: float = rel_own.length()
	var r_slot: float = rel_slot.length()
	if r_own < 1.0 or r_slot < 1.0 or r_own > SWING_REACH * r_slot + SWING_CLEAR_M:
		_swinging = false
		return null
	if not _swinging:
		if rel_own.dot(rel_slot) >= 0.0:
			return null
		var over: Vector3 = -up if rel_own.dot(forward.cross(up)) > 0.0 else up
		var turn: Vector3 = rel_own.cross(over)
		_swing_axis = turn.normalized() if turn.length() > 0.1 * r_own else rel_own.cross(rel_slot).normalized()
		_swinging = true
	var axis: Vector3 = _swing_axis
	var a_own: float = rel_own.dot(axis)
	var a_slot: float = rel_slot.dot(axis)
	var flat_own: Vector3 = rel_own - axis * a_own
	var flat_slot: Vector3 = rel_slot - axis * a_slot
	var f_own: float = flat_own.length()
	var f_slot: float = flat_slot.length()
	var angle: float = atan2(flat_own.cross(flat_slot).dot(axis), flat_own.dot(flat_slot))
	if angle < 0.0:
		angle += TAU
	if f_own < 1.0 or angle < SWING_DONE_RAD or angle > TAU - SWING_DONE_RAD:
		_swinging = false
		return null
	var step: float = minf(angle, SWING_STEP_RAD)
	var k: float = step / angle
	var out: Vector3 = (flat_own / f_own).rotated(axis, step)
	return leader_at + (out * (f_own + (f_slot - f_own) * k) + axis * (a_own + (a_slot - a_own) * k))


# `aim` moved off the line the leader at `leader_at` comes along while it burns toward the ship, to `SWING_CLEAR_M`.
static func _clear_of_burn(leader_at: Vector3, leader_accel: Vector3, up: Vector3, aim: Vector3) -> Vector3:
	var burn: float = leader_accel.length()
	if burn <= SWING_BURN_MPS2:
		return aim
	var a_dir: Vector3 = leader_accel / burn
	var rel: Vector3 = aim - leader_at
	var along: float = rel.dot(a_dir)
	var lateral: Vector3 = rel - a_dir * along
	var wide: float = lateral.length()
	if along <= 0.0 or wide >= SWING_CLEAR_M:
		return aim
	var side: Vector3 = lateral / wide if wide > 1.0 else (up - a_dir * up.dot(a_dir)).normalized()
	return leader_at + (a_dir * along + side * SWING_CLEAR_M)


## `_kept_apart` for another behaviour that brings a ship back into its wing (M8-T06: an evasion on its leash).
static func keep_apart(p: Perception, v_des: Vector3) -> Vector3:
	return _kept_apart(p, v_des)


# `v_des` kept off every friendly ship: one the ship is closing on within the room it needs to stop (a settle, then the
# side thrusters) is a wall the wish may not close on, and one nearer than `SEPARATION_M` is pushed off.
static func _kept_apart(p: Perception, v_des: Vector3) -> Vector3:
	var a_stop: float = maxf(minf(p.capability.a_rcs.x, p.capability.a_rcs.y), 0.01)
	var out: Vector3 = v_des
	for c: Contact in p.contacts:
		if not c.is_ship or c.relation != Factions.Relation.FRIENDLY:
			continue
		var off: Vector3 = p.position - c.position
		var d: float = off.length()
		if d < 1e-3:
			continue
		var away: Vector3 = off / d
		var closing_now: float = maxf(-(p.velocity - c.velocity).dot(away), 0.0)
		if d >= SEPARATION_M + closing_now * SETTLE_S + closing_now * closing_now / (2.0 * a_stop):
			continue
		var into: float = -(out - c.velocity).dot(away)
		if into > 0.0:
			out += away * into
		if d < SEPARATION_M:
			out += away * ((SEPARATION_M - d) / SEPARATION_M * SEPARATION_MPS)
	return out


# Where the nose goes away from the slot: toward the velocity change when it is big and not a slow-down along the way,
# else along the desired velocity (or the leader's nose when that is nearly zero).
func _heading(velocity: Vector3, v_des: Vector3, leader: Contact) -> Vector3:
	var dv: Vector3 = v_des - velocity
	var dv_len: float = dv.length()
	if v_des.length_squared() < 1.0:
		if dv_len > FACE_DV_MPS:
			return dv
		return leader.forward if leader != null else Vector3.ZERO
	var along: Vector3 = v_des.normalized()
	if dv_len > FACE_DV_MPS and dv.dot(along) > -_cos_slow_down * dv_len:
		return dv
	return v_des
