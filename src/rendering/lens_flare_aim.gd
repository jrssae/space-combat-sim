class_name LensFlareAim
extends RefCounted
## Where the star is on screen, in the terms the lens flare add-on expects (its own `world_environment.gd` does the same sums
## on the WorldEnvironment; we keep the add-on untouched and drive the effect from `PostEffects` instead).

## How close to square-on to the view the star may sit before it is nudged in front (M6-T09), as a unit direction's depth.
const EDGE_ON: float = 1.0e-4
## Toward the picture's edge the flare fades out over this share of the screen, gone at the edge.
const EDGE_FADE: float = 0.05


## 1 looking straight at the star, -1 looking away.
static func facing(camera_forward: Vector3, to_sun: Vector3) -> float:
	return camera_forward.normalized().dot(to_sun.normalized())


## The star's place in the camera's viewport, 0-1 on both axes with y down. Behind the camera it mirrors; `facing` says which.
## Worked out from the camera's turn alone: a probe point added to a camera thousands of km out is lost to float rounding and
## put the flare's core a few degrees off the star (M7-T72).
static func sun_uv(camera: Camera3D, to_sun: Vector3) -> Vector2:
	var local: Vector3 = camera.get_camera_transform().basis.orthonormalized().inverse() * to_sun.normalized()
	# A star exactly square to the view (the sun lies in the game's XZ plane) has no projection: a hair in front has one,
	# far off screen.
	if absf(local.z) < EDGE_ON:
		local.z = -EDGE_ON
	var clip: Vector4 = camera.get_camera_projection() * Vector4(local.x, local.y, local.z, 1.0)
	var ndc := Vector2(clip.x / clip.w, clip.y / clip.w)
	return Vector2(0.5 + 0.5 * ndc.x, 0.5 - 0.5 * ndc.y)


## How much of the flare shows for a star at `uv` on screen (M8-T29, M8-T31): all of it once the star is `margin` inside the
## picture, fading to none at the edge and nothing beyond. The add-on reads the star's pixel for its occlusion test, and off screen
## that read finds nothing in the way, so without this its ghosts kept drawing for a star out of the picture: soft grey blobs with no
## star (every scene's flare goes through `PostEffects`, so this holds everywhere).
static func screen_weight(uv: Vector2, margin: float = EDGE_FADE) -> float:
	var inside: float = minf(minf(uv.x, 1.0 - uv.x), minf(uv.y, 1.0 - uv.y))  # to the nearest edge; negative off screen
	return clampf(inside / maxf(margin, 1e-6), 0.0, 1.0)
