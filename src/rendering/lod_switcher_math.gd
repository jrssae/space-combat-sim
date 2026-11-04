class_name LodSwitcherMath
extends RefCounted
## Which splat level of detail a ship should draw for its size on screen (M3-T19, Q22). Pure.
##
## Levels by projected diameter: LOD0 from 200 px, LOD1 from 60 px, LOD2 from 16 px, else LOD3. Going coarser happens at
## the threshold; going finer needs 25 % more, so a ship hovering on a threshold never flaps. The player's Starfury has one
## level finer than LOD0, the hero (M3-T24), from 400 px: level -1, so the numbers of the other levels never move.

const THRESHOLDS_PX: Array[float] = [200.0, 60.0, 16.0]
## Level -1, the hero: only for a chain that starts there.
const HERO: int = -1
const HERO_THRESHOLD_PX: float = 400.0
## "No level yet" (a ship's first frame, a level not forced). Below the hero, so no real level is mistaken for it.
const NONE: int = -2
const HYSTERESIS: float = 1.25
const COARSEST: int = 3
## A far dot (M4-T11) shows its levels again only this far inside the dot distance, so a ship on the line never flaps.
const FAR_RETURN: float = 0.9


## The lines the 3D is drawn at in `viewport` (M4-T27): its height times its 3D scale, so a 4K window drawing the 3D at 1 080 lines
## picks levels for 1 080 lines.
static func render_height(viewport: Viewport) -> float:
	if viewport == null:
		return 0.0
	return viewport.get_visible_rect().size.y * maxf(viewport.scaling_3d_scale, 0.01)


## The ship's diameter on screen in pixels (INF when the camera is inside it).
static func projected_px(radius_m: float, distance_m: float, fov_deg: float, viewport_height_px: float) -> float:
	if distance_m <= radius_m:
		return INF
	return radius_m * viewport_height_px / (distance_m * tan(deg_to_rad(fov_deg) * 0.5))


## Where `level` starts: the projected diameter that calls for it, in pixels.
static func threshold_px(level: int) -> float:
	return HERO_THRESHOLD_PX if level < 0 else THRESHOLDS_PX[level]


## The level for `px` given the level drawn now (`current`, anything below `finest` for none yet), before bias and clamping.
## `finest` is the finest level the ship's chain has: 0, or `HERO` for the player's Starfury.
static func next_level(px: float, current: int, finest: int = 0) -> int:
	var target: int = COARSEST
	for level: int in range(finest, THRESHOLDS_PX.size()):
		if px >= threshold_px(level):
			target = level
			break
	if current < finest or target >= current:
		return target
	# Finer than now: only as far as the extra margin allows.
	var finer: int = current
	while finer > finest and px >= threshold_px(finer - 1) * HYSTERESIS:
		finer -= 1
	return finer


## The level to draw: `level` moved by the tester's bias (whole levels, + is coarser) and kept inside the ship's chain.
static func applied(level: int, bias: float, lowest: int, highest: int) -> int:
	return clampi(level + roundi(bias), lowest, highest)


## Whether a ship `distance_m` from the camera is drawn as a far dot (M4-T11), given whether it is one now: past `far_m`, and
## once a dot until it comes `FAR_RETURN` of the way back in.
static func far_dot(distance_m: float, was_far: bool, far_m: float) -> bool:
	return distance_m >= far_m * FAR_RETURN if was_far else distance_m > far_m
