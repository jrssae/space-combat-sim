@tool
extends EditorPlugin
## Registers the project's export steps while the editor (or a headless export) runs.

var _glsl: EditorExportPlugin


func _enter_tree() -> void:
	_glsl = preload("res://addons/scs_export/runtime_glsl_export_plugin.gd").new()
	add_export_plugin(_glsl)


func _exit_tree() -> void:
	remove_export_plugin(_glsl)
	_glsl = null
