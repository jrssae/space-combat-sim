class_name Perception
extends RefCounted
## One tick's snapshot of the world for a `PilotBrain` (architecture §15.8). Built fresh by the `AiPilotDriver` every
## physics tick, so nothing in it can go stale across a `World.rebase()`: positions are `World`-local as of this tick,
## and brains that remember places (waypoints) keep them as `UniversePos` and convert them every tick with
## `to_local(...)`. Plain data; no scene-tree access from a brain.

## Sim time, s.
var now_s: float = 0.0
## Own pose and motion, World frame.
var position: Vector3 = Vector3.ZERO
var basis: Basis = Basis.IDENTITY
var velocity: Vector3 = Vector3.ZERO
var angular_velocity: Vector3 = Vector3.ZERO
## Hull 0..1.
var hull_fraction: float = 1.0
var faction: StringName = Factions.NEUTRAL
## What this ship can do: accelerations and turn rates (`ShipCapability`).
var capability: ShipCapability = ShipCapability.new()
## The weapon's muzzle speed (m/s, relative to the shooter) and a bolt's lifetime (s).
var muzzle_speed_mps: float = 400.0
var weapon_lifetime_s: float = 4.0
## The universe position of the World origin this tick.
var frame_origin: UniversePos = UniversePos.new()
## The ship's selected target as of this tick (position and velocity are current), or null.
var target: TargetInfo = null
## Whether `target` is hostile to this ship.
var target_hostile: bool = false


## Forward unit vector (the nose, -Z).
func forward() -> Vector3:
	return -basis.z


## A universe position (a waypoint) as a World-local point this tick.
func to_local(point: UniversePos) -> Vector3:
	return frame_origin.offset_to(point)
