class_name SplatLod
extends RefCounted
## Which PLY of an asset a ship draws at a given level of detail (architecture §16 D35). Level 0 is the asset's own
## `<asset_id>.ply`; a lower level (1 = about a quarter of the splats) is whatever the generator's `manifest.json` lists for it
## under `lods`. Pure: reads a file or a Dictionary, never touches the scene tree.

const ASSET_ROOT: String = ShipSpec.ASSET_ROOT


## The manifest entry that lists `level`, or {} when none does. Godot parses every JSON number as a float, so the levels
## compare as ints; an entry that is not a Dictionary or has no numeric level is skipped.
static func entry_for(manifest: Dictionary, level: int) -> Dictionary:
	var lods: Variant = manifest.get("lods")
	if not (lods is Array):
		return {}
	for entry: Variant in lods as Array:
		if not (entry is Dictionary):
			continue
		var lod: Dictionary = entry
		var number: Variant = lod.get("level")
		if (number is int or number is float) and int(number) == level:
			return lod
	return {}


## The PLY file name `manifest` lists for `level`, or "" when it lists none.
static func file_for(manifest: Dictionary, level: int) -> String:
	var file: Variant = entry_for(manifest, level).get("file")
	return file if file is String else ""


## The lighting records file `manifest` lists for `level`, or "" when it lists none.
static func lighting_for(manifest: Dictionary, level: int) -> String:
	var lighting: Variant = entry_for(manifest, level).get("lighting")
	return lighting if lighting is String else ""


## The parsed `manifest.json` of `asset_id`, or {} when it is missing or unreadable. Parse once per ship, then ask it.
static func read_manifest(asset_id: String, asset_root: String = ASSET_ROOT) -> Dictionary:
	var file := FileAccess.open(asset_root.path_join(asset_id).path_join("manifest.json"), FileAccess.READ)
	if file == null:
		return {}
	var data: Variant = JSON.parse_string(file.get_as_text())
	return data if data is Dictionary else {}


## The PLY `manifest`, read once by the caller, lists for `level`, or "" when it lists none.
static func file_path_in(manifest: Dictionary, asset_id: String, level: int, asset_root: String = ASSET_ROOT) -> String:
	var file_name: String = file_for(manifest, level)
	return asset_root.path_join(asset_id).path_join(file_name) if not file_name.is_empty() else ""


## The lighting records of `asset_id` at `level` from an already parsed `manifest`, or "" when it lists none (the sky).
static func lighting_path_in(manifest: Dictionary, asset_id: String, level: int, asset_root: String = ASSET_ROOT) -> String:
	var file_name: String = lighting_for(manifest, level)
	return asset_root.path_join(asset_id).path_join(file_name) if not file_name.is_empty() else ""


## The lighting records of `asset_id` at `level`, or "" when its manifest is missing or lists none. Reads the manifest each
## call: a caller that asks for several levels uses `read_manifest` and `lighting_path_in`.
static func lighting_path(asset_id: String, level: int, asset_root: String = ASSET_ROOT) -> String:
	return lighting_path_in(read_manifest(asset_id, asset_root), asset_id, level, asset_root)


## The PLY file name of the hero level `manifest` lists, or "". The hero is an entry of its own, outside the `lods` ladder
## (the player's ship draws it close up, M3-T24).
static func hero_file_for(manifest: Dictionary) -> String:
	return _hero_name(manifest, "file")


## The lighting records file of the hero level `manifest` lists, or "".
static func hero_lighting_for(manifest: Dictionary) -> String:
	return _hero_name(manifest, "lighting")


## The hero level of `asset_id` as `{"path": String, "lighting": String}`; both are "" when the asset lists no hero level
## (every asset but the player's Starfury) or has no manifest.
static func hero_paths(asset_id: String, asset_root: String = ASSET_ROOT) -> Dictionary:
	var manifest: Dictionary = read_manifest(asset_id, asset_root)
	var dir: String = asset_root.path_join(asset_id)
	var file_name: String = hero_file_for(manifest)
	var light_name: String = hero_lighting_for(manifest)
	return {
		"path": dir.path_join(file_name) if not file_name.is_empty() else "",
		"lighting": dir.path_join(light_name) if not light_name.is_empty() else "",
	}


static func _hero_name(manifest: Dictionary, key: String) -> String:
	var hero: Variant = manifest.get("hero")
	if not (hero is Dictionary):
		return ""
	var name: Variant = (hero as Dictionary).get(key)
	return name if name is String else ""


## The PLY to draw for `asset_id` at `level`, as `{"path": String, "level": int, "warning": String}`.
## - Level 0 (or below): `<asset_id>.ply`, level 0, no warning, and the manifest is not read.
## - A higher level the manifest lists: that file, that level, no warning.
## - A higher level the manifest does not list: LOD0, level 0, and a warning saying so.
## - A manifest that is missing or unreadable: no path (the asset has not been generated, or is damaged), level -1, and one
##   warning saying so. The caller reports the warning and draws nothing, so one problem is one message.
static func resolve(asset_id: String, level: int, asset_root: String = ASSET_ROOT) -> Dictionary:
	var dir: String = asset_root.path_join(asset_id)
	var full: String = dir.path_join(asset_id + ".ply")
	if level <= 0:
		return {"path": full, "level": 0, "warning": ""}
	var manifest_path: String = dir.path_join("manifest.json")
	var file := FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		return {"path": "", "level": -1, "warning": "%s is missing (run scripts/gen_assets.sh); no hull splats at LOD %d" % [manifest_path, level]}
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not (data is Dictionary):
		return {"path": "", "level": -1, "warning": "%s is not a readable manifest; no hull splats at LOD %d" % [manifest_path, level]}
	var file_name: String = file_for(data as Dictionary, level)
	if file_name.is_empty():
		return {"path": full, "level": 0, "warning": "%s lists no LOD %d; drawing LOD0" % [manifest_path, level]}
	return {"path": dir.path_join(file_name), "level": level, "warning": ""}
