class_name StarPointMath
extends RefCounted
## How a star is drawn as a point (architecture §17.19, M4-T30c): a disc of a fixed angular radius that is never drawn smaller than
## the 1 px floor, dimmed by the inverse square of how far under the floor it is, so the light it delivers is the same at every
## render height. It is the running lights' rule (`RunningLightDimming`, Q26) with the distance fixed at 1 and the radius an
## angle. `star_point.gdshader` mirrors it; keep the two in parity. Pure.
##
## `focal_px` is the vertical focal length in pixels: `projection[1][1] * 0.5 * viewport_height`.

## The light a point delivers per unit brightness over a footprint of radius 1 px (kept from the first sprite's profile, so the
## star file's brightness means the same).
const PROFILE_AREA: float = PI / 3.0
## The soft point's Gaussian width as a share of its footprint radius: wide enough that a star's brightest pixel varies under 2x
## as it crosses pixel centres and corners, narrow enough to stay a point (Q26).
const SOFTNESS: float = 0.7
## How many widths the drawn quad reaches.
const KERNEL_SIGMAS: float = 3.0


## The focal length in pixels of a camera with this vertical field of view at this render height.
static func focal_px(fov_deg: float, height_px: float) -> float:
	return 0.5 * height_px / tan(deg_to_rad(fov_deg) * 0.5)


## The drawn radius in pixels: the disc's own, never under the floor.
static func footprint_radius_px(radius_rad: float, focal: float, floor_px: float) -> float:
	return RunningLightDimming.footprint_radius_px(radius_rad, focal, floor_px, 1.0)


## 1 while the disc is at least the floor, else (disc / floor)^2.
static func brightness_factor(radius_rad: float, focal: float, floor_px: float) -> float:
	return RunningLightDimming.brightness_factor(radius_rad, focal, floor_px, 1.0)


## The light the drawn point delivers, in radiance times steradians: what the eye gets, whatever the render height.
static func delivered_light(brightness: float, radius_rad: float, focal: float, floor_px: float) -> float:
	var footprint_rad: float = footprint_radius_px(radius_rad, focal, floor_px) / focal
	return brightness * brightness_factor(radius_rad, focal, floor_px) * PROFILE_AREA * footprint_rad * footprint_rad


## How far from its centre a star with this footprint lights pixels, px.
static func kernel_radius_px(footprint_px: float) -> float:
	return KERNEL_SIGMAS * SOFTNESS * footprint_px


## The light a star of unit brightness and full brightness factor puts in a pixel `r_px` from its centre: a Gaussian holding
## `PROFILE_AREA * footprint^2` in all, cut at `KERNEL_SIGMAS` widths and renormalised for the cut.
static func kernel_weight(r_px: float, footprint_px: float) -> float:
	var sigma: float = SOFTNESS * footprint_px
	if r_px > KERNEL_SIGMAS * sigma:
		return 0.0
	var kept: float = 1.0 - exp(-0.5 * KERNEL_SIGMAS * KERNEL_SIGMAS)
	var area: float = PROFILE_AREA * footprint_px * footprint_px
	return area * exp(-0.5 * r_px * r_px / (sigma * sigma)) / (TAU * sigma * sigma * kept)


## Where a world direction falls on the sky's panorama (Godot's convention: the centre looks toward +Z, +u turns toward -X,
## v = 0 is straight up).
static func panorama_uv(direction: Vector3) -> Vector2:
	var d: Vector3 = direction.normalized()
	return Vector2(atan2(-d.x, d.z) / TAU + 0.5, 0.5 - asin(clampf(d.y, -1.0, 1.0)) / PI)
