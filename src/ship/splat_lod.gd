class_name SplatLod
extends RefCounted
## Which PLY of an asset a ship draws at a given level of detail (architecture §16 D35). Level 0 is the asset's own
## `<asset_id>.ply`; a lower level (1 = about a quarter of the splats) is whatever the generator's `manifest.json` lists for it
## under `lods`. Pure: reads a file or a Dictionary, never touches the scene tree.

const ASSET_ROOT: String = "res://assets/generated"


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


## `res://` path of the PLY for `asset_id` at `level`. Level 0 (or below) is `<asset_id>.ply` and never reads the manifest. A higher
## level is looked up in `manifest.json`; "" when the manifest cannot be read or does not list it.
static func ply_path(asset_id: String, level: int, asset_root: String = ASSET_ROOT) -> String:
	var dir: String = asset_root.path_join(asset_id)
	if level <= 0:
		return dir.path_join(asset_id + ".ply")
	var file := FileAccess.open(dir.path_join("manifest.json"), FileAccess.READ)
	if file == null:
		return ""
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not (data is Dictionary):
		return ""
	var file_name: String = file_for(data as Dictionary, level)
	return dir.path_join(file_name) if not file_name.is_empty() else ""
