class_name VelocityProbeEffect
extends CompositorEffect
## Reads back the motion vector and depth the renderer holds at a few pixels (M4-T38), so a GPU test can check
## that a moving thing writes the vector its movement implies. A diagnostic: it stalls the GPU for the readback, so only the GPU
## test (`test_motion_vectors_gpu`) builds it; it is never in the shipped scene.
##
## Velocity is in uv units, the current frame's place minus the previous one's (Godot's convention, jitter removed).
## Needs a RenderingDevice: with none (headless runs) it reads nothing.

const SHADER_PATH: String = "res://src/rendering/velocity_probe.glsl"
const WORKGROUP: int = 64

## Frames read since the effect was made (a test waits for this to move).
var frames_read: int = 0

var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _sampler: RID
var _lock := Mutex.new()
var _points: PackedVector2Array = PackedVector2Array()
var _samples: Array[Vector4] = []
var _size: Vector2i = Vector2i.ZERO


func _init(callback_type: int = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT) -> void:
	effect_callback_type = callback_type
	needs_motion_vectors = true
	access_resolved_depth = true
	RenderingServer.call_on_render_thread(_init_render)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd != null:
		for rid: RID in [_pipeline, _shader, _sampler]:
			if rid.is_valid():
				_rd.free_rid(rid)


## The pixels to read from the next frame on, in the render buffer's own pixels (top left 0, 0).
func set_points(points: PackedVector2Array) -> void:
	_lock.lock()
	_points = points.duplicate()
	_lock.unlock()


## The last frame's readings, one per point: velocity x, y (uv), depth (reverse Z, 0 at the far plane) and 1 if read.
func samples() -> Array[Vector4]:
	_lock.lock()
	var out: Array[Vector4] = _samples.duplicate()
	_lock.unlock()
	return out


## The render buffer's size the last reading came from.
func buffer_size() -> Vector2i:
	_lock.lock()
	var out: Vector2i = _size
	_lock.unlock()
	return out


func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if _rd == null or not _pipeline.is_valid() or callback_type != effect_callback_type:
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null:
		return
	_lock.lock()
	var points: PackedVector2Array = _points.duplicate()
	_lock.unlock()
	if points.is_empty():
		return
	var velocity: RID = buffers.get_velocity_layer(0)
	if not velocity.is_valid():
		return
	var size: Vector2i = buffers.get_internal_size()
	var ints := PackedInt32Array()
	for p: Vector2 in points:
		ints.append(int(p.x))
		ints.append(int(p.y))
	var points_buffer: RID = _rd.storage_buffer_create(ints.size() * 4, ints.to_byte_array())
	var out_buffer: RID = _rd.storage_buffer_create(points.size() * 16)
	var uniforms: Array[RDUniform] = [
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 0, [_sampler, velocity]),
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 1, [_sampler, buffers.get_depth_layer(0)]),
		_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 2, [points_buffer]),
		_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 3, [out_buffer]),
	]
	var uniform_set: RID = _rd.uniform_set_create(uniforms, _shader, 0)
	var params := PackedInt32Array([size.x, size.y, points.size(), 0])
	var list: int = _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _pipeline)
	_rd.compute_list_bind_uniform_set(list, uniform_set, 0)
	_rd.compute_list_set_push_constant(list, params.to_byte_array(), params.size() * 4)
	_rd.compute_list_dispatch(list, ceili(float(points.size()) / WORKGROUP), 1, 1)
	_rd.compute_list_end()
	var floats: PackedFloat32Array = _rd.buffer_get_data(out_buffer).to_float32_array()
	_rd.free_rid(uniform_set)
	_rd.free_rid(points_buffer)
	_rd.free_rid(out_buffer)
	var read: Array[Vector4] = []
	for i: int in points.size():
		read.append(Vector4(floats[i * 4], floats[i * 4 + 1], floats[i * 4 + 2], floats[i * 4 + 3]))
	_lock.lock()
	_samples = read
	_size = size
	frames_read += 1
	_lock.unlock()


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
