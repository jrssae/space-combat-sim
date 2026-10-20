class_name ScenarioLoader
extends RefCounted
## Reads a scenario file (`data/scenarios/*.json`) into a validated spawn list (architecture §3, §14.6, §14.9).
## Pure: parses and checks, never touches the scene tree; the caller spawns every entry through `World.spawn()`.
##
## Positions are universe coordinates and come back as `UniversePos` (64-bit: JSON numbers are doubles, and they
## are never squeezed through a float32 `Vector3`). Velocities and directions are small local vectors (`Vector3`).
##
## Result (also on failure, so callers can read it without checking every key):
##     {"ok": bool, "error": String,               # error is "" when ok, else "<source>: <what is wrong>"
##      "scenario_id": StringName, "system_id": StringName,
##      "player": {"position": UniversePos, "forward": Vector3, "basis": Basis},
##      "props": Array[Dictionary]}                 # each {"type": StringName, "name": String,
##                                                  #       "position": UniversePos, "velocity": Vector3}
## Errors are returned, not pushed: the caller decides how loud a broken scenario is.

const FREE_FLIGHT_PATH: String = "res://data/scenarios/free_flight.json"
## Prop types a scenario may spawn (the caller maps each to a scene). Unknown types are an error, not a silent skip.
const PROP_TYPES: Array[StringName] = [&"nav_buoy"]


## Reads and validates the scenario at `path` (`res://` or `user://`).
static func load(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("%s: cannot open (%s)" % [path, error_string(FileAccess.get_open_error())])
	return parse(file.get_as_text(), path)


## Validates scenario JSON text; `source` names it in error messages.
static func parse(text: String, source: String = "scenario") -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		return _failure("%s: invalid JSON at line %d: %s" % [source, json.get_error_line(), json.get_error_message()])
	return from_data(json.data, source)


## Validates already parsed JSON data.
static func from_data(data: Variant, source: String = "scenario") -> Dictionary:
	if not (data is Dictionary):
		return _failure("%s: the root must be an object" % source)
	var root: Dictionary = data
	var scenario_id: Variant = root.get("scenario_id")
	if not (scenario_id is String) or (scenario_id as String).is_empty():
		return _failure("%s: scenario_id must be a non-empty string" % source)
	var system_id: Variant = root.get("system_id", "local")
	if not (system_id is String) or (system_id as String).is_empty():
		return _failure("%s: system_id must be a non-empty string" % source)
	var system := StringName(system_id as String)

	var player: Variant = root.get("player")
	if not (player is Dictionary):
		return _failure("%s: player must be an object" % source)
	var player_dict: Dictionary = player
	var player_pos: Variant = _universe_pos(player_dict.get("position"), system)
	if player_pos == null:
		return _failure("%s: player.position must be [x, y, z] (numbers)" % source)
	var forward: Variant = _vector3(player_dict.get("forward", [0.0, 0.0, -1.0]))
	if forward == null or (forward as Vector3).is_zero_approx():
		return _failure("%s: player.forward must be a non-zero [x, y, z]" % source)
	var forward_unit: Vector3 = (forward as Vector3).normalized()

	var props_raw: Variant = root.get("props", [])
	if not (props_raw is Array):
		return _failure("%s: props must be an array" % source)
	var props: Array[Dictionary] = []
	var names: Dictionary = {}
	var index: int = 0
	for raw: Variant in props_raw as Array:
		var where: String = "%s: props[%d]" % [source, index]
		index += 1
		if not (raw is Dictionary):
			return _failure("%s must be an object" % where)
		var entry: Dictionary = raw
		var prop_type: Variant = entry.get("type")
		if not (prop_type is String) or not PROP_TYPES.has(StringName(prop_type as String)):
			return _failure("%s: type must be one of %s, got %s" % [where, PROP_TYPES, JSON.stringify(prop_type)])
		var prop_name: Variant = entry.get("name")
		if not (prop_name is String) or (prop_name as String).strip_edges().is_empty():
			return _failure("%s: name must be a non-empty string" % where)
		var key: String = (prop_name as String).to_lower()
		if names.has(key):
			return _failure("%s: duplicate name '%s' (targets are selected by name)" % [where, prop_name])
		names[key] = true
		var position: Variant = _universe_pos(entry.get("position"), system)
		if position == null:
			return _failure("%s: position must be [x, y, z] (numbers)" % where)
		var velocity: Variant = _vector3(entry.get("velocity", [0.0, 0.0, 0.0]))
		if velocity == null:
			return _failure("%s: velocity must be [x, y, z] (numbers)" % where)
		props.append({"type": StringName(prop_type as String), "name": prop_name as String,
				"position": position as UniversePos, "velocity": velocity as Vector3})

	var result: Dictionary = _empty()
	result["ok"] = true
	result["scenario_id"] = StringName(scenario_id as String)
	result["system_id"] = system
	result["player"] = {"position": player_pos as UniversePos, "forward": forward_unit,
			"basis": basis_facing(forward_unit)}
	result["props"] = props
	return result


## An orientation whose forward axis (-Z) points along `forward`, up as close to +Y as possible.
static func basis_facing(forward: Vector3) -> Basis:
	var f: Vector3 = forward.normalized()
	var up: Vector3 = Vector3.UP if absf(f.dot(Vector3.UP)) < 0.999 else Vector3.BACK
	return Basis.looking_at(f, up)


## Three finite numbers -> UniversePos in `system`, or null. Validated here so UniversePos.from_array never errors.
static func _universe_pos(value: Variant, system: StringName) -> Variant:
	var parts: Variant = _numbers3(value)
	if parts == null:
		return null
	var p: PackedFloat64Array = parts
	return UniversePos.new(p[0], p[1], p[2], system)


static func _vector3(value: Variant) -> Variant:
	var parts: Variant = _numbers3(value)
	if parts == null:
		return null
	var p: PackedFloat64Array = parts
	return Vector3(p[0], p[1], p[2])


static func _numbers3(value: Variant) -> Variant:
	if not (value is Array) or (value as Array).size() != 3:
		return null
	var out := PackedFloat64Array()
	for v: Variant in value as Array:
		if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
			return null
		var f: float = float(v)
		if is_nan(f) or is_inf(f):
			return null
		out.append(f)
	return out


static func _empty() -> Dictionary:
	return {"ok": false, "error": "", "scenario_id": &"", "system_id": &"local",
			"player": {"position": UniversePos.new(), "forward": Vector3.FORWARD, "basis": Basis.IDENTITY},
			"props": [] as Array[Dictionary]}


static func _failure(message: String) -> Dictionary:
	var result: Dictionary = _empty()
	result["error"] = message
	return result
