@tool
extends RefCounted
class_name GaussianGpuStateCache

const RenderingDeviceContext := preload("res://addons/gdgs_scs/runtime/render/compute/gaussian_rendering_device_context.gd")

const TILE_SIZE := 16
const RADIX := 256
const MAX_RENDER_STATES := 4
# [space-combat-sim patch] A state holds a whole budget of sort memory, so a window size not drawn for this long gives it back.
const UNUSED_STATE_FRAMES := 120
const FLOATS_PER_SPLAT := 60
const BYTES_PER_FLOAT := 4
# Relighting. Must match gsplat_projection.glsl and gaussian_light_rig.gd.
const LIGHTING_BYTES_PER_SPLAT := 4
const RELIGHT_FLOATS_PER_INSTANCE := 8
const MAX_LIGHTS := 8
const LIGHT_RIG_FLOATS := MAX_LIGHTS * 16

const SHADER_PATH_PROJECTION := "res://addons/gdgs_scs/runtime/render/compute/shaders/gsplat_projection.glsl"
const SHADER_PATH_RADIX_UPSWEEP := "res://addons/gdgs_scs/runtime/render/compute/shaders/radix_sort_upsweep.glsl"
const SHADER_PATH_RADIX_SPINE := "res://addons/gdgs_scs/runtime/render/compute/shaders/radix_sort_spine.glsl"
const SHADER_PATH_RADIX_DOWNSWEEP := "res://addons/gdgs_scs/runtime/render/compute/shaders/radix_sort_downsweep.glsl"
const SHADER_PATH_BOUNDARIES := "res://addons/gdgs_scs/runtime/render/compute/shaders/gsplat_boundaries.glsl"
const SHADER_PATH_RENDER := "res://addons/gdgs_scs/runtime/render/compute/shaders/gsplat_render.glsl"

class RenderState:
	extends RefCounted

	var last_used_frame := 0  # [space-combat-sim patch]
	var texture_size := Vector2i.ONE
	var tile_dims := Vector2i.ONE
	var camera_projection: Projection
	var camera_view: Projection
	var camera_push_constants := PackedByteArray()
	var camera_world_position := Vector3.ZERO
	var depth_capture_alpha := 0.5
	var needs_gpu_rebuild := true
	var needs_splat_upload := false
	var needs_instance_upload := false
	var needs_relight_upload := false
	# [space-combat-sim patch] What this state's buffers were sized for, and what the current dispatch sizes cover.
	var budget_splats := 0
	var sort_capacity := 0
	var frame_elements := -1
	var projection_dims: Array = [1, 1, 1]
	var context: GdgsRenderingDeviceContext
	var shaders: Dictionary = {}
	var pipelines: Dictionary = {}
	var descriptors: Dictionary = {}

var _render_states: Dictionary = {}
var _render_state_lru: Array = []
var _pending_gpu_cleanup := false
# [space-combat-sim patch] How often the expensive paths ran. A LOD switch must never bump either.
var _rebuild_count := 0
var _splat_upload_count := 0

func get_rebuild_count() -> int:
	return _rebuild_count

func get_splat_upload_count() -> int:
	return _splat_upload_count

func has_render_states() -> bool:
	return not _render_states.is_empty()

# [space-combat-sim patch] How many window sizes hold buffers now.
func render_state_count() -> int:
	return _render_states.size()

func request_cleanup() -> void:
	_pending_gpu_cleanup = true

func flush_pending_cleanup() -> void:
	if _pending_gpu_cleanup:
		cleanup_all()

func get_or_create_render_state(texture_size: Vector2i, frame: int = Engine.get_frames_drawn()):
	var state: RenderState = _render_states.get(texture_size, null)
	if state == null:
		state = RenderState.new()
		state.texture_size = texture_size
		state.tile_dims = (texture_size + Vector2i(TILE_SIZE - 1, TILE_SIZE - 1)) / TILE_SIZE
		_render_states[texture_size] = state
	state.last_used_frame = frame  # [space-combat-sim patch]
	_touch_render_state(texture_size)
	_evict_unused_render_states(frame)  # [space-combat-sim patch]
	_enforce_render_state_cache_limit()
	return state

func mark_all_render_states_needs_gpu_rebuild() -> void:
	for state in _render_states.values():
		state.needs_gpu_rebuild = true

func mark_all_render_states_needs_splat_upload(value: bool) -> void:
	for state in _render_states.values():
		state.needs_splat_upload = value

func mark_all_render_states_needs_instance_upload(value: bool) -> void:
	for state in _render_states.values():
		state.needs_instance_upload = value

func mark_all_render_states_needs_relight_upload(value: bool) -> void:
	for state in _render_states.values():
		state.needs_relight_upload = value

# [space-combat-sim patch] The culled, sort and histogram buffers follow the budget, not the resident splats, so nothing here
# changes when visibility does.
func rebuild_gpu_state(state, unique_data_size: int, instance_count: int, budget_splats: int) -> void:
	cleanup_state(state)
	if unique_data_size <= 0:
		return
	_rebuild_count += 1
	state.budget_splats = budget_splats
	state.sort_capacity = GaussianSplatBudget.sort_capacity(budget_splats)
	state.frame_elements = -1
	var budget_sizes: Dictionary = GaussianSplatBudget.sizes(budget_splats)

	state.context = RenderingDeviceContext.create(RenderingServer.get_rendering_device())

	state.shaders["projection"] = state.context.load_shader(SHADER_PATH_PROJECTION)
	state.shaders["radix_upsweep"] = state.context.load_shader(SHADER_PATH_RADIX_UPSWEEP)
	state.shaders["radix_spine"] = state.context.load_shader(SHADER_PATH_RADIX_SPINE)
	state.shaders["radix_downsweep"] = state.context.load_shader(SHADER_PATH_RADIX_DOWNSWEEP)
	state.shaders["boundaries"] = state.context.load_shader(SHADER_PATH_BOUNDARIES)
	state.shaders["render"] = state.context.load_shader(SHADER_PATH_RENDER)

	# Pre-size indirect dispatch dimensions on the CPU. On macOS/Metal, updating this
	# buffer from the projection pass can cause the entire GS pipeline to go blank.
	# [space-combat-sim patch] Now only a start: set_frame_elements() keeps them on the visible total.
	var block_dims: PackedInt32Array = GaussianSplatBudget.dispatch_dims(0)

	# Relighting buffers, sized off the same unique-splat and instance counts as
	# the data above. Always allocated (a minimum of one element) so the shader's
	# bindings stay valid even with nothing baked; the per-instance `enabled`
	# flag is what actually gates the maths.
	var unique_splat_count := maxi(1, unique_data_size / (FLOATS_PER_SPLAT * BYTES_PER_FLOAT))
	state.descriptors["splats"] = state.context.create_storage_buffer(unique_data_size)
	state.descriptors["splat_lighting"] = state.context.create_storage_buffer(
		unique_splat_count * LIGHTING_BYTES_PER_SPLAT)
	state.descriptors["light_rig"] = state.context.create_storage_buffer(
		LIGHT_RIG_FLOATS * BYTES_PER_FLOAT)
	state.descriptors["instance_relight"] = state.context.create_storage_buffer(
		maxi(1, instance_count) * RELIGHT_FLOATS_PER_INSTANCE * BYTES_PER_FLOAT)
	# [space-combat-sim patch] Sized from the budget. Scratch: the GPU writes them before it reads, so no zero-filled upload.
	state.descriptors["culled_splats"] = state.context.create_scratch_buffer(budget_sizes["culled"])
	state.descriptors["grid_dimensions"] = state.context.create_storage_buffer(6 * 4, block_dims.to_byte_array(), RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT)
	state.descriptors["histogram"] = state.context.create_scratch_buffer(budget_sizes["histogram"])
	state.descriptors["sort_keys"] = state.context.create_scratch_buffer(budget_sizes["sort_keys"])
	state.descriptors["sort_values"] = state.context.create_scratch_buffer(budget_sizes["sort_values"])
	# [space-combat-sim patch] The visible-instance table takes the old splat_instance_ids binding. One row at least: a binding cannot be empty.
	state.descriptors["visible_table"] = state.context.create_scratch_buffer(maxi(1, instance_count) * GaussianVisibleTable.BYTES_PER_ROW)
	state.descriptors["instance_transforms"] = state.context.create_storage_buffer(instance_count * 16 * BYTES_PER_FLOAT)
	state.descriptors["uniforms"] = state.context.create_uniform_buffer(12 * 4)  # [space-combat-sim patch] 8 -> 12: the table's row count
	state.descriptors["tile_bounds"] = state.context.create_storage_buffer(state.tile_dims.x * state.tile_dims.y * 2 * 4)
	state.descriptors["tile_splat_pos"] = state.context.create_storage_buffer(4 * 4)
	state.descriptors["render_texture"] = state.context.create_texture(state.texture_size, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)
	state.descriptors["depth_texture"] = state.context.create_texture(state.texture_size, RenderingDevice.DATA_FORMAT_R32_SFLOAT)

	var projection_set: RID = state.context.create_descriptor_set([
		state.descriptors["splats"],
		state.descriptors["culled_splats"],
		state.descriptors["histogram"],
		state.descriptors["sort_keys"],
		state.descriptors["sort_values"],
		state.descriptors["grid_dimensions"],
		state.descriptors["visible_table"],  # [space-combat-sim patch]
		state.descriptors["instance_transforms"],
		state.descriptors["uniforms"],
		# Bindings are assigned by position in create_descriptor_set, so these
		# three must stay last and in this order to match bindings 9/10/11.
		state.descriptors["light_rig"],
		state.descriptors["splat_lighting"],
		state.descriptors["instance_relight"]
	], state.shaders["projection"], 0)

	var radix_upsweep_set: RID = state.context.create_descriptor_set([
		state.descriptors["histogram"],
		state.descriptors["sort_keys"]
	], state.shaders["radix_upsweep"], 0)

	var radix_spine_set: RID = state.context.create_descriptor_set([
		state.descriptors["histogram"]
	], state.shaders["radix_spine"], 0)

	var radix_downsweep_set: RID = state.context.create_descriptor_set([
		state.descriptors["histogram"],
		state.descriptors["sort_keys"],
		state.descriptors["sort_values"]
	], state.shaders["radix_downsweep"], 0)

	var boundaries_set: RID = state.context.create_descriptor_set([
		state.descriptors["histogram"],
		state.descriptors["sort_keys"],
		state.descriptors["tile_bounds"]
	], state.shaders["boundaries"], 0)

	var render_set: RID = state.context.create_descriptor_set([
		state.descriptors["culled_splats"],
		state.descriptors["sort_values"],
		state.descriptors["tile_bounds"],
		state.descriptors["tile_splat_pos"],
		state.descriptors["render_texture"],
		state.descriptors["depth_texture"]
	], state.shaders["render"], 0)

	# [space-combat-sim patch] Shared with the pipeline, which reads it at every dispatch; set_frame_elements() keeps it on the visible splats.
	state.projection_dims = [1, 1, 1]
	state.pipelines["gsplat_projection"] = state.context.create_pipeline(state.projection_dims, [projection_set], state.shaders["projection"])
	state.pipelines["radix_sort_upsweep"] = state.context.create_pipeline([], [radix_upsweep_set], state.shaders["radix_upsweep"])
	state.pipelines["radix_sort_spine"] = state.context.create_pipeline([RADIX, 1, 1], [radix_spine_set], state.shaders["radix_spine"])
	state.pipelines["radix_sort_downsweep"] = state.context.create_pipeline([], [radix_downsweep_set], state.shaders["radix_downsweep"])
	state.pipelines["gsplat_boundaries"] = state.context.create_pipeline([], [boundaries_set], state.shaders["boundaries"])
	state.pipelines["gsplat_render"] = state.context.create_pipeline([state.tile_dims.x, state.tile_dims.y, 1], [render_set], state.shaders["render"])

	state.needs_gpu_rebuild = false
	state.needs_splat_upload = true
	state.needs_instance_upload = true
	state.needs_relight_upload = true

func upload_splats(state, point_data_byte: PackedByteArray) -> void:
	if state.context == null or point_data_byte.is_empty():
		return
	_splat_upload_count += 1  # [space-combat-sim patch]
	state.context.device.buffer_update(state.descriptors["splats"].rid, 0, point_data_byte.size(), point_data_byte)
	state.needs_splat_upload = false

## [space-combat-sim patch] This frame's visible-instance table. Empty when nothing is drawn: the shader then reads no row.
func upload_visible_table(state, table_byte: PackedByteArray) -> void:
	if state.context == null or table_byte.is_empty():
		return
	state.context.device.buffer_update(state.descriptors["visible_table"].rid, 0, table_byte.size(), table_byte)

## [space-combat-sim patch] Keeps the dispatch sizes on the visible total, on the CPU (see the Metal note above) and only when the
## total changes, so a big budget does not dispatch tens of thousands of no-op workgroups.
func set_frame_elements(state, visible_splats: int) -> void:
	if state.context == null:
		return
	var tile_count: int = state.tile_dims.x * state.tile_dims.y
	var elements: int = GaussianSplatBudget.frame_elements(visible_splats, state.budget_splats, tile_count)
	if elements != state.frame_elements:
		state.frame_elements = elements
		var dims := GaussianSplatBudget.dispatch_dims(elements).to_byte_array()
		state.context.device.buffer_update(state.descriptors["grid_dimensions"].rid, 0, dims.size(), dims)
	state.projection_dims[0] = GaussianSplatBudget.projection_groups(visible_splats)

func upload_instance_transforms(state, instance_transforms_byte: PackedByteArray) -> void:
	if state.context == null or instance_transforms_byte.is_empty():
		return
	state.context.device.buffer_update(state.descriptors["instance_transforms"].rid, 0, instance_transforms_byte.size(), instance_transforms_byte)
	state.needs_instance_upload = false

## The baked per-splat records travel with the splat data (they change only when
## the scene's resources do), while the light rig and per-instance knobs move on
## their own cadence, so they upload separately.
func upload_splat_lighting(state, splat_lighting_byte: PackedByteArray) -> void:
	if state.context == null or splat_lighting_byte.is_empty():
		return
	state.context.device.buffer_update(state.descriptors["splat_lighting"].rid, 0, splat_lighting_byte.size(), splat_lighting_byte)

func upload_relight(state, light_rig_byte: PackedByteArray, instance_relight_byte: PackedByteArray) -> void:
	if state.context == null:
		return
	if not light_rig_byte.is_empty():
		state.context.device.buffer_update(state.descriptors["light_rig"].rid, 0, light_rig_byte.size(), light_rig_byte)
	if not instance_relight_byte.is_empty():
		state.context.device.buffer_update(state.descriptors["instance_relight"].rid, 0, instance_relight_byte.size(), instance_relight_byte)
	state.needs_relight_upload = false

func cleanup_state(state) -> void:
	if state == null:
		return
	if state.context != null:
		state.context.free()
		state.context = null
	state.shaders.clear()
	state.pipelines.clear()
	state.descriptors.clear()
	state.budget_splats = 0  # [space-combat-sim patch]
	state.sort_capacity = 0
	state.frame_elements = -1
	state.needs_gpu_rebuild = true
	state.needs_splat_upload = true
	state.needs_instance_upload = true
	state.needs_relight_upload = true

func cleanup_all() -> void:
	for state in _render_states.values():
		cleanup_state(state)
	_render_states.clear()
	_render_state_lru.clear()
	_pending_gpu_cleanup = false

func _touch_render_state(texture_size: Vector2i) -> void:
	var existing_index := _render_state_lru.find(texture_size)
	if existing_index != -1:
		_render_state_lru.remove_at(existing_index)
	_render_state_lru.push_back(texture_size)

# [space-combat-sim patch] Frees the sort memory of window sizes no longer drawn, so a fullscreen toggle does not strand it.
func _evict_unused_render_states(frame: int) -> void:
	for size in _render_state_lru.duplicate():
		var state = _render_states.get(size, null)
		if state != null and frame - state.last_used_frame > UNUSED_STATE_FRAMES:
			cleanup_state(state)
			_render_states.erase(size)
			_render_state_lru.erase(size)

func _enforce_render_state_cache_limit() -> void:
	while _render_state_lru.size() > MAX_RENDER_STATES:
		var stale_size = _render_state_lru[0]
		_render_state_lru.remove_at(0)
		var stale_state = _render_states.get(stale_size, null)
		if stale_state != null:
			cleanup_state(stale_state)
			_render_states.erase(stale_size)
