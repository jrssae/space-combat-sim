class_name RadarModel
extends RefCounted
## The radar sphere's maths (architecture §15.9, M2-T08), pure. A contact's bearing in the ship's frame and its range give a
## point inside a unit sphere drawn in the ship's frame: the nose is up the screen, the ship's right is screen right and the
## ship's top comes toward the viewer.
##
## Radar space: X right, Y forward (nose, up the screen), Z ship-up (toward the viewer). A contact dead ahead is (0, r, 0),
## dead astern (0, -r, 0), above (0, 0, r), below (0, 0, -r), to the right (r, 0, 0), to the left (-r, 0, 0).
##
## Radius `r` grows linearly to `LINEAR_RANGE_M` (5 km) where it reaches `LINEAR_RADIUS` (0.6), then logarithmically to
## 1.0 at `MAX_RANGE_M` (25 km, the sensor range); contacts beyond that are dropped. Each dot has a stalk down (or up) to the
## equatorial plane (Z = 0), which tells above from below at a glance.

const MAX_RANGE_M: float = 25000.0
const LINEAR_RANGE_M: float = 5000.0
const LINEAR_RADIUS: float = 0.6


## One contact on the sphere.
class Dot extends RefCounted:
	var id: int = 0
	## Radar-space point, inside the unit sphere.
	var point: Vector3 = Vector3.ZERO
	## The same point projected onto the equatorial plane (the stalk's foot).
	var foot: Vector3 = Vector3.ZERO
	var range_m: float = 0.0
	var faction: StringName = Factions.NEUTRAL
	var color: Color = Factions.NEUTRAL_COLOR
	var selected: bool = false
	## True when the contact is above the ship's plane (the stalk runs down to the foot).
	var above: bool = true


## Sphere radius (0..1) for a range; 0 at 0 m, `LINEAR_RADIUS` at 5 km, 1 at 25 km, more than that is clamped to 1.
static func radius_for_range(range_m: float) -> float:
	if range_m <= 0.0:
		return 0.0
	if range_m <= LINEAR_RANGE_M:
		return LINEAR_RADIUS * range_m / LINEAR_RANGE_M
	var t: float = log(minf(range_m, MAX_RANGE_M) / LINEAR_RANGE_M) / log(MAX_RANGE_M / LINEAR_RANGE_M)
	return LINEAR_RADIUS + (1.0 - LINEAR_RADIUS) * t


## The radar-space direction (unit) of a body-frame offset (+X right, +Y up, -Z forward): X right, Y forward, Z up.
static func radar_direction(body_offset: Vector3) -> Vector3:
	var d: Vector3 = Vector3(body_offset.x, -body_offset.z, body_offset.y)
	return d.normalized() if d.length_squared() > 1e-12 else Vector3.ZERO


## The dot for a contact at World-frame `position`, seen from a ship at `own_position` with orientation `own_basis`; null
## beyond `MAX_RANGE_M`. `faction` and `selected` are carried onto the dot; `viewer_faction` colours it by relation.
static func dot_for(id: int, position: Vector3, faction: StringName, selected: bool, own_position: Vector3,
		own_basis: Basis, viewer_faction: StringName) -> Dot:
	var offset: Vector3 = position - own_position
	var range_m: float = offset.length()
	if range_m > MAX_RANGE_M:
		return null
	var dot := Dot.new()
	dot.id = id
	dot.range_m = range_m
	dot.faction = faction
	dot.color = Factions.hud_color(Factions.relation(viewer_faction, faction))
	dot.selected = selected
	dot.point = radar_direction(own_basis.transposed() * offset) * radius_for_range(range_m)
	dot.foot = Vector3(dot.point.x, dot.point.y, 0.0)
	dot.above = dot.point.z >= 0.0
	return dot


## Every contact in `infos` (`TargetInfo`s) within sensor range, farthest first and the selected one last, so a drawing pass
## in this order leaves the near ones and the selection on top.
static func dots(infos: Array[TargetInfo], selected_id: int, own_position: Vector3, own_basis: Basis,
		viewer_faction: StringName) -> Array[Dot]:
	var out: Array[Dot] = []
	for info: TargetInfo in infos:
		var dot: Dot = dot_for(info.id, info.position, info.faction, info.id == selected_id, own_position, own_basis, viewer_faction)
		if dot != null:
			out.append(dot)
	out.sort_custom(func(a: Dot, b: Dot) -> bool:
		if a.selected != b.selected:
			return b.selected
		return a.range_m > b.range_m or (a.range_m == b.range_m and a.id < b.id))
	return out


## The sphere is viewed from slightly above its own plane: tilted `TILT_RAD` about the X axis, so contacts above the ship
## are drawn a little higher than the ones level with it, and a slow perspective (`PERSPECTIVE`) draws points toward the
## viewer a little larger.
const TILT_RAD: float = 0.35
const PERSPECTIVE: float = 0.18


## Screen position of a radar-space point for a sphere of `radius_px` centred at `centre` (y down, nose up the screen).
static func to_screen(point: Vector3, centre: Vector2, radius_px: float) -> Vector2:
	var up: float = point.y * cos(TILT_RAD) + point.z * sin(TILT_RAD)
	var depth: float = point.z * cos(TILT_RAD) - point.y * sin(TILT_RAD)  # toward the viewer
	var scale: float = 1.0 + PERSPECTIVE * depth
	return centre + Vector2(point.x * scale, -up * scale) * radius_px
