class_name CargoFerryPlan
extends RefCounted
## Where the cargo ferry bots go (M7-T11, Q11 as the maintainer extended it): between the cargo bay between the bow's forks and a
## Saturn 3 holding at the bay's hold point, **stern toward the bay** (maintainer: it backs in, its nose away from the station, its
## cargo pods nearest the bay; T10's freighters will do the same). Read from the station's `cargo_bay` hardpoints and the
## freighter's cargo-pod boxes; no number of the bay is written here. Pure, in the station's frame.
##
## A route runs from inside the bay's back wall (where a bot vanishes and appears), out along its own lane through the throat and
## the slot between the forks, and ends a few metres behind one of the freighter's pods; the return lane is the other side of
## the bay's line, so bots going and coming never share a lane.

## The freighter's three cargo pods, as its collision boxes name them.
const POD_NAMES: Array[String] = ["top_pod", "low_pod_r", "low_pod_l"]
## How far behind a pod's aft face a bot hovers, metres.
const STANDOFF_M: float = 8.0
## The lanes' offsets from the bay's line: out one side, back the other, and how high each flies (m).
const LANE_X_M: float = 9.0
const LANE_Y_M: float = 4.0
## Metres between control points along the straight, and the length over which a route moves from its lane to its pod's place.
const SPACING_M: float = 300.0
const BLEND_M: float = 160.0
## How far inside the bay's back wall a route starts and ends (a bot is hidden by the wall there), metres.
const SINK_M: float = 5.0

var valid: bool = false
var error: String = ""
## The hold point (the freighter's origin) and the bay's entry, in the station's frame.
var hold: Vector3 = Vector3.ZERO
var entry: Vector3 = Vector3.ZERO
## The unit vector from the hold point toward the bay.
var axis: Vector3 = Vector3.BACK
## The freighter's orientation in the station's frame: its nose (-Z) away from the bay.
var freighter_basis: Basis = Basis.IDENTITY
## The bay's back wall's z, the throat's front z, the bay's floor-to-roof middle height.
var wall_z: float = 0.0
var throat_z: float = 0.0
var lane_y: float = 0.0
## Where a bot waits behind each pod (`POD_NAMES` order, those found), and each pod's box in the station's frame.
var pod_stops: Array[Vector3] = []
var pod_boxes: Array[AABB] = []


## The plan for `bay` (`StationHardpoints.cargo_bay`) and the freighter's collision `shapes` (`Hardpoints.load_collision_only`).
static func build(bay: Dictionary, shapes: Array[Dictionary]) -> CargoFerryPlan:
	var plan := CargoFerryPlan.new()
	for key: String in ["cargo_bay_hold", "cargo_bay_entry", "cargo_bay_clear_min", "cargo_bay_clear_max"]:
		if not bay.get(key) is Vector3:
			plan.error = "the cargo bay has no %s" % key
			return plan
	plan.hold = bay["cargo_bay_hold"]
	plan.entry = bay["cargo_bay_entry"]
	plan.axis = (plan.entry - plan.hold).normalized()
	if plan.axis.dot(Vector3.BACK) < 0.999:
		plan.error = "the cargo bay's line does not run along +Z"
		return plan
	plan.freighter_basis = Basis.looking_at(-plan.axis, Vector3.UP)
	var clear_min: Vector3 = bay["cargo_bay_clear_min"]
	var clear_max: Vector3 = bay["cargo_bay_clear_max"]
	plan.throat_z = clear_min.z
	plan.wall_z = clear_max.z + 2.0
	plan.lane_y = plan.entry.y
	for pod_name: String in POD_NAMES:
		for entry: Dictionary in shapes:
			if entry.get("name") != pod_name or not entry["shape"] is BoxShape3D:
				continue
			var size: Vector3 = (entry["shape"] as BoxShape3D).size
			var centre: Vector3 = (entry["transform"] as Transform3D).origin
			var aft: Vector3 = plan.hold + plan.freighter_basis * (centre + Vector3(0.0, 0.0, size.z * 0.5))
			plan.pod_stops.append(aft + plan.axis * STANDOFF_M)
			var world_centre: Vector3 = plan.hold + plan.freighter_basis * centre
			var world_size: Vector3 = (plan.freighter_basis * size).abs()
			plan.pod_boxes.append(AABB(world_centre - world_size * 0.5, world_size))
	if plan.pod_stops.is_empty():
		plan.error = "the freighter has no cargo pods (%s)" % ", ".join(POD_NAMES)
		return plan
	plan.valid = true
	return plan


## The freighter's pose in the station's frame: at the hold point, stern toward the bay.
func freighter_transform() -> Transform3D:
	return Transform3D(freighter_basis, hold)


## Where a bot of `lane` (any whole number) goes and comes back: `[out, back]` routes to the pod behind which it waits (`lane` picks
## the pod, round and round) and the side of the bay's line it goes out on (the return is the other side, a little lower).
func routes_for(lane: int) -> Array[BotRoute]:
	var stop: Vector3 = pod_stops[lane % pod_stops.size()]
	var side: float = (-1.0 if lane % 2 == 0 else 1.0) * LANE_X_M
	var out := BotRoute.from_points(_points(Vector2(side, lane_y + LANE_Y_M), stop))
	var back_points := _points(Vector2(-side, lane_y - LANE_Y_M), stop)
	back_points.reverse()
	return [out, BotRoute.from_points(back_points)]


# Control points from the bay's back wall, out along the lane (x, y) and in to `stop`. The bay's line runs along +Z (checked in `build`),
# so the way out is toward -Z.
func _points(lane: Vector2, stop: Vector3) -> PackedVector3Array:
	var points := PackedVector3Array()
	points.append(Vector3(lane.x * 0.3, lane.y, wall_z + SINK_M))
	points.append(Vector3(lane.x, lane.y, wall_z - 8.0))
	points.append(Vector3(lane.x, lane.y, throat_z - 20.0))
	var z: float = throat_z - SPACING_M
	while z > stop.z + BLEND_M + 0.5 * SPACING_M:
		points.append(Vector3(lane.x, lane.y, z))
		z -= SPACING_M
	# The last stretch: the lane eases onto the pod's place.
	var z_from: float = points[points.size() - 1].z
	for k: int in 3:
		var t: float = float(k + 1) / 3.0
		var eased: float = t * t * (3.0 - 2.0 * t)
		points.append(Vector3(lerpf(lane.x, stop.x, eased), lerpf(lane.y, stop.y, eased), lerpf(z_from, stop.z, t)))
	return points
