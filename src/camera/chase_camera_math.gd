class_name ChaseCameraMath
extends RefCounted
## Chase camera pose (architecture §8), pure.
##
## The camera is bolted to the ship: its pose is the ship's pose times one fixed ship-space transform (`local_pose`:
## behind and above the ship, looking at a point ahead of its nose), so it follows orientation (not velocity), sits
## exactly the same distance behind the ship whatever the ship does (reverse thrust, yaw, roll) and keeps the same
## picture of it on screen. Sideways drift and pod tank-steering stay visible because the world moves, not the camera.
##
## With `ChaseCameraConfig.smoothing_s = 0` (the default) `step` returns exactly `target_pose`. A positive value lags
## only the *orientation* of the camera frame behind the ship's, with that time constant; the position is always
## `ship origin + frame * offset`, so the camera never falls behind or overtakes the ship along its path. Exponentials
## compose, so stepping twice by dt / 2 equals stepping once by dt for a fixed goal (the same holds for the slerp),
## which makes the lag frame-rate independent.
##
## The only state is the `current` pose the caller passes in and gets back, so a world rebase (which shifts the
## camera node together with the ship) cannot leave anything stale in here.

## Below this a direction is treated as degenerate (camera on its look-at point, or looking along the up axis).
const _EPSILON: float = 1e-6


## The fixed camera pose in the ship's own frame: at `cfg.offset_local`, looking at the point `cfg.look_ahead_m` ahead
## of the ship's origin along its forward (-Z) axis with the ship's up as up.
static func local_pose(cfg: ChaseCameraConfig) -> Transform3D:
	var direction: Vector3 = Vector3(0.0, 0.0, -cfg.look_ahead_m) - cfg.offset_local
	# Basis.looking_at errors out on a zero direction or one parallel to up; fall back to the ship's own heading.
	if direction.length_squared() < _EPSILON or direction.normalized().cross(Vector3.UP).length_squared() < _EPSILON:
		return Transform3D(Basis.IDENTITY, cfg.offset_local)
	return Transform3D(Basis.looking_at(direction, Vector3.UP), cfg.offset_local)


## The rigid pose for a ship at `ship` (its scale is ignored): `ship * local_pose`.
static func target_pose(ship: Transform3D, cfg: ChaseCameraConfig) -> Transform3D:
	return Transform3D(ship.basis.orthonormalized(), ship.origin) * local_pose(cfg)


## Fraction of the remaining error that closes in `dt` seconds for a first-order lag with time constant
## `time_constant_s`. No time passes: 0. No lag: 1.
static func blend(dt: float, time_constant_s: float) -> float:
	if dt <= 0.0:
		return 0.0
	if time_constant_s <= 0.0:
		return 1.0
	return 1.0 - exp(-dt / time_constant_s)


## One step: the pose for a ship at `ship`, given the pose `current` the camera has now. Rigid (`target_pose`, `current`
## and `dt` ignored) when `cfg.smoothing_s` is 0; otherwise the camera frame (`current` with the fixed local rotation
## taken out) slerps toward the ship's orientation while the position stays glued to the ship.
static func step(current: Transform3D, ship: Transform3D, dt: float, cfg: ChaseCameraConfig) -> Transform3D:
	if cfg.smoothing_s <= 0.0:
		return target_pose(ship, cfg)
	var local: Transform3D = local_pose(cfg)
	var frame_now: Quaternion = (current.basis.orthonormalized() * local.basis.inverse()).get_rotation_quaternion()
	var frame_goal: Quaternion = ship.basis.orthonormalized().get_rotation_quaternion()
	var frame := Transform3D(Basis(frame_now.slerp(frame_goal, blend(dt, cfg.smoothing_s))), ship.origin)
	return frame * local
