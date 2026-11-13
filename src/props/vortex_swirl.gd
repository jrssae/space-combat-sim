class_name VortexSwirl
extends RefCounted
## Which way a jump vortex's pattern moves (M6-T19 round 3, maintainer 2026-11-11). Pure.
##
## Seen from in front of the mouth, an arrival (ships coming out of hyperspace) turns counter-clockwise and its patches travel
## out from the throat to the rim; a departure turns clockwise and its patches travel in. Both follow the same spiral, one
## outward and one inward.

const ARRIVAL: int = 0
const DEPARTURE: int = 1


## +1 when the patches travel out toward the rim, -1 when they travel in toward the throat.
static func radial(direction: int) -> float:
	return 1.0 if direction == ARRIVAL else -1.0


## The turn as a viewer in front of the mouth sees it: +1 counter-clockwise, -1 clockwise.
static func turn_from_front(direction: int) -> float:
	return 1.0 if direction == ARRIVAL else -1.0


## The turn in the funnel mesh's own angle (from its +X toward its +Y), which is what the shader counts in. A viewer in front
## looks along the funnel's +Z with +X on the left, so the mesh's angle runs clockwise to them.
static func turn_in_mesh(direction: int) -> float:
	return -turn_from_front(direction)


## Where a patch that starts at mesh angle `angle_rad` is after turning `turned_rad`, as the front viewer's screen direction (x
## right, y up) from the axis. For tests and for checking captures.
static func seen_from_front(angle_rad: float, turned_rad: float, direction: int) -> Vector2:
	var a: float = angle_rad + turn_in_mesh(direction) * turned_rad
	return Vector2(-cos(a), sin(a))
