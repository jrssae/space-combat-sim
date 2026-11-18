extends GutTest
## The warning itself shows only with a real renderer (the headless one has no multimesh storage), so the live check is a windowed
## run (M7-T53); here the helper runs without error and no batched draw bypasses it.
## The batched draws interpolate their own instances, so uploading to them must not trip Godot's multimesh interpolation warning.


class WarningCatcher:
	extends Logger
	var lines: Array[String] = []

	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			lines.append(code + rationale)


func _node() -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = QuadMesh.new()
	multimesh.instance_count = 4
	var node := MultiMeshInstance3D.new()
	node.multimesh = multimesh
	add_child_autofree(node)
	return node


func _buffer() -> PackedFloat32Array:
	var buffer := PackedFloat32Array()
	buffer.resize(4 * 12)
	return buffer


func test_helper_uploads_raise_no_interpolation_warning() -> void:
	var catcher := WarningCatcher.new()
	OS.add_logger(catcher)
	var node := _node()
	MultiMeshUpload.set_buffer(node.multimesh, _buffer())
	MultiMeshUpload.set_instance_transform(node.multimesh, 1, Transform3D.IDENTITY)
	await get_tree().process_frame
	OS.remove_logger(catcher)
	assert_eq(catcher.lines.size(), 0, "no warning from the helper: %s" % str(catcher.lines))


func test_no_batched_draw_uploads_straight_to_the_server() -> void:
	var allowed: Array[String] = ["res://src/rendering/multimesh_upload.gd", "res://src/hud/radar_dot_batch.gd"]
	var offenders: Array[String] = []
	var stack: Array[String] = ["res://src"]
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		for sub: String in DirAccess.get_directories_at(dir):
			stack.append("%s/%s" % [dir, sub])
		for file: String in DirAccess.get_files_at(dir):
			var path: String = "%s/%s" % [dir, file]
			if not file.ends_with(".gd") or allowed.has(path):
				continue
			var text: String = FileAccess.get_file_as_string(path).replace("MultiMeshUpload.set_instance_transform(", "")
			if text.contains("multimesh_set_buffer(") or text.contains(".set_instance_transform("):
				offenders.append(path)
	# Build-time fills (props, lights, gate glows) run once outside the frame and are listed here on purpose.
	for path: String in ["res://src/rendering/render_piece.gd", "res://src/world/station_lights.gd", "res://src/world/asteroid_belt.gd",
			"res://src/ship/running_lights.gd", "res://src/props/jumpgate.gd", "res://src/perf/standins/mine_standin.gd"]:
		offenders.erase(path)
	assert_eq(offenders, [], "uploads go through MultiMeshUpload")
