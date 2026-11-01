class_name BehaviourRam
extends AiBehaviour
## The last-ditch ram (architecture §16 D34, M3-T13, maintainer Q12): a reckless pilot that is losing flies into the enemy.
##
## Eligible only at aggression 1 (`AiTemperament.may_ram`), with its hull under `HULL_BELOW`, and with at most a quarter of the
## most friendly ships it has seen in sensor range this life still there (none counts: a ship alone is eligible). While it is
## eligible a seeded roll every `ROLL_EVERY_S` commits it with `COMMIT_CHANCE`. A committed rammer takes the target it was
## attacking (`AiContext.current_target_id`) or else the nearest hostile ship (never a prop), flies a collision course on it
## (its velocity plus `CLOSURE_MPS` along the line of sight, the mains and the RCS together), and has the driver leave that one
## contact out of avoidance (`PilotBrain.avoid_exempt_id`; every other contact is still avoided). It stays committed until the
## target is gone from sight (destroyed), then normal selection resumes. `RamResolver` (M3-T04) does the damage.
##
## Score: 1 while committed (it outranks everything; the hit reaction does not interrupt it), else 0. Below reckless the score
## returns at once, so the other pilots pay one comparison for it (AC13's paired budget).

const HULL_BELOW: float = 0.25
const ALLIES_LEFT_SHARE: float = 0.25
const ROLL_EVERY_S: float = 5.0
const COMMIT_CHANCE: float = 0.35
const CLOSURE_MPS: float = 200.0

var committed: bool = false
var target_id_value: int = 0
## Rolls made and how many friendly ships it has seen at most (the tests and the console).
var rolls: int = 0
var max_friends_seen: int = 0

var _may_ram: bool = false
var _seed: int = 0
var _rng := RandomNumberGenerator.new()
var _eligible_since_s: float = -INF
var _target: Contact = null


func _init(p_seed: int = 0) -> void:
	id = &"ram"
	_seed = p_seed
	reset()


func retune(_profile: AiProfile, temperament: AiTemperament) -> void:
	_may_ram = temperament.may_ram()
	if not _may_ram:
		committed = false


func reset() -> void:
	_rng.seed = _seed
	committed = false
	target_id_value = 0
	rolls = 0
	max_friends_seen = 0
	_eligible_since_s = -INF
	_target = null


func score(ctx: AiContext) -> float:
	if not _may_ram:
		return 0.0
	var p: Perception = ctx.perception
	if committed:
		_target = _hostile(ctx, target_id_value)
		if _target == null:
			committed = false  # the target is down: back to normal selection
			target_id_value = 0
			_eligible_since_s = -INF
			return 0.0
		return 1.0
	var friends: int = 0
	for c: Contact in p.contacts:
		if c.is_ship and c.relation == Factions.Relation.FRIENDLY:
			friends += 1
	max_friends_seen = maxi(max_friends_seen, friends)
	var eligible: bool = p.hull_fraction < HULL_BELOW and float(friends) <= ALLIES_LEFT_SHARE * float(max_friends_seen) \
			and not ctx.hostiles.is_empty()
	if not eligible:
		_eligible_since_s = -INF
		return 0.0
	if _eligible_since_s == -INF:
		_eligible_since_s = p.now_s - ROLL_EVERY_S  # the first roll at once
	while p.now_s - _eligible_since_s >= ROLL_EVERY_S:
		_eligible_since_s += ROLL_EVERY_S
		rolls += 1
		if _rng.randf() < COMMIT_CHANCE:
			commit(ctx)
			break
	return 1.0 if committed else 0.0


## Commits to a ram now (the roll came up; tests call it directly): the attack's target, else the nearest hostile ship.
func commit(ctx: AiContext) -> bool:
	var pick: Contact = _hostile(ctx, ctx.current_target_id)
	if pick == null:
		var best: float = INF
		for i: int in ctx.hostiles.size():
			if ctx.hostile_ranges[i] < best:
				best = ctx.hostile_ranges[i]
				pick = ctx.hostiles[i]
	if pick == null:
		return false
	committed = true
	target_id_value = pick.id
	_target = pick
	return true


func think(ctx: AiContext, _dt: float) -> PilotCommand:
	var p: Perception = ctx.perception
	var cmd := PilotCommand.new()
	if _target == null:
		return cmd
	var los: Vector3 = _target.position - p.position
	var los_dir: Vector3 = los.normalized() if los.length() > 1e-3 else p.forward()
	var v_des: Vector3 = _target.velocity + los_dir * CLOSURE_MPS
	var dv: Vector3 = v_des - p.velocity
	cmd.flight.rot = PilotSteering.face(p.basis, dv if dv.length() > 5.0 else los_dir, p.capability.rate_max_rad)
	seek_velocity(cmd.flight, p, v_des, true)
	return cmd


func target_id() -> int:
	return target_id_value if committed else PilotBrain.TARGET_NONE


func describe() -> Dictionary:
	return {"state": "committed" if committed else "not committed", "target": _target.name if committed and _target != null else "",
			"rolls": rolls}


static func _hostile(ctx: AiContext, wanted: int) -> Contact:
	if wanted == 0:
		return null
	for c: Contact in ctx.hostiles:
		if c.id == wanted:
			return c
	return null
