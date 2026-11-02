class_name StarCatalog
extends RefCounted
## Each system's star (Q30): `data/star_systems.json`, keyed by the scenario's `system_id`. A new system is one more entry.

const PATH: String = "res://data/star_systems.json"
## When the table cannot be read at all.
const FALLBACK_K: float = 5084.0


## The temperature of `system_id`'s star, from the data file.
static func temperature_k(system_id: StringName) -> float:
	var file := FileAccess.open(PATH, FileAccess.READ)
	var table: Dictionary = parse(file.get_as_text() if file != null else "")
	if table.has("error"):
		push_warning("StarCatalog: %s: %s" % [PATH, table["error"]])
	return temperature_in(table, system_id)


## The file's table, or a table with only an `error`.
static func parse(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		return {"error": "not a JSON object"}
	var data: Dictionary = json.data
	var systems: Variant = data.get("systems")
	var fallback: Variant = data.get("default")
	if not (systems is Dictionary) or not (fallback is String) or not (systems as Dictionary).has(fallback):
		return {"error": "default must name an entry of systems"}
	for key: Variant in systems as Dictionary:
		var entry: Variant = (systems as Dictionary)[key]
		if not (entry is Dictionary) or not ((entry as Dictionary).get("temperature_k") is float):
			return {"error": "systems.%s.temperature_k must be a number" % str(key)}
	return data


## The star's temperature in `table`: the default star's for a system it does not list.
static func temperature_in(table: Dictionary, system_id: StringName) -> float:
	if table.has("error") or not table.has("systems"):
		return FALLBACK_K
	var systems: Dictionary = table["systems"]
	var entry: Dictionary = systems.get(String(system_id), systems[table["default"]])
	return float(entry["temperature_k"])
