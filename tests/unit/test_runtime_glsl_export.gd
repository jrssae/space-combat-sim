extends GutTest
## M4-T44 (F1): the release export must carry every GLSL file the game reads as text at run time. A `.glsl` imported as
## `RDShaderFile` ships only its imported resource, so `RuntimeShader` and the lens flare found nothing in the pack. Our own
## files are kept as files (`importer="keep"`); the vendored flare's shader, which we may not touch, is added by our export
## plugin.

const PLUGIN_CFG: String = "res://addons/scs_export/plugin.cfg"
const EXPORT_PLUGIN: String = "res://addons/scs_export/runtime_glsl_export_plugin.gd"
## Where the game names the shaders it reads: our code, and the vendored flare's default shader path.
const SEARCH_DIRS: PackedStringArray = ["res://src", "res://addons/lens_effects"]


func test_every_runtime_glsl_reaches_the_export() -> void:
	var added: PackedStringArray = _plugin_files()
	var paths: PackedStringArray = _runtime_glsl_paths()
	assert_gt(paths.size(), 4, "found the four effect shaders and the flare's")
	assert_has(paths, "res://addons/lens_effects/lens_flares.glsl", "the flare's shader is among them")
	for path: String in paths:
		assert_true(FileAccess.file_exists(path), "%s exists" % path)
		var kept: bool = _importer(path) == "keep"
		assert_true(kept or added.has(path), "%s is kept as a file or added by the export plugin" % path)


func test_the_export_plugin_is_enabled() -> void:
	var enabled: PackedStringArray = ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())
	assert_has(enabled, PLUGIN_CFG, "the export runs our plugin")


func test_the_plugin_adds_only_files_that_exist() -> void:
	for path: String in _plugin_files():
		assert_true(FileAccess.file_exists(path), "%s exists" % path)


func _plugin_files() -> PackedStringArray:
	var script: GDScript = load(EXPORT_PLUGIN) as GDScript
	assert_not_null(script, "the export plugin loads")
	if script == null:
		return PackedStringArray()
	return script.get_script_constant_map().get("FILES", PackedStringArray())


## The importer a `.glsl` file's `.import` names, or "" without one.
func _importer(path: String) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(path + ".import") != OK:
		return ""
	return str(cfg.get_value("remap", "importer", ""))


func _runtime_glsl_paths() -> PackedStringArray:
	var found: PackedStringArray = []
	var pattern := RegEx.create_from_string("\"(res://[^\"]+\\.glsl)\"")
	for dir: String in SEARCH_DIRS:
		for script_path: String in _scripts_under(dir):
			for m: RegExMatch in pattern.search_all(FileAccess.get_file_as_string(script_path)):
				if not found.has(m.get_string(1)):
					found.append(m.get_string(1))
	return found


func _scripts_under(dir: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			out.append(dir.path_join(file))
	for sub: String in DirAccess.get_directories_at(dir):
		out.append_array(_scripts_under(dir.path_join(sub)))
	return out
