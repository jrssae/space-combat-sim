class_name ChaseCameraMath
extends RefCounted
## Chase camera pose smoothing (architecture §8), pure.
##
## The goal pose sits behind and above the ship in the ship's own frame and looks at a point ahead of it, so the
## camera follows orientation (not velocity): sideways drift and pod tank-steering stay visible. The camera eases
## toward the goal with exponential half-life smoothing, `1 - 2^(-dt / half_life)` of the remaining error per
## step. Because exponentials compose, stepping twice by dt / 2 equals stepping once by dt for a fixed goal (the
## same holds for the slerp), which is what makes it frame-rate independent; with a moving goal it is the usual
## first-order approximation.
##
## The only state is the `current` pose the caller passes in and gets back, so a world rebase (which shifts the
## camera node together with the ship) cannot leave anything stale in here.

## Below this a direction is treated as degenerate (camera on its look-at point, or looking along the up axis).
const _EPSILON: float = 1e-6


## The pose the camera is easing toward for a ship at `ship`.
static func target_pose(ship: Transform3D, cfg: ChaseCameraConfig) -> Transform3D:
	var ship_basis: Basis = ship.basis.orthonormalized()
	var position: Vector3 = ship.origin + ship_basis * cfg.offset_local
	var look_at_point: Vector3 = ship.origin - ship_basis.z * cfg.look_ahead_m
	var direction: Vector3 = look_at_point - position
	var up: Vector3 = ship_basis.y
	# Basis.looking_at errors out on a zero direction or one parallel to up; fall back to the ship's own heading.
	if direction.length_squared() < _EPSILON or direction.normalized().cross(up).length_squared() < _EPSILON:
		return Transform3D(ship_basis, position)
	return Transform3D(Basis.looking_at(direction, up), position)


## Fraction of the remaining error that closes in `dt` seconds for a given half-life.
static func blend(dt: float, half_life_s: float) -> float:
	if dt <= 0.0:
		return 0.0
	if half_life_s <= 0.0:
		return 1.0
	return 1.0 - pow(2.0, -dt / half_life_s)  # GDScript has no exp2


## One smoothing step: `current` moved toward the goal pose for `ship` by `dt` seconds.
static func step(current: Transform3D, ship: Transform3D, dt: float, cfg: ChaseCameraConfig) -> Transform3D:
	var goal: Transform3D = target_pose(ship, cfg)
	var position: Vector3 = current.origin.lerp(goal.origin, blend(dt, cfg.position_half_life_s))
	var from: Quaternion = current.basis.get_rotation_quaternion()
	var to: Quaternion = goal.basis.get_rotation_quaternion()
	return Transform3D(Basis(from.slerp(to, blend(dt, cfg.rotation_half_life_s))), position)
