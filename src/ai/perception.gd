class_name Perception
extends RefCounted
## One tick's snapshot of the world for a `PilotBrain` (architecture §15.8). Built fresh by the `AiPilotDriver` every
## physics tick, so nothing in it can go stale across a `World.rebase()`: positions are `World`-local as of this tick,
## and brains that remember places (waypoints) keep them as `UniversePos` and convert them every tick with
## `to_local(...)`. Plain data; no scene-tree access from a brain.
##
## The defaults of `capability` and `frame_origin` are shared (read, never write) to save two allocations per AI ship per
## tick (AC13's budget). The driver sets both every tick.

static var _default_capability: ShipCapability = ShipCapability.new()
static var _default_origin: UniversePos = UniversePos.new()
static var _no_broadcasts: Array[Contact] = []

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
## Where the bolts leave the ship, relative to `position`, World axes. The Starfury's guns hang 1.4 m under its centre,
## enough to miss a raider when the lead is solved from the centre.
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
## The broadcasts this ship hears (M3-T17, Q21): contacts beyond the 5 km of `contacts` and within their own broadcast
## range (buoys 1 000 km, allies 100 km). Avoidance and the fire lane never read it, and behaviours chase it only for a pilot
## objective (`AiContext.objective_name`). Shared: read, never write.
var broadcasts: Array[Contact] = _no_broadcasts
## The nearest rocks and mines within the sensor range (`ai_nearest_static_k`, M4-T09): obstacles avoidance steers round,
## never contacts. Shared: read, never write.
var statics: Array[Contact] = []
## Hostile bolts that will pass within `ContactScan.INCOMING_MISS_M` (15 m) in the next `ContactScan.INCOMING_HORIZON_S` (2 s).
var incoming_fire: int = 0
## Sim time of the latest hit this hull took (a bolt or anything else `Damageable.hit_taken` reports), -INF when none yet.
var last_hit_s: float = -INF
## Sim time of the latest bolt hit (not rams or the console), -INF when none. The hit reaction's trigger (M3-T10, Q11).
var last_bolt_hit_s: float = -INF
## The `Targetable` id of whoever made the latest hit (a bolt or a ram), 0 when none. A passive pilot fires back at it (M3-T13).
var last_attacker_id: int = 0
## `settings.friendly_fire` this tick: bolts then hurt every hull but the shooter's (`FireLane`).
var friendly_fire: bool = false
## The native pilot kernels over the core's rows (M4-T16), null off the core: then `AvoidanceMath`, `FireLane` and
## `AiContext` answer in GDScript. With them, the core row of each of `contacts` and `statics` (in the lists' order) and
## this ship's `Factions.Relation` to each faction of the core's table.
var kernels: Object = null
var contact_rows: PackedInt32Array = PackedInt32Array()
var static_rows: PackedInt32Array = PackedInt32Array()
var relation_row: PackedByteArray = PackedByteArray()
## The native brain host (M4-T17, `ScsBrains`), null off the core: with it an `AiPilot` thinks natively, picking its own
## contacts from the rows, so `contacts`, `statics`, `broadcasts` and `incoming_fire` are left empty by the driver. The
## fields below give the native think what the driver would otherwise pick or compute: the ship's body id, its selection
## (0 for none), where the bolts leave in the ship's frame, its hull's bounding radius and the avoidance tie-break
## (`hash(display_name)`).
var brains: Object = null
var own_body_id: int = 0
var selected_id: int = 0
var muzzle_local: Vector3 = Vector3.ZERO
var bounding_radius: float = 0.0
var tie_hash: int = 0


## Whether the kernels can answer for this perception: they are there and the rows line up with the lists.
func on_rows() -> bool:
	return kernels != null and contact_rows.size() == contacts.size() and static_rows.size() == statics.size()


## Forward unit vector (the nose, -Z).
func forward() -> Vector3:
	return -basis.z


## A universe position (a waypoint) as a World-local point this tick.
func to_local(point: UniversePos) -> Vector3:
	return frame_origin.offset_to(point)
