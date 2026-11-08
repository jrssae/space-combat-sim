@tool
extends EditorExportPlugin
## Puts the GLSL sources the game compiles at run time into the pack. Our own shaders are kept as files by their `.import`
## (`importer="keep"`); the vendored lens flare's shader is imported as an `RDShaderFile`, which ships no source, and its
## folder is not ours to edit, so it is added here.

## Sources added as they are, at the same `res://` path.
const FILES: PackedStringArray = ["res://addons/lens_effects/lens_flares.glsl"]


func _get_name() -> String:
	return "scs_runtime_glsl"


func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	for path: String in FILES:
		add_file(path, FileAccess.get_file_as_bytes(path), false)
