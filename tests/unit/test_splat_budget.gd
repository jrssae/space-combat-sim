extends GutTest
## AC29 (M3-T20, Q22): the buffers that follow the splat budget are sized from the budget alone, and the visible-instance table
## that replaces the per-splat instance ids stays conservative against the projection shader's own per-splat test.

const BUDGET: int = 2000000
const ASSET_ROOT: String = ShipSpec.ASSET_ROOT


# --- sizing ----------------------------------------------------------------------------------------------------------


func test_the_real_cost_of_a_budget_splat() -> void:
	# Keys and values are 8 B per element each (double-buffered), 32 elements per splat, plus 64 B of projected data.
	assert_eq(GaussianSplatBudget.MAX_SORT_ELEMENTS_PER_SPLAT, 32)
	assert_eq(GaussianSplatBudget.BYTES_PER_BUDGET_SPLAT, 576)
	var sizes: Dictionary = GaussianSplatBudget.sizes(BUDGET)
	assert_eq(sizes["culled"], 128000000)
	assert_eq(sizes["sort_keys"], 512000000)
	assert_eq(sizes["sort_values"], 512000000)
	# 64 000 000 elements are 15 625 partitions of 256 counters, after the count and the four global histograms.
	assert_eq(sizes["histogram"], 4 + (1 + 4 * 256 + 15625 * 256) * 4)
	assert_eq(sizes["total"], sizes["culled"] + sizes["sort_keys"] + sizes["sort_values"] + sizes["histogram"])


func test_sort_capacity_follows_the_budget() -> void:
	assert_eq(GaussianSplatBudget.sort_capacity(BUDGET), 64000000)
	assert_eq(GaussianSplatBudget.sort_capacity(1), 32)


func test_a_budget_below_one_splat_still_sizes_a_usable_buffer() -> void:
	var sizes: Dictionary = GaussianSplatBudget.sizes(0)
	assert_eq(sizes["culled"], 64)
	assert_eq(GaussianSplatBudget.sort_capacity(0), 32)


# Sum of every level a ship carries, from the generator's manifest: what used to size the buffers.
func _chain_splats(asset_id: String, finest: int) -> PackedInt32Array:
	var file: FileAccess = FileAccess.open(ASSET_ROOT.path_join(asset_id).path_join("manifest.json"), FileAccess.READ)
	assert_not_null(file, "%s manifest: run scripts/gen_assets.sh" % asset_id)
	if file == null:
		return PackedInt32Array()
	var manifest: Dictionary = JSON.parse_string(file.get_as_text()) as Dictionary
	var out := PackedInt32Array()
	for entry: Variant in manifest["lods"] as Array:
		if int((entry as Dictionary)["level"]) >= finest:
			out.append(int((entry as Dictionary)["splats"]))
	return out


func test_100_lod_chained_ships_stay_within_the_budgets_bytes() -> void:
	var raider: PackedInt32Array = _chain_splats("raider_fighter", 0)
	var ally: PackedInt32Array = _chain_splats("starfury_aurora", 1)
	if raider.is_empty() or ally.is_empty():
		return
	var resident: int = 0
	var counts := PackedInt32Array()
	for i: int in 70:
		for n: int in raider:
			resident += n
			counts.append(n)
	for i: int in 30:
		for n: int in ally:
			resident += n
			counts.append(n)
	assert_gt(resident, BUDGET, "100 ships carry more splats than the budget draws")
	var sizes: Dictionary = GaussianSplatBudget.sizes(BUDGET)
	assert_gt(GaussianSplatBudget.sizes(resident)["total"], sizes["total"], "sizing by the resident splats would cost more")
	# One level shown per ship, LOD0 at worst: the table never passes the budget.
	var visible := PackedByteArray()
	visible.resize(counts.size())
	visible.fill(0)
	var at: int = 0
	for i: int in 70:
		visible[at] = 1  # LOD0: the worst case
		at += raider.size()
	for i: int in 30:
		visible[at] = 1
		at += ally.size()
	var table: Dictionary = _build(counts, visible, _spheres_at(counts.size(), Vector3(0.0, 0.0, -100.0), 10.0), _planes(), BUDGET)
	assert_lte(int(table["visible"]), BUDGET)


# --- dispatch sizes --------------------------------------------------------------------------------------------------


func test_frame_elements_follow_the_visible_total_not_the_capacity() -> void:
	var tiles: int = 120 * 68
	var floor_elements: int = tiles * GaussianSplatBudget.MIN_ELEMENTS_PER_TILE
	var capacity: int = GaussianSplatBudget.sort_capacity(BUDGET)
	assert_eq(GaussianSplatBudget.frame_elements(0, BUDGET, tiles), floor_elements, "nothing visible: only the floor")
	assert_eq(GaussianSplatBudget.frame_elements(1000000, BUDGET, tiles), 32000000)
	assert_eq(GaussianSplatBudget.frame_elements(BUDGET, BUDGET, tiles), capacity)
	assert_eq(GaussianSplatBudget.frame_elements(BUDGET * 2, BUDGET, tiles), capacity, "never past the capacity")


func test_frame_elements_keep_room_for_big_splats_when_few_are_visible() -> void:
	# The sky alone: a few thousand nebula splats touch hundreds of tiles each, far past 32 per splat.
	var tiles: int = 120 * 68
	assert_gte(GaussianSplatBudget.frame_elements(16000, BUDGET, tiles), tiles * GaussianSplatBudget.MIN_ELEMENTS_PER_TILE)
	assert_lte(GaussianSplatBudget.frame_elements(16000, 1000, tiles), GaussianSplatBudget.sort_capacity(1000), "a small budget still caps it")


func test_dispatch_dimensions_cover_the_frame_elements() -> void:
	var dims: PackedInt32Array = GaussianSplatBudget.dispatch_dims(8192)
	assert_eq(dims, PackedInt32Array([2, 1, 1, 32, 1, 1]), "partitions of 4096, boundary groups of 256")
	assert_eq(GaussianSplatBudget.dispatch_dims(8193)[0], 3)
	assert_eq(GaussianSplatBudget.dispatch_dims(8193)[3], 33)
	assert_eq(GaussianSplatBudget.dispatch_dims(0), PackedInt32Array([1, 1, 1, 1, 1, 1]), "never a zero dispatch")


func test_projection_groups_cover_the_visible_splats() -> void:
	assert_eq(GaussianSplatBudget.projection_groups(0), 1, "never a zero dispatch")
	assert_eq(GaussianSplatBudget.projection_groups(1), 1)
	assert_eq(GaussianSplatBudget.projection_groups(256), 1)
	assert_eq(GaussianSplatBudget.projection_groups(257), 2)


# --- the visible-instance table --------------------------------------------------------------------------------------


func _planes(view: Transform3D = Transform3D.IDENTITY, projection: Projection = Projection.create_perspective(70.0, 16.0 / 9.0, 0.05, 50000.0)) -> PackedFloat32Array:
	return GaussianVisibleTable.frustum_planes(Projection(view.affine_inverse()), projection)


func _spheres_at(count: int, center: Vector3, radius: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(count * 4)
	for i: int in count:
		out[i * 4] = center.x
		out[i * 4 + 1] = center.y
		out[i * 4 + 2] = center.z
		out[i * 4 + 3] = radius
	return out


func _build(counts: PackedInt32Array, visible: PackedByteArray, spheres: PackedFloat32Array, planes: PackedFloat32Array, budget: int,
		bases: PackedInt32Array = PackedInt32Array()) -> Dictionary:
	var resource_bases: PackedInt32Array = bases
	if resource_bases.is_empty():
		resource_bases.resize(counts.size())
		resource_bases.fill(0)
	var indices := PackedInt32Array()
	for i: int in counts.size():
		indices.append(i)
	return GaussianVisibleTable.build(counts, resource_bases, indices, visible, spheres, planes, budget)


func _rows(table: Dictionary) -> Array[PackedInt32Array]:
	var ints: PackedInt32Array = (table["bytes"] as PackedByteArray).to_int32_array()
	var out: Array[PackedInt32Array] = []
	for i: int in int(table["rows"]):
		out.append(ints.slice(i * 4, i * 4 + 4))
	return out


func test_a_row_per_drawn_instance_with_a_running_start() -> void:
	var counts := PackedInt32Array([100, 50, 25])
	var visible := PackedByteArray([1, 1, 1])
	var table: Dictionary = _build(counts, visible, _spheres_at(3, Vector3(0.0, 0.0, -100.0), 10.0), _planes(), 1000,
			PackedInt32Array([7, 700, 7000]))
	assert_eq(table["visible"], 175)
	assert_false(table["clipped"])
	assert_eq(_rows(table), [
		PackedInt32Array([0, 100, 7, 0]),
		PackedInt32Array([100, 50, 700, 1]),
		PackedInt32Array([150, 25, 7000, 2]),
	] as Array[PackedInt32Array])


func test_hidden_instances_take_no_row_and_no_budget() -> void:
	var counts := PackedInt32Array([100, 50, 25])
	var visible := PackedByteArray([1, 0, 1])
	var table: Dictionary = _build(counts, visible, _spheres_at(3, Vector3(0.0, 0.0, -100.0), 10.0), _planes(), 1000)
	assert_eq(table["visible"], 125)
	assert_eq(table["rows"], 2)
	assert_eq(_rows(table)[1], PackedInt32Array([100, 25, 0, 2]), "the running start skips the hidden one, the index does not")


func test_nothing_visible_is_an_empty_table_of_zero_splats() -> void:
	var table: Dictionary = _build(PackedInt32Array([100]), PackedByteArray([0]), _spheres_at(1, Vector3.ZERO, 1.0), _planes(), 1000)
	assert_eq(table["visible"], 0)
	assert_eq(table["rows"], 0)
	assert_false(table["clipped"])


func test_an_instance_past_the_budget_is_truncated_then_the_rest_dropped() -> void:
	var counts := PackedInt32Array([100, 100, 100])
	var visible := PackedByteArray([1, 1, 1])
	var table: Dictionary = _build(counts, visible, _spheres_at(3, Vector3(0.0, 0.0, -100.0), 10.0), _planes(), 150)
	assert_eq(table["visible"], 150)
	assert_true(table["clipped"])
	assert_eq(table["rows"], 2)
	assert_eq(_rows(table)[1], PackedInt32Array([100, 50, 0, 1]))


func test_exactly_the_budget_is_not_clipped() -> void:
	var table: Dictionary = _build(PackedInt32Array([100, 50]), PackedByteArray([1, 1]), _spheres_at(2, Vector3(0.0, 0.0, -100.0), 10.0),
			_planes(), 150)
	assert_eq(table["visible"], 150)
	assert_false(table["clipped"])


func test_instances_off_screen_cost_nothing() -> void:
	var behind: PackedFloat32Array = _spheres_at(1, Vector3(0.0, 0.0, 200.0), 10.0)
	assert_eq(_build(PackedInt32Array([100]), PackedByteArray([1]), behind, _planes(), 1000)["visible"], 0, "behind the camera")
	var aside: PackedFloat32Array = _spheres_at(1, Vector3(1000.0, 0.0, -100.0), 10.0)
	assert_eq(_build(PackedInt32Array([100]), PackedByteArray([1]), aside, _planes(), 1000)["visible"], 0, "far to one side")


func test_the_sky_always_passes() -> void:
	# A sphere holding the camera, with its centre off to one side and behind, as the sky's is (its mean is not its centre).
	for yaw: float in [0.0, 1.5, 3.1, 4.7]:
		var view := Transform3D(Basis(Vector3.UP, yaw), Vector3(5000.0, -300.0, 900.0))
		var center: Vector3 = view.origin + Vector3(120.0, -40.0, 800.0)
		assert_eq(_build(PackedInt32Array([16000]), PackedByteArray([1]), _spheres_at(1, center, 20000.0), _planes(view), BUDGET)["visible"], 16000,
				"yaw %f" % yaw)


# The shader's own test: the same maths as gsplat_projection.glsl.
func _shader_draws(point: Vector3, view: Projection, projection: Projection) -> bool:
	var v: Vector4 = view * Vector4(point.x, point.y, point.z, 1.0)
	var clip: Vector4 = projection * v
	var bound: float = clip.w * 1.2
	return not (clip.x < -bound or clip.y < -bound or clip.z < 0.0 or clip.x > bound or clip.y > bound or clip.z > clip.w)


# What the renderer hands the shader: reverse-Z, Y flipped, as Godot's scene data has it.
func _render_projection() -> Projection:
	var plain: Projection = Projection.create_perspective(70.0, 16.0 / 9.0, 0.05, 50000.0)
	var correction: Projection = Projection.create_depth_correction(true)
	var reverse_z := Projection(Vector4(1.0, 0.0, 0.0, 0.0), Vector4(0.0, 1.0, 0.0, 0.0), Vector4(0.0, 0.0, -1.0, 0.0), Vector4(0.0, 0.0, 1.0, 1.0))
	return reverse_z * correction * plain


func test_the_cull_never_drops_what_the_shader_would_draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2020
	var projection: Projection = _render_projection()
	var checked: int = 0
	var culled: int = 0
	for round_index: int in 400:
		var pose := Transform3D(Basis.from_euler(Vector3(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0))),
				Vector3(rng.randf_range(-500.0, 500.0), rng.randf_range(-500.0, 500.0), rng.randf_range(-500.0, 500.0)))
		var view: Projection = Projection(pose.affine_inverse())
		var planes: PackedFloat32Array = GaussianVisibleTable.frustum_planes(view, projection)
		var center := Vector3(rng.randf_range(-3000.0, 3000.0), rng.randf_range(-3000.0, 3000.0), rng.randf_range(-3000.0, 3000.0))
		var radius: float = rng.randf_range(1.0, 400.0)
		var table: Dictionary = _build(PackedInt32Array([10]), PackedByteArray([1]), _spheres_at(1, center, radius), planes, 1000)
		var drawn: bool = int(table["visible"]) > 0
		culled += 0 if drawn else 1
		for p: int in 40:
			var dir := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
			var point: Vector3 = center + dir * radius * rng.randf()
			if _shader_draws(point, view, projection):
				checked += 1
				if not drawn:
					fail_test("round %d: a splat at %s passes the shader's test but its instance was culled" % [round_index, str(point)])
					return
	assert_gt(checked, 100, "the check saw points the shader draws")
	assert_gt(culled, 50, "and the cull still removes instances")


func test_the_planes_do_not_depend_on_the_depth_convention() -> void:
	var view: Projection = Projection(Transform3D.IDENTITY)
	var a: PackedFloat32Array = GaussianVisibleTable.frustum_planes(view, Projection.create_perspective(70.0, 16.0 / 9.0, 0.05, 50000.0))
	var b: PackedFloat32Array = GaussianVisibleTable.frustum_planes(view, _render_projection())
	assert_eq(a.size(), b.size())
	# Y is flipped between them, so the top and bottom planes swap; the set of planes is the same.
	for i: int in GaussianVisibleTable.PLANE_COUNT:
		var found: bool = false
		for j: int in GaussianVisibleTable.PLANE_COUNT:
			var same: bool = true
			for k: int in 4:
				same = same and absf(a[i * 4 + k] - b[j * 4 + k]) < 0.001
			found = found or same
		assert_true(found, "plane %d" % i)


func test_a_window_size_no_longer_drawn_gives_its_buffers_back() -> void:
	var cache := GaussianGpuStateCache.new()
	cache.get_or_create_render_state(Vector2i(1920, 1080), 0)
	cache.get_or_create_render_state(Vector2i(960, 540), 1)
	assert_eq(cache.render_state_count(), 2, "just toggled: both still held")
	cache.get_or_create_render_state(Vector2i(960, 540), GaussianGpuStateCache.UNUSED_STATE_FRAMES + 2)
	assert_eq(cache.render_state_count(), 1, "the old size is freed once unused")


func test_two_viewports_drawn_every_frame_keep_their_buffers() -> void:
	var cache := GaussianGpuStateCache.new()
	for frame: int in GaussianGpuStateCache.UNUSED_STATE_FRAMES * 3:
		cache.get_or_create_render_state(Vector2i(1920, 1080), frame)
		cache.get_or_create_render_state(Vector2i(320, 240), frame)
	assert_eq(cache.render_state_count(), 2)
