class_name BehaviourAttack
extends AiBehaviour
## Gun runs (architecture §16 D34): M2's `AttackBrain` state machine (approach, fire, break, extend) with the profile's
## tactics, on a target this behaviour chooses, with the profile's aim error.
##
## Target choice, every tick among the hostile ships the orders allow (`AiContext.may_attack`; under ATTACK MY TARGET that
## is the leader's target alone): the best of `W_NEAR` x nearness (1 at zero range, 0 at sensor range), `W_CLOSING` x the
## closing speed (full at `CLOSING_FULL_MPS`), `W_ATTACKING_FRIEND` when its selected target is this ship or a friend, and
## `W_DAMAGED` x its missing hull; the current target gets `KEEP_BONUS` so the choice does not flicker. A new target
## restarts the run (APPROACH).
##
## Score: 0 without an allowed target, else `SCORE_BASE + SCORE_SPAN` x the best target's value (0.3..0.8), so a tail threat
## (evade) or a retreat outranks it.
##
## Aim: `AiProfile.aim_error_deg` is the amplitude of a slowly wandering offset on the lead (two seeded sines per axis, 0.05
## to 0.35 Hz, in this behaviour's own time), so a pilot's misses are correlated over seconds, not noise from tick to tick.

const W_NEAR: float = 0.4
const W_CLOSING: float = 0.2
const W_ATTACKING_FRIEND: float = 0.3
const W_DAMAGED: float = 0.1
const KEEP_BONUS: float = 0.1
const CLOSING_FULL_MPS: float = 200.0
const SCORE_BASE: float = 0.3
const SCORE_SPAN: float = 0.5
const INV_SENSOR_RANGE: float = 1.0 / ContactScan.SENSOR_RANGE_M

var brain: AttackBrain = null
## Radians: the aim wander's amplitude per axis.
var aim_error_rad: float = 0.0

var _seed: int = 0
var _target: Contact = null
var _engaged_id: int = 0
var _time_s: float = 0.0
## Per axis (x right, y up): two frequencies (Hz) and two phases (rad).
var _wander: PackedFloat64Array = PackedFloat64Array()


func _init(profile: AiProfile, p_seed: int = 0) -> void:
	id = &"attack"
	_seed = p_seed
	brain = AttackBrain.new(profile.tactics, hash([p_seed, "attack brain"]))
	aim_error_rad = deg_to_rad(profile.aim_error_deg)
	reset()


func reset() -> void:
	brain.reset()
	_target = null
	_engaged_id = 0
	_time_s = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_seed, "aim"])
	_wander = PackedFloat64Array()
	for axis: int in 2:
		_wander.append_array([rng.randf_range(0.05, 0.15), rng.randf_range(0.15, 0.35), rng.randf_range(0.0, TAU),
				rng.randf_range(0.0, TAU)])


func score(ctx: AiContext) -> float:
	var p: Perception = ctx.perception
	var keep_id: int = _target.id if _target != null else _engaged_id
	_target = null
	var best: float = -INF
	var at_will: bool = ctx.order == AiContext.Order.ENGAGE_AT_WILL  # every hostile ship: skip the per-contact check
	var own_velocity: Vector3 = p.velocity
	var friendly_ids: PackedInt64Array = ctx.friendly_ids
	var hostiles: Array[Contact] = ctx.hostiles
	for i: int in hostiles.size():
		var c: Contact = hostiles[i]
		if not at_will and not ctx.may_attack(c):
			continue
		var los: Vector3 = ctx.hostile_offsets[i]
		var d: float = ctx.hostile_ranges[i]
		var value: float = W_NEAR * clampf(1.0 - d * INV_SENSOR_RANGE, 0.0, 1.0)
		if d > 1e-3:
			value += W_CLOSING * clampf((own_velocity - c.velocity).dot(los) / (d * CLOSING_FULL_MPS), 0.0, 1.0)
		if friendly_ids.has(c.target_id):
			value += W_ATTACKING_FRIEND
		var hull: float = c.hull_fraction
		if hull >= 0.0:
			value += W_DAMAGED * (1.0 - hull)
		if c.id == keep_id:
			value += KEEP_BONUS
		if value > best:
			best = value
			_target = c
	if _target == null:
		return 0.0
	return clampf(SCORE_BASE + SCORE_SPAN * best, 0.0, 1.0)


func enter() -> void:
	_engaged_id = 0  # the first think restarts the run on whatever target it has


func think(ctx: AiContext, dt: float) -> PilotCommand:
	if _target == null:
		brain.firing = false
		return PilotCommand.new()  # nothing allowed to attack: hold course
	if _target.id != _engaged_id:
		_engaged_id = _target.id
		brain.restart()
	_time_s += dt
	brain.aim_offset_rad = aim_offset_at(_time_s)
	brain.has_desired_velocity = false
	var cmd: PilotCommand = brain.engage(ctx.perception, _target.id, _target.position, _target.velocity, dt)
	desired_velocity = brain.desired_velocity
	has_desired_velocity = brain.has_desired_velocity
	return cmd


func target_id() -> int:
	return _target.id if _target != null else PilotBrain.TARGET_NONE


## The aim offset (radians, right and up) at `t_s` of this behaviour's time: each axis within `aim_error_rad`.
func aim_offset_at(t_s: float) -> Vector2:
	if aim_error_rad <= 0.0:
		return Vector2.ZERO
	var out := Vector2.ZERO
	for axis: int in 2:
		var k: int = axis * 4
		out[axis] = aim_error_rad * (0.6 * sin(TAU * _wander[k] * t_s + _wander[k + 2])
				+ 0.4 * sin(TAU * _wander[k + 1] * t_s + _wander[k + 3]))
	return out


func describe() -> Dictionary:
	if _target == null:
		return {"state": "no target"}
	var inner: Dictionary = brain.describe()
	return {"state": inner["state"], "target": _target.name, "range_m": inner["range_m"], "firing": brain.firing}
