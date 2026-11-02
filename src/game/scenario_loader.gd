class_name ScenarioLoader
extends RefCounted
## Reads a scenario file (`data/scenarios/*.json`) into a validated spawn list (architecture §3, §14.6, §14.9).
## Pure: parses and checks, never touches the scene tree; the caller spawns every entry through `World.spawn()`.
##
## Positions are universe coordinates and come back as `UniversePos`, never squeezed through a float32 `Vector3`.
## Velocities and directions are small local vectors.
##
## Result (also on failure, so callers can read it without checking every key):
##     {"ok": bool, "error": String,               # error is "" when ok, else "<source>: <what is wrong>"
##      "scenario_id": StringName, "system_id": StringName,
##      "player": {"position": UniversePos, "forward": Vector3, "basis": Basis},
##      "props": Array[Dictionary],                 # each {"type": StringName, "name": String,
##                                                  #       "position": UniversePos, "velocity": Vector3}
##      "pools": Dictionary,                        # ship type (StringName) -> how many to build (int); may be empty.
##                                                  # `Main` builds `raider_fighter` and `starfury_ally` (M3-T08) from it
##      "waves": Array[Dictionary],                 # each {"name", "delay_s", "spawns": Array[{type, name, anchor, offset,
##                                                  #       velocity, at_s, behaviour}]} (M2-T09); may be empty; and
##                                                  #       "skill", "aggression": Vector2 ranges (M3-T13; (-1, -1) none)
##      "loop": Dictionary,                         # {"from_wave": int (0 = none), "add_per_loop": int, "skill_step": float}
##      "routes": Array[Route],                     # `routes[]` (M3-T09): {name, cruise_mps (60), pace ("player" | "none"),
##                                                  #       loop (false), waypoints: [{position, demo, hold_s}]}; may be empty
##      "spawns": Array[Dictionary],                # ships placed at load (M3-T09): a wave spawn's fields plus
##                                                  #       "invulnerable" (bool, false) and "route" (a route's name, "" none);
##                                                  #       the members of `wings[]` come last, in their order
##      "wings": Array[Dictionary]}                 # `wings[]` (M3-T10): {name, faction (StringName, &"" for any), leader
##                                                  #       ("player", a spawn's name, or "" for its first ship), formation
##                                                  #       (Formation.Shape), order (AiContext.Order)}; may be empty
## Every spawn (wave or load) carries "wing" (a wing's name, "" for none; it needs an "ai" behaviour). A wing named by a spawn
## but not declared in `wings[]` is a group led by its first ship, engaging at will, in a finger-four.
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
	var routes: Variant = _routes(root.get("routes", []), system, source)
	if routes is String:
		return _failure(routes as String)
	var spawns: Variant = _load_spawns(root.get("spawns", []), routes as Array[Route], pools as Dictionary, system, source)
	if spawns is String:
		return _failure(spawns as String)
	var wings: Variant = _wings(root.get("wings", []), spawns as Array[Dictionary], system, source)
	if wings is String:
		return _failure(wings as String)
	var at_load: Dictionary = _type_counts(spawns as Array[Dictionary])
	for type: StringName in at_load:
		if int(at_load[type]) > int((pools as Dictionary).get(type, 0)):
			return _failure("%s: spawns and wings: %d ships of %s at load but pools.%s holds %d" % [source, at_load[type], type,
					type, int((pools as Dictionary).get(type, 0))])
	var waves: Variant = _waves(root.get("waves", []), pools as Dictionary, system, source, at_load)
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
	result["routes"] = routes
	result["spawns"] = spawns
	result["wings"] = wings
	return result


## `wings[]` (M3-T10): each wing's declaration, its members appended to `spawns`, or an error string. `leader` is "player",
## a spawn's name, or absent (the first ship leads). `faction`, when given, must be every member's. `formation` defaults to
## finger_four, `order` to cover for a player-led wing, else engage.
static func _wings(raw: Variant, spawns: Array[Dictionary], system: StringName, source: String) -> Variant:
	if not (raw is Array):
		return "%s: wings must be an array" % source
	var out: Array[Dictionary] = []
	var seen: Dictionary = {}
	for w: int in (raw as Array).size():
		var where: String = "%s: wings[%d]" % [source, w]
		var entry: Variant = (raw as Array)[w]
		if not (entry is Dictionary):
			return "%s must be an object" % where
		var wing: Dictionary = entry
		var wing_name: Variant = wing.get("name")
		if not (wing_name is String) or (wing_name as String).strip_edges().is_empty():
			return "%s.name must be a non-empty string" % where
		var key: String = (wing_name as String).strip_edges().to_lower()
		if seen.has(key):
			return "%s.name '%s' is declared twice" % [where, wing_name]
		seen[key] = true
		var faction: Variant = wing.get("faction", "")
		if not (faction is String) or (not (faction as String).is_empty() and not Factions.is_known(StringName(faction as String))):
			return "%s.faction must be a known faction, got %s" % [where, JSON.stringify(faction)]
		var shape: Variant = wing.get("formation", String(Formation.NAMES[Formation.Shape.FINGER_FOUR]))
		var shape_value: int = Formation.shape_from_name(shape as String) if shape is String else -1
		if shape_value < 0:
			return "%s.formation must be one of %s, got %s" % [where, ", ".join(PackedStringArray(Formation.NAMES)), JSON.stringify(shape)]
		var leader: Variant = wing.get("leader", "")
		if not (leader is String):
			return "%s.leader must be \"player\" or a spawn's name" % where
		var default_order: AiContext.Order = AiContext.Order.COVER_ME if leader == "player" else AiContext.Order.ENGAGE_AT_WILL
		var order_word: Variant = wing.get("order", String(AiContext.order_word(default_order)))
		var order: int = AiContext.order_from_word(order_word as String) if order_word is String else -1
		if order < 0:
			return "%s.order must be one of %s, got %s" % [where, ", ".join(PackedStringArray(AiContext.ORDER_WORDS)), JSON.stringify(order_word)]
		var members_raw: Variant = wing.get("members", [])
		if not (members_raw is Array):
			return "%s.members must be an array" % where
		var names := PackedStringArray()
		for spawn: Dictionary in spawns:
			names.append(String(spawn["name"]).to_lower())
		for i: int in (members_raw as Array).size():
			var at: String = "%s.members[%d]" % [where, i]
			var member_raw: Variant = (members_raw as Array)[i]
			if member_raw is Dictionary and not (member_raw as Dictionary).has("wing"):
				member_raw = (member_raw as Dictionary).duplicate()
				member_raw["wing"] = wing_name
			var member: Variant = _spawn(member_raw, at, system)
			if member is String:
				return member
			if String((member as Dictionary)["wing"]).to_lower() != key:
				return "%s.wing must be its wing's name (%s) or left out" % [at, wing_name]
			var m: Dictionary = member
			m["invulnerable"] = false
			m["route"] = ""
			if not (faction as String).is_empty() and ShipCatalog.faction_for(m["type"]) != StringName(faction as String):
				return "%s: a %s flies for %s, not the wing's faction %s" % [at, m["type"], ShipCatalog.faction_for(m["type"]), faction]
			spawns.append(m)
			names.append(String(m["name"]).to_lower())
		if leader != "player" and not (leader as String).is_empty() and not names.has((leader as String).to_lower()):
			return "%s.leader '%s' is not a spawn of this scenario (\"player\", or the name of a spawn or member)" % [where, leader]
		out.append({"name": (wing_name as String).strip_edges(), "faction": StringName(faction as String),
				"leader": leader as String, "formation": shape_value, "order": order})
	return out


## `pools`: ship type -> count (whole, 0 or more), or an error string. Any `ShipCatalog` type may be named.
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
	var step: Variant = loop.get("skill_step", 0.0)
	if not _is_number(step) or float(step) < 0.0 or float(step) > 1.0:
		return "%s: loop.skill_step must be a number 0-1" % source
	return {"from_wave": int(from_wave), "add_per_loop": int(add), "skill_step": float(step)}


## A wave's `skill` or `aggression` range (M3-T13): `[low, high]`, each a rank or level name or a number 0-1, low first; absent:
## Vector2(-1, -1). Returns the range or an error string.
static func _temper_range(wave: Dictionary, key: String, where: String) -> Variant:
	if not wave.has(key):
		return Vector2(-1.0, -1.0)
	var raw: Variant = wave[key]
	if not (raw is Array) or (raw as Array).size() != 2:
		return "%s.%s must be [low, high]" % [where, key]
	var parse := AiTemperament.parse_skill if key == "skill" else AiTemperament.parse_aggression
	var lo: float = float(parse.call((raw as Array)[0]))
	var hi: float = float(parse.call((raw as Array)[1]))
	if lo < 0.0 or hi < 0.0 or lo > hi:
		return "%s.%s must be [low, high], names or numbers 0-1 with low <= high, got %s" % [where, key, JSON.stringify(raw)]
	return Vector2(lo, hi)


## `routes[]` as `Route`s, or an error string. The spawner sets `pace_id`.
static func _routes(raw: Variant, system: StringName, source: String) -> Variant:
	if not (raw is Array):
		return "%s: routes must be an array" % source
	var out: Array[Route] = []
	for r: int in (raw as Array).size():
		var where: String = "%s: routes[%d]" % [source, r]
		var entry: Variant = (raw as Array)[r]
		if not (entry is Dictionary):
			return "%s must be an object" % where
		var data: Dictionary = entry
		var route_name: Variant = data.get("name")
		if not (route_name is String) or (route_name as String).strip_edges().is_empty():
			return "%s.name must be a non-empty string" % where
		for other: Route in out:
			if other.name == route_name:
				return "%s.name: duplicate route '%s'" % [where, route_name]
		var cruise: Variant = data.get("cruise_mps", Route.DEFAULT_CRUISE_MPS)
		if not _is_number(cruise) or float(cruise) <= 0.0:
			return "%s.cruise_mps must be a number above 0" % where
		var pace: Variant = data.get("pace", String(Route.PACE_PLAYER))
		if not (pace is String) or not Route.PACE_WORDS.has(StringName(pace as String)):
			return "%s.pace must be one of %s, got %s" % [where, ", ".join(PackedStringArray(Route.PACE_WORDS)), JSON.stringify(pace)]
		var loop: Variant = data.get("loop", false)
		if typeof(loop) != TYPE_BOOL:
			return "%s.loop must be true or false" % where
		var points: Variant = data.get("waypoints")
		if not (points is Array) or (points as Array).is_empty():
			return "%s.waypoints must be a non-empty array" % where
		var route := Route.new()
		route.name = route_name as String
		route.cruise_mps = float(cruise)
		route.pace = StringName(pace as String)
		route.loop = loop as bool
		for i: int in (points as Array).size():
			var at: String = "%s.waypoints[%d]" % [where, i]
			var point: Variant = (points as Array)[i]
			if not (point is Dictionary):
				return "%s must be an object" % at
			var position: Variant = _universe_pos((point as Dictionary).get("position"), system)
			if position == null:
				return "%s.position must be [x, y, z] (numbers)" % at
			var demo: Variant = (point as Dictionary).get("demo", "")
			if not (demo is String) or (not (demo as String).is_empty() and not Manoeuvres.NAMES.has(StringName(demo as String))):
				return "%s.demo must be one of %s, got %s" % [at, ", ".join(PackedStringArray(Manoeuvres.NAMES)), JSON.stringify(demo)]
			var hold: Variant = (point as Dictionary).get("hold_s", 0.0)
			if not _is_number(hold) or float(hold) < 0.0:
				return "%s.hold_s must be a number, 0 or more" % at
			route.add(position as UniversePos, StringName(demo as String), float(hold))
		out.append(route)
	return out


## `spawns[]`, the ships placed when the scenario loads (a wave spawn's fields, plus `invulnerable` and `route`), or an error
## string. Together they must fit the pools.
static func _load_spawns(raw: Variant, routes: Array[Route], pools: Dictionary, system: StringName, source: String) -> Variant:
	if not (raw is Array):
		return "%s: spawns must be an array" % source
	var out: Array[Dictionary] = []
	var route_names := PackedStringArray()
	for route: Route in routes:
		route_names.append(route.name)
	for i: int in (raw as Array).size():
		var where: String = "%s: spawns[%d]" % [source, i]
		var spawn: Variant = _spawn((raw as Array)[i], where, system)
		if spawn is String:
			return spawn
		var entry: Dictionary = (raw as Array)[i]
		var invulnerable: Variant = entry.get("invulnerable", false)
		if typeof(invulnerable) != TYPE_BOOL:
			return "%s.invulnerable must be true or false" % where
		var route: Variant = entry.get("route", "")
		if route == null:
			route = ""
		if not (route is String):
			return "%s.route must be the name of a route" % where
		if not (route as String).is_empty():
			if not route_names.has(route as String):
				return "%s.route '%s' is not a route of this scenario (%s)" % [where, route,
						", ".join(route_names) if not route_names.is_empty() else "none"]
			if str(((spawn as Dictionary)["behaviour"] as Dictionary).get("type", "")) != "ai":
				return "%s.route needs an \"ai\" behaviour (an AiPilot leads it)" % where
		(spawn as Dictionary)["invulnerable"] = invulnerable as bool
		(spawn as Dictionary)["route"] = route as String
		out.append(spawn as Dictionary)
	var counts: Dictionary = _type_counts(out)
	for type: StringName in counts:
		if int(counts[type]) > int(pools.get(type, 0)):
			return "%s: spawns: %d ships of %s but pools.%s holds %d" % [source, counts[type], type, type, int(pools.get(type, 0))]
	return out


## Ship type -> how many of `spawns` take one.
static func _type_counts(spawns: Array[Dictionary]) -> Dictionary:
	var out: Dictionary = {}
	for spawn: Dictionary in spawns:
		out[spawn["type"]] = int(out.get(spawn["type"], 0)) + 1
	return out


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT


## `waves[]`, or an error string. `at_load` (type -> count) is what the ships placed at load already hold of each pool.
static func _waves(raw: Variant, pools: Dictionary, system: StringName, source: String, at_load: Dictionary = {}) -> Variant:
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
		var type_counts: Dictionary = _type_counts(spawns)
		for type: StringName in type_counts:
			var held: int = int(at_load.get(type, 0))
			if int(type_counts[type]) + held > int(pools.get(type, 0)):
				var also: String = " and %d ship%s at load" % [held, "" if held == 1 else "s"] if held > 0 else ""
				return "%s: %d spawns of %s%s but pools.%s holds %d" % [where, type_counts[type], type, also, type,
						int(pools.get(type, 0))]
		var skill: Variant = _temper_range(wave as Dictionary, "skill", where)
		if skill is String:
			return skill
		var aggression: Variant = _temper_range(wave as Dictionary, "aggression", where)
		if aggression is String:
			return aggression
		out.append({"name": wave_name as String, "delay_s": float(delay), "spawns": spawns, "skill": skill as Vector2,
				"aggression": aggression as Vector2})
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
	var wing: Variant = entry.get("wing", "")
	if not (wing is String):
		return "%s.wing must be a wing's name" % where
	if not (wing as String).strip_edges().is_empty() and not (made["brain"] is AiPilot):
		return "%s.wing needs an \"ai\" behaviour (a wing's members fly an AiPilot)" % where
	return {"type": StringName(type as String), "name": str(entry.get("name", "")), "anchor": StringName(anchor as String),
			"offset": offset as Vector3, "velocity": velocity as Vector3, "at_s": float(at_s), "behaviour": behaviour,
			"wing": (wing as String).strip_edges()}


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
			"loop": {"from_wave": 0, "add_per_loop": 1}, "routes": [] as Array[Route], "spawns": [] as Array[Dictionary],
			"wings": [] as Array[Dictionary]}


static func _failure(message: String) -> Dictionary:
	var result: Dictionary = _empty()
	result["error"] = message
	return result
