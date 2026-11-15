class_name BotTripPlanner
extends RefCounted
## Builds the maintenance crew's trips (M7-T35) from `BotData`'s roads: every trip leaves the cargo bay down the trunk, takes the
## high road over the spine or the low road under the drum, does its patrol or its repair and comes back the same way. The drum is
## boarded from under it (`BotTrip.spin_up`), the jumpgate reached by a fast run out past the bow. Choices that vary (which vane,
## how far along the drum, which gate arm, how long a stop) come from `unit(...)`, a hash of the area and the trip's number, never a
## shared random generator. Pure.

## The gate's arms where its hardpoints are missing (`Jumpgate`'s defaults): front and back ends in the gate's frame.
const GATE_HARDPOINTS: String = Jumpgate.HARDPOINTS_PATH

var data: BotData = null
var frames: BotFrames = null
var areas: BotRepairAreas = null
## Each gate arm: `front`, `back` (gate frame) and `out` (away from the gate's axis).
var gate_arms: Array[Dictionary] = []


static func make(p_data: BotData, p_frames: BotFrames, p_areas: BotRepairAreas) -> BotTripPlanner:
	var made := BotTripPlanner.new()
	made.data = p_data
	made.frames = p_frames
	made.areas = p_areas
	made.gate_arms = read_gate_arms()
	return made


## A number 0..1 from `parts` (a seeded per-entity hash).
static func unit(parts: Array) -> float:
	return float(hash(parts) & 0xFFFFFF) / 16777216.0


## The jumpgate's arms from its hardpoints, else the generator's defaults.
static func read_gate_arms(path: String = GATE_HARDPOINTS) -> Array[Dictionary]:
	var arms: Array[Dictionary] = []
	var file := FileAccess.open(path, FileAccess.READ) if FileAccess.file_exists(path) else null
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if parsed is Dictionary and (parsed as Dictionary).get("arms") is Array:
		for a: Variant in (parsed as Dictionary)["arms"] as Array:
			var f: Array = (a as Dictionary).get("front", [0, 0, 0])
			var b: Array = (a as Dictionary).get("back", [0, 0, 0])
			arms.append(_arm(Vector3(float(f[0]), float(f[1]), float(f[2])), Vector3(float(b[0]), float(b[1]), float(b[2]))))
	if arms.is_empty():
		var top: float = Jumpgate.DEFAULT_ARM_RADIUS_M
		var side: float = Jumpgate.DEFAULT_SIDE_RADIUS_M
		var back: float = Jumpgate.DEFAULT_BACK_Z_M
		for f: Vector3 in [Vector3(0, top, 0), Vector3(-side, 0, 0), Vector3(0, -top, 0), Vector3(side, 0, 0)]:
			arms.append(_arm(f, f + Vector3(0, 0, back)))
	return arms


static func _arm(front: Vector3, back: Vector3) -> Dictionary:
	return {"front": front, "back": back, "out": Vector3(front.x, front.y, 0.0).normalized()}


## The peace trip `n` to `area` (a `BotData.peace` entry); null when it cannot be flown now (no gate in the scene).
func peace_trip(area: Dictionary, n: int) -> BotTrip:
	var label: String = area["name"]
	var stop := BotTrip.hold(lerpf(data.peace_hold_s.x, data.peace_hold_s.y, unit([label, n, "hold"])))
	match String(area["kind"]):
		"spine":
			var points: PackedVector3Array = area["points"]
			var out: Array[Dictionary] = [
				BotTrip.fly(_road_to(points[0], PackedVector3Array()), BotTrip.Frame.STATION, data.cruise_mps),
				BotTrip.fly(BotRoute.from_corners(points, data.corner_m), BotTrip.Frame.STATION, data.patrol_mps)]
			return BotTrip.symmetric(label, out, stop)
		"fins":
			var vanes: Array = area.get("vanes_z", [])
			var z: float = float(vanes[int(unit([label, n, "vane"]) * vanes.size()) % vanes.size()])
			var x: float = float(area["x"])
			var tip: float = float(area["tip_y"]) * (1.0 if unit([label, n, "half"]) < 0.5 else -1.0)
			var entry := Vector3(x, data.top_y, float(area["entry_z"]))
			var root := Vector3(x, data.top_y, z)
			var side := Vector3(signf(x), 0.0, 0.0)
			var out: Array[Dictionary] = [
				BotTrip.fly(_road_to(root, PackedVector3Array([Vector3(0.0, data.top_y, entry.z), entry])), BotTrip.Frame.STATION,
						data.cruise_mps),
				BotTrip.fly(BotRoute.from_corners(PackedVector3Array([root, Vector3(x, tip, z)]), data.corner_m),
						BotTrip.Frame.STATION, data.patrol_mps, side)]
			return BotTrip.symmetric(label, out, stop)
		"drum":
			var span: Array = area.get("z", [0.0, 0.0])
			var a: float = float(span[0])
			var b: float = float(span[1])
			var z_land: float = lerpf(a, b, unit([label, n, "land"]))
			var z_far: float = lerpf(a, b, unit([label, n, "far"]))
			var out: Array[Dictionary] = _board_drum(z_land, data.drum_radius(z_land), NAN)
			out.append(BotTrip.fly(drum_crawl(z_land, z_far), BotTrip.Frame.DRUM, data.patrol_mps))
			return BotTrip.symmetric(label, out, stop)
		"gate":
			if not frames.has_gate or gate_arms.is_empty():
				return null
			var arm: Dictionary = gate_arms[int(unit([label, n, "arm"]) * gate_arms.size()) % gate_arms.size()]
			var lift: Vector3 = (arm["out"] as Vector3) * float(area.get("arm_out_m", 75.0))
			var front: Vector3 = (arm["front"] as Vector3) + lift
			var approach: Vector3 = front + Vector3(0.0, 0.0, -float(area.get("front_out_m", 150.0)))
			var way: PackedVector3Array = data.trunk.duplicate()
			way.append_array(_departure(area))
			var out: Array[Dictionary] = [
				BotTrip.fly(BotRoute.from_corners(way, data.corner_m), BotTrip.Frame.STATION, data.cruise_mps),
				BotTrip.transit(way[way.size() - 1], BotTrip.Frame.STATION, approach, BotTrip.Frame.GATE, data.transit_mps,
						data.transit_accel_mps2),
				BotTrip.fly(BotRoute.from_corners(PackedVector3Array([approach, front, (arm["back"] as Vector3) + lift]),
						data.corner_m), BotTrip.Frame.GATE, data.patrol_mps, arm["out"])]
			return BotTrip.symmetric(label, out, stop)
	return null


## The repair trip to `area` (a `BotRepairAreas` index): out to its work spot, work there until it is whole, and home.
func repair_trip(area: int) -> BotTrip:
	var t: Dictionary = areas.target(area)
	var label: String = areas.name_of(area)
	var out: Array[Dictionary] = []
	if t["mount"] and data.mount_work.has(t["name"]):
		var given: Dictionary = data.mount_work[t["name"]]
		out = [BotTrip.fly(_road_to(given["work"], given["via"]), BotTrip.Frame.STATION, data.cruise_mps, t["up"])]
	elif t["mount"]:
		var off: float = float(data.mount_offset_m.get(t["kind"], 15.0))
		var spot: Vector3 = (t["position"] as Vector3) + (t["up"] as Vector3) * off
		if t["body"] == StationHardpoints.DRUM:
			var r: float = Vector2(spot.x, spot.y).length()
			out = _board_drum(spot.z + frames.pivot.z, r, atan2(spot.y, spot.x))
		else:
			out = [BotTrip.fly(_road_to(spot, PackedVector3Array()), BotTrip.Frame.STATION, data.cruise_mps, t["up"])]
	else:
		var s: Dictionary = data.sections.get(t["name"], {})
		if s.is_empty():
			return null
		if s.has("work"):
			out = [BotTrip.fly(_road_to(s["work"], s["via"]), BotTrip.Frame.STATION, data.cruise_mps)]
		else:
			out = _board_drum(float(s["z"]), float(s["r"]), NAN)
	return BotTrip.symmetric(label, out, BotTrip.work(area), true)


## The drum's riding line from station `z_from` to `z_to`, in the landing plane (x out from the axis, z in the drum's frame).
func drum_crawl(z_from: float, z_to: float) -> BotRoute:
	var points := PackedVector3Array()
	var steps: int = maxi(1, ceili(absf(z_to - z_from) / 50.0))
	for k: int in steps + 1:
		var z: float = lerpf(z_from, z_to, float(k) / float(steps))
		points.append(Vector3(data.drum_radius(z), 0.0, z - frames.pivot.z))
	if points.size() == 2 and points[0].distance_to(points[1]) < 0.01:
		points[1] += Vector3(0.0, 0.0, 0.5)  # a trip that lands where it stops still crawls a little
	return BotRoute.from_corners(points, data.corner_m)


# Down the trunk, under the drum along the low road and up to the hold point beneath station `z` at `radius`, then on.
func _board_drum(z: float, radius: float, psi: float) -> Array[Dictionary]:
	var way: PackedVector3Array = data.trunk.duplicate()
	var end: Vector3 = way[way.size() - 1]
	way.append(Vector3(end.x, data.lower_y, end.z))
	var hold: Vector3 = frames.on_circle(radius, z, frames.hold_angle)
	way.append(Vector3(hold.x, data.lower_y, z))
	way.append(hold)
	return [BotTrip.fly(BotRoute.from_corners(way, data.corner_m), BotTrip.Frame.STATION, data.cruise_mps, Vector3.DOWN),
			BotTrip.spin_up(radius, z, psi)]


# Down the trunk, up the climb, along the high road to above `spot` (or its `via` points), and down to it.
func _road_to(spot: Vector3, via: PackedVector3Array) -> BotRoute:
	var way: PackedVector3Array = data.trunk.duplicate()
	way.append_array(data.climb)
	if via.is_empty():
		way.append(Vector3(0.0, data.top_y, spot.z))
		if absf(spot.x) > 0.5:
			way.append(Vector3(spot.x, data.top_y, spot.z))
	else:
		way.append(Vector3(0.0, data.top_y, via[0].z))
		way.append_array(via)
	way.append(spot)
	return BotRoute.from_corners(_without_repeats(way), data.corner_m)


# Out past the bow toward the gate: straight on when it lies ahead, else round the station's side first.
func _departure(area: Dictionary) -> PackedVector3Array:
	var depart: Vector3 = BotData._vec3(area.get("depart", [0, 339, -4800]))
	var out := PackedVector3Array([depart])
	var toward: Vector3 = (frames.gate.origin - depart).normalized()
	if toward.z > -0.5:
		var side := Vector3(toward.x, toward.y, 0.0)
		side = side.normalized() if side.length() > 0.05 else Vector3.RIGHT
		out.append(depart + side * float(area.get("detour_m", 1800.0)))
	return out


static func _without_repeats(points: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p: Vector3 in points:
		if out.is_empty() or out[out.size() - 1].distance_to(p) > 0.5:
			out.append(p)
	return out
