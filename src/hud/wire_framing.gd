class_name WireFraming
extends RefCounted
## How the target preview looks at a hull (architecture §18.20, M5-T43), pure: the hull turns about its own up axis under a
## fixed orthographic view from a little above, sized from its bounding box so a Starfury and a Saturn 8 both fill the
## panel at every angle of the turn.

## The turn, degrees a second, and where it starts (from ahead and well to one side, so a long hull shows its length).
const TURN_DEG_S: float = 15.0
const START_YAW_DEG: float = 125.0
## The camera looks down on the hull by this, degrees.
const ELEVATION_DEG: float = 20.0
## Share of the view the hull takes at its widest.
const FILL: float = 0.9


## The hull's yaw `seconds` after it was highlighted, radians.
static func yaw_at(seconds: float) -> float:
	return deg_to_rad(fposmod(START_YAW_DEG + TURN_DEG_S * seconds, 360.0))


## The widest the box gets across the view over a whole turn about its centre: half the diagonal of its plan.
static func half_width(bounds: AABB) -> float:
	return Vector2(bounds.size.x, bounds.size.z).length() * 0.5


## The tallest it gets, seen from `elevation_deg` above.
static func half_height(bounds: AABB, elevation_deg: float = ELEVATION_DEG) -> float:
	var e: float = deg_to_rad(elevation_deg)
	return bounds.size.y * 0.5 * cos(e) + half_width(bounds) * sin(e)


## The height of an orthographic view of `aspect` (width / height) that holds the box through the turn. Never zero.
static func view_height(bounds: AABB, aspect: float, elevation_deg: float = ELEVATION_DEG, fill: float = FILL) -> float:
	var tall: float = 2.0 * half_height(bounds, elevation_deg)
	var wide: float = 2.0 * half_width(bounds) / maxf(aspect, 0.01)
	return maxf(maxf(tall, wide) / maxf(fill, 0.01), 0.01)


## A sphere about the box's centre that holds it: the camera stands off by it and the depth range spans it.
static func radius(bounds: AABB) -> float:
	return maxf(bounds.size.length() * 0.5, 0.01)


## Where the camera sits, the box's centre at the origin: `distance` away, `elevation_deg` above the horizon, on +Z.
static func camera_offset(distance: float, elevation_deg: float = ELEVATION_DEG) -> Vector3:
	var e: float = deg_to_rad(elevation_deg)
	return Vector3(0.0, sin(e), cos(e)) * distance
