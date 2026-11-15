class_name LodSwitcherMath
extends RefCounted
## When an AI ship is small enough on screen to be drawn as a dot (M4-T11; by size on screen since M7-T26). Pure.

## A far dot shows its detail again only this far inside the dot distance, so a ship on the line never flaps.
const FAR_RETURN: float = 0.9
## The fewest picture lines the dot rule counts (M7-T26 fix): a smaller window (a 960x540 capture, a headless 64 px test window)
## keeps ships as meshes as far out as 1 080 lines would, so a ship is never a dot just because the window is small.
const MIN_VIEW_LINES: float = 1080.0


## Whether a ship `distance_m` from the camera is drawn as a far dot (M4-T11), given whether it is one now: past `far_m`, and
## once a dot until it comes `FAR_RETURN` of the way back in.
static func far_dot(distance_m: float, was_far: bool, far_m: float) -> bool:
	return distance_m >= far_m * FAR_RETURN if was_far else distance_m > far_m


## Where a hull of bounding radius `radius_m` covers `dot_px` pixels of radius, for a view of `k_px_per_rad` pixels per radian
## (M7-T26): a 100 m freighter holds its shape ten times farther out than a 10 m fighter.
static func dot_distance_m(radius_m: float, k_px_per_rad: float, dot_px: float) -> float:
	return radius_m * k_px_per_rad / maxf(dot_px, 0.001)


## The pixels per radian the dot rule counts for a view of `k_px_per_rad` and a vertical field of view of `fov_deg`: never fewer
## than `MIN_VIEW_LINES` would give.
static func view_k(k_px_per_rad: float, fov_deg: float) -> float:
	return maxf(k_px_per_rad, FarPropMath.px_per_rad(MIN_VIEW_LINES, fov_deg))
