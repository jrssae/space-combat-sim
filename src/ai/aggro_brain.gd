class_name AggroBrain
extends PilotBrain
## Patrols until a hostile comes within `aggro_range_m` or the hull drops below full, then attacks for good (architecture
## §15.8). Wraps a `PatrolBrain` and an `AttackBrain`.

var patrol: PatrolBrain = null
var attack: AttackBrain = null
var aggro_range_m: float = 1500.0
var aggroed: bool = false


func _init(p_patrol: PatrolBrain = null, p_attack: AttackBrain = null, p_aggro_range_m: float = 1500.0) -> void:
	patrol = p_patrol if p_patrol != null else PatrolBrain.new()
	attack = p_attack if p_attack != null else AttackBrain.new()
	aggro_range_m = p_aggro_range_m


func think(p: Perception, dt: float) -> PilotCommand:
	if not aggroed:
		if p.hull_fraction < 1.0 - 1e-6:
			aggroed = true
		elif p.target != null and p.target_hostile and p.target.position.distance_to(p.position) <= aggro_range_m:
			aggroed = true
	var inner: PilotBrain = attack if aggroed else patrol
	inner.has_desired_velocity = false
	var cmd: PilotCommand = inner.think(p, dt)
	desired_velocity = inner.desired_velocity
	has_desired_velocity = inner.has_desired_velocity
	return cmd


func describe() -> Dictionary:
	var inner: Dictionary = attack.describe() if aggroed else patrol.describe()
	return {"behaviour": "aggro", "state": "attack: %s" % inner["state"] if aggroed else "patrol: %s" % inner["state"]}


func reset() -> void:
	aggroed = false
	patrol.reset()
	attack.reset()
