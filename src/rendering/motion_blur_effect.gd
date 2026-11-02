class_name MotionBlurEffect
extends CompositorEffect
## Motion blur on fast turns, as an option (`settings.motion_blur`, off by default). Runs after the splats are composited, so
## stars and hulls blur together; the HUD and console are canvas layers drawn later and stay sharp. While the effect is disabled
## the renderer is not asked for motion vectors, so it costs nothing. `PostEffects` switches it and feeds `strength`.
##
## Needs a RenderingDevice: with none (headless runs) the callback does nothing.

const BLUR_SHADER_PATH: String = "res://src/rendering/motion_blur.glsl"
const COPY_SHADER_PATH: String = "res://src/rendering/motion_blur_copy.glsl"
const CONTEXT: StringName = &"motion_blur"
const SCRATCH_TEXTURE: StringName = &"scratch"
const WORKGROUP: int = 16
## Longest smear as a share of the frame height.
const MAX_BLUR_SCREEN_FRACTION: float = 0.06

## Share of the frame's motion that is smeared, 0-1. 0 skips the work for the frame.
var strength: float = 0.5

var _rd: RenderingDevice
var _blur_shader: RID
var _blur_pipeline: RID
var _copy_shader: RID
var _copy_pipeline: RID
var _sampler: RID


func _init() -> void:
	effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	needs_motion_vectors = true
	access_resolved_depth = true
	RenderingServer.call_on_render_thread(_init_render)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd != null:
		# Inline: a method call on an object that is being deleted no longer finds its script.
		for rid: RID in [_blur_pipeline, _blur_shader, _copy_pipeline, _copy_shader, _sampler]:
			if rid.is_valid():
				_rd.free_rid(rid)


func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if _rd == null or not _blur_pipeline.is_valid() or callback_type != effect_callback_type or strength <= 0.0:
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var scene_data: RenderSceneData = render_data.get_render_scene_data()
	if buffers == null or scene_data == null:
		return
	var size: Vector2i = buffers.get_internal_size()
	if size.x <= 0 or size.y <= 0:
		return
	for view: int in buffers.get_view_count():
		_blur_view(buffers, scene_data, size, view)


func _blur_view(buffers: RenderSceneBuffersRD, scene_data: RenderSceneData, size: Vector2i, view: int) -> void:
	var velocity: RID = buffers.get_velocity_layer(view)
	if not velocity.is_valid():
		return
	var color: RID = buffers.get_color_layer(view)
	var scratch: RID = _scratch(buffers, size)
	var groups := Vector2i(ceili(float(size.x) / WORKGROUP), ceili(float(size.y) / WORKGROUP))
	# Pass 1: read the frame, write the blurred one beside it. The colour buffer is never read and written in one pass.
	var blur_uniforms: Array[RDUniform] = [
		_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, 0, [scene_data.get_uniform_buffer()]),
		_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 1, [scratch]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 2, [_sampler, buffers.get_depth_layer(view)]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 3, [_sampler, velocity]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 4, [_sampler, color]),
	]
	_dispatch(_blur_shader, _blur_pipeline, blur_uniforms, groups,
			PackedFloat32Array([strength, MAX_BLUR_SCREEN_FRACTION * size.y, size.x, size.y]))
	# Pass 2: lay the blurred frame over the colour buffer.
	var copy_uniforms: Array[RDUniform] = [
		_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 0, [color]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 1, [_sampler, scratch]),
	]
	_dispatch(_copy_shader, _copy_pipeline, copy_uniforms, groups, PackedFloat32Array([size.x, size.y, 0.0, 0.0]))


func _dispatch(shader: RID, pipeline: RID, uniforms: Array[RDUniform], groups: Vector2i, params: PackedFloat32Array) -> void:
	var list: int = _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, pipeline)
	_rd.compute_list_bind_uniform_set(list, UniformSetCacheRD.get_cache(shader, 0, uniforms), 0)
	_rd.compute_list_set_push_constant(list, params.to_byte_array(), params.size() * 4)
	_rd.compute_list_dispatch(list, groups.x, groups.y, 1)
	_rd.compute_list_end()


## The scratch image the blurred frame is written to, made again when the frame size changes.
func _scratch(buffers: RenderSceneBuffersRD, size: Vector2i) -> RID:
	if buffers.has_texture(CONTEXT, SCRATCH_TEXTURE):
		var existing: RDTextureFormat = buffers.get_texture_format(CONTEXT, SCRATCH_TEXTURE)
		if Vector2i(existing.width, existing.height) != size:
			buffers.clear_context(CONTEXT)
	if not buffers.has_texture(CONTEXT, SCRATCH_TEXTURE):
		buffers.create_texture(CONTEXT, SCRATCH_TEXTURE, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
				RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT,
				RenderingDevice.TEXTURE_SAMPLES_1, size, 1, 1, true, false)
	return buffers.get_texture(CONTEXT, SCRATCH_TEXTURE)


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
	_blur_shader = _make_shader(BLUR_SHADER_PATH)
	_copy_shader = _make_shader(COPY_SHADER_PATH)
	if not _blur_shader.is_valid() or not _copy_shader.is_valid():
		return
	_blur_pipeline = _rd.compute_pipeline_create(_blur_shader)
	_copy_pipeline = _rd.compute_pipeline_create(_copy_shader)
	var sampler_state := RDSamplerState.new()
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_sampler = _rd.sampler_create(sampler_state)


func _make_shader(path: String) -> RID:
	return RuntimeShader.compile(_rd, path)
