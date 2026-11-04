class_name AsteroidField
extends Node3D
## An asteroid field stand-in (M4-T07, Q19): bench-only, built by code with no assets, replaced by M14's fields. One
## `MultiMeshInstance3D` draws every rock and each rock's collision is a static sphere body made through `PhysicsServer3D` by
## RID, so no mesh or physics node exists per rock. What the contact scan and the hit and ram resolvers find today is a
## `Damageable` in the tree, so each rock also carries one bare marker node with an unbreakable, `hit_by_anyone` hull; the
## body registry (M4-T09) and the native hit sweep (M4-T08) can take rows straight from the field instead.
##
## Spawn it with `WorldFrame.spawn` (it is shiftable, so its markers and multimesh follow a rebase) and call `on_rebased`
## after one: the RID bodies do not follow a node.

const HULL: float = 1.0e9
## Rocks do not move, so a ram is decided by the ship's own change of velocity.
const MASS_KG: float = 1.0e15
const ROCK_COLOR: Color = Color(0.36, 0.33, 0.30)

var _local: Array[Transform3D] = []
var _bodies: Array[RID] = []
var _shapes: Array[RID] = []
var _markers: Array[Node3D] = []
var _mesh: MultiMeshInstance3D = null


func _exit_tree() -> void:
	free_bodies()


## Builds the rocks (`offset` m from this node, `radius` m) into `space`. Call it once, after the node is in the tree.
func build(rocks: Array[Dictionary], space: RID) -> void:
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
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform * local)
		_shapes.append(shape)
		_bodies.append(body)
		_markers.append(_marker(i, at, radius))
	_mesh = MultiMeshInstance3D.new()
	_mesh.name = "Rocks"
	_mesh.multimesh = multimesh
	add_child(_mesh)
	move_child(_mesh, 0)


## Stub (M4-T29, tests first).
func row_id(_i: int) -> int:
	return 0


func count() -> int:
	return _bodies.size()


func body_rids() -> Array[RID]:
	return _bodies


## The node that stands for rock `i` in the scan and the resolvers.
func marker(i: int) -> Node3D:
	return _markers[i]


func multimesh() -> MultiMesh:
	return _mesh.multimesh if _mesh != null else null


## Puts every rock's body back under its marker after a rebase moved this node.
func on_rebased(_offset: Vector3) -> void:
	for i: int in _bodies.size():
		PhysicsServer3D.body_set_state(_bodies[i], PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform * _local[i])


## Releases the physics bodies (also when the node leaves the tree).
func free_bodies() -> void:
	for body: RID in _bodies:
		PhysicsServer3D.free_rid(body)
	for shape: RID in _shapes:
		PhysicsServer3D.free_rid(shape)
	_bodies.clear()
	_shapes.clear()


func _marker(i: int, at: Vector3, radius: float) -> Node3D:
	var node := Node3D.new()
	node.name = "Rock%d" % i
	node.position = at
	add_child(node)
	var hull := Damageable.new()
	hull.name = "Damageable"
	node.add_child(hull)
	var sphere := CapsuleShape3D.new()
	sphere.radius = radius
	sphere.height = 2.0 * radius
	var collision: Array[Dictionary] = [{"name": "rock", "shape": sphere, "transform": Transform3D.IDENTITY}]
	hull.setup(collision, HULL, Factions.NEUTRAL)
	hull.hit_by_anyone = true
	hull.invulnerable = true
	hull.ram_mass_kg = MASS_KG
	return node
