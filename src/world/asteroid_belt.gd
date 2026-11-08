class_name AsteroidBelt
extends Node3D
## A sparse belt of generated rocks (M5-T29, D63): the `asteroids` shapes placed by a `BeltLayout`, one
## `MultiMeshInstance3D` per shape, so the belt costs a handful of draw calls (the importer's mesh levels still apply). Each rock collides as its shape's spheres (one, or two or three along a
## long rock): static bodies made through `PhysicsServer3D` by RID and registered as `StaticRows`, so the contact scan, the
## hit sweep, rams and avoidance see them with no node per rock and nothing walked per tick. The rocks do not move.
##
## Spawn it with `WorldFrame.spawn` (it is shiftable, so its meshes follow a rebase), call `build`, and connect the world's
## `rebased` to `on_rebased`: the RID bodies do not follow a node. Everything is released when it leaves the tree.

const ASSET_DIR: String = "res://assets/generated/asteroids"

## Rocks placed, collision spheres made, and multimeshes drawing them.
var rock_count: int = 0
var sphere_count: int = 0
var draw_groups: int = 0

var _local: Array[Transform3D] = []
var _bodies: Array[RID] = []
var _shapes: Array[RID] = []
var _row_ids := PackedInt64Array()


func _exit_tree() -> void:
	free_bodies()


## The generated shapes (`shapes.json`): each with its mesh section, bounding radius and spheres; empty when not generated.
static func shapes() -> Array:
	var text: String = FileAccess.get_file_as_string(ASSET_DIR.path_join("shapes.json"))
	if text.is_empty():
		return []
	var data: Variant = JSON.parse_string(text)
	return (data as Dictionary).get("shapes", []) if data is Dictionary else []


## Builds `layout`'s rocks into `space` and registers their spheres as rows of `world`. Call once, in the tree.
func build(layout: BeltLayout, space: RID, world: Node, shape_list: Array = shapes()) -> void:
	if shape_list.is_empty():
		push_warning("AsteroidBelt: %s is not generated (scripts/gen_assets.sh); the belt is not built" % ASSET_DIR)
		return
	var groups: Dictionary = {}  # shape index -> Array[Transform3D]
	for rock: Dictionary in layout.rocks:
		var shape: Dictionary = shape_list[int(rock["shape"]) % shape_list.size()]
		var scale: float = float(rock["radius"]) / float(shape["bounding_radius_m"])
		var placed := Transform3D((rock["basis"] as Basis).scaled(Vector3.ONE * scale), rock["offset"])
		var key: int = int(rock["shape"]) % shape_list.size()
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(placed)
		for sphere: Dictionary in shape["spheres"]:
			var c: Array = sphere["centre"]
			_add_sphere(placed * Vector3(float(c[0]), float(c[1]), float(c[2])), float(sphere["radius_m"]) * scale, space, world)
		rock_count += 1
	for key: int in groups:
		_add_group(shape_list[key], groups[key])


## Puts every sphere's body back under the belt after a rebase moved this node.
func on_rebased(_offset: Vector3) -> void:
	for i: int in _bodies.size():
		PhysicsServer3D.body_set_state(_bodies[i], PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform * _local[i])


## Releases the bodies and the rows (also when the node leaves the tree).
func free_bodies() -> void:
	StaticRows.unregister_many(_row_ids)
	_row_ids.clear()
	for body: RID in _bodies:
		PhysicsServer3D.free_rid(body)
	for shape: RID in _shapes:
		PhysicsServer3D.free_rid(shape)
	_bodies.clear()
	_shapes.clear()
	_local.clear()


# One collision sphere: a static body by RID, and its row.
func _add_sphere(at: Vector3, radius: float, space: RID, world: Node) -> void:
	var shape: RID = PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(shape, radius)
	var body: RID = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(body, shape)
	PhysicsServer3D.body_set_space(body, space)
	PhysicsServer3D.body_set_collision_layer(body, CollisionLayers.layer_of(&"rock"))
	PhysicsServer3D.body_set_collision_mask(body, CollisionLayers.mask_of(&"rock"))
	var local := Transform3D(Basis.IDENTITY, at)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform * local)
	_local.append(local)
	_shapes.append(shape)
	_bodies.append(body)
	_row_ids.append(body.get_id())
	StaticRows.register(body.get_id(), global_transform * at, radius, BodyKind.STATIC, Factions.NEUTRAL, world)
	sphere_count += 1


# One shape's rocks as a multimesh.
func _add_group(shape: Dictionary, transforms: Array) -> void:
	var mesh: Mesh = MeshAssets.load_textured(ASSET_DIR, shape["mesh"], false)
	if mesh == null:
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for i: int in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = "Rocks%d" % draw_groups
	instance.multimesh = multimesh
	add_child(instance)
	draw_groups += 1
