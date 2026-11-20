class_name ShipCatalogData
extends RefCounted
## The ship catalogue file (`data/ships/catalogue.json`, M10-T61), parsed and checked: one entry per hull type, so adding a hull
## is one entry here and one `ShipSpec` `.tres`. Pure; `ShipCatalog` holds the game's copy.
##
## Each entry of `ships[]`:
## - `id`: the type scenarios, recordings and saved careers name. Never rename one.
## - `spec`: the `ShipSpec` resource; `asset`: its generated asset (the spec's `asset_id`, kept here so lookups by asset need no load).
## - `faction`: whose side the type flies for by default; `role`: `fighter`, `civilian` or `capital` (with its `capital_class`).
## - `ai_profile`: the `AiProfile` that flies it by default ("" for the player's own type).
## - `pooled`: `ShipPool` builds it by type (default true); false for a hull that comes another way (the strike carrier rides
##   `CapitalStandin` until capitals get their own).
## - `name`: what the target preview calls the asset (the first entry of an asset that has one).
## - `look_sheet`: `pool` parks a pooled ship of this type for the asset's look sheet, `hull` the bare hull (`LookScene`).
## - `docking`: where it docks at the station: `tunnel` (the main docking bay) or `cargo_bay` (`DockingPlan`).
## - `callsign`: the name an encounter or station civilian of this type calls in under.
## Entry order matters: every list built from the file keeps it, and seeded picks index into those lists.

const ROLES: Array[String] = ["fighter", "civilian", "capital"]
const DOCKING: Array[String] = ["", "tunnel", "cargo_bay"]
const LOOK_SHEETS: Array[String] = ["", "pool", "hull"]
const REQUIRED: Array[String] = ["id", "spec", "asset", "faction", "role"]
const OPTIONAL: Array[String] = ["ai_profile", "capital_class", "pooled", "name", "look_sheet", "docking", "callsign"]

## Why the file was refused ("" when it is good); a refused file has no entries.
var error: String = ""

var _entries: Array[Dictionary] = []
var _by_id: Dictionary[StringName, Dictionary] = {}
# Lists already built, so callers share one read-only copy each.
var _lists: Dictionary = {}


static func load_file(path: String) -> ShipCatalogData:
	if not FileAccess.file_exists(path):
		var missing := ShipCatalogData.new()
		missing.error = "%s: no such file" % path
		return missing
	return parse(FileAccess.get_file_as_string(path), path)


## The catalogue in `text`; `source` names it in errors.
static func parse(text: String, source: String) -> ShipCatalogData:
	var out := ShipCatalogData.new()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		out.error = "%s: not a JSON object" % source
		return out
	var ships: Variant = (parsed as Dictionary).get("ships")
	if not (ships is Array):
		out.error = "%s: ships must be an array" % source
		return out
	for i: int in (ships as Array).size():
		var why: String = out._add((ships as Array)[i])
		if not why.is_empty():
			out.error = "%s: ships[%d]: %s" % [source, i, why]
			out._entries.clear()
			out._by_id.clear()
			return out
	return out


func has(id: StringName) -> bool:
	return _by_id.has(id)


## Whether `id` is listed and `ShipPool` builds it by name.
func is_pooled(id: StringName) -> bool:
	return _by_id.has(id) and bool(_by_id[id].get("pooled", true))


## Every type, in file order.
func ids() -> Array[StringName]:
	return _list("ids", func(_e: Dictionary) -> bool: return true)


## The types `ShipPool` builds by name, in file order.
func pooled_ids() -> Array[StringName]:
	return _list("pooled", func(e: Dictionary) -> bool: return bool(e.get("pooled", true)))


## The types whose `key` is `value`, in file order.
func ids_where(key: String, value: String) -> Array[StringName]:
	return _list("%s=%s" % [key, value], func(e: Dictionary) -> bool: return str(e.get(key, "")) == value)


## A text field of `id`'s entry, "" when absent or for an unknown id.
func text(id: StringName, key: String) -> String:
	return str(_by_id[id].get(key, "")) if _by_id.has(id) else ""


func spec_path(id: StringName) -> String:
	return text(id, "spec")


func faction(id: StringName) -> StringName:
	return StringName(text(id, "faction"))


func role(id: StringName) -> StringName:
	return StringName(text(id, "role"))


## Asset id -> `key`'s value, from the first entry of each asset that has one. With `value`, only entries whose `key` is
## `value`, mapped to their type instead (which type stands for the asset). Shared and read-only.
func by_asset(key: String, value: String = "") -> Dictionary:
	var cache_key: String = "asset:%s=%s" % [key, value]
	if _lists.has(cache_key):
		return _lists[cache_key]
	var out: Dictionary = {}
	for e: Dictionary in _entries:
		var asset: String = e["asset"]
		var v: String = str(e.get(key, ""))
		if out.has(asset) or v.is_empty() or (not value.is_empty() and v != value):
			continue
		out[asset] = v if value.is_empty() else StringName(e["id"])
	out.make_read_only()
	_lists[cache_key] = out
	return out


func _add(raw: Variant) -> String:
	if not (raw is Dictionary):
		return "not an object"
	var e: Dictionary = raw
	for key: String in REQUIRED:
		if not (e.get(key) is String) or (e[key] as String).is_empty():
			return "%s must be a non-empty string" % key
	for key: Variant in e:
		if not REQUIRED.has(key) and not OPTIONAL.has(key):
			return "unknown key %s" % key
	var id := StringName(e["id"])
	if _by_id.has(id):
		return "%s is listed twice" % id
	if not ROLES.has(e["role"]):
		return "role must be one of %s" % [ROLES]
	if e["role"] == "capital" and str(e.get("capital_class", "")).is_empty():
		return "a capital needs its capital_class"
	if not DOCKING.has(str(e.get("docking", ""))):
		return "docking must be one of %s" % [DOCKING]
	if not LOOK_SHEETS.has(str(e.get("look_sheet", ""))):
		return "look_sheet must be one of %s" % [LOOK_SHEETS]
	if e.has("pooled") and not (e["pooled"] is bool):
		return "pooled must be true or false"
	_entries.append(e)
	_by_id[id] = e
	return ""


func _list(key: String, keep: Callable) -> Array[StringName]:
	if not _lists.has(key):
		var out: Array[StringName] = []
		for e: Dictionary in _entries:
			if keep.call(e):
				out.append(StringName(e["id"]))
		out.make_read_only()
		_lists[key] = out
	return _lists[key]
