extends GutTest
## AC30: a generator's `.light` bytes become a `GaussianLightingResource` format 1 with no per-splat work, and a splat node gets them
## and the relight settings before it enters the tree.

const SPLATS: String = "user://test_splat_lighting.light"

# Three records as GDGS's codec writes them: +Z, +X and -Y.
const RECORDS: PackedByteArray = [128, 128, 255, 255, 255, 128, 255, 255, 128, 0, 255, 255]


func before_each() -> void:
	SplatLightingLoader.clear_cache()


func after_each() -> void:
	if FileAccess.file_exists(SPLATS):
		DirAccess.remove_absolute(SPLATS)
	SplatLightingLoader.clear_cache()
	for key: StringName in [&"splat_relight", &"relight_ambient", &"relight_unlit_level", &"relight_light_gain"]:
		Settings.reset(key)


func _write(bytes: PackedByteArray, path: String = SPLATS) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func _gaussian(count: int) -> GaussianResource:
	var resource := GaussianResource.new()
	resource.point_count = count
	return resource


func test_it_wraps_the_bytes_as_gdgs_format_one() -> void:
	var lighting: GaussianLightingResource = SplatLightingLoader.from_bytes(RECORDS)
	assert_eq(lighting.format_version, GaussianLightingResource.FORMAT_VERSION)
	assert_eq(lighting.source_point_count, 3)
	assert_eq(lighting.splat_data, RECORDS)
	assert_true(lighting.is_splat_data_valid())
	assert_false(lighting.has_proxy_mesh(), "no shadow proxy: splats cast no shadows in M3")


func test_gdgs_reads_the_records_back() -> void:
	var lighting: GaussianLightingResource = SplatLightingLoader.from_bytes(RECORDS)
	assert_almost_eq(lighting.read_splat(0)["normal"].distance_to(Vector3.BACK), 0.0, 0.01)
	assert_almost_eq(lighting.read_splat(1)["normal"].distance_to(Vector3.RIGHT), 0.0, 0.01)
	assert_almost_eq(lighting.read_splat(2)["normal"].distance_to(Vector3.DOWN), 0.0, 0.01)
	assert_almost_eq(float(lighting.read_splat(1)["ao"]), 1.0, 1e-5)
	assert_almost_eq(float(lighting.read_splat(1)["confidence"]), 1.0, 1e-5)


func test_a_wrong_length_is_refused() -> void:
	assert_null(SplatLightingLoader.from_bytes(PackedByteArray([1, 2, 3, 4, 5])))
	assert_null(SplatLightingLoader.from_bytes(PackedByteArray()))


func test_a_file_loads_once_and_is_shared() -> void:
	_write(RECORDS)
	var first: GaussianLightingResource = SplatLightingLoader.load_file(SPLATS)
	assert_not_null(first)
	assert_eq(first.source_point_count, 3)
	assert_eq(SplatLightingLoader.load_file(SPLATS), first, "every node of a resource shares one bake")


func test_a_missing_file_gives_nothing() -> void:
	assert_null(SplatLightingLoader.load_file("user://no_such_file.light"))


func test_attach_sets_the_records_and_the_settings() -> void:
	_write(RECORDS)
	Settings.set_value(&"relight_ambient", 0.4)
	Settings.set_value(&"relight_unlit_level", 0.2)
	Settings.set_value(&"relight_light_gain", 0.7)
	var node := GaussianSplatNode.new()
	autofree(node)
	node.gaussian = _gaussian(3)
	SplatLightingLoader.attach(node, SPLATS)
	assert_not_null(node.lighting)
	assert_true(node.relight_enabled)
	assert_false(node.relight_cast_shadows, "nothing mesh-like receives a splat's shadow")
	assert_almost_eq(node.relight_ambient.r, 0.4, 1e-5)
	assert_almost_eq(node.relight_ambient.b, 0.4, 1e-5)
	assert_almost_eq(node.relight_unlit_level, 0.2, 1e-5)
	assert_almost_eq(node.relight_light_gain, 0.7, 1e-5)
	assert_true(node.is_in_group(SplatLightingLoader.GROUP))


func test_attach_refuses_records_of_another_splat_count() -> void:
	_write(RECORDS)
	var node := GaussianSplatNode.new()
	autofree(node)
	node.gaussian = _gaussian(4)
	SplatLightingLoader.attach(node, SPLATS)
	assert_null(node.lighting, "stale records would light the wrong splats")
	assert_false(node.relight_enabled)


func test_without_records_a_node_stays_unlit() -> void:
	var node := GaussianSplatNode.new()
	autofree(node)
	node.gaussian = _gaussian(3)
	SplatLightingLoader.attach(node, "user://no_such_file.light")
	assert_null(node.lighting)
	assert_false(node.relight_enabled)


func test_the_setting_switches_a_node_with_records_only() -> void:
	_write(RECORDS)
	var lit := GaussianSplatNode.new()
	autofree(lit)
	lit.gaussian = _gaussian(3)
	SplatLightingLoader.attach(lit, SPLATS)
	var sky := GaussianSplatNode.new()
	autofree(sky)
	Settings.set_value(&"splat_relight", false)
	SplatLightingLoader.apply_settings(lit)
	SplatLightingLoader.apply_settings(sky)
	assert_false(lit.relight_enabled)
	assert_false(sky.relight_enabled)
	Settings.set_value(&"splat_relight", true)
	SplatLightingLoader.apply_settings(lit)
	SplatLightingLoader.apply_settings(sky)
	assert_true(lit.relight_enabled)
	assert_false(sky.relight_enabled, "no records, no relighting")
