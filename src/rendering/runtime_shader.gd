class_name RuntimeShader
extends RefCounted
## Compiles a compute `.glsl` file when the game starts, not when the project is imported. A headless import has no renderer,
## so it cannot resolve Godot's built-in `#include "godot/..."` files and leaves an empty shader behind; compiling at run
## time, with the renderer up, always finds them.


## The compiled shader for the GLSL file at `path`, or an invalid RID (after an error is printed) if it does not compile.
static func compile(rd: RenderingDevice, path: String) -> RID:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("RuntimeShader: cannot read %s" % path)
		return RID()
	return compile_text(rd, text, path)


## The same for GLSL already in memory; `path` names it in messages.
static func compile_text(rd: RenderingDevice, text: String, path: String) -> RID:
	var source := RDShaderSource.new()
	source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	source.set_stage_source(RenderingDevice.SHADER_STAGE_COMPUTE, text.replace("#[compute]", ""))
	var spirv: RDShaderSPIRV = rd.shader_compile_spirv_from_source(source)
	if not spirv.compile_error_compute.is_empty():
		push_error("RuntimeShader: %s: %s" % [path, spirv.compile_error_compute])
		return RID()
	return rd.shader_create_from_spirv(spirv, path.get_file())
