class_name LensFlareAim
extends RefCounted
## Where the star is on screen, in the terms the lens flare add-on expects (its own `world_environment.gd` does the same sums
## on the WorldEnvironment; we keep the add-on untouched and drive the effect from `PostEffects` instead).

## Smallest distance of the probe point, m: keeps it clear of the camera's near plane.
const MIN_PROBE_M: float = 1.0


## 1 looking straight at the star, -1 looking away.
static func facing(camera_forward: Vector3, to_sun: Vector3) -> float:
	return camera_forward.normalized().dot(to_sun.normalized())


## A point on the way to the star that the camera can project; the star itself is at infinity.
static func probe_point(camera_position: Vector3, to_sun: Vector3, near: float) -> Vector3:
	return camera_position + to_sun.normalized() * maxf(near, MIN_PROBE_M)


## The star's place in the camera's viewport, 0-1 on both axes with y down. Behind the camera it mirrors; `facing` says which.
static func sun_uv(camera: Camera3D, to_sun: Vector3) -> Vector2:
	var point: Vector3 = probe_point(camera.global_position, to_sun, camera.near)
	return camera.unproject_position(point) / camera.get_viewport().get_visible_rect().size
