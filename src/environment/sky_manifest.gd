class_name SkyManifest
extends RefCounted
## The part of `assets/generated/sky_default/manifest.json` that the sky needs at run time (tools/procgen README).
## Pure: parses text or reads a file, never touches the scene tree. A missing or malformed manifest is not fatal:
## the offset stays zero, `valid` is false and `error` says why, so the caller can warn and carry on.

## Godot-frame vector the generator subtracted when it re-centred the splats on their centroid. GDGS subtracts the
## centroid again at import, so the imported sphere is shifted by this much: authored position = imported position +
## centroid_offset, and the sky node belongs at `camera + centroid_offset`.
var centroid_offset: Vector3 = Vector3.ZERO
## Whether the manifest was read and contained a usable `centroid_offset`.
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
	var data: Variant = json.data
	if not (data is Dictionary):
		manifest.error = "manifest root is not an object"
		return manifest
	var offset: Variant = (data as Dictionary).get("centroid_offset")
	if not (offset is Array) or (offset as Array).size() != 3:
		manifest.error = "manifest has no centroid_offset [x, y, z]"
		return manifest
	var parts: Array = offset
	for part: Variant in parts:
		if not (part is float or part is int):
			manifest.error = "centroid_offset holds a non-number"
			return manifest
	manifest.centroid_offset = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	manifest.valid = true
	return manifest
