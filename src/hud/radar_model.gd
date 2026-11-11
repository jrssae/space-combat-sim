class_name RadarModel
extends RefCounted
## The radar sphere's maths (architecture §15.9, M2-T08), pure. A contact's bearing in the ship's frame and its range give a
## point inside a unit sphere drawn in the ship's frame: the nose is up the screen, the ship's right is screen right and the
## ship's top comes toward the viewer.
##
## Radar space: X right, Y forward (nose, up the screen), Z ship-up (toward the viewer). A contact dead ahead is (0, r, 0),
## dead astern (0, -r, 0), above (0, 0, r), below (0, 0, -r), to the right (r, 0, 0), to the left (-r, 0, 0).
##
## Radius `r` grows linearly to `LINEAR_RADIUS` (0.6) at `LINEAR_RANGE_M` (5 km), then logarithmically to 1.0 at
## `MAX_RANGE_M` (25 km, the sensor range). Contacts beyond that are dropped, except a broadcast contact (M3-T17) within its
## own range: it sits on the rim in its true direction, drawn hollow (`Dot.rim`). Each dot has a stalk to the equatorial plane
## (Z = 0), which tells above from below at a glance.

const MAX_RANGE_M: float = 25000.0
## The native class that plots the radar (M4-T23).
const NATIVE_CLASS: StringName = &"ScsRadarPlot"
const LINEAR_RANGE_M: float = 5000.0
const LINEAR_RADIUS: float = 0.6

static var _native: Object = null


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
	## True for a broadcast contact beyond `MAX_RANGE_M`: on the rim, drawn as a hollow dot.
	var rim: bool = false


## The radar-space direction (unit) of a body-frame offset (+X right, +Y up, -Z forward): X right, Y forward, Z up.
static func radar_direction(body_offset: Vector3) -> Vector3:
	var d: Vector3 = Vector3(body_offset.x, -body_offset.z, body_offset.y)
	return d.normalized() if d.length_squared() > 1e-12 else Vector3.ZERO


## Every contact of `contacts` within sensor or broadcast range placed on the sphere, in drawing order (far to near, so the
## near ones draw on top, the selected one last; two contacts whose ranges agree to a millimetre follow the contacts' own
## order), as packed arrays for a batched painter (M4-T36). The maths runs in the native library (`NATIVE_CLASS`, M4-T23):
## with the tier's ships on the radar a frame at `battle` 1 000 plots a thousand contacts.
static func plot(contacts: RadarContacts, selected_id: int, own_position: Vector3, own_basis: Basis,
		viewer_faction: StringName) -> RadarPlot:
	if _native == null:
		_native = NativeLib.instantiate(NATIVE_CLASS)  # the native library is required (M4-T37)
	var palette := PackedColorArray()
	for faction: StringName in contacts.faction_names:
		palette.append(Factions.hud_color(Factions.relation(viewer_faction, faction)))
	var r: Array = _native.plot(contacts.ids, contacts.positions, contacts.reach, contacts.faction_ix, palette, own_position,
			own_basis, selected_id)
	var out := RadarPlot.new()
	var order: PackedInt32Array = r[0]
	out.ids = r[1]
	out.points = r[2]
	out.ranges = r[3]
	out.colors = r[4]
	out.rims = r[5]
	out.point_units = r[6]
	out.stalk_units = r[7]
	out.stalk_colors = r[8]
	out.selected_index = int(r[9])
	out.factions.resize(order.size())
	for k: int in order.size():
		out.factions[k] = contacts.faction_names[contacts.faction_ix[order[k]]]
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
