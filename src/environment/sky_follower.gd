class_name SkyFollower
extends Node
## Pins the sky's star field to the active camera so the stars never parallax (architecture §7.2, §17.19).
##
## The star field draws each star from its direction alone (M4-T30c), so it only has to stay round the camera: its box must
## hold the camera or the renderer culls it. The sky is updated in `_process` (so it moves with the camera that the renderer is
## about to draw, including a chase camera smoothed in `_process`) and in `_physics_process` (so a teleport or world rebase
## made in the physics tick does not leave the sky a frame behind). Both run late (see `LATE_PRIORITY`) so that the cameras
## have moved by the time the sky reads them. Only the camera's position is used, never its rotation: the sky is fixed in the
## world, the camera turns inside it.

## Runs after the default priority 0 so that the camera rig has already moved (lower values run earlier).
const LATE_PRIORITY: int = 1000

## The node to pin. Its parent must not move it: it is `top_level`.
@export var sky: Node3D


func _init() -> void:
	process_priority = LATE_PRIORITY
	process_physics_priority = LATE_PRIORITY


func _process(_delta: float) -> void:
	follow()


func _physics_process(_delta: float) -> void:
	follow()


## Moves the sky to the active camera now. Returns false (and leaves the sky where it is) when there is no sky node
## or no current camera, for example during scene setup.
func follow() -> bool:
	if sky == null or not is_instance_valid(sky) or not sky.is_inside_tree() or not is_inside_tree():
		return false
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return false
	var target: Vector3 = camera.global_position
	# Both loops call this; skip the write (and its transform notification) when nothing moved.
	if sky.global_position != target:
		sky.global_position = target
	return true
