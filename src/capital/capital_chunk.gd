class_name CapitalChunk
extends RigidBody3D
## One section of a destroyed capital, come apart (M10-T11, D12.8): its break-up chunk's mesh (cut from its piece's along the
## section's boundaries, `core/chunks.py`, on the piece's maps and the ship's skin variant) and its section's collision shapes
## (D12.5: one collision piece a section), as a rigid body of its section's share of the ship's mass. Held first, frozen and
## placed by its wreck each tick (`hold`), then loose on its own motion (`release`): zero damping, no gravity of Godot's, the
## frame's pull read once a second (`HeldPull`). It stays as wreckage that ships collide with (Jolt only: no hit volumes, no
## ram damage, no rows in the core), until `CapitalWrecks` frees it.
##
## Frames: the node's origin is the chunk's centroid (`hardpoints.json` `chunks[].offset`); its shapes are moved from their
## piece's frame into the chunk's.

## The section it was, and the ship's name (readouts).
var section: String = ""
var ship_name: String = ""
var mesh_instance: MeshInstance3D = null
## Its box (the section's, in the chunk's frame): where its fires burn.
var box := AABB()

var _held: bool = true
var _pull := HeldPull.new()


## A held chunk of section `p_section`: `mesh` (null: none drawn), `shapes` (`CapitalSections.shapes_of` entries of its
## section, in its piece's frame) moved by `to_chunk` (piece frame -> chunk frame), `mass_kg`, and the ship's collision layers.
static func create(p_section: String, mesh: Mesh, skin_variant: float, shapes: Array[Dictionary], to_chunk: Transform3D,
		mass_kg: float, layer: int, mask: int) -> CapitalChunk:
	var chunk := CapitalChunk.new()
	chunk.name = "Chunk_%s" % p_section.to_pascal_case().validate_node_name()
	chunk.section = p_section
	chunk.mass = maxf(mass_kg, 1000.0)
	chunk.collision_layer = layer
	chunk.collision_mask = mask
	for shape: Dictionary in shapes:
		var node := CollisionShape3D.new()
		node.name = str(shape["name"]).to_pascal_case().validate_node_name()
		node.shape = shape["shape"]
		node.transform = to_chunk * (shape["transform"] as Transform3D)
		chunk.add_child(node, true)
	if mesh != null:
		chunk.mesh_instance = MeshInstance3D.new()
		chunk.mesh_instance.name = "Mesh"
		chunk.mesh_instance.mesh = mesh
		chunk.add_child(chunk.mesh_instance)
		HullSheenMaterial.set_variant(chunk.mesh_instance, skin_variant)
	return chunk


func _init() -> void:
	gravity_scale = 0.0
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.0
	can_sleep = false
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	add_to_group(WorldFrame.SHIFTABLE_GROUP)


func _physics_process(delta: float) -> void:
	if not _held:
		linear_velocity = _pull.kick(self, linear_velocity, delta)


## Whether its wreck still holds it.
func is_held() -> bool:
	return _held


## Placed by its wreck at `xform` (World-local) for this tick.
func hold(xform: Transform3D) -> void:
	global_transform = xform


## Let go at `velocity` and `spin` (World frame): from now on it flies on its own motion.
func release(velocity: Vector3, spin: Vector3) -> void:
	_held = false
	freeze = false
	linear_velocity = velocity
	angular_velocity = spin
	_pull.reset()


## A velocity rebase: a loose chunk keeps its universe velocity (a held one follows its wreck).
func frame_boost(dv: Vector3) -> void:
	if not _held:
		linear_velocity -= dv
		_pull.reset()
