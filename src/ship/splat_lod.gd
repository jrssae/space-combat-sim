class_name SplatLod
extends RefCounted
## Which PLY of an asset a ship draws at a given level of detail (architecture §16 D35). Level 0 is the asset's own
## `<asset_id>.ply`; a lower level (1 = about a quarter of the splats) is whatever the generator's `manifest.json` lists for it
## under `lods`. Pure: reads a file or a Dictionary, never touches the scene tree.

const ASSET_ROOT: String = ShipSpec.ASSET_ROOT


## The PLY file name `manifest` lists for `level`, or "" when it lists none. Godot parses every JSON number as a float, so the
## levels compare as ints.
static func file_for(manifest: Dictionary, level: int) -> String:
	var lods: Variant = manifest.get("lods")
	if not (lods is Array):
		return ""
	for entry: Variant in lods as Array:
		if not (entry is Dictionary):
			continue
		var lod: Dictionary = entry
		var number: Variant = lod.get("level")
		if (number is int or number is float) and int(number) == level and lod.get("file") is String:
			return lod["file"]
	return ""


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
