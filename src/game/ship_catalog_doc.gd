class_name ShipCatalogDoc
extends RefCounted
## `docs/catalogue/ships.md` (M10-T61): the ship catalogue as a page a mission author reads instead of the code, built from
## `data/ships/catalogue.json`, each type's `ShipSpec` and its generated manifest and hardpoints. `scripts/gen_ship_catalog.sh`
## writes it; `test_ship_catalog_doc.gd` fails while the committed page is stale. `render` is pure; `rows` reads the files.

const OUT_PATH: String = "res://docs/catalogue/ships.md"
const COLUMNS: Array[String] = ["id", "faction", "role", "size", "hull", "weapons", "jump", "fighters"]
const HEADERS: Array[String] = ["id", "faction", "role", "size L x W x H (m)", "hull points", "weapons", "jump capable",
		"carries fighters"]
const FLAG_COLUMNS: Array[String] = ["id", "spec", "ai_profile", "pooled", "random_pool", "docking", "look_sheet", "name", "callsign"]


## One row of facts per catalogue entry, in catalogue order, every value already text.
static func rows(data: ShipCatalogData, asset_root: String = ShipSpec.ASSET_ROOT) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: StringName in data.ids():
		var spec: ShipSpec = load(data.spec_path(id)) as ShipSpec
		var asset: String = data.text(id, "asset")
		var role: String = data.text(id, "role")
		if role == "capital":
			role = "capital (%s)" % data.text(id, "capital_class")
		var row: Dictionary = {"id": String(id), "faction": data.text(id, "faction"), "role": role,
				"size": _size(_json(asset_root.path_join(asset).path_join("manifest.json"))), "hull": "?", "weapons": "?",
				"jump": "?", "fighters": _fighters(_json(asset_root.path_join(asset).path_join("hardpoints.json")))}
		if spec != null:
			row["hull"] = "%d" % roundi(spec.hull_max)
			row["weapons"] = _weapons(spec)
			row["jump"] = "yes" if spec.can_open_jump_point else "no"
		for key: String in FLAG_COLUMNS:
			if not row.has(key):
				if key == "pooled":
					row[key] = "yes" if data.is_pooled(id) else "no"
				elif key == "random_pool":
					row[key] = "" if data.role(id) != &"civilian" else ("traffic" if data.is_traffic_only(id) else ("yes" if data.in_random_pool(id) else "no"))
				else:
					row[key] = data.text(id, key)
		out.append(row)
	return out


## The page for `rows`.
static func render(p_rows: Array[Dictionary]) -> String:
	var lines: PackedStringArray = [
		"# Ship catalogue",
		"",
		"Generated from `data/ships/catalogue.json`, each type's `ShipSpec` and its generated manifest and hardpoints by",
		"`ShipCatalogDoc` (M10-T61). Do not edit by hand: after a change run `scripts/gen_assets.sh` (if a hull changed) and",
		"`scripts/gen_ship_catalog.sh`. `tests/unit/test_ship_catalog_doc.gd` fails while this page is stale.",
		"",
		"Adding a hull: one entry in the catalogue (keys in `src/game/ship_catalog_data.gd`) and one `ShipSpec` `.tres` in",
		"`assets/ships/`. Scenarios name ships by `id`; never rename one (recordings and saved careers hold them).",
		"",
		"## Hulls",
		"",
	]
	lines.append_array(_table(p_rows, COLUMNS, HEADERS))
	lines.append_array(["", "## What other code reads from each entry", "",
		"`pooled`: `ShipPool` builds it by type. `random_pool`: whether random traffic, encounters and `random_civilian` spawns",
		"may draw a civilian (`no`: only a mission that names it places it; `traffic`: the traffic and encounters of a scenario",
		"that pools it, never a mission's `random_civilian`). `docking`: `tunnel` (the main docking bay) or",
		"`cargo_bay`. `look_sheet`: what `sheet <asset>` parks. `name`: the target preview's class line. `callsign`: a",
		"civilian's radio name.", ""])
	lines.append_array(_table(p_rows, FLAG_COLUMNS, FLAG_COLUMNS))
	return "\n".join(lines) + "\n"


static func _table(p_rows: Array[Dictionary], keys: Array[String], headers: Array[String]) -> PackedStringArray:
	var out: PackedStringArray = ["| %s |" % " | ".join(headers), "|%s" % "---|".repeat(headers.size())]
	for row: Dictionary in p_rows:
		var cells: PackedStringArray = []
		for key: String in keys:
			var cell: String = str(row.get(key, ""))
			cells.append("`%s`" % cell if key in ["id", "spec"] and not cell.is_empty() else (cell if not cell.is_empty() else "-"))
		out.append("| %s |" % " | ".join(cells))
	return out


static func _size(manifest: Dictionary) -> String:
	if not (manifest.get("aabb_min") is Array and manifest.get("aabb_max") is Array):
		return "?"
	var lo: Array = manifest["aabb_min"]
	var hi: Array = manifest["aabb_max"]
	return "%.1f x %.1f x %.1f" % [float(hi[2]) - float(lo[2]), float(hi[0]) - float(lo[0]), float(hi[1]) - float(lo[1])]


static func _weapons(spec: ShipSpec) -> String:
	var out: PackedStringArray = []
	if spec.weapon != null:
		out.append("fixed `%s`" % spec.weapon.resource_path.get_file().get_basename())
	if spec.turret_weapon != null:
		out.append("turrets `%s`" % spec.turret_weapon.resource_path.get_file().get_basename())
	return ", ".join(out) if not out.is_empty() else "none"


static func _fighters(hardpoints: Dictionary) -> String:
	if hardpoints.is_empty():
		return "?"
	var cradles: Variant = hardpoints.get("cradles", [])
	var count: int = (cradles as Array).size() if cradles is Array else 0
	return "yes (%d cradles)" % count if count > 0 else "no"


# A generated JSON file, {} when it is missing (the assets not built) or not an object.
static func _json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
