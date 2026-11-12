class_name HeldPull
extends RefCounted
## Gravity for a short-lived mover moved in GDScript (M6-T07, D66): a debris chunk, a held wreck, an explosion's fireball, a
## projectile node. The frame's pull at the mover's place is read once a second and after a velocity rebase, not every tick:
## over a chunk's 8.5 s life it changes by under 1 mm/s^2 even in a low orbit, so a per-tick read would cost the tick for
## nothing (the error is measured in `test_gravity_movers.gd`). Where nothing pulls it holds zero and the mover keeps its bits.

## How long a read pull is kept, seconds of sim time.
const REFRESH_S: float = 1.0

## The pull last read, m/s^2 (World frame).
var accel: Vector3 = Vector3.ZERO

var _age_s: float = INF


## Makes the next `kick` read the pull again: a new life, or a velocity rebase (which changes what the frame falls with).
func reset() -> void:
	_age_s = INF


## `velocity` after `delta` seconds of the pull at `node`'s place, read again when it is due.
func kick(node: Node3D, velocity: Vector3, delta: float) -> Vector3:
	_age_s += delta
	if _age_s >= REFRESH_S:
		_age_s = 0.0
		var world: WorldFrame = WorldFrame.of(node)
		accel = world.environment_accel(world.to_local(node.global_position)) if world != null else Vector3.ZERO
	return _kicked(velocity, delta)


## `kick` for a mover with no node of its own (a held wreck): its place `at` in `world`'s coordinates.
func kick_at(world: WorldFrame, at: Vector3, velocity: Vector3, delta: float) -> Vector3:
	_age_s += delta
	if _age_s >= REFRESH_S:
		_age_s = 0.0
		accel = world.environment_accel(at) if world != null and is_instance_valid(world) else Vector3.ZERO
	return _kicked(velocity, delta)


func _kicked(velocity: Vector3, delta: float) -> Vector3:
	if accel == Vector3.ZERO:
		return velocity
	return velocity + accel * delta
