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

## The closure cap beyond `FAR_RANGE_M`: the profile's cruise + `FAR_EXTRA_MPS`.
var far_closure_mps: float = 200.0
## Distance from the slot (from the leader on the link) at the last `think`, m; -1 before it.
var slot_error_m: float = -1.0

var _on_link: bool = false
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


func enter() -> void:
	_last_s = -INF  # the leader's acceleration needs two consecutive ticks


func score(ctx: AiContext) -> float:
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
	_on_link = false
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
			var leader_accel: Vector3 = (leader.velocity - _last_leader_velocity) / since
			var path_rate: Vector3 = leader.velocity.cross(leader_accel) / speed_sq
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
	var error: Vector3 = to_slot + (slot_velocity - p.velocity) * LEAD_S
	var cap: float = NEAR_CLOSURE_MPS if slot_error_m <= FAR_RANGE_M else far_closure_mps
	var v_des: Vector3 = slot_velocity + (error * K_PER_S).limit_length(cap) + slot_accel * PilotSteering.HORIZON_S
	var rate: Vector3 = p.capability.rate_max_rad
	if leader != null and slot_error_m <= ALIGN_RANGE_M:
		# The leader's nose, leant toward the acceleration the wish asks for when the RCS alone cannot give its sideways part.
		var a_need: Vector3 = (v_des - p.velocity) / PilotSteering.HORIZON_S
		var nose: Vector3 = PilotSteering.lean_toward(leader.forward, a_need, minf(p.capability.a_rcs.x, p.capability.a_rcs.y),
				_max_lean_rad)
		var rot: Vector3 = PilotSteering.face(p.basis, nose, rate)
		rot.z = PilotSteering.align_roll(p.basis, leader.up, rate)
		cmd.flight.rot = rot
		seek_velocity(cmd.flight, p, v_des, true)  # the nose is the leader's: every axis works at once
	else:
		cmd.flight.rot = PilotSteering.face(p.basis, _heading(p.velocity, v_des, leader), rate)
		seek_velocity(cmd.flight, p, v_des)
	return cmd


func describe() -> Dictionary:
	var state: String = "in slot"
	if slot_error_m < 0.0 or slot_error_m > ALIGN_RANGE_M:
		state = "joining"
	elif slot_error_m > IN_SLOT_M:
		state = "closing"
	if _on_link:
		state = "joining (link)"
	return {"state": state, "slot_error_m": snappedf(slot_error_m, 0.1)}


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
