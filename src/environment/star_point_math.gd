class_name StarPointMath
extends RefCounted
## How a star is drawn as a point (architecture §17.19, M4-T30c): a disc of a fixed angular radius that is never drawn smaller than
## the 1 px floor, dimmed by the inverse square of how far under the floor it is, so the light it delivers is the same at every
## render height. It is the running lights' rule (`RunningLightDimming`, Q26) with the distance fixed at 1 and the radius an
## angle. `star_point.gdshader` mirrors it; keep the two in parity. Pure.
##
## `focal_px` is the vertical focal length in pixels: `projection[1][1] * 0.5 * viewport_height`.

## The light the sprite's (1 - r^2)^2 profile gives over a disc of radius 1, per unit brightness.
const PROFILE_AREA: float = PI / 3.0


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
