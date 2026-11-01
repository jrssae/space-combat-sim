class_name BehaviourGuard
extends AiBehaviour
## Hold a post (architecture §16 D34, M3-T10): a fixed point (`AiContext.guard_post`, a `UniversePos`) or a ship's slot (the
## ship `AiContext.guard_name` plus `guard_offset` in its body frame). The context does the gating: while a pilot guards,
## `AiContext.may_attack` allows only hostiles inside `guard_radius_m` (1 500 m) of the post or attacking the guarded ship,
## so the attack behaviour engages those and lets go of a hostile that leaves the zone. This behaviour flies back to the
## post and keeps station there.
##
## Score: 0 while the pilot has no post this tick (none set, or the guarded ship out of sight). Otherwise `SCORE` (beats
## idle by more than the stickiness) while nothing in sight may be attacked, and `STAND_BY_SCORE` while something may, so
## the attack (0.3 or more) takes over; evade and retreat outrank it either way.
##
## Station keeping: v_des = v_post + the error times `K_PER_S`, its closure capped at `NEAR_CLOSURE_MPS` within
## `NEAR_RANGE_M` of the post and at the profile's cruise beyond (the formation's loop without the leader's attitude). The
## nose turns toward the velocity change while it is over `FACE_DV_MPS`, else holds.
##
## Only pilots given a post have this behaviour (`attach`), so the others pay nothing for it (AC13's paired budget).

const SCORE: float = 0.25
const STAND_BY_SCORE: float = 0.1
const DEFAULT_RADIUS_M: float = 1500.0
const K_PER_S: float = 0.4
const NEAR_RANGE_M: float = 300.0
const NEAR_CLOSURE_MPS: float = 40.0
const FACE_DV_MPS: float = 20.0
## `describe` calls a ship this close to its post "on post".
const ON_POST_M: float = 50.0

var cruise_mps: float = 100.0
## Distance from the post at the last `think`, m; -1 before it.
var post_error_m: float = -1.0


func _init(profile: AiProfile = null) -> void:
	id = &"guard"
	if profile != null:
		cruise_mps = profile.cruise_mps


## Gives `pilot` a fixed post (`post`, a universe position) or a ship to guard (`ship_name`, with `offset` in its body
## frame), `radius_m` round it, and adds this behaviour once. Returns the behaviour.
static func attach(pilot: AiPilot, post: UniversePos, ship_name: String = "", offset: Vector3 = Vector3.ZERO,
		radius_m: float = DEFAULT_RADIUS_M) -> BehaviourGuard:
	pilot.context.guard_post = post
	pilot.context.guard_name = ship_name
	pilot.context.guard_offset = offset
	pilot.context.guard_radius_m = radius_m
	var b := pilot.behaviour(&"guard") as BehaviourGuard
	if b == null:
		b = BehaviourGuard.new(pilot.profile)
		pilot.add_behaviour(b)
	return b


func score(ctx: AiContext) -> float:
	if not ctx.guarding:
		return 0.0
	return STAND_BY_SCORE if ctx.has_attackable() else SCORE


func think(ctx: AiContext, _dt: float) -> PilotCommand:
	var p: Perception = ctx.perception
	var cmd := PilotCommand.new()
	var error: Vector3 = ctx.guard_point - p.position
	post_error_m = error.length()
	var cap: float = NEAR_CLOSURE_MPS if post_error_m <= NEAR_RANGE_M else cruise_mps
	var closure: Vector3 = error * K_PER_S
	if closure.length() > cap:
		closure = closure.normalized() * cap
	var v_des: Vector3 = ctx.guard_velocity + closure
	var dv: Vector3 = v_des - p.velocity
	if dv.length() > FACE_DV_MPS:
		cmd.flight.rot = PilotSteering.face(p.basis, dv, p.capability.rate_max_rad)
	seek_velocity(cmd.flight, p, v_des)
	return cmd


func describe() -> Dictionary:
	return {"state": "on post" if post_error_m >= 0.0 and post_error_m <= ON_POST_M else "return",
			"post_m": snappedf(post_error_m, 1.0)}


func reset() -> void:
	post_error_m = -1.0
