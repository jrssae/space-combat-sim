class_name ShotCull
extends RefCounted
## Range culling for the frills of a shot (M5-T37, review L6): a flash or a shot sound far from the camera cannot be seen or
## heard, so it is not made. Pure maths plus the camera lookup; the pool and the audio director count what they skip.

## Beyond this a 1.2 m flash is under a pixel and the light reaches nothing, m.
const FLASH_RANGE_M: float = 2500.0
## Beyond this a shot is more than 40 dB down (inverse distance from a 60 m unit size), m.
const SOUND_RANGE_M: float = 3000.0


## The camera's position for `node`'s viewport; false when there is no camera (nothing is culled then).
static func listener(node: Node) -> Variant:
	if node == null or not node.is_inside_tree():
		return null
	var camera: Camera3D = node.get_viewport().get_camera_3d()
	return camera.global_position if camera != null else null


## True when `at` is within `range_m` of `from` (squared distances, no root).
static func within(from: Vector3, at: Vector3, range_m: float) -> bool:
	return from.distance_squared_to(at) <= range_m * range_m
