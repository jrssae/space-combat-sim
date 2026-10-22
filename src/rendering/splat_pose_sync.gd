class_name SplatPoseSync
extends Node
## Draws a splat node at the physics-interpolated pose of its parent body (architecture §7.2).
##
## Godot interpolates meshes between physics ticks, but GDGS's Compute backend reads a splat node's plain
## `global_transform`, the pose of the last physics tick. Left alone, the hull splats would jump from tick to tick
## while the interpolated plumes, proxy mesh and a camera locked to the ship move smoothly, so the hull would judder
## against everything attached to it. This node, a child of the body, puts the splat node on
## `parent.get_global_transform_interpolated() * local` every rendered frame, and switches the splat node's own
## physics interpolation off so the engine does not blend a pose that is already interpolated (the Raster backend's
## quads are children of the splat node and follow it).
##
## `local` is the splat node's pose relative to the body when this node becomes ready (for GDGS: its Rz(180) model
## correction), so the scene keeps its layout. Rebase-safe: nothing but that fixed offset is cached.

## The splat node to drive (a `GaussianSplatNode`, or any `Node3D`). Must be below the body this node is a child of.
@export var splats: Node3D = null

var _body: Node3D = null
var _local: Transform3D = Transform3D.IDENTITY


func _ready() -> void:
	_body = get_parent() as Node3D
	if splats == null or _body == null:
		push_warning("SplatPoseSync: needs a Node3D parent and a splat node; not syncing")
		set_process(false)
		return
	_local = _body.global_transform.affine_inverse() * splats.global_transform
	splats.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _process(_delta: float) -> void:
	sync()


## The splat node's pose relative to the body (its scene pose, GDGS's Rz(180) correction included).
func local_pose() -> Transform3D:
	return _local


## Puts the splat node on the body's interpolated pose now. `_process` calls it each frame; public so tests can too.
func sync() -> void:
	if _body == null or splats == null or not is_instance_valid(splats) or not splats.is_inside_tree():
		return
	var pose: Transform3D = _body.get_global_transform_interpolated() * _local
	# Skip a no-op write: it would still notify GDGS, and the scene's exact pose should survive a resting body.
	if not pose.is_equal_approx(splats.global_transform):
		splats.global_transform = pose
