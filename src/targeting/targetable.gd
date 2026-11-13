class_name Targetable
extends Node3D
## Marks its parent as something the targeting system can select (architecture §6.3). A component, not a base
## class: add one as a child of a buoy, a ship or a station, at the point the bracket should sit on. It joins group
## `targetable`, which `TargetingController` reads every physics tick.
##
## Do not add it to `world_shiftable`: it moves with its parent, which is the shiftable node.

const GROUP: StringName = &"targetable"

## What sort of thing it marks (M4-T07): later scans, broad phases and the tier read it so a rock or a mine never fills a
## fighter's contacts. Ships are the default; the battle's stand-ins set their own.
enum Kind { SHIP, CAPITAL, TURRET, MISSILE, MINE, STATIC, PROP }

## What it is to a pilot picking from the target menu (M5-T25): civilians and nav beacons get their own categories.
enum Role { SHIP, CIVILIAN, BEACON }

## What the pilot reads ("NAV ALPHA"); the console selects targets by it.
@export var display_name: String = ""
## IFF (§14.9, `Factions`). Buoys are `neutral`; ships carry their own.
@export var faction: StringName = &"neutral"
## Its `Kind` (M4-T07).
@export var kind: Kind = Kind.SHIP
## Its `Role` (M5-T25).
var role: Role = Role.SHIP
## How far this target is heard beyond the sensors (M3-T17, Q21), m: 0 = not at all, `INF` = everywhere. Nav buoys use
## 1 000 km, allied ships 100 km. Broadcasters are kept in one list (`broadcasters`) so the AI's
## `ContactScan.shared_broadcasts` need not sweep every body.
@export var broadcast_range_m: float = 0.0:
	set(value):
		broadcast_range_m = maxf(value, 0.0)
		_sync_broadcaster()
		if is_inside_tree():
			ContactScan.touch(get_parent())  # the core keeps the reach with the body's other attributes
## World-frame velocity of the marked object, m/s, for owners that move kinematically (a drifting buoy keeps it
## current). Ignored when the parent is a RigidBody3D: its `linear_velocity` is the truth.
var velocity: Vector3 = Vector3.ZERO


## Lookups of an owner's hull so far (M4-T34): a work count for tests and profiling, never gameplay.
static var hull_lookups: int = 0

static var _broadcasters: Array[Targetable] = []

# The owner's hull as `Damageable.of` last gave it, kept while in the tree until the owner's children change.
var _hull: Damageable = null
var _hull_known: bool = false


func _init() -> void:
	add_to_group(GROUP)


func _enter_tree() -> void:
	_sync_broadcaster()
	_hull_known = false
	var parent: Node = get_parent()
	if parent != null and not parent.child_order_changed.is_connected(_forget_hull):
		parent.child_order_changed.connect(_forget_hull)


func _exit_tree() -> void:
	_broadcasters.erase(self)
	_hull_known = false
	var parent: Node = get_parent()
	if parent != null and parent.child_order_changed.is_connected(_forget_hull):
		parent.child_order_changed.disconnect(_forget_hull)


## Every targetable in the tree with a broadcast range above 0, active or not (callers check `is_active()`). Read, never
## write.
static func broadcasters() -> Array[Targetable]:
	return _broadcasters


func _sync_broadcaster() -> void:
	var listed: bool = _broadcasters.has(self)
	var wanted: bool = broadcast_range_m > 0.0 and is_inside_tree()
	if wanted and not listed:
		_broadcasters.append(self)
	elif listed and not wanted:
		_broadcasters.erase(self)


## True while the target can be selected: visible and its parent processing (parked and destroyed ships are neither).
func is_active() -> bool:
	if not is_inside_tree() or not is_visible_in_tree():
		return false
	var parent: Node = get_parent()
	return parent != null and parent.can_process()


## Hull 0..1 of the owner (its `Damageable` sibling), or -1 when it has none (a buoy).
func get_hull_fraction() -> float:
	var damageable: Damageable = _owner_hull()
	return damageable.hull.fraction() if damageable != null else -1.0


## Radius of a sphere around the owner that holds it (its `Damageable`'s bounding radius), 0 when it has none.
func get_bounding_radius() -> float:
	var damageable: Damageable = _owner_hull()
	return damageable.bounding_radius if damageable != null else 0.0


func get_target_velocity() -> Vector3:
	var body := get_parent() as RigidBody3D
	if body != null:
		return body.linear_velocity
	# A marker on something tied to the World's anchor (a buoy, a gate) holds its own motion against the anchor (M6-T08).
	var owner_node: Node = get_parent()
	if owner_node != null and owner_node.is_in_group(WorldFrame.ANCHORED_GROUP):
		var world: WorldFrame = WorldFrame.of(owner_node)
		if world != null:
			return velocity + world.rest_velocity()
	return velocity


## A snapshot for `TargetingSystem`: this tick's position and velocity, never kept across ticks.
func to_target_info() -> TargetInfo:
	var damageable: Damageable = _owner_hull()
	var info := TargetInfo.new(get_instance_id(), display_name, faction, global_position, get_target_velocity(),
			damageable.hull.fraction() if damageable != null else -1.0,
			damageable.bounding_radius if damageable != null else 0.0)
	info.broadcast_range_m = broadcast_range_m
	info.role = role
	if damageable != null:
		info.damage_layout = damageable.zones.layout
		info.damage_zones = damageable.zone_severities()
	return info


# The owner's hull (`Damageable.of(parent)`), found once while in the tree: the player's candidate list asks for it for
# every targetable every tick (M4-T34).
func _owner_hull() -> Damageable:
	if _hull_known and (_hull == null or is_instance_valid(_hull)):
		return _hull
	hull_lookups += 1
	_hull = Damageable.of(get_parent())
	_hull_known = is_inside_tree()
	return _hull


func _forget_hull() -> void:
	_hull_known = false
