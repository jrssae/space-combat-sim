class_name FactionTable
extends RefCounted
## The faction relation table parsed from `data/factions.json` (architecture §16 D30). Pure: no scene tree. `Factions`
## holds the active table and answers every combat system's `relation` query through it.
##
## File shape:
##
##     {"factions":  [{"id": "earth_alliance", "name": "Earth Alliance"}, ...],
##      "relations": [{"a": "earth_alliance", "b": "raiders", "relation": "hostile"}, ...],
##      "default":   "neutral"}
##
## Rule, checked in this order (M2's rule with the data behind it):
## 1. Same faction id -> FRIENDLY, always (this includes two identical unknown ids).
## 2. Either id is not listed under `factions` -> NEUTRAL.
## 3. The pair is listed under `relations` -> that relation. Pairs are symmetric: `a`/`b` order does not matter.
## 4. Otherwise -> `default`.
##
## `from_dict` validates everything and returns path-qualified errors (`relations[0].relation must be one of ...`);
## a broken file never produces a table, so a caller that keeps its current table is unchanged by a bad load.
## `set_relation` changes one pair in memory (the console's `relation` command); nothing here writes a file.

const RELATION_NAMES: Array[StringName] = [&"friendly", &"neutral", &"hostile"]
## Faction ids are lower_snake so they type cleanly in the console and in scenario files.
const ID_PATTERN: String = "^[a-z0-9_]{1,32}$"

# id (StringName) -> display name (String), in file order.
var _names: Dictionary = {}
# id -> {other id -> relation (int)}, symmetric: both directions are stored so a lookup allocates nothing.
var _matrix: Dictionary = {}
# The listed pairs in the order they were set: {"a": StringName, "b": StringName, "relation": int}.
var _pairs: Array[Dictionary] = []
var _default: int = Factions.Relation.NEUTRAL


## The M2 rule as a table: `earth_alliance`, `raiders` and `neutral`, the one hostile pair, default neutral. What
## `Factions` falls back to when the data file is broken; `data/factions.json` holds the same values.
static func builtin() -> FactionTable:
	var table := FactionTable.new()
	table._add_faction(Factions.EARTH_ALLIANCE, "Earth Alliance")
	table._add_faction(Factions.RAIDERS, "Raiders")
	table._add_faction(Factions.NEUTRAL, "Neutral")
	table._store_pair(Factions.EARTH_ALLIANCE, Factions.RAIDERS, Factions.Relation.HOSTILE)
	return table


## Reads and validates the file at `path` (`res://` or `user://`). Same result as `from_dict`, with `path` in the error.
static func load_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("%s: cannot open (%s)" % [path, error_string(FileAccess.get_open_error())])
	return parse(file.get_as_text(), path)


## Validates faction JSON text; `source` names it in error messages.
static func parse(text: String, source: String = "factions") -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		return _failure("%s: invalid JSON at line %d: %s" % [source, json.get_error_line(), json.get_error_message()])
	var result: Dictionary = from_dict(json.data)
	if not result["ok"]:
		result["error"] = "%s: %s" % [source, result["error"]]
	return result


## Validates already parsed data. Returns `{"ok": bool, "error": String, "table": FactionTable}`; `error` is "" when ok and
## names the JSON path of the first problem otherwise, and `table` is null on failure.
static func from_dict(data: Variant) -> Dictionary:
	if not (data is Dictionary):
		return _failure("the root must be an object")
	var root: Dictionary = data
	var table := FactionTable.new()

	var factions: Variant = root.get("factions")
	if not (factions is Array) or (factions as Array).is_empty():
		return _failure("factions must be a non-empty array")
	var id_pattern: RegEx = RegEx.create_from_string(ID_PATTERN)
	var listed_at: Dictionary = {}  # id (String) -> "factions[i]"
	var index: int = 0
	for raw: Variant in factions as Array:
		var path: String = "factions[%d]" % index
		index += 1
		if not (raw is Dictionary):
			return _failure("%s must be an object" % path)
		var entry: Dictionary = raw
		var id: Variant = entry.get("id")
		if not (id is String) or id_pattern.search(id as String) == null:
			return _failure("%s.id must match %s, got %s" % [path, ID_PATTERN, JSON.stringify(id)])
		var display: Variant = entry.get("name")
		if not (display is String) or (display as String).strip_edges().is_empty():
			return _failure("%s.name must be a non-empty string, got %s" % [path, JSON.stringify(display)])
		if listed_at.has(id):
			return _failure("%s.id %s repeats %s.id" % [path, JSON.stringify(id), listed_at[id]])
		listed_at[id] = path
		table._add_faction(StringName(id as String), display as String)

	var default_name: Variant = root.get("default")
	var default_relation: int = relation_from_name(default_name)
	if default_relation < 0:
		return _failure("default must be one of %s, got %s" % [_choices(), JSON.stringify(default_name)])
	table._default = default_relation

	var relations: Variant = root.get("relations")
	if not (relations is Array):
		return _failure("relations must be an array")
	var set_at: Dictionary = {}  # sorted pair key -> "relations[i]"
	index = 0
	for raw: Variant in relations as Array:
		var path: String = "relations[%d]" % index
		index += 1
		if not (raw is Dictionary):
			return _failure("%s must be an object" % path)
		var entry: Dictionary = raw
		for side: String in ["a", "b"]:
			var id: Variant = entry.get(side)
			if not (id is String) or not listed_at.has(id):
				return _failure("%s.%s must be one of the listed faction ids (%s), got %s" % [path, side,
						", ".join(PackedStringArray(table.ids())), JSON.stringify(id)])
		var a := StringName(entry["a"] as String)
		var b := StringName(entry["b"] as String)
		if a == b:
			return _failure("%s pairs %s with itself (a faction is always friendly to itself)" % [path,
					JSON.stringify(entry["a"])])
		var rel: int = relation_from_name(entry.get("relation"))
		if rel < 0:
			return _failure("%s.relation must be one of %s, got %s" % [path, _choices(),
					JSON.stringify(entry.get("relation"))])
		var key: String = _pair_key(a, b)
		if set_at.has(key):
			return _failure("%s repeats the pair %s/%s already set by %s (pairs are symmetric)" % [path, a, b,
					set_at[key]])
		set_at[key] = path
		table._store_pair(a, b, rel)
	return {"ok": true, "error": "", "table": table}


## The `Factions.Relation` value for "friendly" / "neutral" / "hostile" (case-insensitive), or -1 for anything else.
static func relation_from_name(text: Variant) -> int:
	if not (text is String or text is StringName):
		return -1
	return RELATION_NAMES.find(StringName(String(text).to_lower()))


## "friendly" / "neutral" / "hostile".
static func relation_name(rel: int) -> StringName:
	return RELATION_NAMES[rel] if rel >= 0 and rel < RELATION_NAMES.size() else &"neutral"


## How a ship of faction `a` regards a ship of faction `b`. Symmetric.
func relation(a: StringName, b: StringName) -> Factions.Relation:
	if a == b:
		return Factions.Relation.FRIENDLY
	if not _names.has(a) or not _names.has(b):
		return Factions.Relation.NEUTRAL
	var row: Dictionary = _matrix[a]
	return int(row.get(b, _default)) as Factions.Relation


## True when `id` is listed under `factions`.
func has(id: StringName) -> bool:
	return _names.has(id)


## Every listed faction id, in file order.
func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _names.keys():
		out.append(id)
	return out


## The listed name of a faction; an unlisted id is its own name.
func display_name(id: StringName) -> String:
	return _names.get(id, String(id))


## The relation of a known pair that `relations` does not list.
func default_relation() -> Factions.Relation:
	return _default as Factions.Relation


## The listed pairs, each {"a": StringName, "b": StringName, "relation": Factions.Relation}, in the order they were set.
func listed_pairs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for pair: Dictionary in _pairs:
		out.append(pair.duplicate())
	return out


## Sets (or changes) the relation of two listed factions for as long as this table lives. Returns "" or why not.
func set_relation(a: StringName, b: StringName, rel: Factions.Relation) -> String:
	if not _names.has(a):
		return "unknown faction '%s'" % a
	if not _names.has(b):
		return "unknown faction '%s'" % b
	if a == b:
		return "a faction is always friendly to itself"
	_store_pair(a, b, rel)
	return ""


func _add_faction(id: StringName, display: String) -> void:
	_names[id] = display
	_matrix[id] = {}


func _store_pair(a: StringName, b: StringName, rel: int) -> void:
	(_matrix[a] as Dictionary)[b] = rel
	(_matrix[b] as Dictionary)[a] = rel
	for pair: Dictionary in _pairs:
		if (pair["a"] == a and pair["b"] == b) or (pair["a"] == b and pair["b"] == a):
			pair["relation"] = rel
			return
	_pairs.append({"a": a, "b": b, "relation": rel})


static func _pair_key(a: StringName, b: StringName) -> String:
	return "%s|%s" % [a, b] if String(a) < String(b) else "%s|%s" % [b, a]


static func _choices() -> String:
	return "|".join(PackedStringArray(RELATION_NAMES))


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message, "table": null}
