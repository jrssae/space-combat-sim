class_name AsteroidField
extends Node3D
## An asteroid field stand-in (M4-T07, Q19): bench-only, built by code with no assets, replaced by M14's fields. One
## `MultiMeshInstance3D` draws every rock and each rock's collision is a static sphere body made through `PhysicsServer3D` by
## RID, so no mesh or physics node exists per rock. The contact scan and the hit and ram resolvers see each rock as a row of
## `StaticRows` (M4-T29, §17.16), registered once when the field is built (kind `STATIC`, neutral, the body's RID id) and
## removed with the bodies: an obstacle for every side, hit by bolts and rammed by ships, never walked a tick.
##
## Spawn it with `WorldFrame.spawn` (it is shiftable, so its multimesh follows a rebase) and pass that world to `build`, so
## its rebases move the rows; call `on_rebased` after one: the RID bodies do not follow a node.

const ROCK_COLOR: Color = Color(0.36, 0.33, 0.30)

var _local: Array[Transform3D] = []
var _bodies: Array[RID] = []
var _shapes: Array[RID] = []
var _row_ids := PackedInt64Array()
var _mesh: MultiMeshInstance3D = null


func _exit_tree() -> void:
	free_bodies()


## Builds the rocks (`offset` m from this node, `radius` m) into `space` and registers each as a row of `world` (the frame
## that spawned the field). Call it once, after the node is in the tree.
func build(rocks: Array[Dictionary], space: RID, world: Node = null) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	var material := StandardMaterial3D.new()
	material.albedo_color = ROCK_COLOR
	material.roughness = 1.0
	sphere.material = material
	multimesh.mesh = sphere
	multimesh.instance_count = rocks.size()
	for i: int in rocks.size():
		var at: Vector3 = rocks[i]["offset"]
		var radius: float = rocks[i]["radius"]
		var local := Transform3D(Basis.IDENTITY, at)
		_local.append(local)
		multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * radius), at))
		var shape: RID = PhysicsServer3D.sphere_shape_create()
		PhysicsServer3D.shape_set_data(shape, radius)
		var body: RID = PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(body, shape)
		PhysicsServer3D.body_set_space(body, space)
		PhysicsServer3D.body_set_collision_layer(body, CollisionLayers.layer_of(&"rock"))
		PhysicsServer3D.body_set_collision_mask(body, CollisionLayers.mask_of(&"rock"))
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform * local)
		_shapes.append(shape)
		_bodies.append(body)
		_row_ids.append(body.get_id())
		StaticRows.register(body.get_id(), global_transform * at, radius, BodyKind.STATIC, Factions.NEUTRAL, world)
	_mesh = MultiMeshInstance3D.new()
	_mesh.name = "Rocks"
	_mesh.multimesh = multimesh
	add_child(_mesh)
	move_child(_mesh, 0)


## Rock `i`'s row id in `StaticRows` (its body's RID id).
func row_id(i: int) -> int:
	return _row_ids[i]


func count() -> int:
	return _bodies.size()


func body_rids() -> Array[RID]:
	return _bodies


func multimesh() -> MultiMesh:
	return _mesh.multimesh if _mesh != null else null


## Puts every rock's body back under its marker after a rebase moved this node.
func on_rebased(_offset: Vector3) -> void:
	for i: int in _bodies.size():
		PhysicsServer3D.body_set_state(_bodies[i], PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform * _local[i])


## Releases the physics bodies and the rows (also when the node leaves the tree).
func free_bodies() -> void:
	StaticRows.unregister_many(_row_ids)
	_row_ids.clear()
	for body: RID in _bodies:
		PhysicsServer3D.free_rid(body)
	for shape: RID in _shapes:
		PhysicsServer3D.free_rid(shape)
	_bodies.clear()
	_shapes.clear()
