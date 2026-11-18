class_name FarHulls
extends Node3D
## Ships and capitals in the low-attention tier, drawn (M4-T23, architecture §17.14). A far capital is not a dot: a 1 200 m carrier
## at 10 km is about 130 px tall at 1 080 lines, and a 190 m Saturn 8 is still 13 px (M7-T26). A tier row has no node to draw (its
## body is parked), so it is drawn as an instance of the mesh its body draws, in one `MultiMesh` per mesh (a class's box or its
## textured hull), so every far hull of a class is one draw call. The mesh is registered when the ship is demoted (`class_of`);
## each frame the core writes every class's instances from the rows, leaving out the rows only a few pixels across, which
## `FarDots` draws instead (`FarDots.view_rows`). Each class's bounds follow its instances, so the mesh's own levels of detail
## thin it out by its nearest instance's distance (a world-sized box would keep every far hull at full detail).
##
## A child of `World` at its origin: the rows are World-local, so the instances need no offset, and a rebase moves the rows
## in the core before the next frame writes them. Each class is shiftable, so a rebase moves what it drew with everything else at
## once (no frame at the old place); it then goes back to the origin and moves its instances instead, as `FarDots` does. A promotion takes the row in the tick its body shows, so a capital is drawn
## by its body or its row, never both and never neither. Visual only.

const NODE_NAME: String = "FarHulls"
## Floats per instance: a 3x4 transform.
const STRIDE: int = 12

## The last frame's instances over every class, and its time, us (a readout, wall clock).
var shown: int = 0
var last_refresh_us: int = 0

var _meshes: Array[Mesh] = []
var _instances: Array[MultiMeshInstance3D] = []
# What each class was last given, so the readouts need not ask the renderer.
var _buffers: Array[PackedFloat32Array] = []


## The world's far hulls, or null before any capital went into the tier.
static func of(world: Node) -> FarHulls:
	if world == null or not is_instance_valid(world):
		return null
	return world.get_node_or_null(NodePath(NODE_NAME)) as FarHulls


## The world's far hulls, made on first use.
static func attach(world: Node) -> FarHulls:
	var found: FarHulls = of(world)
	if found != null or world == null or not is_instance_valid(world):
		return found
	var made := FarHulls.new()
	world.add_child(made)
	return made


func _init() -> void:
	name = NODE_NAME


func _ready() -> void:
	var world := get_parent() as WorldFrame
	if world != null and not world.rebased.is_connected(_on_rebased):
		world.rebased.connect(_on_rebased)


func _process(_delta: float) -> void:
	refresh()


## The class drawing `mesh` (one multimesh each), made on first ask; -1 for no mesh.
func class_of(mesh: Mesh) -> int:
	if mesh == null:
		return -1
	var found: int = _meshes.find(mesh)
	if found >= 0:
		return found
	var instance := MultiMeshInstance3D.new()
	instance.name = "Class%d" % _meshes.size()
	instance.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	instance.custom_aabb = AABB(Vector3.ONE * -1.0e6, Vector3.ONE * 2.0e6)  # spread over the whole world: never culled as one
	instance.add_to_group(WorldFrame.SHIFTABLE_GROUP)
	instance.multimesh = MultiMesh.new()
	instance.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	instance.multimesh.mesh = mesh
	add_child(instance)
	_meshes.append(mesh)
	_instances.append(instance)
	_buffers.append(PackedFloat32Array())
	return _meshes.size() - 1


## The box holding every instance in `buffer` (MultiMesh transforms) of a mesh bounded by `mesh_box`, in this node's frame.
static func instances_aabb(buffer: PackedFloat32Array, mesh_box: AABB) -> AABB:
	var reach: float = maxf(mesh_box.position.length(), mesh_box.end.length())  # any rotation stays inside this
	var box := AABB()
	for k: int in buffer.size() / STRIDE:
		var o: int = k * STRIDE
		var at := Vector3(buffer[o + 3], buffer[o + 7], buffer[o + 11])
		var one := AABB(at - Vector3.ONE * reach, Vector3.ONE * 2.0 * reach)
		box = one if k == 0 else box.merge(one)
	return box


## Classes made so far.
func class_count() -> int:
	return _meshes.size()


## The mesh class `index` draws.
func class_mesh(index: int) -> Mesh:
	return _meshes[index]


## Instances class `index` drew in the last refresh.
func instance_count(index: int) -> int:
	return _buffers[index].size() / STRIDE


## Instance `k` of class `index` as drawn, in this node's frame.
func instance_transform(index: int, k: int) -> Transform3D:
	var b: PackedFloat32Array = _buffers[index]
	var o: int = k * STRIDE
	return Transform3D(Vector3(b[o], b[o + 4], b[o + 8]), Vector3(b[o + 1], b[o + 5], b[o + 9]), Vector3(b[o + 2], b[o + 6], b[o + 10]),
			Vector3(b[o + 3], b[o + 7], b[o + 11]))


## Writes every class's instances from the tier rows. `_process` calls it each frame; public for the tests.
func refresh() -> void:
	var started: int = Time.get_ticks_usec()  # a readout, never gameplay time
	var sim: SimCore = SimCore.for_tree(get_tree()) if is_inside_tree() else null
	var core: Object = sim.core if sim != null else null
	var rows: int = int(core.tier_count()) if core != null else 0
	if rows > 0:
		FarDots.view_rows(self, core)
	shown = 0
	for index: int in _instances.size():
		var multimesh: MultiMesh = _instances[index].multimesh
		var buffer := PackedFloat32Array()
		if rows > 0:
			buffer = core.tier_fill_hulls(index, -position)  # rows are World-local
		var count: int = buffer.size() / STRIDE
		if multimesh.instance_count != count:
			multimesh.instance_count = count
		if count > 0:
			MultiMeshUpload.set_buffer(multimesh, buffer)
			_instances[index].custom_aabb = instances_aabb(buffer, _meshes[index].get_aabb())
		_buffers[index] = buffer
		shown += count
	last_refresh_us = Time.get_ticks_usec() - started


# The rebase moved every class with the world; back to the origin, with the instances and their bounds moved instead.
func _on_rebased(offset: Vector3) -> void:
	for index: int in _instances.size():
		var instance: MultiMeshInstance3D = _instances[index]
		instance.position += offset
		var buffer: PackedFloat32Array = _buffers[index]
		for k: int in buffer.size() / STRIDE:
			var o: int = k * STRIDE
			buffer[o + 3] -= offset.x
			buffer[o + 7] -= offset.y
			buffer[o + 11] -= offset.z
		_buffers[index] = buffer
		if buffer.size() > 0:
			MultiMeshUpload.set_buffer(instance.multimesh, buffer)
			instance.custom_aabb = AABB(instance.custom_aabb.position - offset, instance.custom_aabb.size)
