class_name SkyManifest
extends RefCounted
## The part of `assets/generated/sky_default/manifest.json` that the sky needs at run time (M4-T30c): the star file and its layout,
## and the panorama. Pure: parses text or reads a file, never touches the scene tree. A missing or malformed manifest is not
## fatal: `valid` is false and `error` says why, so the caller can warn and carry on with a black sky.

## The star file's record, as the generator writes it.
const STAR_RECORD: Array[String] = ["dir_x", "dir_y", "dir_z", "red", "green", "blue", "brightness"]
const STAR_FORMAT: String = "float32 little-endian"

## The star file's name, beside the manifest.
var star_file: String = ""
var star_count: int = 0
## The angular radius of a star's disc.
var star_radius_mrad: float = 0.0
## A star's smallest drawn radius on screen.
var star_floor_px: float = 0.0
## The panorama's name beside the manifest, or "" when it was not built.
var panorama_file: String = ""
## Whether the manifest was read and describes a usable star file.
var valid: bool = false
## Why `valid` is false, for log messages. Empty when valid.
var error: String = ""


static func load_file(path: String) -> SkyManifest:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		var missing := SkyManifest.new()
		missing.error = "cannot open %s (error %d); run scripts/gen_assets.sh" % [path, FileAccess.get_open_error()]
		return missing
	return from_json_text(file.get_as_text())


static func from_json_text(text: String) -> SkyManifest:
	var manifest := SkyManifest.new()
	var json := JSON.new()
	if json.parse(text) != OK:
		manifest.error = "manifest is not valid JSON (line %d: %s)" % [json.get_error_line(), json.get_error_message()]
		return manifest
	if not (json.data is Dictionary):
		manifest.error = "manifest root is not an object"
		return manifest
	var data: Dictionary = json.data
	var field: Variant = data.get("star_field")
	if not (field is Dictionary):
		manifest.error = "manifest has no star_field (built before M4-T30c? run scripts/gen_assets.sh)"
		return manifest
	manifest.error = _star_field_error(field as Dictionary)
	if manifest.error != "":
		return manifest
	var star_field: Dictionary = field
	manifest.star_file = star_field["file"]
	manifest.star_count = int(star_field["count"])
	manifest.star_radius_mrad = float(star_field["radius_mrad"])
	manifest.star_floor_px = float(star_field["floor_px"])
	var files: Variant = data.get("files")
	if files is Dictionary and (files as Dictionary).get("panorama") is String:
		manifest.panorama_file = (files as Dictionary)["panorama"]
	manifest.valid = true
	return manifest


## What is wrong with the star field's description, or "".
static func _star_field_error(field: Dictionary) -> String:
	if not (field.get("file") is String) or String(field["file"]).is_empty():
		return "star_field.file is not a file name"
	var count: Variant = field.get("count")
	if not (count is int or count is float) or int(count) < 1:
		return "star_field.count is not a positive number"
	for key: String in ["radius_mrad", "floor_px"]:
		var value: Variant = field.get(key)
		if not (value is int or value is float) or float(value) <= 0.0:
			return "star_field.%s is not a positive number" % key
	if field.get("format") != STAR_FORMAT:
		return "star_field.format is not %s" % STAR_FORMAT
	var record: Variant = field.get("record")
	if not (record is Array) or (record as Array) != STAR_RECORD:
		return "star_field.record is not %s" % str(STAR_RECORD)
	return ""
