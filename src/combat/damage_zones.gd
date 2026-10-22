class_name DamageZones
extends RefCounted
## Where on a ship the damage landed (HUD damage silhouette), pure. A ship type has a layout, a handful of main components
## seen from the front (the Starfury's cabin and four arms, a raider's two wings and centre), not exact hit locations.
## `record` adds the hull points a hit removed to the zone the hit point falls in (ship-local coordinates, +X right,
## +Y up, -Z forward); `severity` turns a zone's total into 0 (untouched) to 1 (gone).
##
## A zone is "gone" when it has taken `ZONE_SHARE` of the ship's full hull in damage, so a zone can be wrecked well before
## the ship dies.

enum Layout { NONE, X_FIGHTER, DELTA }

## Zone indices of the X fighter (Starfury): the cabin and the four arms, upper then lower, left then right.
const CABIN: int = 0
const UPPER_LEFT: int = 1
const UPPER_RIGHT: int = 2
const LOWER_LEFT: int = 3
const LOWER_RIGHT: int = 4
## Zone indices of the delta (raider).
const DELTA_CENTRE: int = 0
const DELTA_LEFT: int = 1
const DELTA_RIGHT: int = 2

## Share of the full hull that wrecks one zone.
const ZONE_SHARE: float = 0.4
## |x| in metres beyond which a point belongs to an arm (X fighter) or a wing (delta), not the middle.
const X_FIGHTER_ARM_X: float = 2.0
const DELTA_WING_X: float = 1.8

var layout: Layout = Layout.NONE
var totals: PackedFloat64Array = PackedFloat64Array()


func _init(p_layout: Layout = Layout.NONE) -> void:
	layout = p_layout
	totals.resize(zone_count(layout))


static func layout_from_name(layout_name: StringName) -> Layout:
	match layout_name:
		&"x_fighter":
			return Layout.X_FIGHTER
		&"delta":
			return Layout.DELTA
	return Layout.NONE


static func zone_count(p_layout: Layout) -> int:
	match p_layout:
		Layout.X_FIGHTER:
			return 5
		Layout.DELTA:
			return 3
	return 0


## The zone a ship-local point falls in, or -1 for a layout without zones.
static func zone_for(p_layout: Layout, local: Vector3) -> int:
	match p_layout:
		Layout.X_FIGHTER:
			if absf(local.x) <= X_FIGHTER_ARM_X:
				return CABIN
			if local.y >= 0.0:
				return UPPER_RIGHT if local.x > 0.0 else UPPER_LEFT
			return LOWER_RIGHT if local.x > 0.0 else LOWER_LEFT
		Layout.DELTA:
			if absf(local.x) <= DELTA_WING_X:
				return DELTA_CENTRE
			return DELTA_RIGHT if local.x > 0.0 else DELTA_LEFT
	return -1


func zone_count_now() -> int:
	return totals.size()


## Adds `amount` hull points of damage at the ship-local point `local`.
func record(local: Vector3, amount: float) -> void:
	var zone: int = zone_for(layout, local)
	if zone >= 0 and amount > 0.0:
		totals[zone] += amount


## 0 (untouched) to 1 (wrecked) per zone for a ship whose full hull is `hull_max`.
func severities(hull_max: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(totals.size())
	var capacity: float = maxf(hull_max * ZONE_SHARE, 1e-6)
	for i: int in totals.size():
		out[i] = clampf(float(totals[i]) / capacity, 0.0, 1.0)
	return out


func reset() -> void:
	totals.fill(0.0)
