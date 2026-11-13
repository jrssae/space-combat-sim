class_name TransitScale
extends RefCounted
## Scales one body uniformly while it flies a jump vortex's funnel (M6-T22): its meshes and effects, its Jolt shapes and its hit
## volumes, about the body's origin. The body's own transform is never scaled (Jolt does not take a scaled rigid body): each
## direct child and each shape owner is, so Jolt collides with the shrunk shapes. Its mass, inertia and centre of mass are held
## as they were (a body whose inertia Jolt worked out from its shapes is pinned to it for the passage), its damping stays zero.
##
## The meshes follow every change (but not while the ship is a far dot, which draws none of them); the shapes and hit volumes follow in steps of `COLLISION_STEP` (and exactly at 1), and only
## when the caller allows one (`VortexTransits` hands out a few a tick), so a wave of hundreds of ships shrinking at once does not
## rebuild every hull every tick. The core is asked to read the body's radius again
## at each step, so the hit sweep, the contacts, the radar and the HUD's markers see the scaled size. `restore` puts every
## transform back exactly as captured.

## The meshes are redrawn once the scale has moved this share from theirs (finer than the eye sees at a funnel's pace).
const VISUAL_STEP: float = 0.01
## The shapes and hit volumes are rebuilt once the scale has moved this share from theirs.
const COLLISION_STEP: float = 0.15

var body: RigidBody3D = null
## The scale it is at now (the last asked), the one its meshes are drawn at, and the one its shapes and hit volumes have.
var scale: float = 1.0
var visual_scale: float = 1.0
var collision_scale: float = 1.0
## Shape and hit-volume rebuilds so far (tests, the provider).
var collision_steps: int = 0

var _visuals: Array[Node3D] = []
var _visual_base: Array[Transform3D] = []
var _shape_nodes: Array[CollisionShape3D] = []
var _shape_node_base: Array[Transform3D] = []
var _owners := PackedInt32Array()
var _owner_base: Array[Transform3D] = []
var _damageable: Damageable = null
var _pinned_inertia: bool = false
var _pinned_com: bool = false


## Captures `p_body`'s children and shapes as they are now (its whole size).
func _init(p_body: RigidBody3D) -> void:
	body = p_body
	for child: Node in body.get_children():
		if child is CollisionShape3D:
			_shape_nodes.append(child as CollisionShape3D)
			_shape_node_base.append((child as CollisionShape3D).transform)
		elif child is Marker3D:
			continue  # a point, not a look: the cockpit camera's anchor keeps its place (its camera must not be scaled)
		elif child is Node3D:
			_visuals.append(child as Node3D)
			_visual_base.append((child as Node3D).transform)
		elif child is Damageable:
			_damageable = child as Damageable
	for owner_id: int in body.get_shape_owners():
		if body.shape_owner_get_owner(owner_id) == body:
			_owners.append(owner_id)
			_owner_base.append(body.shape_owner_get_transform(owner_id))
	_pin_mass()


## Draws the body at `factor` of its size, and collides at it too when the shapes are a step off and `may_step` allows a
## rebuild (always at 1). Returns whether the shapes were rebuilt.
func apply(factor: float, may_step: bool = true) -> bool:
	if not is_instance_valid(body):
		return false
	scale = factor
	var unseen: bool = body is Ship and (body as Ship).is_far_dot() and factor != 1.0  # a far dot draws none of its meshes
	if not unseen and (factor == 1.0 or absf(factor / visual_scale - 1.0) >= VISUAL_STEP):
		visual_scale = factor
		var s := Transform3D(Basis.from_scale(Vector3.ONE * factor), Vector3.ZERO)
		for i: int in _visuals.size():
			if is_instance_valid(_visuals[i]):
				_visuals[i].transform = s * _visual_base[i]
	if factor == collision_scale:
		return false
	if factor != 1.0 and (not may_step or absf(factor / collision_scale - 1.0) < COLLISION_STEP):
		return false
	_apply_collision(factor)
	return true


## Back to the whole size, every transform as captured, the mass properties as they were.
func restore() -> void:
	if not is_instance_valid(body):
		return
	apply(1.0)
	if _pinned_inertia:
		body.inertia = Vector3.ZERO
	if _pinned_com:
		body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_AUTO
	_pinned_inertia = false
	_pinned_com = false


func _apply_collision(factor: float) -> void:
	collision_scale = factor
	collision_steps += 1
	var s := Transform3D(Basis.from_scale(Vector3.ONE * factor), Vector3.ZERO)
	for i: int in _shape_nodes.size():
		if is_instance_valid(_shape_nodes[i]):
			_shape_nodes[i].transform = s * _shape_node_base[i]
	for i: int in _owners.size():
		body.shape_owner_set_transform(_owners[i], s * _owner_base[i])
	if _damageable != null and is_instance_valid(_damageable):
		_damageable.set_hull_scale(factor)
	var sim: SimCore = SimCore.for_tree(body.get_tree()) if body.is_inside_tree() else null
	if sim != null:
		sim.touch(body)


# A body whose inertia or centre of mass Jolt takes from its shapes keeps what it has now for the passage: shrinking the shapes
# must not make it spin or balance differently.
func _pin_mass() -> void:
	if not body.is_inside_tree():
		return
	var state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(body.get_rid())
	if state == null:
		return
	if body.inertia == Vector3.ZERO:
		var inv: Vector3 = state.inverse_inertia
		body.inertia = Vector3(_invert(inv.x), _invert(inv.y), _invert(inv.z))
		_pinned_inertia = true
	if body.center_of_mass_mode == RigidBody3D.CENTER_OF_MASS_MODE_AUTO:
		var com: Vector3 = state.center_of_mass_local
		body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		body.center_of_mass = com
		_pinned_com = true


static func _invert(x: float) -> float:
	return 1.0 / x if x > 1e-12 else 0.0
