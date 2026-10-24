class_name BehaviourEvade
extends AiBehaviour
## Get out of the line of fire (architecture §16 D34). Scores:
##
## - a hostile ship within `RANGE_M` in the rear hemisphere with its nose within `NOSE_CONE_DEG` of us: `TAIL_SCORE_MIN` at
##   1.2 km up to 1 point blank (it outranks an attack);
## - `Perception.incoming_fire` (hostile bolts about to pass within 15 m): `INCOMING_SCORE`;
## - a hit in the last `HIT_MEMORY_S`: `HIT_SCORE`;
## the highest that applies, 0 when none does: the evasion ends when the threat no longer points at us, the bolts have
## passed and the last hit is 2 s old.
##
## The threat is the tail hostile, or else the hostile whose nose points closest at us (the likely shooter). The line of fire
## runs from it to us. Jinks, seeded: a break turn across the line of fire (the nose turned toward the sideways velocity
## change, mains and RCS strafe together), held `JINK_MIN_S`..`JINK_MAX_S`, then a reversal to the other side (turned by up
## to `REVERSAL_SPREAD_DEG` about the line of fire), and so on. Each jink seeks the velocity the ship had when the evasion
## began plus `JINK_SPEED_MPS` across the line of fire: more than a jink can reach, so the thrust stays on for the whole jink
## (a steady acceleration is what spoils a shooter's lead), and the speed stays bounded however long it lasts.

const RANGE_M: float = 1200.0
const NOSE_CONE_DEG: float = 15.0
const HIT_MEMORY_S: float = 2.0
const TAIL_SCORE_MIN: float = 0.75
const INCOMING_SCORE: float = 0.6
const HIT_SCORE: float = 0.5
const JINK_MIN_S: float = 2.0
const JINK_MAX_S: float = 4.0
const JINK_SPEED_MPS: float = 100.0
const REVERSAL_SPREAD_DEG: float = 45.0

## The current jink: the sideways direction (World frame, unit), seconds left, and how many jinks so far this evasion.
var side: Vector3 = Vector3.ZERO
var jink_left_s: float = 0.0
var jinks: int = 0

var _seed: int = 0
var _rng := RandomNumberGenerator.new()
var _cos_cone: float = cos(deg_to_rad(NOSE_CONE_DEG))
var _threat: Contact = null
var _reason: StringName = &""
var _base_velocity: Vector3 = Vector3.ZERO
var _fresh: bool = true


func _init(p_seed: int = 0) -> void:
	id = &"evade"
	_seed = p_seed
	reset()


func reset() -> void:
	_rng.seed = _seed
	side = Vector3.ZERO
	jink_left_s = 0.0
	jinks = 0
	_threat = null
	_reason = &""
	_fresh = true


func score(ctx: AiContext) -> float:
	var p: Perception = ctx.perception
	_threat = null
	_reason = &""
	var best: float = 0.0
	var forward: Vector3 = p.forward()
	for c: Contact in ctx.hostiles:
		var off: Vector3 = p.position - c.position  # from the hostile to us
		var d2: float = off.length_squared()
		if d2 > RANGE_M * RANGE_M or d2 < 1e-6 or forward.dot(off) <= 0.0:
			continue  # too far, or not behind us (behind: we are ahead of it along our own nose)
		var d: float = sqrt(d2)
		if c.forward.dot(off / d) < _cos_cone:
			continue
		var s: float = TAIL_SCORE_MIN + (1.0 - TAIL_SCORE_MIN) * (1.0 - d / RANGE_M)
		if s > best:
			best = s
			_threat = c
			_reason = &"tail"
	if best < INCOMING_SCORE and p.incoming_fire > 0:
		best = INCOMING_SCORE
		_reason = &"fire"
	if best < HIT_SCORE and ctx.seconds_since_hit() < HIT_MEMORY_S:
		best = HIT_SCORE
		_reason = &"hit"
	if best > 0.0 and _threat == null:
		_threat = _likely_shooter(ctx)
	return best


func enter() -> void:
	_fresh = true


func think(ctx: AiContext, dt: float) -> PilotCommand:
	var p: Perception = ctx.perception
	var cmd := PilotCommand.new()
	var line_of_fire: Vector3 = p.forward()
	if _threat != null and _threat.position.distance_squared_to(p.position) > 1e-6:
		line_of_fire = (p.position - _threat.position).normalized()
	if _fresh:
		_fresh = false
		_base_velocity = p.velocity
		jinks = 0
		_new_jink(line_of_fire)
	else:
		jink_left_s -= dt
		if jink_left_s <= 0.0:
			_new_jink(line_of_fire)
	var across: Vector3 = _across(line_of_fire)
	var v_des: Vector3 = _base_velocity + across * JINK_SPEED_MPS
	var dv: Vector3 = v_des - p.velocity
	cmd.flight.rot = PilotSteering.face(p.basis, dv if dv.length() > 1.0 else across, p.capability.rate_max_rad)
	seek_velocity(cmd.flight, p, v_des)
	return cmd


## The threat's name ("" without one), for the console and the tests.
func threat_name() -> String:
	return _threat.name if _threat != null else ""


func describe() -> Dictionary:
	return {"state": "jink %d (%s)" % [jinks, _reason], "threat": threat_name(),
			"jink_left_s": snappedf(jink_left_s, 0.1)}


# The hostile whose nose points closest at us: who is shooting (incoming fire and hits name no shooter).
func _likely_shooter(ctx: AiContext) -> Contact:
	var best: Contact = null
	var best_dot: float = -INF
	for c: Contact in ctx.hostiles:
		var off: Vector3 = ctx.perception.position - c.position
		if off.length_squared() < 1e-6:
			continue
		var dot: float = c.forward.dot(off.normalized())
		if dot > best_dot:
			best_dot = dot
			best = c
	return best


# The first jink breaks to a seeded side; the next ones reverse, turned by a seeded angle about the line of fire.
func _new_jink(line_of_fire: Vector3) -> void:
	if jinks == 0:
		side = _perpendicular(line_of_fire).rotated(line_of_fire, _rng.randf_range(0.0, TAU))
	else:
		side = (-_across(line_of_fire)).rotated(line_of_fire,
				deg_to_rad(_rng.randf_range(-REVERSAL_SPREAD_DEG, REVERSAL_SPREAD_DEG)))
	jink_left_s = _rng.randf_range(JINK_MIN_S, JINK_MAX_S)
	jinks += 1


# The jink side kept square to the line of fire as the geometry turns.
func _across(line_of_fire: Vector3) -> Vector3:
	var s: Vector3 = side - line_of_fire * side.dot(line_of_fire)
	if s.length_squared() < 0.01:
		return _perpendicular(line_of_fire)
	return s.normalized()


static func _perpendicular(v: Vector3) -> Vector3:
	var helper: Vector3 = Vector3.UP if absf(v.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	return v.cross(helper).normalized()
