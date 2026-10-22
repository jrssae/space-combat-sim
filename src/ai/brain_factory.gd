class_name BrainFactory
extends RefCounted
## Scenario `behaviour` dictionary -> `PilotBrain` (architecture §15.8). Pure; waypoints in the dictionary are metres
## relative to an `anchor` universe position (the spawn point), so a scenario stays valid wherever it is placed.
##
##     {"type": "idle", "hold": false}
##     {"type": "patrol", "waypoints": [[x, y, z], ...], "cruise_mps": 80}
##     {"type": "attack"}
##     {"type": "aggro", "waypoints": [...], "cruise_mps": 80, "aggro_range_m": 1500}
##
## Returns `{"ok": bool, "error": String, "brain": PilotBrain}`; the error names the offending key
## (`behaviour.waypoints[1]: ...`) so a scenario loader can report it with its own prefix.

const BEHAVIOURS: Array[StringName] = [&"idle", &"patrol", &"attack", &"aggro"]
const DEFAULT_TACTICS_PATH: String = "res://assets/ai/raider_tactics.tres"
const DEFAULT_CRUISE_MPS: float = 80.0
const DEFAULT_AGGRO_RANGE_M: float = 1500.0


static func from_behaviour(data: Variant, anchor: UniversePos, seed_value: int, tactics: RaiderTactics = null) -> Dictionary:
	if not (data is Dictionary):
		return _fail("behaviour must be an object")
	var spec: Dictionary = data
	var type: StringName = StringName(str(spec.get("type", "")))
	if not BEHAVIOURS.has(type):
		return _fail("behaviour.type must be one of %s, got '%s'" % [", ".join(BEHAVIOURS), str(spec.get("type", ""))])
	var tac: RaiderTactics = tactics if tactics != null else load(DEFAULT_TACTICS_PATH) as RaiderTactics
	match type:
		&"idle":
			return _ok(IdleBrain.new(bool(spec.get("hold", false))))
		&"attack":
			return _ok(AttackBrain.new(tac, seed_value))
	var patrol: Dictionary = _patrol(spec, anchor)
	if not bool(patrol["ok"]):
		return patrol
	if type == &"patrol":
		return patrol
	var aggro_range: Variant = spec.get("aggro_range_m", DEFAULT_AGGRO_RANGE_M)
	if not _is_number(aggro_range) or float(aggro_range) <= 0.0:
		return _fail("behaviour.aggro_range_m must be a number above 0")
	return _ok(AggroBrain.new(patrol["brain"] as PatrolBrain, AttackBrain.new(tac, seed_value), float(aggro_range)))


static func _patrol(spec: Dictionary, anchor: UniversePos) -> Dictionary:
	var list: Variant = spec.get("waypoints")
	if not (list is Array) or (list as Array).size() < 2:
		return _fail("behaviour.waypoints must be an array of at least two [x, y, z]")
	var points: Array[UniversePos] = []
	for i: int in (list as Array).size():
		var entry: Variant = (list as Array)[i]
		if not (entry is Array) or (entry as Array).size() != 3:
			return _fail("behaviour.waypoints[%d] must be [x, y, z]" % i)
		for v: Variant in entry as Array:
			if not _is_number(v):
				return _fail("behaviour.waypoints[%d] must hold numbers" % i)
		var a: Array = entry
		points.append(UniversePos.new(anchor.x + float(a[0]), anchor.y + float(a[1]), anchor.z + float(a[2]), anchor.system_id))
	var cruise: Variant = spec.get("cruise_mps", DEFAULT_CRUISE_MPS)
	if not _is_number(cruise) or float(cruise) <= 0.0:
		return _fail("behaviour.cruise_mps must be a number above 0")
	return _ok(PatrolBrain.new(points, float(cruise)))


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT


static func _ok(brain: PilotBrain) -> Dictionary:
	return {"ok": true, "error": "", "brain": brain}


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message, "brain": null}
