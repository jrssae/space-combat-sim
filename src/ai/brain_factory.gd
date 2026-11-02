class_name BrainFactory
extends RefCounted
## Scenario `behaviour` dictionary -> `PilotBrain` (architecture §15.8). Pure; waypoints in the dictionary are metres
## relative to an `anchor` universe position (the spawn point), so a scenario stays valid wherever it is placed.
##
##     {"type": "idle", "hold": false}
##     {"type": "patrol", "waypoints": [[x, y, z], ...], "cruise_mps": 80}
##     {"type": "attack"}
##     {"type": "aggro", "waypoints": [...], "cruise_mps": 80, "aggro_range_m": 1500}
##     {"type": "ai", "profile": "ally_starfury" | "raider" | "instructor", "orders": "engage" | "attack" | "form" | "cover",
##      "skill": "rookie" | "regular" | "veteran" | "ace" | 0-1, "aggression": "passive" | ... | "reckless" | 0-1,
##      "objective": "NAV ALPHA", "guard": {"post": [x, y, z]} | {"ship": "ALPHA 2", "offset": [x, y, z]}, + "radius_m": 1500}
##
## `ai` (M3-T06) is an `AiPilot` with the named `AiProfile` (required), orders (`AiContext.ORDER_WORDS`, default `engage`),
## skill and aggression (M3-T13, default the profile's) and an optional objective (M3-T17), seeded from the seed. `guard`
## (M3-T10) gives it a post: a point relative to the anchor, or a ship by name and a body-frame slot (x right, y up, +z
## behind), with `radius_m` (default 1500). `patrol` (M3-T10) is `{"waypoints": [[x, y, z], ...], "cruise_mps": 80}`
## relative to the anchor, looped, and yields to any attack the orders allow.
##
## Any behaviour may carry `"running_lights": "on" | "off"` (M3-T27, Q27): whether the ship starts lit, or dark until it attacks. By
## default a ship on patrol hides (`patrol`, `aggro`, and `ai` with a `patrol` route); every other starts lit. Pure data, so a scenario
## can change one with no code.
##
## Returns `{"ok": bool, "error": String, "brain": PilotBrain}`; the error names the offending key
## (`behaviour.waypoints[1]: ...`) so a scenario loader can report it with its own prefix.

const BEHAVIOURS: Array[StringName] = [&"idle", &"patrol", &"attack", &"aggro", &"ai"]
const DEFAULT_TACTICS_PATH: String = "res://assets/ai/raider_tactics.tres"
const DEFAULT_CRUISE_MPS: float = 80.0
const DEFAULT_AGGRO_RANGE_M: float = 1500.0


static func from_behaviour(data: Variant, anchor: UniversePos, seed_value: int, tactics: RaiderTactics = null) -> Dictionary:
	var made: Dictionary = _build(data, anchor, seed_value, tactics)
	if not bool(made["ok"]):
		return made
	var spec: Dictionary = data
	var lights: Variant = spec.get("running_lights", "off" if _hides_by_default(spec) else "on")
	if not (lights is String) or (lights != "on" and lights != "off"):
		return _fail("behaviour.running_lights must be on or off, got %s" % JSON.stringify(lights))
	(made["brain"] as PilotBrain).flies_dark = lights == "off"
	return made


# A ship going about a patrol hides.
static func _hides_by_default(spec: Dictionary) -> bool:
	var type: String = str(spec.get("type", ""))
	return type == "patrol" or type == "aggro" or (type == "ai" and spec.has("patrol"))


static func _build(data: Variant, anchor: UniversePos, seed_value: int, tactics: RaiderTactics) -> Dictionary:
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
		&"ai":
			return _ai(spec, seed_value, anchor)
	var patrol: Dictionary = _patrol(spec, anchor)
	if not bool(patrol["ok"]):
		return patrol
	if type == &"patrol":
		return patrol
	var aggro_range: Variant = spec.get("aggro_range_m", DEFAULT_AGGRO_RANGE_M)
	if not _is_number(aggro_range) or float(aggro_range) <= 0.0:
		return _fail("behaviour.aggro_range_m must be a number above 0")
	return _ok(AggroBrain.new(patrol["brain"] as PatrolBrain, AttackBrain.new(tac, seed_value), float(aggro_range)))


static func _ai(spec: Dictionary, seed_value: int, anchor: UniversePos) -> Dictionary:
	var profile_name: Variant = spec.get("profile")
	if not (profile_name is String) or not AiProfile.PATHS.has(StringName(profile_name as String)):
		return _fail("behaviour.profile must be one of %s, got %s" % [", ".join(PackedStringArray(AiProfile.PATHS.keys())),
				JSON.stringify(profile_name)])
	var orders: Variant = spec.get("orders", String(AiContext.order_word(AiContext.Order.ENGAGE_AT_WILL)))
	var order: int = AiContext.order_from_word(orders as String) if orders is String else -1
	if order < 0:
		return _fail("behaviour.orders must be one of %s, got %s" % [", ".join(PackedStringArray(AiContext.ORDER_WORDS)),
				JSON.stringify(orders)])
	var profile: AiProfile = AiProfile.load_named(StringName(profile_name as String))
	var problem: String = profile.validate() if profile != null else "does not load"
	if not problem.is_empty():
		return _fail("behaviour.profile '%s': %s" % [profile_name, problem])
	var objective: Variant = spec.get("objective", "")
	if not (objective is String):
		return _fail("behaviour.objective must be a target's name, got %s" % JSON.stringify(objective))
	var skill: float = AiTemperament.parse_skill(spec.get("skill", profile.skill))
	if skill < 0.0:
		return _fail("behaviour.skill must be one of %s or a number 0-1, got %s" % [", ".join(PackedStringArray(AiTemperament.SKILL_RANKS.keys())),
				JSON.stringify(spec.get("skill"))])
	var aggression: float = AiTemperament.parse_aggression(spec.get("aggression", profile.aggression))
	if aggression < 0.0:
		return _fail("behaviour.aggression must be one of %s or a number 0-1, got %s" % [", ".join(PackedStringArray(AiTemperament.AGGRESSION_LEVELS.keys())),
				JSON.stringify(spec.get("aggression"))])
	var pilot := AiPilot.new(profile, seed_value, [] as Array[AiBehaviour], AiTemperament.new(skill, aggression))
	pilot.context.order = order as AiContext.Order
	pilot.context.objective_name = (objective as String).strip_edges()
	if spec.has("patrol"):
		var patrol: Variant = _ai_patrol(spec["patrol"], anchor)
		if patrol is String:
			return _fail(patrol as String)
		BehaviourFollowPath.attach(pilot, patrol as Route)
	if spec.has("guard"):
		var problem_guard: String = _guard(pilot, spec["guard"], anchor)
		if not problem_guard.is_empty():
			return _fail(problem_guard)
	return _ok(pilot)


# The route an `ai` behaviour's `patrol` describes, or what is wrong with it.
static func _ai_patrol(raw: Variant, anchor: UniversePos) -> Variant:
	if not (raw is Dictionary):
		return "behaviour.patrol must be an object: {\"waypoints\": [[x, y, z], ...], \"cruise_mps\": 80}"
	var list: Variant = (raw as Dictionary).get("waypoints")
	if not (list is Array) or (list as Array).size() < 2:
		return "behaviour.patrol.waypoints must be an array of at least two [x, y, z]"
	var route := Route.new()
	route.name = "PATROL"
	route.pace = Route.PACE_NONE
	route.loop = true
	route.yield_to_attack = true
	for i: int in (list as Array).size():
		var point: Variant = _vector((list as Array)[i])
		if point == null:
			return "behaviour.patrol.waypoints[%d] must be [x, y, z] (numbers)" % i
		route.add(anchor.plus_local(point as Vector3))
	var cruise: Variant = (raw as Dictionary).get("cruise_mps", DEFAULT_CRUISE_MPS)
	if not _is_number(cruise) or float(cruise) <= 0.0:
		return "behaviour.patrol.cruise_mps must be a number above 0"
	route.cruise_mps = float(cruise)
	return route


# Attaches the guard post `raw` describes; "" when valid, else what is wrong.
static func _guard(pilot: AiPilot, raw: Variant, anchor: UniversePos) -> String:
	if not (raw is Dictionary):
		return "behaviour.guard must be an object: {\"post\": [x, y, z]} or {\"ship\": name, \"offset\": [x, y, z]}"
	var guard: Dictionary = raw
	var radius: Variant = guard.get("radius_m", BehaviourGuard.DEFAULT_RADIUS_M)
	if not _is_number(radius) or float(radius) <= 0.0:
		return "behaviour.guard.radius_m must be a number above 0"
	if guard.has("ship"):
		if not (guard["ship"] is String) or (guard["ship"] as String).strip_edges().is_empty():
			return "behaviour.guard.ship must be a ship's name"
		var offset: Variant = _vector(guard.get("offset", [0, 0, 0]))
		if offset == null:
			return "behaviour.guard.offset must be [x, y, z]"
		BehaviourGuard.attach(pilot, null, (guard["ship"] as String).strip_edges(), offset as Vector3, float(radius))
		return ""
	var post: Variant = _vector(guard.get("post"))
	if post == null:
		return "behaviour.guard needs \"post\": [x, y, z] (relative to the spawn's anchor) or \"ship\": a name"
	BehaviourGuard.attach(pilot, anchor.plus_local(post as Vector3), "", Vector3.ZERO, float(radius))
	return ""


# [x, y, z] of numbers as a Vector3, else null.
static func _vector(raw: Variant) -> Variant:
	if not (raw is Array) or (raw as Array).size() != 3:
		return null
	for v: Variant in raw:
		if not _is_number(v):
			return null
	return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))


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
