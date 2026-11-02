class_name SceneLensFlareEffect
extends LensFlareEffect
## The vendored add-on's lens flare, unchanged, with one difference: its shader is compiled when the game starts
## (`RuntimeShader`) instead of read from the import cache, which a headless import leaves empty for a shader that uses
## Godot's built-in includes. Everything else is the add-on's.


func create_shader(p_file_path: String) -> RID:
	var shader: RID = RuntimeShader.compile(rd, p_file_path)
	if not shader.is_valid():
		# The add-on would retry and fail on every frame.
		push_warning("SceneLensFlareEffect: %s did not compile; the lens flare stays off" % p_file_path)
		enabled = false
		return shader
	add_rid_to_free(shader, "shader: %s" % p_file_path)
	return shader
