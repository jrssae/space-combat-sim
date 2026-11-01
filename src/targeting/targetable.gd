class_name Targetable
extends Node3D
## Marks its parent as something the targeting system can select (architecture §6.3). A component, not a base
## class: add one as a child of a buoy, a ship or a station, at the point the bracket should sit on. It joins group
## `targetable`, which `TargetingController` reads every physics tick.
##
## Do not add it to `world_shiftable`: it moves with its parent, which is the shiftable node.

const GROUP: StringName = &"targetable"

## What the pilot reads ("NAV ALPHA"); the console selects targets by it.
@export var display_name: String = ""
## IFF (§14.9, `Factions`). Buoys are `neutral`; ships carry their own.
@export var faction: StringName = &"neutral"
## How far this target is heard beyond the sensors, as with a beacon's broadcast (M3-T17, Q21), m: 0 = not at all, `INF` =
## everywhere. A contact counts when it is within the 25 km sensor range or within its own broadcast range (nav buoys
## 1 000 km, allied ships 100 km). The targetables with a broadcast are kept in one list (`broadcasters`), which the AI's
## `ContactScan.shared_broadcasts` reads instead of sweeping every body.
@export var broadcast_range_m: float = 0.0:
	set(value):
		broadcast_range_m = maxf(value, 0.0)
		_sync_broadcaster()
## World-frame velocity of the marked object, m/s, for owners that move kinematically (a drifting buoy keeps it
## current). Ignored when the parent is a RigidBody3D: its `linear_velocity` is the truth.
var velocity: Vector3 = Vector3.ZERO


static var _broadcasters: Array[Targetable] = []


func _init() -> void:
	add_to_group(GROUP)


func _enter_tree() -> void:
	_sync_broadcaster()


func _exit_tree() -> void:
	_broadcasters.erase(self)


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


## True while the target can be selected: visible in the tree and its parent processing (a parked pool ship is hidden
## and disabled, a destroyed one the same). `TargetingController` skips inactive targetables and drops a selection that
## turns inactive.
func is_active() -> bool:
	if not is_inside_tree() or not is_visible_in_tree():
		return false
	var parent: Node = get_parent()
	return parent != null and parent.can_process()


## Hull 0..1 of the owner (its `Damageable` sibling), or -1 when it has none (a buoy).
func get_hull_fraction() -> float:
	var damageable: Damageable = Damageable.of(get_parent())
	return damageable.hull.fraction() if damageable != null else -1.0


## Radius of a sphere around the owner that holds it (its `Damageable`'s bounding radius), 0 when it has none.
func get_bounding_radius() -> float:
	var damageable: Damageable = Damageable.of(get_parent())
	return damageable.bounding_radius if damageable != null else 0.0


func get_target_velocity() -> Vector3:
	var body := get_parent() as RigidBody3D
	if body != null:
		return body.linear_velocity
	return velocity


## A snapshot for `TargetingSystem`: this tick's position and velocity, never kept across ticks.
func to_target_info() -> TargetInfo:
	var info := TargetInfo.new(get_instance_id(), display_name, faction, global_position, get_target_velocity(),
			get_hull_fraction(), get_bounding_radius())
	info.broadcast_range_m = broadcast_range_m
	var damageable: Damageable = Damageable.of(get_parent())
	if damageable != null:
		info.damage_layout = damageable.zones.layout
		info.damage_zones = damageable.zone_severities()
	return info
