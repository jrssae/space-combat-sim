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
##      "props": Array[Dictionary],                 # each {"type": StringName, "name": String,
##                                                  #       "position": UniversePos, "velocity": Vector3}
##      "pools": Dictionary,                        # ship type (StringName) -> how many to build (int); may be empty
##      "waves": Array[Dictionary],                 # each {"name", "delay_s", "spawns": Array[{type, name, anchor, offset,
##                                                  #       velocity, at_s, behaviour}]} (M2-T09); may be empty
##      "loop": Dictionary}                         # {"from_wave": int (0 = none), "add_per_loop": int}
## Errors are returned, not pushed: the caller decides how loud a broken scenario is.

const FREE_FLIGHT_PATH: String = "res://data/scenarios/free_flight.json"
## Prop types a scenario may spawn (the caller maps each to a scene). Unknown types are an error, not a silent skip.
const PROP_TYPES: Array[StringName] = [&"nav_buoy"]
const SANDBOX_PATH: String = "res://data/scenarios/combat_sandbox.json"
const ANCHORS: Array[StringName] = [&"player", &"origin"]


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

	var pools: Variant = _pools(root.get("pools", {}), source)
	if pools is String:
		return _failure(pools as String)
	var loop: Variant = _loop(root.get("loop", {}), source)
	if loop is String:
		return _failure(loop as String)
	var waves: Variant = _waves(root.get("waves", []), pools as Dictionary, system, source)
	if waves is String:
		return _failure(waves as String)
	var wave_list: Array[Dictionary] = waves
	if (loop as Dictionary)["from_wave"] > wave_list.size():
		return _failure("%s: loop.from_wave %d is beyond the %d waves" % [source, (loop as Dictionary)["from_wave"], wave_list.size()])

	var result: Dictionary = _empty()
	result["ok"] = true
	result["scenario_id"] = StringName(scenario_id as String)
	result["system_id"] = system
	result["player"] = {"position": player_pos as UniversePos, "forward": forward_unit,
			"basis": basis_facing(forward_unit)}
	result["props"] = props
	result["pools"] = pools
	result["waves"] = wave_list
	result["loop"] = loop
	return result


## `pools`: `{"raider_fighter": 6}` -> `{&"raider_fighter": 6}`, or an error string.
static func _pools(raw: Variant, source: String) -> Variant:
	if not (raw is Dictionary):
		return "%s: pools must be an object" % source
	var out: Dictionary = {}
	for key: Variant in (raw as Dictionary).keys():
		var where: String = "%s: pools.%s" % [source, str(key)]
		if not ShipCatalog.has_type(StringName(str(key))):
			return "%s: unknown ship type (expected one of %s)" % [where, ShipCatalog.types()]
		var count: Variant = (raw as Dictionary)[key]
		if typeof(count) != TYPE_FLOAT and typeof(count) != TYPE_INT or float(count) != floorf(float(count)) or int(count) < 0:
			return "%s must be a whole number, 0 or more" % where
		out[StringName(str(key))] = int(count)
	return out


## `loop`: `{"from_wave": 3, "add_per_loop": 1}`, or an error string. Absent = no loop (`from_wave` 0).
static func _loop(raw: Variant, source: String) -> Variant:
	if not (raw is Dictionary):
		return "%s: loop must be an object" % source
	var loop: Dictionary = raw
	var from_wave: Variant = loop.get("from_wave", 0)
	if typeof(from_wave) != TYPE_FLOAT and typeof(from_wave) != TYPE_INT or float(from_wave) != floorf(float(from_wave)) or int(from_wave) < 0:
		return "%s: loop.from_wave must be a whole number, 0 or more (1 = the first wave)" % source
	var add: Variant = loop.get("add_per_loop", 1)
	if typeof(add) != TYPE_FLOAT and typeof(add) != TYPE_INT or float(add) != floorf(float(add)) or int(add) < 0:
		return "%s: loop.add_per_loop must be a whole number, 0 or more" % source
	return {"from_wave": int(from_wave), "add_per_loop": int(add)}


## `waves[]`, or an error string.
static func _waves(raw: Variant, pools: Dictionary, system: StringName, source: String) -> Variant:
	if not (raw is Array):
		return "%s: waves must be an array" % source
	var out: Array[Dictionary] = []
	for w: int in (raw as Array).size():
		var where: String = "%s: waves[%d]" % [source, w]
		var wave: Variant = (raw as Array)[w]
		if not (wave is Dictionary):
			return "%s must be an object" % where
		var wave_name: Variant = (wave as Dictionary).get("name")
		if not (wave_name is String) or (wave_name as String).strip_edges().is_empty():
			return "%s: name must be a non-empty string" % where
		var delay: Variant = (wave as Dictionary).get("delay_s", 5.0)
		if typeof(delay) != TYPE_FLOAT and typeof(delay) != TYPE_INT or float(delay) < 0.0:
			return "%s: delay_s must be a number, 0 or more" % where
		var spawns_raw: Variant = (wave as Dictionary).get("spawns")
		if not (spawns_raw is Array) or (spawns_raw as Array).is_empty():
			return "%s: spawns must be a non-empty array" % where
		var spawns: Array[Dictionary] = []
		for i: int in (spawns_raw as Array).size():
			var spawn: Variant = _spawn((spawns_raw as Array)[i], "%s.spawns[%d]" % [where, i], system)
			if spawn is String:
				return spawn
			spawns.append(spawn as Dictionary)
		var type_counts: Dictionary = {}
		for spawn: Dictionary in spawns:
			type_counts[spawn["type"]] = int(type_counts.get(spawn["type"], 0)) + 1
		for type: StringName in type_counts:
			if int(type_counts[type]) > int(pools.get(type, 0)):
				return "%s: %d spawns of %s but pools.%s holds %d" % [where, type_counts[type], type, type, int(pools.get(type, 0))]
		out.append({"name": wave_name as String, "delay_s": float(delay), "spawns": spawns})
	return out


## One spawn, or an error string. The behaviour is checked by building it once (its own errors are returned with the path).
static func _spawn(raw: Variant, where: String, system: StringName) -> Variant:
	if not (raw is Dictionary):
		return "%s must be an object" % where
	var entry: Dictionary = raw
	var type: Variant = entry.get("type")
	if not (type is String) or not ShipCatalog.has_type(StringName(type as String)):
		return "%s: type must be one of %s, got %s" % [where, ShipCatalog.types(), JSON.stringify(type)]
	var anchor: Variant = entry.get("anchor", "player")
	if not (anchor is String) or not ANCHORS.has(StringName(anchor as String)):
		return "%s: anchor must be one of %s, got %s" % [where, ANCHORS, JSON.stringify(anchor)]
	var offset: Variant = _vector3(entry.get("offset", [0.0, 0.0, 0.0]))
	if offset == null:
		return "%s: offset must be [x, y, z] (numbers)" % where
	var velocity: Variant = _vector3(entry.get("velocity", [0.0, 0.0, 0.0]))
	if velocity == null:
		return "%s: velocity must be [x, y, z] (numbers)" % where
	var at_s: Variant = entry.get("at_s", 0.0)
	if typeof(at_s) != TYPE_FLOAT and typeof(at_s) != TYPE_INT or float(at_s) < 0.0:
		return "%s: at_s must be a number, 0 or more" % where
	var behaviour: Variant = entry.get("behaviour", {"type": "idle"})
	var made: Dictionary = BrainFactory.from_behaviour(behaviour, UniversePos.new(0.0, 0.0, 0.0, system), 0)
	if not bool(made["ok"]):
		return "%s: %s" % [where, String(made["error"])]
	return {"type": StringName(type as String), "name": str(entry.get("name", "")), "anchor": StringName(anchor as String),
			"offset": offset as Vector3, "velocity": velocity as Vector3, "at_s": float(at_s), "behaviour": behaviour}


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
			"props": [] as Array[Dictionary], "pools": {}, "waves": [] as Array[Dictionary],
			"loop": {"from_wave": 0, "add_per_loop": 1}}


static func _failure(message: String) -> Dictionary:
	var result: Dictionary = _empty()
	result["error"] = message
	return result
