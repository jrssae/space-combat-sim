class_name SkyVelocityEffect
extends CompositorEffect
## Gives the sky its motion vectors (M4-T38, architecture §7.6). Godot writes velocity only for opaque meshes and leaves the sky,
## the star points and the far dots (none of which write depth) at zero, so under TAA a star on a turn blends with the dark
## sky where it used to be and dims or smears. This fills every depth-0 pixel with the camera's turn, the motion a thing at
## infinity has, before TAA resolves. `AntiAliasing` enables it only while TAA is on; off, it asks the renderer for nothing.
##
## Needs a RenderingDevice: with none (headless runs) the callback does nothing.

const SHADER_PATH: String = "res://src/rendering/sky_velocity.glsl"
const WORKGROUP: int = 16

var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _sampler: RID


func _init() -> void:
	effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_SKY
	needs_motion_vectors = true
	access_resolved_depth = true
	enabled = false
	RenderingServer.call_on_render_thread(_init_render)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd != null:
		for rid: RID in [_pipeline, _shader, _sampler]:
			if rid.is_valid():
				_rd.free_rid(rid)


func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if _rd == null or not _pipeline.is_valid() or callback_type != effect_callback_type:
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var scene_data: RenderSceneData = render_data.get_render_scene_data()
	if buffers == null or scene_data == null:
		return
	var size: Vector2i = buffers.get_internal_size()
	if size.x <= 0 or size.y <= 0:
		return
	var groups := Vector2i(ceili(float(size.x) / WORKGROUP), ceili(float(size.y) / WORKGROUP))
	var params := PackedFloat32Array([size.x, size.y, 0.0, 0.0])
	for view: int in buffers.get_view_count():
		var velocity: RID = buffers.get_velocity_layer(view)
		if not velocity.is_valid():
			continue
		var uniforms: Array[RDUniform] = [
			_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, 0, [scene_data.get_uniform_buffer()]),
			_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 1, [velocity]),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 2, [_sampler, buffers.get_depth_layer(view)]),
		]
		var list: int = _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(list, _pipeline)
		_rd.compute_list_bind_uniform_set(list, UniformSetCacheRD.get_cache(_shader, 0, uniforms), 0)
		_rd.compute_list_set_push_constant(list, params.to_byte_array(), params.size() * 4)
		_rd.compute_list_dispatch(list, groups.x, groups.y, 1)
		_rd.compute_list_end()


static func _uniform(type: RenderingDevice.UniformType, binding: int, ids: Array) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = type
	uniform.binding = binding
	for id: RID in ids:
		uniform.add_id(id)
	return uniform


func _init_render() -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		return
	_shader = RuntimeShader.compile(_rd, SHADER_PATH)
	if not _shader.is_valid():
		return
	_pipeline = _rd.compute_pipeline_create(_shader)
	var sampler_state := RDSamplerState.new()
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	_sampler = _rd.sampler_create(sampler_state)
