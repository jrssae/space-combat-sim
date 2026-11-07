class_name LodSwitcherMath
extends RefCounted
## When an AI ship is far enough from the camera to be drawn as a dot (M4-T11). Pure.

## A far dot shows its detail again only this far inside the dot distance, so a ship on the line never flaps.
const FAR_RETURN: float = 0.9


## Whether a ship `distance_m` from the camera is drawn as a far dot (M4-T11), given whether it is one now: past `far_m`, and
## once a dot until it comes `FAR_RETURN` of the way back in.
static func far_dot(distance_m: float, was_far: bool, far_m: float) -> bool:
	return distance_m >= far_m * FAR_RETURN if was_far else distance_m > far_m
