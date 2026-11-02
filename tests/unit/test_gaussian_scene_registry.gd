extends GutTest
## GaussianSceneRegistry's costs at many nodes (M3-T20, R5): registrations coalesce into one merge, a moved node patches its own
## entry, a hidden node writes nothing, the bytes are produced once per frame, relight knobs follow changes. Headless has no GDGS
## backend, so the tests drive the registry directly with real nodes in the tree.

const BYTES_PER_MATRIX: int = 64
const BYTES_PER_RELIGHT: int = 96

var registry: GaussianSceneRegistry = null
var holder: Node3D = null


func before_each() -> void:
	registry = GaussianSceneRegistry.new()
	holder = Node3D.new()
	add_child_autofree(holder)


func _resource(splats: int) -> GaussianResource:
	var resource := GaussianResource.new()
	resource.point_count = splats
	var data := PackedByteArray()
	data.resize(splats * GaussianSceneRegistry.FLOATS_PER_SPLAT * GaussianSceneRegistry.BYTES_PER_FLOAT)
	data.fill(0)
	resource.point_data_byte = data
	resource.aabb = AABB(Vector3(-2.0, -1.0, -1.0), Vector3(4.0, 2.0, 2.0))
	return resource


func _node(resource: GaussianResource, at: Vector3 = Vector3.ZERO) -> GaussianSplatNode:
	var node := GaussianSplatNode.new()
	node.gaussian = resource
	holder.add_child(node)
	node.global_transform = Transform3D(Basis.IDENTITY, at)
	return node


func _matrix(bytes: PackedByteArray, instance: int) -> PackedFloat32Array:
	return bytes.slice(instance * BYTES_PER_MATRIX, (instance + 1) * BYTES_PER_MATRIX).to_float32_array()


func test_registrations_coalesce_into_one_merge() -> void:
	var resource: GaussianResource = _resource(4)
	for i: int in 10:
		var result: Dictionary = registry.register_splat_node(_node(resource))
		assert_true(result.get("scene_dirty", false), "the manager is told to merge later")
	assert_eq(registry.get_merge_count(), 0, "no merge while nodes register")
	assert_false(registry.has_gpu_data())
	var change: Dictionary = registry.flush_scene()
	assert_eq(registry.get_merge_count(), 1)
	assert_true(change["require_gpu_rebuild"])
	assert_true(change["require_splat_upload"])
	assert_true(change["require_instance_upload"])
	assert_eq(registry.get_instance_count(), 10)
	assert_eq(registry.get_point_count(), 40, "every instanced splat counted")
	assert_eq(registry.get_point_data_byte().size(), 4 * 240, "one shared resource stored once")
	assert_true(registry.flush_scene().is_empty(), "nothing to do twice")
	assert_eq(registry.get_merge_count(), 1)


func test_a_resident_scene_is_not_marked_for_a_rebuild_by_a_moved_node() -> void:
	var node: GaussianSplatNode = _node(_resource(4))
	registry.register_splat_node(node)
	registry.flush_scene()
	node.global_position = Vector3(5.0, 0.0, 0.0)
	var change: Dictionary = registry.mark_transform_dirty(node)
	assert_false(change.get("require_gpu_rebuild", false))
	assert_false(change.get("require_splat_upload", false))
	assert_true(change["require_instance_upload"])


func test_a_moved_node_patches_only_its_own_matrix() -> void:
	var a: GaussianSplatNode = _node(_resource(4), Vector3(1.0, 0.0, 0.0))
	var b: GaussianSplatNode = _node(_resource(8), Vector3(2.0, 0.0, 0.0))
	registry.register_splat_node(a)
	registry.register_splat_node(b)
	registry.flush_scene()
	var before: PackedByteArray = registry.get_instance_transforms_byte().duplicate()
	assert_eq(before.size(), 2 * BYTES_PER_MATRIX)
	b.global_position = Vector3(9.0, 8.0, 7.0)
	registry.mark_transform_dirty(b)
	var after: PackedByteArray = registry.get_instance_transforms_byte()
	assert_eq(_matrix(after, 0), _matrix(before, 0), "the other instance is untouched")
	var moved: PackedFloat32Array = _matrix(after, 1)
	assert_eq([moved[12], moved[13], moved[14]], [9.0, 8.0, 7.0])


func test_the_matrix_is_affine_with_visibility_kept_apart() -> void:
	var node: GaussianSplatNode = _node(_resource(4))
	registry.register_splat_node(node)
	registry.flush_scene()
	assert_eq(_matrix(registry.get_instance_transforms_byte(), 0)[3], 0.0)
	assert_eq(registry.get_instance_visible()[0], 1)
	node.visible = false
	registry.mark_transform_dirty(node)
	assert_eq(registry.get_instance_visible()[0], 0)


func test_the_bytes_are_produced_once_per_frame_when_dirty() -> void:
	var node: GaussianSplatNode = _node(_resource(4))
	registry.register_splat_node(node)
	registry.flush_scene()
	registry.get_instance_transforms_byte()
	var builds: int = registry.get_transform_byte_builds()
	registry.get_instance_transforms_byte()
	registry.get_instance_transforms_byte()
	assert_eq(registry.get_transform_byte_builds(), builds, "nothing moved: no rebuild")
	for i: int in 5:
		node.global_position = Vector3(float(i) + 1.0, 0.0, 0.0)
		registry.mark_transform_dirty(node)
	assert_eq(registry.get_transform_byte_builds(), builds, "moving only patches")
	var moved: PackedFloat32Array = _matrix(registry.get_instance_transforms_byte(), 0)
	assert_eq(moved[12], 5.0, "the last pose")
	assert_eq(registry.get_transform_byte_builds(), builds + 1)


func test_a_hidden_node_writes_nothing_until_it_is_shown() -> void:
	var node: GaussianSplatNode = _node(_resource(4), Vector3(1.0, 0.0, 0.0))
	registry.register_splat_node(node)
	registry.flush_scene()
	node.visible = false
	registry.mark_transform_dirty(node)
	var hidden_bytes: PackedByteArray = registry.get_instance_transforms_byte().duplicate()
	node.global_position = Vector3(50.0, 0.0, 0.0)
	assert_true(registry.mark_transform_dirty(node).is_empty(), "a hidden node's move is not an upload")
	assert_eq(registry.get_instance_transforms_byte(), hidden_bytes, "and writes nothing")
	node.visible = true
	assert_true(registry.mark_transform_dirty(node)["require_instance_upload"])
	assert_eq(_matrix(registry.get_instance_transforms_byte(), 0)[12], 50.0, "shown: at its real pose at once")


func test_the_visible_total_counts_only_what_is_shown() -> void:
	var a: GaussianSplatNode = _node(_resource(4))
	var b: GaussianSplatNode = _node(_resource(8))
	registry.register_splat_node(a)
	registry.register_splat_node(b)
	registry.flush_scene()
	assert_eq(registry.get_visible_flag_total(), 12)
	b.visible = false
	registry.mark_transform_dirty(b)
	assert_eq(registry.get_visible_flag_total(), 4)
	holder.visible = false
	registry.mark_transform_dirty(a)
	registry.mark_transform_dirty(b)
	assert_eq(registry.get_visible_flag_total(), 0, "a parent's visibility counts")


func test_the_table_inputs_follow_the_nodes() -> void:
	var shared: GaussianResource = _resource(4)
	var other: GaussianResource = _resource(8)
	var a: GaussianSplatNode = _node(shared, Vector3(10.0, 0.0, 0.0))
	var b: GaussianSplatNode = _node(other, Vector3(20.0, 0.0, 0.0))
	var c: GaussianSplatNode = _node(shared, Vector3(30.0, 0.0, 0.0))
	for n: GaussianSplatNode in [a, b, c]:
		registry.register_splat_node(n)
	registry.flush_scene()
	assert_eq(registry.get_instance_counts(), PackedInt32Array([4, 8, 4]))
	assert_eq(registry.get_instance_bases(), PackedInt32Array([0, 4, 0]), "instances of one resource share its base")
	var spheres: PackedFloat32Array = registry.get_instance_spheres()
	assert_almost_eq(spheres[4], 20.0, 0.001)
	b.global_position = Vector3(77.0, 0.0, 0.0)
	registry.mark_transform_dirty(b)
	assert_almost_eq(registry.get_instance_spheres()[4], 77.0, 0.001, "a moved node moves its sphere")


func test_the_sphere_covers_the_resource_and_grows_with_scale() -> void:
	var node: GaussianSplatNode = _node(_resource(4))
	registry.register_splat_node(node)
	registry.flush_scene()
	var half_diagonal: float = Vector3(2.0, 1.0, 1.0).length()
	var plain: float = registry.get_instance_spheres()[3]
	assert_gte(plain, half_diagonal, "holds every splat centre")
	node.scale = Vector3(1.0, 3.0, 1.0)
	registry.mark_transform_dirty(node)
	assert_gte(registry.get_instance_spheres()[3], half_diagonal * 3.0, "the largest scale axis")


func test_a_node_whose_resource_is_empty_takes_no_instance() -> void:
	var empty: GaussianSplatNode = GaussianSplatNode.new()
	holder.add_child(empty)
	var real: GaussianSplatNode = _node(_resource(4))
	registry.register_splat_node(empty)
	registry.register_splat_node(real)
	registry.flush_scene()
	assert_eq(registry.get_instance_count(), 1)
	assert_true(registry.mark_transform_dirty(empty).is_empty())


func test_everything_unregistered_asks_for_cleanup() -> void:
	var node: GaussianSplatNode = _node(_resource(4))
	registry.register_splat_node(node)
	registry.flush_scene()
	registry.unregister_splat_node(node)
	assert_true(registry.flush_scene()["request_cleanup"])
	assert_false(registry.has_gpu_data())
	assert_eq(registry.get_instance_count(), 0)


func test_a_changed_relight_knob_patches_its_own_entry() -> void:
	var a: GaussianSplatNode = _node(_resource(4))
	var b: GaussianSplatNode = _node(_resource(8))
	registry.register_splat_node(a)
	registry.register_splat_node(b)
	registry.flush_scene()
	var before: PackedByteArray = registry.get_instance_relight_byte().duplicate()
	assert_eq(before.size(), 2 * BYTES_PER_RELIGHT)
	b.relight_unlit_level = 0.75
	assert_true(registry.mark_relight_dirty(b), "the renderer needs a new upload")
	var after: PackedFloat32Array = registry.get_instance_relight_byte().to_float32_array()
	var stride: int = GaussianSceneRegistry.RELIGHT_FLOATS_PER_INSTANCE
	assert_almost_eq(after[stride], 0.75, 0.001, "the second instance's unlit level")
	assert_eq(after.slice(0, stride), before.to_float32_array().slice(0, stride), "the first is untouched")
	assert_false(registry.mark_relight_dirty(b), "no change: no upload")


func test_a_nodes_own_lights_ride_in_its_record_and_patch_only_it() -> void:
	# M3-T27: the second vec4's w counts them and the lights follow; instances without any have a count of 0 and skip the loop.
	var a: GaussianSplatNode = _node(_resource(4))
	var b: GaussianSplatNode = _node(_resource(8))
	var lamp: PackedFloat32Array = GaussianOwnLights.surface(Vector3(1.0, -2.0, 3.0), Color.WHITE, 2.0, 4.0)
	b.set_own_lights(lamp)
	registry.register_splat_node(a)
	registry.register_splat_node(b)
	registry.flush_scene()
	var stride: int = GaussianSceneRegistry.RELIGHT_FLOATS_PER_INSTANCE
	var floats: PackedFloat32Array = registry.get_instance_relight_byte().to_float32_array()
	assert_eq(floats.size(), 2 * stride)
	assert_eq(floats[GaussianSceneRegistry.RELIGHT_KNOB_FLOATS - 1], 0.0, "no own lights on the first")
	assert_eq(floats[stride + GaussianSceneRegistry.RELIGHT_KNOB_FLOATS - 1], 1.0, "one on the second")
	assert_eq(Array(floats.slice(stride + GaussianSceneRegistry.RELIGHT_KNOB_FLOATS, stride + GaussianSceneRegistry.RELIGHT_KNOB_FLOATS + 8)), Array(lamp))
	var merges: int = registry.get_merge_count()
	b.set_own_lights(lamp + lamp)
	assert_true(registry.mark_relight_dirty(b), "a change asks for an upload")
	var after: PackedFloat32Array = registry.get_instance_relight_byte().to_float32_array()
	assert_eq(after[stride + GaussianSceneRegistry.RELIGHT_KNOB_FLOATS - 1], 2.0)
	assert_eq(after.slice(0, stride), floats.slice(0, stride), "the first is untouched")
	assert_eq(registry.get_merge_count(), merges, "no merge")
	assert_true(registry.flush_scene().is_empty(), "and nothing else waits")


func test_the_light_rig_still_reports_changes() -> void:
	var node: GaussianSplatNode = _node(_resource(4))
	registry.register_splat_node(node)
	registry.flush_scene()
	var rig: PackedByteArray = PackedFloat32Array([1.0, 2.0]).to_byte_array()
	assert_true(registry.refresh_relight(rig, 1))
	assert_false(registry.refresh_relight(rig.duplicate(), 1), "the same bytes are not a change")
	assert_eq(registry.get_light_count(), 1)
	assert_true(registry.refresh_relight(PackedFloat32Array([3.0, 2.0]).to_byte_array(), 1))


# A scene swap leaves cached lights valid but out of the tree, where reading their transform is an error (patch 7).
func test_the_light_rig_skips_a_light_out_of_the_tree() -> void:
	var rig_script: GDScript = load("res://addons/gdgs_scs/runtime/lighting/gaussian_light_rig.gd")
	var light := OmniLight3D.new()
	light.light_energy = 1.0
	assert_false(rig_script._is_active(light), "out of the tree")
	add_child_autofree(light)
	assert_true(rig_script._is_active(light), "in the tree")

