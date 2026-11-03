class_name RunningLightDimming
extends RefCounted
## How a point-like emitter (a running light marker) looks beyond the distance where its real disc shrinks under the on-screen floor
## (architecture §7.3, M4-T28). Its footprint stays at the floor so it is still seen, and its brightness falls with the inverse square of
## distance, so the light it delivers is what the real disc would. The marker shader (`running_light_marker.gdshader`) mirrors
## `brightness_factor`; keep the two in parity. Pure.
##
## `focal_px` is the vertical focal length in pixels: `projection[1][1] * 0.5 * viewport_height`.


## The real disc's radius on screen, px.
static func real_radius_px(radius_m: float, focal_px: float, distance_m: float) -> float:
	return radius_m * focal_px / maxf(distance_m, 0.001)


## The distance where the real disc is `floor_px` wide in radius: closer, nothing changes; farther, the light dims.
static func crossover_distance_m(radius_m: float, focal_px: float, floor_px: float) -> float:
	return radius_m * focal_px / maxf(floor_px, 0.001)


## The drawn radius: the real one up close, never under the floor.
static func footprint_radius_px(radius_m: float, focal_px: float, floor_px: float, distance_m: float) -> float:
	return maxf(real_radius_px(radius_m, focal_px, distance_m), floor_px)


## 1 up to the crossover, then (real / floor)^2, which is 1 / d^2 and meets 1 at the crossover with no jump.
static func brightness_factor(radius_m: float, focal_px: float, floor_px: float, distance_m: float) -> float:
	var ratio: float = minf(real_radius_px(radius_m, focal_px, distance_m) / maxf(floor_px, 0.001), 1.0)
	return ratio * ratio
