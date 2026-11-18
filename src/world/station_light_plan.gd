class_name StationLightPlan
extends RefCounted
## The station's exterior lights as data (M7-T18), from its light hardpoints: the small lights drawn as points (beacons, navigation
## lights, bay lamps), grouped by the piece that carries them and whether they blink, and the floods that light the hull in pools.
## Pure: `StationLights` draws the points and hands each hull section the floods that can reach it.
##
## Frames: a `frame` light is in the station node's frame, a `drum` light in the drum node's frame (it turns with the drum).

## The hull shader's per-section flood list (`station_hull.gdshader` MAX_FLOODS).
const MAX_FLOODS: int = 64
## The point groups: the frame's steady points, the frame's blinking points (the beacons), the drum's steady points.
const FRAME_STEADY: StringName = &"frame_steady"
const FRAME_BLINK: StringName = &"frame_blink"
const DRUM_STEADY: StringName = &"drum_steady"
const DRUM_BLINK: StringName = &"drum_blink"

## Each group's points: `name`, Vector3 `position` (in its piece's frame), Color `colour` (linear, before the marker's gain) and
## `radius_m`.
var points: Dictionary = {FRAME_STEADY: [], FRAME_BLINK: [], DRUM_STEADY: [], DRUM_BLINK: []}
## The floods: `name`, `body`, Vector3 `position` (the fixture) and `direction` (unit), `cos_outer`, `cos_inner`, `range_m`, and
## Color `light` (the colour times its energy).
var floods: Array[Dictionary] = []
## The beacons' beat, seconds (all beacons together): one cycle, dark at its start, then a linear fade up, full, and a fade down as
## long as the fade up.
var blink_period_s: float = 0.0
var blink_off_s: float = 0.0
var blink_ramp_s: float = 0.0
var blink_full_s: float = 0.0


## The plan of a station's hardpoints (every light with a `marker` is drawn; every `flood` lights the hull).
static func from_hardpoints(hp: StationHardpoints) -> StationLightPlan:
	var plan := StationLightPlan.new()
	if hp == null:
		return plan
	for light: Dictionary in hp.lights:
		var body: String = str(light.get("body", ""))
		if str(light.get("kind", "")) == "flood":
			var rgb: Vector3 = light["rgb"]
			var energy: float = float(light.get("energy", 1.0))
			plan.floods.append({"name": str(light["name"]), "body": body, "position": light["position"],
					"direction": (light["direction"] as Vector3).normalized(),
					"cos_outer": cos(deg_to_rad(float(light["outer_deg"]))), "cos_inner": cos(deg_to_rad(float(light["inner_deg"]))),
					"range_m": float(light["range_m"]), "light": Color(rgb.x * energy, rgb.y * energy, rgb.z * energy)})
			continue
		var marker: Variant = light.get("marker")
		if not marker is Dictionary:
			continue
		var rgb_m: Array = (marker as Dictionary).get("rgb", [1.0, 1.0, 1.0])
		var blinks: bool = bool(light.get("blink", false))
		if blinks:
			plan.blink_period_s = float(light.get("blink_period_s", 0.0))
			plan.blink_off_s = float(light.get("blink_off_s", 0.0))
			plan.blink_ramp_s = float(light.get("blink_ramp_s", 0.0))
			plan.blink_full_s = float(light.get("blink_full_s", 0.0))
		var group: StringName
		if body == StationHardpoints.DRUM:
			group = DRUM_BLINK if blinks else DRUM_STEADY
		else:
			group = FRAME_BLINK if blinks else FRAME_STEADY
		(plan.points[group] as Array).append({"name": str(light["name"]), "position": light["position"],
				"colour": Color(float(rgb_m[0]), float(rgb_m[1]), float(rgb_m[2])),
				"radius_m": float((marker as Dictionary).get("radius_m", 1.0))})
	return plan


## How bright a beacon is at `time_s` (the system's sim time), 0 to 1: dark for the first `off_s` of every `period_s`, then rising
## linearly over `ramp_s`, full for `full_s`, falling over `ramp_s`, dark for the rest. A period of 0 is always full.
static func blink_level(time_s: float, period_s: float, off_s: float, ramp_s: float, full_s: float) -> float:
	if period_s <= 0.0:
		return 1.0
	var u: float = fposmod(time_s, period_s) - off_s
	if u < 0.0:
		return 0.0
	if u < ramp_s:
		return u / ramp_s
	u -= ramp_s
	if u < full_s:
		return 1.0
	u -= full_s
	if u < ramp_s:
		return 1.0 - u / ramp_s
	return 0.0


## This plan's beacons' brightness at `time_s`.
func beacon_level(time_s: float) -> float:
	return blink_level(time_s, blink_period_s, blink_off_s, blink_ramp_s, blink_full_s)


func point_count() -> int:
	var n: int = 0
	for group: StringName in points:
		n += (points[group] as Array).size()
	return n


## The floods that can reach a hull section of `body` whose box (in that piece's frame) is `box`: `fixed`, those on the same piece,
## by their cone and throw; `turning`, those on the other piece, which the drum's turn carries round, by the band of radius and depth
## they can sweep (the drum's node at `drum_origin` in the station node's frame). Indices into `floods`.
func section_floods(body: String, box: AABB, drum_origin: Vector3) -> Dictionary:
	var fixed := PackedInt32Array()
	var turning := PackedInt32Array()
	for i: int in floods.size():
		var f: Dictionary = floods[i]
		if str(f["body"]) == body:
			if _reaches(f, box):
				fixed.append(i)
		else:
			var shift: Vector3 = drum_origin if body == StationHardpoints.FRAME else -drum_origin
			if _sweeps(f, box, shift):
				turning.append(i)
	return {"fixed": fixed, "turning": turning}


## A section's flood uniforms in its piece's frame, the drum standing at `drum_xform` in the station node's frame: the fixtures and
## throws, the directions and outer cosines, the light and inner cosines (`station_hull.gdshader`'s flood_pos, flood_dir, flood_col).
func pack(body: String, indices: PackedInt32Array, drum_xform: Transform3D) -> Array[PackedVector4Array]:
	var pos := PackedVector4Array()
	var dir := PackedVector4Array()
	var col := PackedVector4Array()
	var into_frame: bool = body == StationHardpoints.FRAME
	var to_drum: Transform3D = drum_xform.affine_inverse()
	for i: int in indices:
		var f: Dictionary = floods[i]
		var p: Vector3 = f["position"]
		var d: Vector3 = f["direction"]
		if str(f["body"]) != body:
			var t: Transform3D = drum_xform if into_frame else to_drum
			p = t * p
			d = (t.basis * d).normalized()
		var c: Color = f["light"]
		pos.append(Vector4(p.x, p.y, p.z, float(f["range_m"])))
		dir.append(Vector4(d.x, d.y, d.z, float(f["cos_outer"])))
		col.append(Vector4(c.r, c.g, c.b, float(f["cos_inner"])))
	return [pos, dir, col]


# Whether a flood on the section's own piece can light anything in the box: within its throw, and the box's bounding sphere
# touching its cone.
static func _reaches(f: Dictionary, box: AABB) -> bool:
	var p: Vector3 = f["position"]
	var range_m: float = float(f["range_m"])
	var nearest: Vector3 = p.clamp(box.position, box.end)
	if nearest.distance_to(p) >= range_m:
		return false
	var centre: Vector3 = box.get_center()
	var radius: float = box.size.length() * 0.5
	var to_box: Vector3 = centre - p
	var dist: float = to_box.length()
	if dist <= radius:
		return true
	var off_axis: float = acos(clampf(to_box.dot(f["direction"]) / dist, -1.0, 1.0))
	return off_axis <= acos(float(f["cos_outer"])) + asin(clampf(radius / dist, 0.0, 1.0))


# Whether a flood on the other piece can light the box at some turn of the drum: the depths and radii its throw sweeps about the
# axis overlap the box's; `shift` takes its fixture into the box's frame along the axis.
static func _sweeps(f: Dictionary, box: AABB, shift: Vector3) -> bool:
	var p: Vector3 = (f["position"] as Vector3) + shift
	var range_m: float = float(f["range_m"])
	if p.z + range_m < box.position.z or p.z - range_m > box.end.z:
		return false
	var r: float = Vector2(p.x, p.y).length()
	var near_x: float = clampf(0.0, box.position.x, box.end.x)
	var near_y: float = clampf(0.0, box.position.y, box.end.y)
	var box_min: float = Vector2(near_x, near_y).length()
	var box_max: float = 0.0
	for x: float in [box.position.x, box.end.x]:
		for y: float in [box.position.y, box.end.y]:
			box_max = maxf(box_max, Vector2(x, y).length())
	return r + range_m >= box_min and r - range_m <= box_max
