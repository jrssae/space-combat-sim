class_name Projectile
extends Node3D
## A pulse-cannon bolt (architecture §6.3, §7.1): a kinematic Node3D carrying an emissive capsule, no physics body
## and no hit detection in M1. It flies in a straight line at the velocity it was launched with and frees itself
## `lifetime_s` of sim time after launch (`SimClock`, never the wall clock, so time warp and pausing work).
##
## Spawn it with `PulseCannon`, or by hand: instantiate `projectile.tscn`, add it to the tree under `World`, then
## `launch(...)`. It joins `world_shiftable` itself, so `World.rebase()` moves it with everything else. `velocity` is
## a World-frame vector; a velocity rebase (roadmap) must subtract the frame velocity from it, as for rigid bodies.
##
## The capsule is built along the node's -Z axis, and `launch` points -Z along the velocity.

const SCENE_PATH: String = "res://src/weapons/projectile.tscn"

## Seconds of sim time from launch to `queue_free`.
@export var lifetime_s: float = 4.0

## World-frame velocity, m/s. Set by `launch`.
var velocity: Vector3 = Vector3.ZERO
## Sim time at which the projectile is freed.
var expires_at_s: float = INF


func _ready() -> void:
	add_to_group(WorldFrame.SHIFTABLE_GROUP)


func _physics_process(delta: float) -> void:
	if is_expired(SimClock.now()):
		queue_free()
		return
	global_position += velocity * delta


## Places the projectile at the World-frame `at`, points it along `launch_velocity` and starts the lifetime clock at
## `now_s` (`SimClock.now()`). The node must be in the tree. With a near-zero velocity the orientation is left alone.
func launch(at: Vector3, launch_velocity: Vector3, now_s: float) -> void:
	velocity = launch_velocity
	expires_at_s = now_s + lifetime_s
	global_position = at
	if launch_velocity.length_squared() > 1e-6:
		var direction: Vector3 = launch_velocity.normalized()
		# looking_at needs an up vector that is not parallel to the direction; the capsule is round, so any will do.
		var up: Vector3 = Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
		global_basis = Basis.looking_at(direction, up)
	# Appear here, not smeared from wherever the node was a tick ago (project-wide physics interpolation is on).
	reset_physics_interpolation()


func is_expired(now_s: float) -> bool:
	return now_s >= expires_at_s
