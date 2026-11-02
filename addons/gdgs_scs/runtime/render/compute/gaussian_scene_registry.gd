@tool
extends RefCounted
class_name GaussianSceneRegistry

const FLOATS_PER_SPLAT := 60
const BYTES_PER_FLOAT := 4
# Relighting: one baked record per splat (oct normal, AO, confidence) and two
# vec4 of per-instance knobs. Must match gsplat_projection.glsl.
const LIGHTING_BYTES_PER_SPLAT := 4
const RELIGHT_FLOATS_PER_INSTANCE := 8
# [space-combat-sim patch] One mat4 per instance, and one world sphere (x, y, z, r) for the visible-instance table.
const FLOATS_PER_TRANSFORM := 16
const FLOATS_PER_SPHERE := 4
# [space-combat-sim patch] The resource's aabb holds splat centres only; this also covers the splats' own extent.
const SPHERE_RADIUS_FACTOR := 1.25
const SPHERE_RADIUS_EXTRA := 1.0
# [space-combat-sim patch] What a moved node asks of the renderer. A constant, because every moving node returns it every frame.
const INSTANCE_UPLOAD_RESULT := {
	"request_cleanup": false,
	"require_gpu_rebuild": false,
	"require_splat_upload": false,
	"require_instance_upload": true,
}

class NodeEntry:
	extends RefCounted

	var point_count := 0
	var instance_index := -1
	var point_data_byte := PackedByteArray()
	var lighting_byte := PackedByteArray()
	var model_transform: Transform3D = Transform3D.IDENTITY
	var visible: bool = true
	var has_lighting := false
	# [space-combat-sim patch] The resource's bounds, for the visible-instance table.
	var local_center := Vector3.ZERO
	var local_radius := 0.0

var _splat_nodes: Array[Node] = []
var _node_entries: Dictionary = {}

var _point_count := 0
var _point_data_byte := PackedByteArray()
var _splat_lighting_byte := PackedByteArray()
var _instance_count := 0
# [space-combat-sim patch] Patched in place when a node moves; the bytes are produced once per frame, at render time, because
# Godot delivers a node's move after _process and a snapshot taken any earlier would lag a frame behind the camera.
var _instance_transform_floats := PackedFloat32Array()
var _instance_transforms_byte := PackedByteArray()
var _instance_transforms_dirty := false
var _transform_byte_builds := 0
# [space-combat-sim patch] Relight knobs follow the nodes' setters, rather than five property reads per node per frame.
var _instance_relight_floats := PackedFloat32Array()
var _instance_relight_byte := PackedByteArray()
var _instance_relight_dirty := false
# [space-combat-sim patch] Per instance, for the visible-instance table.
var _instance_counts := PackedInt32Array()
var _instance_bases := PackedInt32Array()
var _instance_indices := PackedInt32Array()
var _instance_visible := PackedByteArray()
var _instance_spheres := PackedFloat32Array()
var _visible_flag_total := 0
var _last_table := {"visible": 0, "clipped": false}
# [space-combat-sim patch] Registrations and resource changes wait here for one merge before the next render.
var _scene_dirty := false
var _scene_force_rebuild := false
var _merge_count := 0
# The light rig is produced on the main thread and parked here so the renderer,
# which runs on the rendering thread, only ever uploads bytes.
var _light_rig_byte := PackedByteArray()
var _light_count := 0

func register_splat_node(node: Node) -> Dictionary:
	if node == null or _splat_nodes.has(node):
		return {}
	_splat_nodes.push_back(node)
	return _mark_scene_dirty(true)

func unregister_splat_node(node: Node) -> Dictionary:
	_splat_nodes.erase(node)
	return _mark_scene_dirty(true)

func mark_resource_dirty(node: Node) -> Dictionary:
	if node == null:
		return {}
	return _mark_scene_dirty(false)

func mark_transform_dirty(node: Node) -> Dictionary:
	if node == null:
		return {}
	return _sync_node_transform(node)

# [space-combat-sim patch] Merging is quadratic if each of hundreds of nodes does it as it registers, so they share one.
func _mark_scene_dirty(force_rebuild: bool) -> Dictionary:
	_scene_dirty = true
	_scene_force_rebuild = _scene_force_rebuild or force_rebuild
	return {"scene_dirty": true}

## [space-combat-sim patch] Runs the merge the registrations asked for, on the main thread, before the next render. Returns what
## the renderer must do about it; empty when nothing was waiting.
func flush_scene() -> Dictionary:
	if not _scene_dirty:
		return {}
	_scene_dirty = false
	var force_rebuild := _scene_force_rebuild
	_scene_force_rebuild = false
	return _sync_scene_resources(force_rebuild)

func has_gpu_data() -> bool:
	return _point_count > 0 and not _point_data_byte.is_empty()

func get_point_count() -> int:
	return _point_count

func get_point_data_byte() -> PackedByteArray:
	return _point_data_byte

func get_instance_count() -> int:
	return _instance_count

# [space-combat-sim patch] Produced once per frame, when something moved.
func get_instance_transforms_byte() -> PackedByteArray:
	if _instance_transforms_dirty:
		_instance_transforms_dirty = false
		_instance_transforms_byte = _instance_transform_floats.to_byte_array()
		_transform_byte_builds += 1
	return _instance_transforms_byte

## [space-combat-sim patch] Times the transform bytes were produced, for the tests.
func get_transform_byte_builds() -> int:
	return _transform_byte_builds

## [space-combat-sim patch] Times the scene's splat data was merged, for the tests.
func get_merge_count() -> int:
	return _merge_count

## [space-combat-sim patch] Splats in every instance flagged visible, off-screen ones included. Always current.
func get_visible_flag_total() -> int:
	return _visible_flag_total

func get_instance_counts() -> PackedInt32Array:
	return _instance_counts

func get_instance_bases() -> PackedInt32Array:
	return _instance_bases

func get_instance_visible() -> PackedByteArray:
	return _instance_visible

func get_instance_spheres() -> PackedFloat32Array:
	return _instance_spheres

## [space-combat-sim patch] This frame's visible-instance table (GaussianVisibleTable.build), kept for the stats.
func build_visible_table(planes: PackedFloat32Array, budget_splats: int) -> Dictionary:
	_last_table = GaussianVisibleTable.build(
		_instance_counts, _instance_bases, _instance_indices, _instance_visible, _instance_spheres, planes, budget_splats
	)
	return _last_table

## [space-combat-sim patch] Splats the last frame drew.
func get_last_visible_total() -> int:
	return int(_last_table["visible"])

## [space-combat-sim patch] Whether the last frame's budget cut anything.
func get_last_clipped() -> bool:
	return bool(_last_table["clipped"])

func get_splat_lighting_byte() -> PackedByteArray:
	return _splat_lighting_byte

func get_instance_relight_byte() -> PackedByteArray:
	if _instance_relight_dirty:
		_instance_relight_dirty = false
		_instance_relight_byte = _instance_relight_floats.to_byte_array()
	return _instance_relight_byte

func get_light_rig_byte() -> PackedByteArray:
	return _light_rig_byte

func get_light_count() -> int:
	return _light_count

## Main-thread tick from the render manager: parks the freshly packed light rig.
## Returns true when the renderer needs to re-upload, which is only when something
## actually changed.
## [space-combat-sim patch] The per-instance knobs moved to mark_relight_dirty(): reading five properties of every node each frame
## cost more than the budget allows at 100 ships (PATCHES.md, patch 5).
func refresh_relight(light_rig_byte: PackedByteArray, light_count: int) -> bool:
	if light_count == _light_count and light_rig_byte == _light_rig_byte:
		return false
	_light_rig_byte = light_rig_byte
	_light_count = light_count
	return true

## [space-combat-sim patch] A node's relight knob changed: patches its entry. Returns true when the renderer needs to re-upload.
func mark_relight_dirty(node: Node) -> bool:
	if _scene_dirty or node == null or not is_instance_valid(node):
		return false
	var entry: NodeEntry = _node_entries.get(node.get_instance_id(), null)
	if entry == null or entry.instance_index < 0:
		return false
	var knobs := _relight_floats_of(node, entry)
	var base := entry.instance_index * RELIGHT_FLOATS_PER_INSTANCE
	if _instance_relight_floats.slice(base, base + RELIGHT_FLOATS_PER_INSTANCE) == knobs:
		return false
	for i: int in RELIGHT_FLOATS_PER_INSTANCE:
		_instance_relight_floats[base + i] = knobs[i]
	_instance_relight_dirty = true
	return true

func _sync_scene_resources(force_rebuild: bool) -> Dictionary:
	_prune_splat_nodes()
	_merge_count += 1  # [space-combat-sim patch]

	var next_entries: Dictionary = {}
	var merged_point_data := PackedByteArray()
	var merged_lighting := PackedByteArray()
	# [space-combat-sim patch] Per-instance arrays replace the per-splat instance ids.
	var merged_counts := PackedInt32Array()
	var merged_bases := PackedInt32Array()
	var merged_indices := PackedInt32Array()
	var merged_visible := PackedByteArray()
	var visible_flag_total := 0
	var total_point_count := 0
	var next_instance_index := 0

	# Keep track of which resources we've already packed into the raw VRAM buffer
	var unique_resources := {}
	# The baked lighting records ride alongside the splat data under the same
	# unique index, so instanced nodes share one upload. A bake is a function of
	# the GaussianResource, so nodes sharing a resource are expected to share a
	# bake; if they disagree the first one wins and the conflict is reported.
	var unique_lighting := {}

	for node in _splat_nodes:
		if not is_instance_valid(node):
			continue

		var entry := _build_node_entry(node, next_instance_index)
		next_entries[node.get_instance_id()] = entry
		if entry.point_count <= 0:
			continue

		var gaussian: Resource = node.get("gaussian")
		var resource_start_index: int
		
		# Only upload the splat data if we haven't seen this resource yet
		if not unique_resources.has(gaussian):
			resource_start_index = merged_point_data.size() / (FLOATS_PER_SPLAT * BYTES_PER_FLOAT)
			unique_resources[gaussian] = resource_start_index
			unique_lighting[gaussian] = entry.has_lighting
			merged_point_data.append_array(entry.point_data_byte)
			merged_lighting.append_array(entry.lighting_byte)
		else:
			# If we already uploaded it, just get the index where it lives in the GPU buffer
			resource_start_index = unique_resources[gaussian]
			if entry.has_lighting and not bool(unique_lighting[gaussian]):
				push_warning(
					"[gdgs] compute: instanced nodes share a GaussianResource but only some "
					+ "carry a lighting bake; the first node's bake is used for all of them"
				)

		# [space-combat-sim patch] The per-splat instance ids (a GDScript loop over every splat of every node) became one table
		# entry per instance.
		merged_counts.append(entry.point_count)
		merged_bases.append(resource_start_index)
		merged_indices.append(next_instance_index)
		merged_visible.append(1 if entry.visible else 0)
		if entry.visible:
			visible_flag_total += entry.point_count
		entry.lighting_byte = PackedByteArray()  # [space-combat-sim patch] merged above; do not keep a copy per node

		total_point_count += entry.point_count
		next_instance_index += 1
	
	_node_entries = next_entries

	if total_point_count <= 0 or merged_point_data.is_empty():
		_point_count = 0
		_point_data_byte = PackedByteArray()
		_splat_lighting_byte = PackedByteArray()
		_instance_count = 0
		_instance_transform_floats = PackedFloat32Array()
		_instance_transforms_byte = PackedByteArray()
		_instance_transforms_dirty = false
		_instance_relight_floats = PackedFloat32Array()
		_instance_relight_byte = PackedByteArray()
		_instance_relight_dirty = false
		_instance_counts = PackedInt32Array()
		_instance_bases = PackedInt32Array()
		_instance_indices = PackedInt32Array()
		_instance_visible = PackedByteArray()
		_instance_spheres = PackedFloat32Array()
		_visible_flag_total = 0
		_last_table = {"visible": 0, "clipped": false}
		return _change_result(true, false, false, false)

	var count_changed := total_point_count != _point_count
	var point_data_size_changed := merged_point_data.size() != _point_data_byte.size()
	var instance_count_changed := next_instance_index != _instance_count

	_point_count = total_point_count
	_point_data_byte = merged_point_data
	_splat_lighting_byte = merged_lighting
	_instance_count = next_instance_index
	# [space-combat-sim patch] Poses and knobs from the entries just built.
	_instance_counts = merged_counts
	_instance_bases = merged_bases
	_instance_indices = merged_indices
	_instance_visible = merged_visible
	_visible_flag_total = visible_flag_total
	_instance_transform_floats.resize(_instance_count * FLOATS_PER_TRANSFORM)
	_instance_spheres.resize(_instance_count * FLOATS_PER_SPHERE)
	_instance_relight_floats = _build_instance_relight_floats()
	_instance_relight_dirty = true
	for entry_value: Variant in next_entries.values():
		var entry: NodeEntry = entry_value
		if entry.instance_index >= 0:
			_write_instance_pose(entry)
	_instance_transforms_dirty = true

	return _change_result(
		false,
		force_rebuild or count_changed or point_data_size_changed or instance_count_changed,
		true,
		true
	)

func _sync_node_transform(node: Node) -> Dictionary:
	# [space-combat-sim patch] Keeps one moved node cheap: patch its entry only. A waiting merge reads every pose anyway, and a hidden
	# node writes nothing until it is shown.
	if _scene_dirty or node == null or not is_instance_valid(node):
		return {}

	var entry: NodeEntry = _node_entries.get(node.get_instance_id(), null)
	if entry == null or entry.instance_index < 0:
		return {}

	var model_visible := _get_node_visibility(node)
	if model_visible != entry.visible:
		entry.visible = model_visible
		_instance_visible[entry.instance_index] = 1 if model_visible else 0
		_visible_flag_total += entry.point_count if model_visible else -entry.point_count
	if not model_visible:
		return {}

	var model_transform := _get_node_transform(node)
	if entry.model_transform == model_transform:
		return {}
	entry.model_transform = model_transform
	_write_instance_pose(entry)
	_instance_transforms_dirty = true
	return INSTANCE_UPLOAD_RESULT

# [space-combat-sim patch] Writes one instance's matrix and world sphere. The matrix's fourth row stays affine: visibility now
# lives in the table, so a hidden instance needs no matrix at all.
func _write_instance_pose(entry: NodeEntry) -> void:
	var t: Transform3D = entry.model_transform
	var b: Basis = t.basis
	var m := entry.instance_index * FLOATS_PER_TRANSFORM
	_instance_transform_floats[m] = b.x[0]
	_instance_transform_floats[m + 1] = b.x[1]
	_instance_transform_floats[m + 2] = b.x[2]
	_instance_transform_floats[m + 3] = 0.0
	_instance_transform_floats[m + 4] = b.y[0]
	_instance_transform_floats[m + 5] = b.y[1]
	_instance_transform_floats[m + 6] = b.y[2]
	_instance_transform_floats[m + 7] = 0.0
	_instance_transform_floats[m + 8] = b.z[0]
	_instance_transform_floats[m + 9] = b.z[1]
	_instance_transform_floats[m + 10] = b.z[2]
	_instance_transform_floats[m + 11] = 0.0
	_instance_transform_floats[m + 12] = t.origin.x
	_instance_transform_floats[m + 13] = t.origin.y
	_instance_transform_floats[m + 14] = t.origin.z
	_instance_transform_floats[m + 15] = 1.0
	var center: Vector3 = t * entry.local_center
	var largest_axis := maxf(b.x.length_squared(), maxf(b.y.length_squared(), b.z.length_squared()))
	var s := entry.instance_index * FLOATS_PER_SPHERE
	_instance_spheres[s] = center.x
	_instance_spheres[s + 1] = center.y
	_instance_spheres[s + 2] = center.z
	_instance_spheres[s + 3] = entry.local_radius * sqrt(largest_axis)

func _build_node_entry(node: Node, instance_index: int) -> NodeEntry:
	var entry := NodeEntry.new()
	entry.model_transform = _get_node_transform(node)
	entry.visible = _get_node_visibility(node)

	var gaussian: Resource = node.get("gaussian")
	if gaussian == null:
		return entry

	var point_count := int(gaussian.get("point_count"))
	var point_data: PackedByteArray = gaussian.get("point_data_byte")
	if point_count <= 0 or point_data.is_empty():
		return entry

	var expected_size := point_count * FLOATS_PER_SPLAT * BYTES_PER_FLOAT
	if point_data.size() != expected_size:
		push_warning("[gdgs] GaussianResource data size mismatch. Expected %d, got %d bytes." % [expected_size, point_data.size()])
		return entry

	entry.point_count = point_count
	entry.instance_index = instance_index
	entry.point_data_byte = point_data
	var bounds: AABB = gaussian.get("aabb")  # [space-combat-sim patch]
	entry.local_center = bounds.get_center()
	entry.local_radius = bounds.size.length() * 0.5 * SPHERE_RADIUS_FACTOR + SPHERE_RADIUS_EXTRA
	entry.lighting_byte = _build_lighting_byte(node, point_count)
	entry.has_lighting = entry.lighting_byte.size() == point_count * LIGHTING_BYTES_PER_SPLAT and _node_has_bake(node)
	return entry

## The node's baked per-splat records, or a zero-filled block of the right size
## when there is no usable bake. The buffer must stay parallel to the splat
## data either way; the per-instance `enabled` flag is what actually gates
## relighting, so zeros are never read.
func _build_lighting_byte(node: Node, point_count: int) -> PackedByteArray:
	var expected := point_count * LIGHTING_BYTES_PER_SPLAT
	var lighting: Variant = node.get("lighting")
	if lighting != null and is_instance_valid(lighting) and lighting is Resource:
		var resource := lighting as Resource
		if resource.has_method("is_splat_data_valid") and bool(resource.call("is_splat_data_valid")):
			if int(resource.get("source_point_count")) == point_count:
				var data: PackedByteArray = resource.get("splat_data")
				if data.size() == expected:
					return data
			else:
				push_warning(
					"[gdgs] compute: lighting bake is for %d splats but the resource has %d; rebake it"
					% [int(resource.get("source_point_count")), point_count]
				)
	var empty := PackedByteArray()
	empty.resize(expected)
	return empty

func _node_has_bake(node: Node) -> bool:
	var lighting: Variant = node.get("lighting")
	if lighting == null or not is_instance_valid(lighting) or not (lighting is Resource):
		return false
	var resource := lighting as Resource
	return resource.has_method("is_splat_data_valid") and bool(resource.call("is_splat_data_valid"))

## Two vec4 per instance, in instance order:
##   [0] unlit level, light gain, DC-only flag, enabled flag
##   [1] ambient rgb, unused
func _build_instance_relight_floats() -> PackedFloat32Array:
	var packed := PackedFloat32Array()
	if _instance_count <= 0:
		return packed
	for node in _splat_nodes:
		if not is_instance_valid(node):
			continue
		var entry: NodeEntry = _node_entries.get(node.get_instance_id(), null)
		if entry == null or entry.point_count <= 0 or entry.instance_index < 0:
			continue
		packed.append_array(_relight_floats_of(node, entry))
	return packed

# [space-combat-sim patch] One instance's knobs, split out so a changed knob can patch its own entry.
func _relight_floats_of(node: Node, entry: NodeEntry) -> PackedFloat32Array:
	var enabled := entry.has_lighting and bool(node.get("relight_enabled"))
	var ambient: Color = node.get("relight_ambient")
	return PackedFloat32Array([
		float(node.get("relight_unlit_level")),
		float(node.get("relight_light_gain")),
		1.0 if bool(node.get("relight_dc_only")) else 0.0,
		1.0 if enabled else 0.0,
		ambient.r, ambient.g, ambient.b, 0.0,
	])

func _get_node_transform(node: Node) -> Transform3D:
	if node is Node3D:
		return (node as Node3D).global_transform
	return Transform3D.IDENTITY
	
func _get_node_visibility(node: Node) -> bool:
	if node is Node3D:
		return (node as Node3D).is_visible_in_tree()
	return true

func _prune_splat_nodes() -> void:
	for i in range(_splat_nodes.size() - 1, -1, -1):
		if not is_instance_valid(_splat_nodes[i]):
			_splat_nodes.remove_at(i)

func _change_result(
	request_cleanup: bool,
	require_gpu_rebuild: bool,
	require_splat_upload: bool,
	require_instance_upload: bool
) -> Dictionary:
	return {
		"request_cleanup": request_cleanup,
		"require_gpu_rebuild": require_gpu_rebuild,
		"require_splat_upload": require_splat_upload,
		"require_instance_upload": require_instance_upload
	}
