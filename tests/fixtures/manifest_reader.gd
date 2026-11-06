class_name ManifestReader
extends RefCounted
## Test helper: reads and validates a generator `manifest.json` (tools/procgen/README.md, "Manifest") so the asset
## tests can iterate over whatever assets exist. Pure: parses text or reads a file, never touches the scene tree.
## `SkyManifest` only extracts the star field and the panorama; this covers the rest (aabb, files, the textured mesh) and is
## deliberately independent of it, so a parser bug cannot hide in both. The manifest is in the Godot frame (+X right, +Y up,
## -Z forward).

const GODOT_FRAME: String = "godot"
const METRES: String = "m"

## Asset directory name, which is also the manifest's `asset_id`.
var asset_id: String = ""
## `res://assets/generated/<asset_id>`, no trailing slash.
var directory: String = ""
var data: Dictionary = {}
## The asset's bounds, Godot frame (`aabb_min` / `aabb_max`).
var aabb: AABB = AABB()
var centroid_offset: Vector3 = Vector3.ZERO
## Role (`obj`, `mesh`, `cockpit_mesh`, `hardpoints`, `panorama`, ...) -> file name relative to `directory`.
var files: Dictionary[String, String] = {}
## `kind`: `asset` (the default) or `audio` (a sound set: `sounds`, no bounds).
var kind: String = "asset"
## For an audio asset, sound name -> its manifest entry (`file`, `samples`, `sample_rate`, `duration_s`, `peak_dbfs`, maybe loop points).
var sounds: Dictionary = {}
## Why the manifest is unusable. Empty when valid.
var errors: PackedStringArray = PackedStringArray()


## The manifest of `<directory>/manifest.json`. `asset_id` must equal the directory's name.
static func load_dir(directory_path: String) -> ManifestReader:
	var path: String = directory_path.trim_suffix("/")
	var reader := ManifestReader.new()
	reader.directory = path
	reader.asset_id = path.get_file()
	var file := FileAccess.open(path + "/manifest.json", FileAccess.READ)
	if file == null:
		reader.errors.append("cannot open %s/manifest.json (error %d); run scripts/gen_assets.sh" % [path, FileAccess.get_open_error()])
		return reader
	reader._parse(file.get_as_text())
	return reader


## Parses `text` as the manifest of the asset called `id` (no file access; `directory` stays empty).
static func from_json_text(text: String, id: String) -> ManifestReader:
	var reader := ManifestReader.new()
	reader.asset_id = id
	reader._parse(text)
	return reader


func is_valid() -> bool:
	return errors.is_empty()


func errors_text() -> String:
	return "; ".join(errors)


## `res://` path of a file from the manifest's `files` map, or "" when the role is absent.
func file_path(role: String) -> String:
	if not files.has(role):
		return ""
	return "%s/%s" % [directory, files[role]]


func _parse(text: String) -> void:
	var json := JSON.new()
	if json.parse(text) != OK:
		errors.append("manifest is not valid JSON (line %d: %s)" % [json.get_error_line(), json.get_error_message()])
		return
	if not (json.data is Dictionary):
		errors.append("manifest root is not an object")
		return
	data = json.data
	if data.get("asset_id") != asset_id:
		errors.append("asset_id is %s, expected %s" % [data.get("asset_id"), asset_id])
	if data.get("frame") != GODOT_FRAME:
		errors.append("frame is %s, expected %s" % [data.get("frame"), GODOT_FRAME])
	if data.get("units") != METRES:
		errors.append("units is %s, expected %s" % [data.get("units"), METRES])
	kind = String(data.get("kind", "asset"))
	if kind == "audio":
		_parse_sounds()
		_parse_files()
		return
	if kind != "asset":
		errors.append("kind is %s, expected asset or audio" % kind)
		return
	var box_min: Variant = _vec3("aabb_min")
	var box_max: Variant = _vec3("aabb_max")
	if box_min is Vector3 and box_max is Vector3:
		var lo: Vector3 = box_min
		var hi: Vector3 = box_max
		if lo.x < hi.x and lo.y < hi.y and lo.z < hi.z:
			aabb = AABB(lo, hi - lo)
		else:
			errors.append("aabb_min %s is not below aabb_max %s on every axis" % [lo, hi])
	var offset: Variant = _vec3("centroid_offset")
	if offset is Vector3:
		centroid_offset = offset
	_parse_files()


func _parse_sounds() -> void:
	var raw: Variant = data.get("sounds")
	if not (raw is Dictionary) or (raw as Dictionary).is_empty():
		errors.append("sounds is missing or empty")
		return
	for sound_name: Variant in raw as Dictionary:
		var entry: Variant = (raw as Dictionary)[sound_name]
		if not (entry is Dictionary) or not ((entry as Dictionary).get("file") is String) or _whole_number((entry as Dictionary).get("samples")) == null:
			errors.append("sounds entry %s needs a file and an integer samples" % sound_name)
			continue
		sounds[String(sound_name)] = entry


func _parse_files() -> void:
	var raw: Variant = data.get("files")
	if not (raw is Dictionary):
		errors.append("files is missing or not an object")
		return
	var map: Dictionary = raw
	for role: Variant in map:
		var value: Variant = map[role]
		if role is String and value is String:
			files[role] = value
		else:
			errors.append("files entry %s -> %s is not a string pair" % [role, value])


## `key` as a Vector3, or null (after recording an error) when it is not a list of three numbers.
func _vec3(key: String) -> Variant:
	var raw: Variant = data.get(key)
	if not (raw is Array) or (raw as Array).size() != 3:
		errors.append("%s is missing or not [x, y, z]" % key)
		return null
	var parts: Array = raw
	for part: Variant in parts:
		if not (part is float or part is int):
			errors.append("%s holds a non-number" % key)
			return null
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))


## `value` as an int when it is a JSON number with no fractional part (Godot parses every number as a float), else null.
static func _whole_number(value: Variant) -> Variant:
	if value is int:
		return value
	if value is float and is_equal_approx(floorf(value), value):
		return int(value)
	return null
