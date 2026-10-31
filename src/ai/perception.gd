class_name Perception
extends RefCounted
## One tick's snapshot of the world for a `PilotBrain` (architecture §15.8). Built fresh by the `AiPilotDriver` every
## physics tick, so nothing in it can go stale across a `World.rebase()`: positions are `World`-local as of this tick,
## and brains that remember places (waypoints) keep them as `UniversePos` and convert them every tick with
## `to_local(...)`. Plain data; no scene-tree access from a brain.
##
## The defaults of `capability` and `frame_origin` are shared by every perception that is not given its own (read them,
## never write them): one `ShipCapability` and one `UniversePos` per perception would be two allocations per AI ship per
## tick (AC13's budget). The driver sets both every tick (the origin only when it has a world).

static var _default_capability: ShipCapability = ShipCapability.new()
static var _default_origin: UniversePos = UniversePos.new()

## Sim time, s.
var now_s: float = 0.0
## Own pose and motion, World frame.
var position: Vector3 = Vector3.ZERO
var basis: Basis = Basis.IDENTITY
var velocity: Vector3 = Vector3.ZERO
var angular_velocity: Vector3 = Vector3.ZERO
## This ship's `Targetable` id: what other ships' `Contact.target_id` holds when they have it selected (0 when unknown).
var self_id: int = 0
## Hull 0..1.
var hull_fraction: float = 1.0
var faction: StringName = Factions.NEUTRAL
## What this ship can do: accelerations and turn rates (`ShipCapability`).
var capability: ShipCapability = _default_capability
## Where the bolts leave the ship: the mean muzzle position less `position`, World axes (zero: from the centre). The
## Starfury's guns hang 1.4 m under its centre, enough to miss a raider when the lead is solved from the centre.
var muzzle_offset: Vector3 = Vector3.ZERO
## The weapon's muzzle speed (m/s, relative to the shooter) and a bolt's lifetime (s).
var muzzle_speed_mps: float = 400.0
var weapon_lifetime_s: float = 4.0
## The universe position of the World origin this tick.
var frame_origin: UniversePos = _default_origin
## The ship's selected target as of this tick (position and velocity are current), or null (also for a brain that does
## not read it: `PilotBrain.reads_target`).
var target: TargetInfo = null
## Whether `target` is hostile to this ship.
var target_hostile: bool = false
## Everything active within `ContactScan.SENSOR_RANGE_M` (5 km) but this ship: ships, drones, props, as of this tick,
## with their relation to this ship (§16 D33). Shared with other ships of the faction: read, never write.
var contacts: Array[Contact] = []
## Hostile bolts whose closest approach comes within `ContactScan.INCOMING_MISS_M` (15 m) in the next
## `ContactScan.INCOMING_HORIZON_S` (2 s).
var incoming_fire: int = 0
## Sim time of the latest hit this hull took (a bolt or anything else `Damageable.hit_taken` reports), -INF when none yet.
var last_hit_s: float = -INF
## `settings.friendly_fire` this tick: bolts then hurt every hull but the shooter's (`FireLane`).
var friendly_fire: bool = false


## Forward unit vector (the nose, -Z).
func forward() -> Vector3:
	return -basis.z


## A universe position (a waypoint) as a World-local point this tick.
func to_local(point: UniversePos) -> Vector3:
	return frame_origin.offset_to(point)
