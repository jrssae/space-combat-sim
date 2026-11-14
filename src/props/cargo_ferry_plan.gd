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
##
## `for_freighter` (M7-T30) plans the bots carrying any Saturn's cargo from its break-up chunks' boxes: one `CargoTrip` a pod, in
## the order they come off (the end nearest the bay first), each keeping clear of the hull and of the pods still on it.

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
## Carrying (M7-T30). A pod longer than this has two bots, front and back, m.
const LONG_POD_M: float = 60.0
## The lifts tried off the hull, m; the gap a lifted pod keeps from the Saturn's boxes as it slides aft, and a bot's place from them.
const LIFTS_M: Array[float] = [6.0, 10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0, 45.0, 50.0, 60.0]
const SWEEP_CLEAR_M: float = 6.0
const GRAB_CLEAR_M: float = 5.0
## How far an empty bot's approach keeps from the Saturn's boxes, and the sideways steps tried to find it, m.
const BOT_CLEAR_M: float = 7.0
const SIDESTEPS_M: Array[float] = [0.0, 6.0, 12.0, 18.0, 24.0, 30.0, 40.0, 50.0, 60.0, 80.0]
## How round an empty bot's turns near the Saturn are, m.
const CORNER_M: float = 12.0
## A pod clears the stern by this before it turns for the bay, m, and eases onto the bay's line over this length.
const STERN_MARGIN_M: float = 40.0
const CARRY_BLEND_M: float = 200.0
## A tank's turn onto its side ends this far short of the bay's mouth (its leading face) and takes this long, m.
const ROLL_DONE_M: float = 80.0
const ROLL_LENGTH_M: float = 120.0
## Its bots may let a pod go only while its leading face is this far short of the bay's mouth, m.
const DROP_SHORT_M: float = 60.0

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
## `for_freighter`: the pods' trips in unloading order (loading is the reverse), and the bay's middle the pods fly through.
var trips: Array[CargoTrip] = []
var bay_mid: Vector3 = Vector3.ZERO


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


## The bots' plan for the Saturn whose break-up chunks are `chunks` (`{name, box}`, its own frame; the cargo ones carried) and whose
## collision shapes are `collision` (`Hardpoints.load_collision_only`; what stays on the ship), held at `bay`'s hold point (or at
## `at`, its origin in the station's frame, when given).
static func for_freighter(bay: Dictionary, chunks: Array[Dictionary], collision: Array[Dictionary], at: Variant = null) -> CargoFerryPlan:
	var plan := CargoFerryPlan.new()
	for key: String in ["cargo_bay_hold", "cargo_bay_entry", "cargo_bay_clear_min", "cargo_bay_clear_max"]:
		if not bay.get(key) is Vector3:
			plan.error = "the cargo bay has no %s" % key
			return plan
	plan.hold = at if at is Vector3 else bay["cargo_bay_hold"]
	plan.entry = bay["cargo_bay_entry"]
	plan.axis = ((bay["cargo_bay_entry"] as Vector3) - (bay["cargo_bay_hold"] as Vector3)).normalized()
	if plan.axis.dot(Vector3.BACK) < 0.999:
		plan.error = "the cargo bay's line does not run along +Z"
		return plan
	plan.freighter_basis = Basis.looking_at(-plan.axis, Vector3.UP)
	var clear_min: Vector3 = bay["cargo_bay_clear_min"]
	var clear_max: Vector3 = bay["cargo_bay_clear_max"]
	plan.throat_z = clear_min.z
	plan.wall_z = clear_max.z + 2.0
	plan.lane_y = plan.entry.y
	plan.bay_mid = (clear_min + clear_max) * 0.5
	var xf: Transform3D = plan.freighter_transform()
	var pods: Array[Dictionary] = []
	for entry: Dictionary in chunks:
		if FreighterCargo.is_cargo(String(entry["name"])):
			pods.append({"name": entry["name"], "local": entry["box"], "box": _moved(xf, entry["box"])})
	if pods.is_empty():
		plan.error = "the freighter has no cargo chunks (pod*, tank*)"
		return plan
	# Nearest the bay first; pods level with each other keep the chunks' order.
	var order: Array[int] = []
	for i: int in pods.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		var za: float = (pods[a]["box"] as AABB).end.z
		var zb: float = (pods[b]["box"] as AABB).end.z
		return za > zb + 0.5 or (absf(za - zb) <= 0.5 and a < b))
	var fixed: Array[AABB] = []
	var stern_z: float = -INF
	for entry: Dictionary in collision:
		var box: AABB = _shape_box(entry)
		if box.size == Vector3.ZERO:
			continue
		var inside_cargo: bool = false
		for pod: Dictionary in pods:
			inside_cargo = inside_cargo or (pod["local"] as AABB).grow(0.01).has_point(box.get_center())
		if not inside_cargo:
			fixed.append(_moved(xf, box))
	for entry: Dictionary in chunks:
		stern_z = maxf(stern_z, _moved(xf, entry["box"]).end.z)
	for n: int in order.size():
		var obstacles: Array[AABB] = fixed.duplicate()
		for later: int in range(n + 1, order.size()):
			obstacles.append(pods[order[later]]["box"])
		var trip: CargoTrip = plan._trip(pods[order[n]], obstacles, stern_z)
		if trip == null:
			return plan
		plan.trips.append(trip)
	plan.valid = true
	return plan


# One pod's trip, keeping clear of `obstacles` (the Saturn's boxes and the pods still on it, station frame). Null and `error` when
# no lift off the hull clears them.
func _trip(pod: Dictionary, obstacles: Array[AABB], stern_z: float) -> CargoTrip:
	var trip := CargoTrip.new()
	var box: AABB = pod["box"]
	var local: AABB = pod["local"]
	trip.pod_name = pod["name"]
	trip.size = local.size
	trip.hull_basis = freighter_basis
	trip.roll = trip.pod_name.begins_with("tank")
	trip.wall_z = wall_z
	trip.sink_m = SINK_M
	var c0: Vector3 = box.get_center()
	var half: Vector3 = box.size * 0.5
	var across: Vector3 = c0 - hold
	across.z = 0.0
	var outboard: Vector3 = across.normalized() if across.length() > 1.0 else Vector3.UP
	var two: bool = local.size.z > LONG_POD_M
	var reach: float = half.z + STANDOFF_M
	trip.offsets = [axis * reach] as Array[Vector3]
	if two:
		trip.offsets.append(-axis * reach)
	var at_hull: Array[bool] = []
	for off: Vector3 in trip.offsets:
		at_hull.append(_clearance(c0 + off, obstacles) >= GRAB_CLEAR_M)
	if not at_hull[0] and (not two or not at_hull[1]):
		error = "%s: neither end can be held on the hull" % trip.pod_name
		return null
	# Mounts reaching into the pod's front (a Saturn 3's pylons) are left behind by sliding it aft first; mounts along its side (the
	# arms, the braces) by lifting it off.
	var slide: float = 0.0
	var aside: Array[AABB] = []
	for other: AABB in obstacles:
		if other.intersects(box) and other.get_center().z < box.position.z:
			slide = maxf(slide, other.end.z - box.position.z + SWEEP_CLEAR_M)
		else:
			aside.append(other)
	var lift: float = -1.0
	for u: float in LIFTS_M:
		var moved := AABB(box.position + axis * slide + outboard * u, box.size)
		var swept: AABB = moved.merge(AABB(moved.position + axis * (stern_z - moved.position.z + STERN_MARGIN_M), moved.size))
		var ok: bool = true
		for other: AABB in aside:
			ok = ok and _gap(swept, other) >= SWEEP_CLEAR_M
		for k: int in trip.offsets.size():
			if not at_hull[k]:
				ok = ok and _clearance(c0 + axis * slide + outboard * u + trip.offsets[k], obstacles) >= GRAB_CLEAR_M
		if ok:
			lift = u
			break
	if lift < 0.0:
		error = "%s: no lift off the hull clears the Saturn" % trip.pod_name
		return null
	var slid: Vector3 = c0 + axis * slide
	var p1: Vector3 = slid + outboard * lift
	var gate_z: float = stern_z + half.z + STERN_MARGIN_M
	var lane := Vector2(bay_mid.x, bay_mid.y)
	# Off the hull in straight moves (it stops at each corner), then a smooth way to the bay.
	var off := PackedVector3Array([c0])
	if slide > 0.0:
		off.append(slid)
	off.append(p1)
	# Evenly spaced, so the spline neither loops back at the corner nor swings wide.
	var points := PackedVector3Array()
	var legs: int = maxi(1, ceili((gate_z - p1.z) / (CARRY_BLEND_M / 3.0)))
	for k: int in legs + 1:
		points.append(Vector3(p1.x, p1.y, lerpf(p1.z, gate_z, float(k) / float(legs))))
	for k: int in 3:
		var t: float = float(k + 1) / 3.0
		var eased: float = t * t * (3.0 - 2.0 * t)
		points.append(Vector3(lerpf(p1.x, lane.x, eased), lerpf(p1.y, lane.y, eased), gate_z + CARRY_BLEND_M * t))
	var z: float = gate_z + CARRY_BLEND_M + SPACING_M
	while z < throat_z - 20.0 - 0.5 * SPACING_M:
		points.append(Vector3(lane.x, lane.y, z))
		z += SPACING_M
	points.append(Vector3(lane.x, lane.y, throat_z - 20.0))
	points.append(Vector3(lane.x, lane.y, wall_z - 8.0))
	points.append(Vector3(lane.x, lane.y, wall_z + SINK_M + half.z + (STANDOFF_M + 2.0 if two else 0.0)))
	trip.carry = BotRoute.joined([BotRoute.from_corners(off, 0.0), BotRoute.from_points(points)] as Array[BotRoute])
	trip.unberth_s = _s_nearest(trip.carry, p1)
	if slide > 0.0:
		trip.stops.append(_s_nearest(trip.carry, slid))
	trip.stops.append(trip.unberth_s)
	trip.commit_s = _s_at_z(trip.carry, throat_z - DROP_SHORT_M - half.z)
	trip.roll_to_z = throat_z - ROLL_DONE_M - half.z
	trip.roll_from_z = trip.roll_to_z - ROLL_LENGTH_M
	for k: int in trip.offsets.size():
		trip.grab_s.append(0.0 if at_hull[k] else trip.unberth_s)
		var around: Array[AABB] = obstacles.duplicate()
		around.append(box)
		var route: BotRoute = _approach(k, trip.bot_position(k, trip.grab_s[k]), outboard, around, stern_z)
		if route == null:
			error = "%s: bot %d finds no clear way to its hold" % [trip.pod_name, k]
			return null
		trip.out_routes.append(route)
	return trip


# A bot's route from the bay's back wall to `grab` (on lane `k`): down the lane, round behind the stern, and in from the side
# (stepping outboard until the approach clears `obstacles`).
func _approach(k: int, grab: Vector3, outboard: Vector3, obstacles: Array[AABB], stern_z: float) -> BotRoute:
	var gate_z: float = maxf(stern_z + STERN_MARGIN_M, grab.z + 30.0)
	for w: float in SIDESTEPS_M:
		var side: Vector3 = grab + outboard * w
		var gate := Vector3(side.x, side.y, gate_z)
		# The way in from the side need only be as clear as the hold itself.
		var ok: bool = true
		for i: int in 41:
			var t: float = float(i) / 40.0
			ok = ok and _clearance(gate.lerp(side, t), obstacles) >= BOT_CLEAR_M
			ok = ok and _clearance(side.lerp(grab, t), obstacles) >= GRAB_CLEAR_M
		if not ok:
			continue
		var lane := _points(Vector2((-1.0 if k == 0 else 1.0) * LANE_X_M, lane_y + LANE_Y_M), gate)
		var near := PackedVector3Array([gate])
		if w > 0.0:
			near.append(side)
		near.append(grab)
		return BotRoute.joined([BotRoute.from_points(lane), BotRoute.from_corners(near, CORNER_M)] as Array[BotRoute])
	return null


# The least distance from `p` to any of `boxes`.
static func _clearance(p: Vector3, boxes: Array[AABB]) -> float:
	var least: float = INF
	for b: AABB in boxes:
		var d: Vector3 = (b.position - p).max(p - b.end).max(Vector3.ZERO)
		least = minf(least, d.length())
	return least


# The gap between two boxes (0 when they touch or overlap).
static func _gap(a: AABB, b: AABB) -> float:
	var d: Vector3 = (b.position - a.end).max(a.position - b.end).max(Vector3.ZERO)
	return d.length()


static func _moved(xf: Transform3D, box: AABB) -> AABB:
	return xf * box


# A collision shape's box in the Saturn's frame (capsules and cylinders by their bounds).
static func _shape_box(entry: Dictionary) -> AABB:
	var size := Vector3.ZERO
	var shape: Variant = entry.get("shape")
	if shape is BoxShape3D:
		size = (shape as BoxShape3D).size
	elif shape is CapsuleShape3D:
		size = Vector3(2.0 * (shape as CapsuleShape3D).radius, (shape as CapsuleShape3D).height, 2.0 * (shape as CapsuleShape3D).radius)
	elif shape is CylinderShape3D:
		size = Vector3(2.0 * (shape as CylinderShape3D).radius, (shape as CylinderShape3D).height, 2.0 * (shape as CylinderShape3D).radius)
	else:
		return AABB()
	return (entry["transform"] as Transform3D) * AABB(-size * 0.5, size)


static func _s_nearest(route: BotRoute, p: Vector3) -> float:
	var best: float = INF
	var at: float = 0.0
	for i: int in route.samples.size():
		var d: float = route.samples[i].distance_squared_to(p)
		if d < best:
			best = d
			at = route.along[i]
	return at


# How far along `route` its z first reaches `z` (the route runs toward +Z).
static func _s_at_z(route: BotRoute, z: float) -> float:
	for i: int in route.samples.size():
		if route.samples[i].z >= z:
			return route.along[i]
	return route.length_m
