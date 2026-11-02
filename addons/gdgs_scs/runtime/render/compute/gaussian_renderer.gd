@tool
extends RefCounted
class_name GaussianRenderer

const RenderingDeviceContext := preload("res://addons/gdgs_scs/runtime/render/compute/gaussian_rendering_device_context.gd")
const RADIX := 256

func render_for_compositor(
	state_cache: GaussianGpuStateCache,
	scene_registry: GaussianSceneRegistry,
	texture_size: Vector2i,
	camera_transform: Transform3D,
	camera_projection: Projection,
	camera_world_position: Vector3,
	depth_capture_alpha: float = 0.5,
	budget_splats: int = GaussianSplatBudget.DEFAULT_SPLATS  # [space-combat-sim patch]
) -> Dictionary:
	state_cache.flush_pending_cleanup()

	if not scene_registry.has_gpu_data():
		if state_cache.has_render_states():
			state_cache.cleanup_all()
		return {}

	var safe_size := Vector2i(maxi(texture_size.x, 1), maxi(texture_size.y, 1))
	var state = state_cache.get_or_create_render_state(safe_size)
	_update_camera_from_transform(state, camera_transform, camera_projection)
	state.camera_world_position = camera_world_position
	state.depth_capture_alpha = clampf(depth_capture_alpha, 0.0, 1.0)

	var unique_data_size := scene_registry.get_point_data_byte().size()

	# [space-combat-sim patch] A budget change reallocates here, once.
	if state.context == null or state.needs_gpu_rebuild or state.budget_splats != budget_splats:
		state_cache.rebuild_gpu_state(state, unique_data_size, scene_registry.get_instance_count(), budget_splats)
	if state.context == null:
		return {}

	if state.needs_splat_upload:
		state_cache.upload_splats(state, scene_registry.get_point_data_byte())
		state_cache.upload_splat_lighting(state, scene_registry.get_splat_lighting_byte())
	if state.needs_instance_upload:
		state_cache.upload_instance_transforms(state, scene_registry.get_instance_transforms_byte())
	if state.needs_relight_upload:
		state_cache.upload_relight(
			state, scene_registry.get_light_rig_byte(), scene_registry.get_instance_relight_byte()
		)

	if state.camera_push_constants.is_empty():
		return {}

	# [space-combat-sim patch] Hidden and off-screen instances leave the frame here, at render time: the poses are final by now.
	var planes := GaussianVisibleTable.frustum_planes(state.camera_view, state.camera_projection)
	var table := scene_registry.build_visible_table(planes, state.budget_splats)
	state_cache.upload_visible_table(state, table["bytes"])
	state_cache.set_frame_elements(state, int(table["visible"]))

	_rasterize_state(state, int(table["visible"]), int(table["rows"]), scene_registry.get_light_count())
	if state.descriptors.has("render_texture") and state.descriptors.has("depth_texture"):
		return {
			"color_alpha_texture": state.descriptors["render_texture"].rid,
			"depth_texture": state.descriptors["depth_texture"].rid
		}
	return {}

func _rasterize_state(state, visible_splats: int, table_rows: int, light_count: int) -> void:
	if state.context == null:
		return

	var uniforms := RenderingDeviceContext.create_push_constant([
		state.camera_world_position.x,
		state.camera_world_position.y,
		state.camera_world_position.z,
		Time.get_ticks_msec() * 1e-3,
		state.texture_size.x,
		state.texture_size.y,
		visible_splats,  # [space-combat-sim patch] the shader's point_count: visible splats, not resident ones
		# The trailing slot used to be padding; it now carries the active light
		# count, which is what bounds the projection shader's relight loop.
		light_count,
		table_rows,  # [space-combat-sim patch]
		0, 0, 0
	])
	state.context.device.buffer_update(state.descriptors["uniforms"].rid, 0, 12 * 4, uniforms)
	state.context.device.buffer_clear(state.descriptors["histogram"].rid, 0, 4 + 4 * RADIX * 4)
	state.context.device.buffer_clear(state.descriptors["tile_bounds"].rid, 0, state.tile_dims.x * state.tile_dims.y * 2 * 4)

	var compute_list: int = state.context.compute_list_begin()
	state.pipelines["gsplat_projection"].call(state.context, compute_list, state.camera_push_constants)
	state.context.compute_list_end()

	compute_list = state.context.compute_list_begin()
	# [space-combat-sim patch] The offsets are the buffer's two halves. The element limit is what this frame dispatches over, not the
	# whole capacity: past it the sort would count keys no workgroup ran for. Overflow drops cleanly instead.
	var capacity: int = state.sort_capacity
	var element_limit: int = state.frame_elements
	for radix_shift_pass in range(4):
		var sort_push_constant := RenderingDeviceContext.create_push_constant([
			radix_shift_pass,
			capacity * (radix_shift_pass % 2),
			capacity * (1 - (radix_shift_pass % 2)),
			element_limit  # [space-combat-sim patch] capacity: sort passes clamp element_count to it
		])
		state.pipelines["radix_sort_upsweep"].call(state.context, compute_list, sort_push_constant, [], state.descriptors["grid_dimensions"].rid, 0)
		state.pipelines["radix_sort_spine"].call(state.context, compute_list, sort_push_constant)
		state.pipelines["radix_sort_downsweep"].call(state.context, compute_list, sort_push_constant, [], state.descriptors["grid_dimensions"].rid, 0)
	state.context.compute_list_end()

	compute_list = state.context.compute_list_begin()
	state.pipelines["gsplat_boundaries"].call(
		state.context, compute_list,
		RenderingDeviceContext.create_push_constant([element_limit, 0, 0, 0]),  # [space-combat-sim patch]
		[], state.descriptors["grid_dimensions"].rid, 3 * 4
	)
	state.context.compute_list_end()

	compute_list = state.context.compute_list_begin()
	state.pipelines["gsplat_render"].call(
		state.context,
		compute_list,
		RenderingDeviceContext.create_push_constant([0.0, -1, state.depth_capture_alpha, 0.0])
	)
	state.context.compute_list_end()

func _update_camera_from_transform(state, camera_transform: Transform3D, camera_projection: Projection) -> void:
	var view := Projection(camera_transform.affine_inverse())
	if view != state.camera_view or camera_projection != state.camera_projection:
		state.camera_view = view
		state.camera_projection = camera_projection
		state.camera_push_constants = RenderingDeviceContext.create_push_constant(
			_projection_to_column_major_floats(view) + _projection_to_column_major_floats(camera_projection)
		)

func _projection_to_column_major_floats(matrix: Projection) -> Array:
	return [
		matrix.x[0], matrix.x[1], matrix.x[2], matrix.x[3],
		matrix.y[0], matrix.y[1], matrix.y[2], matrix.y[3],
		matrix.z[0], matrix.z[1], matrix.z[2], matrix.z[3],
		matrix.w[0], matrix.w[1], matrix.w[2], matrix.w[3]
	]
