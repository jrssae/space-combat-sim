class_name TriggerSpec
extends RefCounted
## Builds `Trigger`s (architecture §18 D52): from JSON, so a scenario's objectives can name them, and through short builders a
## mission script calls (`await m.until(TriggerSpec.destroyed(["RAIDER 1"]))`). Pure. Errors are returned, never pushed.
##
## JSON, one object per trigger (points are universe `[x, y, z]` in the scenario's system):
##     {"kind": "proximity", "actor": "player", "to": "NAV ALPHA" | [x, y, z], "radius_m": 300}
##     {"kind": "area", "actor": "player", "centre": [x, y, z], "radius_m": 500}
##     {"kind": "timer", "seconds": 30}
##     {"kind": "destroyed", "names": ["RAIDER 1", "RAIDER 2"], "all": true}      (or "name": "NAV ALPHA")
##     {"kind": "dialog_finished", "line": "intro_1"}
##     {"kind": "input_performed", "action": "roll_right"}                         (a `PlayerActions.NAMES` word)
##     {"kind": "arrived", "actor": "ALPHA 2", "at": [x, y, z], "radius_m": 150}   (no "at": the end of its route)

const KINDS: Array[StringName] = [&"proximity", &"area", &"timer", &"destroyed", &"dialog_finished", &"input_performed",
		&"arrived"]


## `{"ok": bool, "trigger": Trigger or null, "error": String}` for one JSON trigger.
static func from_dict(data: Variant, system: StringName = &"local") -> Dictionary:
	if not (data is Dictionary):
		return _fail("a trigger must be an object, got %s" % JSON.stringify(data))
	var d: Dictionary = data
	var kind := StringName(str(d.get("kind", "")))
	match kind:
		&"proximity":
			var actor: Variant = _name(d, "actor")
			if actor == null:
				return _fail("proximity needs an actor (a ship's name or \"player\")")
			var radius: Variant = _radius(d)
			if radius == null:
				return _fail("proximity: radius_m must be a number above 0")
			var to: Variant = d.get("to")
			if to is String and not (to as String).strip_edges().is_empty():
				return _ok(proximity(actor as String, (to as String).strip_edges(), radius as float))
			var point: UniversePos = _point(to, system)
			if point == null:
				return _fail("proximity: to must be a name or [x, y, z], got %s" % JSON.stringify(to))
			return _ok(near_point(actor as String, point, radius as float))
		&"area":
			var actor: Variant = _name(d, "actor")
			if actor == null:
				return _fail("area needs an actor (a ship's name or \"player\")")
			var centre: UniversePos = _point(d.get("centre"), system)
			if centre == null:
				return _fail("area: centre must be [x, y, z], got %s" % JSON.stringify(d.get("centre")))
			var radius: Variant = _radius(d)
			if radius == null:
				return _fail("area: radius_m must be a number above 0")
			return _ok(area(actor as String, centre, radius as float))
		&"timer":
			var seconds: Variant = d.get("seconds")
			if not _is_number(seconds) or float(seconds) < 0.0:
				return _fail("timer: seconds must be a number, 0 or more")
			return _ok(timer(float(seconds)))
		&"destroyed":
			var names := PackedStringArray()
			var raw: Variant = d.get("names", [d.get("name")] if d.has("name") else [])
			if raw is Array:
				for n: Variant in raw as Array:
					if n is String and not (n as String).strip_edges().is_empty():
						names.append((n as String).strip_edges())
					else:
						names.clear()
						break
			if names.is_empty():
				return _fail("destroyed: names must be a non-empty list of ship names (or one \"name\")")
			var all: Variant = d.get("all", true)
			if typeof(all) != TYPE_BOOL:
				return _fail("destroyed: all must be true or false")
			return _ok(destroyed(names, all as bool))
		&"dialog_finished":
			var line: Variant = _name(d, "line")
			if line == null:
				return _fail("dialog_finished: line must be a dialog line id")
			return _ok(dialog_finished(StringName(line as String)))
		&"input_performed":
			var action := StringName(str(d.get("action", "")))
			if not PlayerActions.NAMES.has(action):
				return _fail("input_performed: action must be one of %s, got %s" % [", ".join(PackedStringArray(PlayerActions.NAMES)),
						JSON.stringify(d.get("action"))])
			return _ok(input_performed(action))
		&"arrived":
			var actor: Variant = _name(d, "actor")
			if actor == null:
				return _fail("arrived needs an actor (an AI ship's name)")
			var radius: Variant = _radius(d, Route.ARRIVAL_M)
			if radius == null:
				return _fail("arrived: radius_m must be a number above 0")
			if not d.has("at"):
				return _ok(arrived(actor as String, null, radius as float))
			var point: UniversePos = _point(d.get("at"), system)
			if point == null:
				return _fail("arrived: at must be [x, y, z], got %s" % JSON.stringify(d.get("at")))
			return _ok(arrived(actor as String, point, radius as float))
	return _fail("unknown kind %s (expected one of %s)" % [JSON.stringify(d.get("kind")), ", ".join(PackedStringArray(KINDS))])


## "" when `data` builds a trigger, else why not.
static func validate(data: Variant, system: StringName = &"local") -> String:
	return String(from_dict(data, system)["error"])


# --- builders for mission scripts --------------------------------------------------------------------------------------


## `actor` within `radius_m` of the actor `other`.
static func proximity(actor: String, other: String, radius_m: float) -> TriggerProximity:
	return TriggerProximity.new(actor, other, null, radius_m)


## `actor` within `radius_m` of a universe point.
static func near_point(actor: String, point: UniversePos, radius_m: float) -> TriggerProximity:
	return TriggerProximity.new(actor, "", point, radius_m)


static func area(actor: String, centre: UniversePos, radius_m: float) -> TriggerArea:
	return TriggerArea.new(actor, centre, radius_m)


static func timer(seconds: float) -> TriggerTimer:
	return TriggerTimer.new(seconds)


## Every one of `names` out of play (`all`), or any one of them.
static func destroyed(names: Variant, all: bool = true) -> TriggerDestroyed:
	return TriggerDestroyed.new(PackedStringArray(names), all)


static func dialog_finished(line_id: StringName) -> TriggerDialogFinished:
	return TriggerDialogFinished.new(line_id)


static func input_performed(action: StringName) -> TriggerInputPerformed:
	return TriggerInputPerformed.new(action)


## An AI actor at a point (within `radius_m`), or with no point at the end of the route it leads.
static func arrived(actor: String, point: UniversePos = null, radius_m: float = Route.ARRIVAL_M) -> TriggerArrived:
	return TriggerArrived.new(actor, point, radius_m)


# --- parsing -----------------------------------------------------------------------------------------------------------


static func _name(d: Dictionary, key: String) -> Variant:
	var value: Variant = d.get(key)
	if not (value is String) or (value as String).strip_edges().is_empty():
		return null
	return (value as String).strip_edges()


static func _radius(d: Dictionary, fallback: float = -1.0) -> Variant:
	var value: Variant = d.get("radius_m", fallback if fallback > 0.0 else null)
	if not _is_number(value) or float(value) <= 0.0:
		return null
	return float(value)


static func _point(value: Variant, system: StringName) -> UniversePos:
	if not (value is Array) or (value as Array).size() != 3:
		return null
	for v: Variant in value as Array:
		if not _is_number(v) or is_nan(float(v)) or is_inf(float(v)):
			return null
	var a: Array = value
	return UniversePos.new(float(a[0]), float(a[1]), float(a[2]), system)


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT


static func _ok(trigger: Trigger) -> Dictionary:
	return {"ok": true, "trigger": trigger, "error": ""}


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "trigger": null, "error": message}
