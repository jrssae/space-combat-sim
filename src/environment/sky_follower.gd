class_name SkyFollower
extends Node
## Pins the sky splat node to the active camera so the star sphere never parallaxes (architecture §7.2).
##
## The sky sits at `camera.global_position + centroid_offset`, NOT exactly at the camera. GDGS unconditionally
## subtracts the mean splat position when it imports a splat file. The generated sky is one-sided (the nebula fills
## one region), so its centroid is about 4.6 km away from the centre of the star sphere, and the import shifts the
## whole sphere by that much. `tools/procgen` records the shift as `centroid_offset` in `manifest.json` (Godot
## frame; authored position = imported position + centroid_offset), so putting the node at camera + centroid_offset
## puts the sphere centre back on the camera. Leaving the offset out makes the sphere off-centre from the camera
## and distorts the sky by about 13 degrees. `SpaceEnvironment` reads the offset from the manifest (`SkyManifest`).
##
## The sky is updated in `_process` (so it moves with the camera that the renderer is about to draw, including a
## chase camera smoothed in `_process`) and in `_physics_process` (so a teleport or world rebase made in the
## physics tick does not leave the sky a frame behind). Both run late (see `LATE_PRIORITY`) so that the cameras
## have moved by the time the sky reads them.
##
## Only the camera position is used, never its rotation: the sky is fixed in the world, the camera turns inside it.
## The camera pose is the last physics-tick one (`global_position`), not the interpolated render pose. At 20 km
## the difference (speed x one tick) is a fraction of a pixel at M1 speeds.

## Runs after the default priority 0 so that the camera rig has already moved (lower values run earlier).
const LATE_PRIORITY: int = 1000

## The node to pin. Its parent must not move it: it is a `top_level` `GaussianSplatNode`.
@export var sky: Node3D
## Godot-frame vector from the camera to the sky node's origin (manifest `centroid_offset`).
@export var centroid_offset: Vector3 = Vector3.ZERO


func _init() -> void:
	process_priority = LATE_PRIORITY
	process_physics_priority = LATE_PRIORITY


func _process(_delta: float) -> void:
	follow()


func _physics_process(_delta: float) -> void:
	follow()


## Where the sky node's origin must be for a camera at `camera_origin`. Pure; the single place the offset is applied.
static func sky_origin(camera_origin: Vector3, offset: Vector3) -> Vector3:
	return camera_origin + offset


## Moves the sky to the active camera now. Returns false (and leaves the sky where it is) when there is no sky node
## or no current camera, for example during scene setup.
func follow() -> bool:
	if sky == null or not is_instance_valid(sky) or not sky.is_inside_tree() or not is_inside_tree():
		return false
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return false
	var target: Vector3 = sky_origin(camera.global_position, centroid_offset)
	# Both loops call this; skip the write (and the transform notification GDGS reacts to) when nothing moved.
	if sky.global_position != target:
		sky.global_position = target
	return true
