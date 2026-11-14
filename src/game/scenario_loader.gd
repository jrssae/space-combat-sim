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
##      "player": {"position": UniversePos, "forward": Vector3, "basis": Basis,
##                 "velocity": Vector3,             # the start velocity (M5-T10), zero unless given
##                 "launch_bay": String},           # (M7-T08) `player.launch_bay` or `player.launch` {wing, door}: the start on
##                                                  #       that Cobra bay's rack ("cobra_bay_alpha_3"); "" in flight
##      "station": Dictionary,                      # (M7-T12) the station's traffic at the start: {"cargo_ferry": int} (the Saturn 3 backed
##                                                  #       in at the cargo bay and that many ferry bots, 0 for none); {} for none
##      "props": Array[Dictionary],                 # each {"type": StringName, "name": String,
##                                                  #       "position": UniversePos, "velocity": Vector3}
##      "jumpgates": Array[Dictionary],             # (M6-T14) `jumpgates[]`, each {"type": &"jumpgate", "name", "position"
##                                                  #       (UniversePos, or null: placed from the system data), "place",
##                                                  #       "from" (StringName ids in `data/star_systems.json`), "station"
##                                                  #       (UniversePos of the `from` place's stand-in), "bearing" and
##                                                  #       "facing" (unit Vector3s)}; `_jumpgate` says how they are read
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
##      "wings": Array[Dictionary],                 # `wings[]` (M3-T10): {name, faction (StringName, &"" for any), leader
##                                                  #       ("player", a spawn's name, or "" for its first ship), formation
##                                                  #       (Formation.Shape), order (AiContext.Order)}; may be empty
##      "mission": Dictionary,                      # (M5-T05, D51) {} for none, else {title, briefing, script (a res://
##                                                  #       MissionScript path, loaded by the runner), dialog (a dialog file
##                                                  #       path), objectives: the raw `objectives[]`, already checked by
##                                                  #       `ObjectiveBook.declare`, closing_lines: {reason, "success" or
##                                                  #       "failure" -> line id (StringName)} (M5-T10)}; strings may be ""
##      "cinematics": Dictionary,                   # (M5-T05, D55) shot id -> shot, passed through for T08; may be empty
##      "belts": Array[Dictionary],                 # `asteroid_belts[]` (M5-T29, D63): each {centre: UniversePos, size: Vector3,
##                                                  #       count, radius_m: Vector2 (min, max bounding radius), seed, min_gap_m},
##                                                  #       the input `BeltLayout.place` takes; may be empty
##      "civilian_names": Dictionary,               # (M5-T30) civilian hull -> PackedStringArray of names; may be empty
##      "placeholders": Dictionary,                 # (M5-T30) filled by `resolve_random_civilian`: "{civilian}" -> name
##      "frame": Dictionary}                        # (M6-T09) the `anchor` and `epoch` blocks: where the World anchors and
##                                                  #       the system time at the start (`ScenarioFrame.parse`); every
##                                                  #       position above is measured from that anchor
## Every spawn (wave or load) carries "wing" (a wing's name, "" for none; it needs an "ai" behaviour), "cargo_pods" (M5-T16: how
## many cargo pods a hull with pod mounts flies with, 0-3; -1, the default, mounts them all) and "forward" (M5-T16: the spawn's
## own heading, a Vector3; zero, the default, takes the player's). A wing named by a spawn
## but not declared in `wings[]` is a group led by its first ship, engaging at will, in a finger-four.
## Errors are returned, not pushed: the caller decides how loud a broken scenario is.

const FREE_FLIGHT_PATH: String = "res://data/scenarios/free_flight.json"
## A launch bay's name begins so (M7-T08): `cobra_bay_<wing>_<door>`.
const LAUNCH_BAY_PREFIX: String = "cobra_bay_"
## Prop types a scenario may spawn (the caller maps each to a scene). Unknown types are an error, not a silent skip.
const PROP_TYPES: Array[StringName] = [&"nav_buoy"]
## A `jumpgates[]` entry's type (M6-T14): placed from `data/star_systems.json` beside the station's stand-in unless it gives a
## position.
const JUMPGATE: StringName = &"jumpgate"
const SANDBOX_PATH: String = "res://data/scenarios/combat_sandbox.json"
const ANCHORS: Array[StringName] = [&"player", &"origin"]
## A spawn and pool type that stands for one civilian hull drawn from the run's seed (M5-T30, D62).
const RANDOM_CIVILIAN: StringName = &"random_civilian"
## Where the drawn civilian's name goes in spawn names, objectives, cinematics and dialog lines.
const CIVILIAN_PLACEHOLDER: String = "{civilian}"


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
	var launch_bay: Variant = _launch_bay(player_dict, source)
	if launch_bay is Dictionary:
		return launch_bay
	# A start in a launch bay puts the player on the station's rack; its position is only where a respawn without one would go.
	var player_pos: Variant = _universe_pos(player_dict.get("position", [0.0, 0.0, 0.0] if not (launch_bay as String).is_empty()
			else null), system)
	if player_pos == null:
		return _failure("%s: player.position must be [x, y, z] (numbers)" % source)
	var forward: Variant = _vector3(player_dict.get("forward", [0.0, 0.0, -1.0]))
	if forward == null or (forward as Vector3).is_zero_approx():
		return _failure("%s: player.forward must be a non-zero [x, y, z]" % source)
	var forward_unit: Vector3 = (forward as Vector3).normalized()
	var start_velocity: Variant = _vector3(player_dict.get("velocity", [0.0, 0.0, 0.0]))
	if start_velocity == null:
		return _failure("%s: player.velocity must be [x, y, z] (numbers)" % source)

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

	var gates_raw: Variant = root.get("jumpgates", [])
	if not (gates_raw is Array):
		return _failure("%s: jumpgates must be an array" % source)
	var jumpgates: Array[Dictionary] = []
	for i: int in (gates_raw as Array).size():
		var where: String = "%s: jumpgates[%d]" % [source, i]
		var raw: Variant = (gates_raw as Array)[i]
		if not (raw is Dictionary):
			return _failure("%s must be an object" % where)
		var gate_name: Variant = (raw as Dictionary).get("name")
		if not (gate_name is String) or (gate_name as String).strip_edges().is_empty():
			return _failure("%s: name must be a non-empty string" % where)
		if names.has((gate_name as String).to_lower()):
			return _failure("%s: duplicate name '%s' (targets are selected by name)" % [where, gate_name])
		names[(gate_name as String).to_lower()] = true
		var gate: Variant = _jumpgate(raw as Dictionary, gate_name as String, system, where)
		if gate is String:
			return _failure(gate as String)
		jumpgates.append(gate as Dictionary)

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
	var mission: Variant = _mission(root.get("mission", {}), system, source)
	if mission is String:
		return _failure(mission as String)
	var cinematics: Variant = root.get("cinematics", {})
	if not (cinematics is Dictionary):
		return _failure("%s: cinematics must be an object (shot id -> shot)" % source)
	var waves: Variant = _waves(root.get("waves", []), pools as Dictionary, system, source, at_load)
	if waves is String:
		return _failure(waves as String)
	var wave_list: Array[Dictionary] = waves
	if (loop as Dictionary)["from_wave"] > wave_list.size():
		return _failure("%s: loop.from_wave %d is beyond the %d waves" % [source, (loop as Dictionary)["from_wave"], wave_list.size()])

	var belts: Variant = _belts(root.get("asteroid_belts", []), system, source)
	if belts is String:
		return _failure(belts as String)
	var civilian_names: Variant = _civilian_names(root.get("civilian_names", {}), source)
	if civilian_names is String:
		return _failure(civilian_names as String)
	var frame: Variant = ScenarioFrame.parse(root.get("anchor"), root.get("epoch"), source)
	if frame is String:
		return _failure(frame as String)

	var station: Variant = _station(root.get("station", {}), source)
	if station is String:
		return _failure(station as String)

	var result: Dictionary = _empty()
	result["ok"] = true
	result["scenario_id"] = StringName(scenario_id as String)
	result["system_id"] = system
	result["player"] = {"position": player_pos as UniversePos, "forward": forward_unit,
			"basis": basis_facing(forward_unit), "velocity": start_velocity as Vector3, "launch_bay": launch_bay as String}
	result["props"] = props
	result["jumpgates"] = jumpgates
	result["pools"] = pools
	result["waves"] = wave_list
	result["loop"] = loop
	result["routes"] = routes
	result["spawns"] = spawns
	result["wings"] = wings
	result["mission"] = mission
	result["cinematics"] = cinematics
	result["belts"] = belts
	result["station"] = station
	result["civilian_names"] = civilian_names
	result["frame"] = frame
	return result


## Draws the hull of every `random_civilian` spawn from `seed_value` (M5-T30, D62) before the pools are built, so only that
## hull is pooled and a retry (same seed) flies the same ship. A Bokmai draws 1 to 3 pods from the same seed. The ship's name
## comes from the scenario's `civilian_names` for that hull and replaces `CIVILIAN_PLACEHOLDER` in spawn names, the mission
## block and the cinematics; `placeholders` keeps it for the dialog. Changes `scenario` in place.
static func resolve_random_civilian(scenario: Dictionary, seed_value: int) -> void:
	var pools: Dictionary = scenario.get("pools", {})
	if not pools.has(RANDOM_CIVILIAN):
		return
	var types: Array[StringName] = ShipCatalog.CIVILIAN_TYPES
	var hull: StringName = types[posmod(hash([seed_value, "random_civilian"]), types.size())]
	var names: PackedStringArray = (scenario.get("civilian_names", {}) as Dictionary).get(hull, PackedStringArray())
	var ship_name: String = names[posmod(hash([seed_value, "civilian_name"]), names.size())] if not names.is_empty() \
			else String(hull).replace("_", " ").to_upper()
	pools[hull] = int(pools.get(hull, 0)) + int(pools[RANDOM_CIVILIAN])
	pools.erase(RANDOM_CIVILIAN)
	var fill: Dictionary = {CIVILIAN_PLACEHOLDER: ship_name}
	for spawn: Dictionary in scenario.get("spawns", []):
		if spawn["type"] != RANDOM_CIVILIAN:
			continue
		spawn["type"] = hull
		if hull == &"brakiri_bokmai" and int(spawn.get("cargo_pods", -1)) < 0:
			spawn["cargo_pods"] = 1 + posmod(hash([seed_value, "cargo_pods"]), CargoPods.MAX_PODS)
	for spawn: Dictionary in scenario.get("spawns", []):
		spawn["name"] = fill_placeholders(spawn["name"], fill)
	scenario["mission"] = fill_placeholders(scenario.get("mission", {}), fill)
	scenario["cinematics"] = fill_placeholders(scenario.get("cinematics", {}), fill)
	scenario["placeholders"] = fill


## `value` with every placeholder of `fill` (text -> replacement) replaced in its strings, through arrays and dictionaries.
static func fill_placeholders(value: Variant, fill: Dictionary) -> Variant:
	if value is String:
		var text: String = value
		for key: String in fill:
			text = text.replace(key, String(fill[key]))
		return text
	if value is Array:
		var out: Array = (value as Array).duplicate()
		for i: int in out.size():
			out[i] = fill_placeholders(out[i], fill)
		return out
	if value is Dictionary:
		var out: Dictionary = (value as Dictionary).duplicate()
		for key: Variant in out:
			out[key] = fill_placeholders(out[key], fill)
		return out
	return value


static func _is_ship_type(type: StringName) -> bool:
	return type == RANDOM_CIVILIAN or ShipCatalog.has_type(type)


## `civilian_names` (M5-T30): civilian hull -> the names a drawn civilian of that hull may fly under; or an error string.
static func _civilian_names(raw: Variant, source: String) -> Variant:
	if not (raw is Dictionary):
		return "%s: civilian_names must be an object (civilian hull -> [names])" % source
	var out: Dictionary = {}
	for key: Variant in raw as Dictionary:
		var hull := StringName(str(key))
		if not ShipCatalog.is_civilian(hull):
			return "%s: civilian_names.%s is not a civilian hull (%s)" % [source, key, ShipCatalog.CIVILIAN_TYPES]
		var list: Variant = (raw as Dictionary)[key]
		var names := PackedStringArray()
		if list is Array:
			for n: Variant in list as Array:
				if n is String and not (n as String).strip_edges().is_empty():
					names.append((n as String).strip_edges())
		if names.is_empty() or not (list is Array) or names.size() != (list as Array).size():
			return "%s: civilian_names.%s must be a non-empty list of names" % [source, key]
		out[hull] = names
	return out


## `station` (M7-T12): the station's traffic at the start, `{"cargo_ferry": n}` with n from 0 to 12 (the cargo ferry's bots); or an error string.
static func _station(raw: Variant, source: String) -> Variant:
	if not raw is Dictionary:
		return "%s: station must be an object" % source
	var out: Dictionary = {}
	for key: String in (raw as Dictionary).keys():
		if key != "cargo_ferry":
			return "%s: station.%s is not a known key (cargo_ferry)" % [source, key]
		var n: Variant = (raw as Dictionary)[key]
		if typeof(n) != TYPE_INT and typeof(n) != TYPE_FLOAT or float(n) != floorf(float(n)) or int(n) < 0 or int(n) > BotCargoScene.MAX_BOTS:
			return "%s: station.cargo_ferry must be a whole number from 0 to %d" % [source, BotCargoScene.MAX_BOTS]
		out["cargo_ferry"] = int(n)
	return out


## `asteroid_belts[]` (M5-T29, D63): each belt's box, rock count and sizes; or an error string.
static func _belts(raw: Variant, system: StringName, source: String) -> Variant:
	if not (raw is Array):
		return "%s: asteroid_belts must be an array" % source
	var out: Array[Dictionary] = []
	for b: int in (raw as Array).size():
		var where: String = "%s: asteroid_belts[%d]" % [source, b]
		var entry: Variant = (raw as Array)[b]
		if not (entry is Dictionary):
			return "%s must be an object" % where
		var belt: Dictionary = entry
		var centre: Variant = _universe_pos(belt.get("centre"), system)
		if centre == null:
			return "%s: centre must be [x, y, z] (numbers)" % where
		var size: Variant = _vector3(belt.get("size"))
		if size == null or (size as Vector3).x <= 0.0 or (size as Vector3).y <= 0.0 or (size as Vector3).z <= 0.0:
			return "%s: size must be [x, y, z], each above 0" % where
		var count: Variant = belt.get("count")
		if not (count is float or count is int) or int(count) < 1 or float(count) != floorf(float(count)):
			return "%s: count must be a whole number of at least 1" % where
		var radii: Variant = belt.get("radius_m")
		if not (radii is Array) or (radii as Array).size() != 2 or not ((radii as Array)[0] is float or (radii as Array)[0] is int) \
				or not ((radii as Array)[1] is float or (radii as Array)[1] is int) or float((radii as Array)[0]) <= 0.0 \
				or float((radii as Array)[1]) < float((radii as Array)[0]):
			return "%s: radius_m must be [min, max] with 0 < min <= max" % where
		var gap: Variant = belt.get("min_gap_m", 0.0)
		if not (gap is float or gap is int) or float(gap) < 0.0:
			return "%s: min_gap_m must be a number of at least 0" % where
		var seed_value: Variant = belt.get("seed", 1)
		if not (seed_value is float or seed_value is int):
			return "%s: seed must be a number" % where
		out.append({"centre": centre as UniversePos, "size": size as Vector3, "count": int(count),
				"radius_m": Vector2(float((radii as Array)[0]), float((radii as Array)[1])), "seed": int(seed_value),
				"min_gap_m": float(gap)})
	return out


## The `mission` block (D51), or an error string: `{}` when absent. Strings are checked for type only (the script and the
## dialog file are loaded by the mission runner), the objectives by `ObjectiveBook.declare`.
static func _mission(raw: Variant, system: StringName, source: String) -> Variant:
	if not (raw is Dictionary):
		return "%s: mission must be an object" % source
	var block: Dictionary = raw
	if block.is_empty():
		return {}
	var out: Dictionary = {}
	for key: String in ["title", "briefing", "script", "dialog"]:
		var value: Variant = block.get(key, "")
		if not (value is String):
			return "%s: mission.%s must be a string" % [source, key]
		out[key] = (value as String).strip_edges() if key != "briefing" else value as String
	var objectives: Variant = block.get("objectives", [])
	var problem: String = ObjectiveBook.new().declare(objectives, system)
	if not problem.is_empty():
		return "%s: mission.%s" % [source, problem]
	out["objectives"] = objectives
	var closing: Variant = _closing_lines(block.get("closing_lines", {}), source)
	if closing is String:
		return closing
	out["closing_lines"] = closing
	return out


## A mission's closing lines (M5-T10): the line to say as it ends, by the result's reason or by "success" / "failure"; or an
## error string. The dialog file is checked by `tests/unit/test_dialog_ids.gd`, not here.
static func _closing_lines(raw: Variant, source: String) -> Variant:
	if not (raw is Dictionary):
		return "%s: mission.closing_lines must be an object (reason, success or failure -> line id)" % source
	var out: Dictionary = {}
	for key: Variant in raw as Dictionary:
		var line_id: Variant = (raw as Dictionary)[key]
		if not (line_id is String) or (line_id as String).strip_edges().is_empty():
			return "%s: mission.closing_lines.%s must be a line id" % [source, key]
		out[str(key)] = StringName((line_id as String).strip_edges())
	return out


## One spawn by the scenario's rules (a mission's `m.spawn`, M5-T05), or an error string naming `where`.
static func parse_spawn(raw: Variant, where: String, system: StringName) -> Variant:
	return _spawn(raw, where, system)


## `wings[]` (M3-T10): each wing's declaration, its members appended to `spawns`, or an error string. `leader` is "player",
## a spawn's name, or absent (the first ship leads). `faction`, when given, must be every member's. `formation` is a `Formation.NAMES` word, default
## finger_four; `order` an `AiContext.ORDER_WORDS` word, default cover for a player-led wing, else engage.
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
		if not _is_ship_type(StringName(str(key))):
			return "%s: unknown ship type (expected one of %s or %s)" % [where, ShipCatalog.types(), RANDOM_CIVILIAN]
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
	if not (type is String) or not _is_ship_type(StringName(type as String)):
		return "%s: type must be one of %s or %s, got %s" % [where, ShipCatalog.types(), RANDOM_CIVILIAN, JSON.stringify(type)]
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
	var pods: Variant = entry.get("cargo_pods", -1)
	if typeof(pods) != TYPE_FLOAT and typeof(pods) != TYPE_INT or float(pods) != floorf(float(pods)) \
			or int(pods) < -1 or int(pods) > CargoPods.MAX_PODS:
		return "%s: cargo_pods must be a whole number from 0 to %d" % [where, CargoPods.MAX_PODS]
	var forward: Variant = _vector3(entry.get("forward", [0.0, 0.0, 0.0]))
	if forward == null:
		return "%s: forward must be [x, y, z] (numbers)" % where
	return {"type": StringName(type as String), "name": str(entry.get("name", "")), "anchor": StringName(anchor as String),
			"offset": offset as Vector3, "velocity": velocity as Vector3, "at_s": float(at_s), "behaviour": behaviour,
			"wing": (wing as String).strip_edges(), "cargo_pods": int(pods), "forward": forward as Vector3}


## An orientation whose forward axis (-Z) points along `forward`, up as close to +Y as possible.
static func basis_facing(forward: Vector3) -> Basis:
	var f: Vector3 = forward.normalized()
	var up: Vector3 = Vector3.UP if absf(f.dot(Vector3.UP)) < 0.999 else Vector3.BACK
	return Basis.looking_at(f, up)


# A `jumpgates[]` entry (M6-T14, M6-T09): `position` [x, y, z] puts it there; else `Main` puts it on the rail of the star-system
# place `place` (default "jumpgate") from the ephemeris, its front (-Z, the way its arrivals leave) toward the place `from`
# (default "babylon5") unless `facing` is given. Only when the system cannot place it does it stand `bearing` (default
# [0, 0, -1]) from `station` ([0, 0, 0] unless given) at the data's distance between the two. Returns the entry or why it is
# wrong.
static func _jumpgate(entry: Dictionary, prop_name: String, system: StringName, where: String) -> Variant:
	var position: Variant = null
	if entry.has("position"):
		position = _universe_pos(entry["position"], system)
		if position == null:
			return "%s: position must be [x, y, z] (numbers)" % where
	var station: Variant = _universe_pos(entry.get("station", [0.0, 0.0, 0.0]), system)
	if station == null:
		return "%s: station must be [x, y, z] (numbers)" % where
	var bearing: Variant = _vector3(entry.get("bearing", [0.0, 0.0, -1.0]))
	if bearing == null or (bearing as Vector3).is_zero_approx():
		return "%s: bearing must be a non-zero [x, y, z]" % where
	var facing: Variant = _vector3(entry["facing"]) if entry.has("facing") else -(bearing as Vector3)
	if facing == null or (facing as Vector3).is_zero_approx():
		return "%s: facing must be a non-zero [x, y, z]" % where
	for key: String in ["place", "from"]:
		if entry.has(key) and (not (entry[key] is String) or (entry[key] as String).strip_edges().is_empty()):
			return "%s: %s must be a star-system place id" % [where, key]
	return {"type": JUMPGATE, "name": prop_name, "position": position, "velocity": Vector3.ZERO,
			"place": StringName(str(entry.get("place", "jumpgate"))), "from": StringName(str(entry.get("from", "babylon5"))),
			"station": station, "bearing": (bearing as Vector3).normalized(), "facing": (facing as Vector3).normalized()}


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


## The player's launch bay (M7-T08, D76): `player.launch_bay` ("cobra_bay_<wing>_<door>"), or `player.launch` ({"wing", "door"})
## written as that name; "" when the scenario starts in flight, or a failure dictionary.
static func _launch_bay(player: Dictionary, source: String) -> Variant:
	var named: Variant = player.get("launch_bay")
	var parts: Variant = player.get("launch")
	if named != null and parts != null:
		return _failure("%s: player takes launch_bay or launch, not both" % source)
	if named != null:
		if not (named is String) or not (named as String).begins_with(LAUNCH_BAY_PREFIX):
			return _failure("%s: player.launch_bay must name a bay, \"%s<wing>_<door>\"" % [source, LAUNCH_BAY_PREFIX])
		return named
	if parts == null:
		return ""
	if not (parts is Dictionary) or not ((parts as Dictionary).get("wing") is String) or not _is_number((parts as Dictionary).get("door")):
		return _failure("%s: player.launch must be {\"wing\": \"alpha\", \"door\": 1 to 6}" % source)
	return "%s%s_%d" % [LAUNCH_BAY_PREFIX, ((parts as Dictionary)["wing"] as String).to_lower(), int((parts as Dictionary)["door"])]


static func _empty() -> Dictionary:
	return {"ok": false, "error": "", "scenario_id": &"", "system_id": &"local",
			"player": {"position": UniversePos.new(), "forward": Vector3.FORWARD, "basis": Basis.IDENTITY,
					"velocity": Vector3.ZERO, "launch_bay": ""},
			"props": [] as Array[Dictionary], "jumpgates": [] as Array[Dictionary], "pools": {}, "waves": [] as Array[Dictionary],
			"loop": {"from_wave": 0, "add_per_loop": 1}, "routes": [] as Array[Route], "spawns": [] as Array[Dictionary],
			"wings": [] as Array[Dictionary], "mission": {}, "cinematics": {}, "belts": [] as Array[Dictionary],
			"civilian_names": {}, "placeholders": {}, "station": {}}


static func _failure(message: String) -> Dictionary:
	var result: Dictionary = _empty()
	result["error"] = message
	return result
