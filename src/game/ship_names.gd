class_name ShipNames
extends RefCounted
## The names a hull class's ships are given (M10-T21), read from `data/ships/names.json`: a list per catalogue type (the Omegas'
## Greek names) and a prefix per faction (`EAS`), so a scenario, mission or console spawn names a capital the same way every
## run. A type with no list has no names here; its caller keeps its own label.

const FILE: String = "res://data/ships/names.json"

static var _cache: Dictionary = {}


## The file's lists, read on first use: `{"prefixes": {faction: prefix}, "names": {type: [name, ...]}}`.
static func data() -> Dictionary:
	if _cache.is_empty():
		_cache = parse(FileAccess.get_file_as_string(FILE))
	return _cache


## The lists in `text`, with anything malformed dropped (a broken file names nothing rather than failing a spawn).
static func parse(text: String) -> Dictionary:
	var json := JSON.new()
	var raw: Dictionary = json.data if json.parse(text) == OK and json.data is Dictionary else {}
	var prefixes: Dictionary = {}
	if raw.get("prefixes") is Dictionary:
		for faction: Variant in raw["prefixes"]:
			prefixes[StringName(str(faction))] = str(raw["prefixes"][faction])
	var names: Dictionary = {}
	if raw.get("names") is Dictionary:
		for type: Variant in raw["names"]:
			var list: PackedStringArray = []
			if raw["names"][type] is Array:
				for n: Variant in raw["names"][type]:
					if n is String and not (n as String).is_empty():
						list.append(n)
			if not list.is_empty():
				names[StringName(str(type))] = list
	var numbers: Dictionary = {}
	if raw.get("hull_numbers") is Dictionary:
		for n: Variant in raw["hull_numbers"]:
			numbers[str(n)] = str(int(raw["hull_numbers"][n]))
	return {"prefixes": prefixes, "names": names, "hull_numbers": numbers}


## The names a ship of `type` may carry, in order (empty when the type has none).
static func names_for(type: StringName) -> PackedStringArray:
	return (data()["names"] as Dictionary).get(type, PackedStringArray())


## The `index`th name for a ship of `type` flying for `faction`: its faction's prefix and the list's name, with a number once the
## list has gone round ("EAS Agamemnon", then "EAS Agamemnon 2"); "" when the type has no names.
static func pick(type: StringName, faction: StringName, index: int, lists: Dictionary = {}) -> String:
	var source: Dictionary = lists if not lists.is_empty() else data()
	var names: PackedStringArray = (source["names"] as Dictionary).get(type, PackedStringArray())
	if names.is_empty():
		return ""
	var i: int = maxi(index, 0)
	var chosen: String = names[i % names.size()]
	@warning_ignore("integer_division")
	var round_number: int = i / names.size() + 1
	if round_number > 1:
		chosen = "%s %d" % [chosen, round_number]
	var prefix: String = str((source["prefixes"] as Dictionary).get(faction, ""))
	return chosen if prefix.is_empty() else "%s %s" % [prefix, chosen]


## The number painted on the hull of the ship called `display_name` ("EAS Hyperion 2" wears Hyperion's number), or "" when its name
## has none. A repeated name (the "2") keeps its number.
static func hull_number_of(display_name: String, lists: Dictionary = {}) -> String:
	var source: Dictionary = lists if not lists.is_empty() else data()
	var numbers: Dictionary = source.get("hull_numbers", {})
	var name: String = HullMarks.name_of(display_name)
	if numbers.has(name):
		return numbers[name]
	var words: PackedStringArray = name.split(" ", false)
	if words.size() > 1 and words[words.size() - 1].is_valid_int():
		return numbers.get(" ".join(words.slice(0, words.size() - 1)), "")
	return ""
