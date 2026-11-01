class_name LodSwitcherMath
extends RefCounted
## Which splat level of detail a ship should draw for its size on screen (M3-T19, Q22). Pure.
##
## Levels by projected diameter: LOD0 from 200 px, LOD1 from 60 px, LOD2 from 16 px, else LOD3. Going coarser happens at
## the threshold; going finer needs 25 % more, so a ship hovering on a threshold never flaps.

const THRESHOLDS_PX: Array[float] = [200.0, 60.0, 16.0]
const HYSTERESIS: float = 1.25
const COARSEST: int = 3


## The ship's diameter on screen in pixels (INF when the camera is inside it).
static func projected_px(radius_m: float, distance_m: float, fov_deg: float, viewport_height_px: float) -> float:
	if distance_m <= radius_m:
		return INF
	return radius_m * viewport_height_px / (distance_m * tan(deg_to_rad(fov_deg) * 0.5))


## The level for `px` given the level drawn now (`current`, -1 for none yet), before bias and clamping.
static func next_level(px: float, current: int) -> int:
	var target: int = COARSEST
	for level: int in THRESHOLDS_PX.size():
		if px >= THRESHOLDS_PX[level]:
			target = level
			break
	if current < 0 or target >= current:
		return target
	# Finer than now: only as far as the extra margin allows.
	var finer: int = current
	while finer > 0 and px >= THRESHOLDS_PX[finer - 1] * HYSTERESIS:
		finer -= 1
	return finer


## The level to draw: `level` moved by the tester's bias (whole levels, + is coarser) and kept inside the ship's chain.
static func applied(level: int, bias: float, lowest: int, highest: int) -> int:
	return clampi(level + roundi(bias), lowest, highest)
