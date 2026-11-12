class_name PauseOrbitPath
extends RefCounted
## The slow camera move behind the pause menu (M5-T42): a figure 8 around the ship, in the ship's own frame.
##
## The camera circles the ship once per loop while rising and dipping twice (a vertical lemniscate: seen from the side it is
## an 8, and the crossing is off to the side, so the path never nears the hull). It passes the nose and the tail in turn.
## Pure: a phase in [0, 1) in, a ship-local pose out; the caller owns the clock, so it runs while the tree is paused and a
## rebase cannot touch it.

## Orbit radius as a multiple of the chase camera's distance, and as a multiple of the hull's bounding radius (the larger wins).
const CHASE_DISTANCE_SCALE: float = 1.3
const HULL_RADIUS_SCALE: float = 2.0
## Peak height above and below the orbit plane, as a fraction of the radius (about 20 degrees of tilt).
const HEIGHT_FRACTION: float = 0.36
## The aim point sits this far ahead of the ship's centre, as a fraction of the radius.
const LEAD_FRACTION: float = 0.12
## How far the aim is pushed to the camera's left so the ship sits in the right half of the frame, as a fraction of the radius.
const FRAME_SHIFT_FRACTION: float = 0.22

var radius_m: float = 12.0


## `chase_distance_m` is the length of the chase camera's offset; `hull_radius_m` the ship's bounding radius.
static func create(chase_distance_m: float, hull_radius_m: float) -> PauseOrbitPath:
	var path := PauseOrbitPath.new()
	path.radius_m = maxf(chase_distance_m * CHASE_DISTANCE_SCALE, hull_radius_m * HULL_RADIUS_SCALE)
	return path


## The camera's position on the loop, ship-local. Phase 0 is behind the ship (the chase view's side).
func position_at(phase: float) -> Vector3:
	var a: float = TAU * phase
	return Vector3(radius_m * sin(a), radius_m * HEIGHT_FRACTION * sin(2.0 * a), radius_m * cos(a))


## The point the camera looks at, ship-local: ahead of the centre, pushed aside so the ship frames to the right.
func look_at_at(phase: float) -> Vector3:
	var eye: Vector3 = position_at(phase)
	var aim := Vector3(0.0, 0.0, -radius_m * LEAD_FRACTION)
	var forward: Vector3 = (aim - eye).normalized()
	var right: Vector3 = forward.cross(Vector3.UP)
	if right.length_squared() < 0.0001:
		return aim
	return aim - right.normalized() * radius_m * FRAME_SHIFT_FRACTION


## The ship-local camera transform at `phase`: on the loop, -z at the aim point.
func transform_at(phase: float) -> Transform3D:
	var eye: Vector3 = position_at(phase)
	return Transform3D(Basis.IDENTITY, eye).looking_at(look_at_at(phase), Vector3.UP)


## The phase whose camera position is closest to the ship-local `point`, so the move from the player's view starts short.
func nearest_phase(point: Vector3, samples: int = 360) -> float:
	var best_phase: float = 0.0
	var best_d: float = INF
	for i: int in samples:
		var phase: float = float(i) / float(samples)
		var d: float = position_at(phase).distance_squared_to(point)
		if d < best_d:
			best_d = d
			best_phase = phase
	return best_phase
