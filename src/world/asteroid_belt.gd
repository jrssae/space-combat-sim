class_name AsteroidBelt
extends Node3D
## A sparse belt of generated rocks (M5-T29, D63): the `asteroids` shapes placed by a `BeltLayout`, one
## `MultiMeshInstance3D` per shape, so the belt costs a handful of draw calls (the importer's mesh levels still apply). Each rock collides as its shape's spheres (one, or two or three along a
## long rock): static bodies made through `PhysicsServer3D` by RID and registered as `StaticRows`, so the contact scan, the
## hit sweep, rams and avoidance see them with no node per rock and nothing walked per tick. The rocks do not move.
##
## Spawn it with `WorldFrame.spawn` (it is shiftable, so its meshes follow a rebase), call `build`, and connect the world's
## `rebased` to `on_rebased`: the RID bodies do not follow a node. Everything is released when it leaves the tree. Only the
## spheres near a ship live as Jolt bodies (`RockBodies`, M6-T21), stepped late in every tick; the rest are rows only.
## The bench's asteroid slab is built the same way (`build_rocks`, M7-T48), so benches and tests fly among the game's rocks.

const ASSET_DIR: String = "res://assets/generated/asteroids"

## Rocks placed, collision spheres made, and multimeshes drawing them.
var rock_count: int = 0
var sphere_count: int = 0
var draw_groups: int = 0

var _rocks := RockBodies.new()
var _row_ids := PackedInt64Array()
var _world: WorldFrame = null


func _init() -> void:
	process_physics_priority = RockBodies.STEP_PRIORITY


func _exit_tree() -> void:
	free_bodies()


func _physics_process(_delta: float) -> void:
	_rocks.step(self, _world)


## The generated shapes (`shapes.json`): each with its mesh section, bounding radius and spheres; empty when not generated.
static func shapes() -> Array:
	var text: String = FileAccess.get_file_as_string(ASSET_DIR.path_join("shapes.json"))
	if text.is_empty():
		return []
	var data: Variant = JSON.parse_string(text)
	return (data as Dictionary).get("shapes", []) if data is Dictionary else []


## A rock's shape and turn picked from `seed_value` alone (a per-rock hash, no shared generator): `{"shape", "basis"}`, to merge
## into a rock that only has its place and size.
static func seeded_look(seed_value: int) -> Dictionary:
	var u: Array[float] = []
	for k: int in 4:
		u.append(float(hash([seed_value, k]) % 1000003) / 1000003.0)
	var axis := Vector3(2.0 * u[0] - 1.0, 2.0 * u[1] - 1.0, 2.0 * u[2] - 1.0)
	axis = axis.normalized() if axis.length_squared() > 1e-6 else Vector3.UP
	return {"shape": hash([seed_value, 4]), "basis": Basis(axis, (2.0 * u[3] - 1.0) * PI)}


## Builds `layout`'s rocks into `space` and registers their spheres as rows of `world`. Call once, in the tree.
func build(layout: BeltLayout, space: RID, world: Node, shape_list: Array = shapes()) -> void:
	build_rocks(layout.rocks, space, world, shape_list)


## Builds `rocks` (each `offset` m from this node, `radius` its bounding radius, `shape` any index, wrapped over the shapes, and
## `basis`) into `space`, their spheres rows of `world`. Call once, in the tree.
func build_rocks(rocks: Array[Dictionary], space: RID, world: Node, shape_list: Array = shapes()) -> void:
	if shape_list.is_empty():
		push_warning("AsteroidBelt: %s is not generated (scripts/gen_assets.sh); the rocks are not built" % ASSET_DIR)
		return
	var groups: Dictionary = {}  # shape index -> Array[Transform3D]
	for rock: Dictionary in rocks:
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
	_world = world as WorldFrame if world != null else WorldFrame.of(self)
	_rocks.step(self, _world)  # the spheres a ship is near already live before Jolt's next step


## Puts every live sphere's body back under the belt after a rebase or a drift moved this node.
func on_rebased(_offset: Vector3) -> void:
	_rocks.place(global_transform)


## Sphere `i`'s row id in `StaticRows` (its body's RID id); a rock's spheres follow each other in build order.
func row_id(i: int) -> int:
	return _row_ids[i]


## The spheres' bodies, and which of them live in Jolt now (M6-T21).
func body_rids() -> Array[RID]:
	return _rocks.body_rids()


func rock_bodies() -> RockBodies:
	return _rocks


## Releases the bodies and the rows (also when the node leaves the tree).
func free_bodies() -> void:
	StaticRows.unregister_many(_row_ids)
	_row_ids.clear()
	_rocks.free_all()


# One collision sphere: a static body by RID, dormant until a ship comes near, and its row.
func _add_sphere(at: Vector3, radius: float, space: RID, world: Node) -> void:
	var body: RID = _rocks.add(space, Transform3D(Basis.IDENTITY, at), radius, global_transform)
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
