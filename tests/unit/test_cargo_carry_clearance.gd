extends GutTest
## The bots carrying cargo keep their distance (M7-T30), for every pod of the five Saturns, measured against the drawn meshes: the
## station's frame and the Saturn's chunks (what stays on it, and the pods still on it). Each bot's way out to its hold, each
## carried pod and its bots on the way in, and the way home of a bot letting go of the pod in a fight. Left out by design: the pod's
## lift off the hull (it starts touching its mounts), and the last metres at the bay's back wall, where bot and pod go in.
##
## A pod in the bay's mouth has less room than a bot: the opening is 26.7 m high and a pod 17.2 m (a tank on its side 17.6 m).

const DIR: String = "res://assets/generated/babylon5_station/"
const HULL_CLEARANCE_M: float = 8.0
const SATURN_CLEARANCE_M: float = 5.0
## A pod's room from the hull in the bay's mouth and inside it (and that far outside it), m.
const POD_BAY_CLEARANCE_M: float = 4.0
const BAY_REACH_M: float = 60.0
const WALL_M: float = 20.0
const STEP_M: float = 12.0
const FACE_STEP_M: float = 6.0

var hull: BotMeshField
var bay: Dictionary
var least: Dictionary = {}


func before_all() -> void:
	var hp: StationHardpoints = StationHardpoints.from_manifest(MeshAssets.read_manifest(Station.ASSET_ID))
	assert_true(hp.valid, hp.error)
	bay = hp.cargo_bay
	hull = BotMeshField.of_faces(BotMeshField.faces_of_glb(DIR + "babylon5_station_frame.glb"))


func after_all() -> void:
	for key: String in least:
		gut.p("least %s: %.1f m" % [key, least[key]])


func test_saturn_3_freighter() -> void:
	_check("saturn_3_freighter")


func test_saturn_4_transport() -> void:
	_check("saturn_4_transport")


func test_saturn_4_tanker() -> void:
	_check("saturn_4_tanker")


func test_saturn_8_transport() -> void:
	_check("saturn_8_transport")


func test_saturn_8_tanker() -> void:
	_check("saturn_8_tanker")


func _check(hull_id: String) -> void:
	var chunks: Array[Dictionary] = FreighterCargo.chunk_boxes_of(hull_id)
	var plan: CargoFerryPlan = CargoFerryPlan.for_freighter(bay, chunks,
			Hardpoints.load_collision_only(ShipSpec.ASSET_ROOT.path_join(hull_id).path_join("hardpoints.json")))
	assert_true(plan.valid, plan.error)
	if not plan.valid:
		return
	var xf: Transform3D = plan.freighter_transform()
	var fixed := PackedVector3Array()
	var pod_faces: Dictionary = {}
	for entry: Dictionary in Hardpoints.load_file(ShipSpec.ASSET_ROOT.path_join(hull_id).path_join("hardpoints.json")).chunks:
		if not entry.has("mesh"):
			continue
		var faces := PackedVector3Array()
		var at: Transform3D = xf * Transform3D(Basis.IDENTITY, entry.get("offset", Vector3.ZERO))
		for p: Vector3 in BotMeshField.faces_of_glb(ShipSpec.ASSET_ROOT.path_join(hull_id).path_join(String(entry["mesh"]))):
			faces.append(at * p)
		if FreighterCargo.is_cargo(String(entry["name"])):
			pod_faces[String(entry["name"])] = faces
		else:
			fixed.append_array(faces)
	for n: int in plan.trips.size():
		var trip: CargoTrip = plan.trips[n]
		var label: String = "%s %s" % [hull_id, trip.pod_name]
		# What is on the Saturn during this trip: its own parts and the pods still to come off.
		var saturn_faces := fixed.duplicate()
		for later: int in range(n + 1, plan.trips.size()):
			saturn_faces.append_array(pod_faces[plan.trips[later].pod_name])
		var saturn: BotMeshField = BotMeshField.of_faces(saturn_faces)
		var with_own_faces := saturn_faces.duplicate()
		with_own_faces.append_array(pod_faces[trip.pod_name])
		var with_own: BotMeshField = BotMeshField.of_faces(with_own_faces)
		for k: int in trip.bot_count():
			_route_clear("%s bot %d out" % [label, k], trip.out_routes[k], plan, with_own, null, 0.0)
		_carry_clear(label, trip, plan, saturn)
		var s: float = maxf(trip.unberth_s, 0.0)
		while s <= trip.commit_s:
			for k: int in trip.bot_count():
				if trip.grab_s[k] <= s:
					var home: BotRoute = BotRoute.from_points(trip.escape_points(k, s))
					_route_clear("%s bot %d home from %.0f m" % [label, k, s], home, plan, saturn, trip, s)
			s += 60.0


# A bot's route keeps its distance from the hull and the Saturn (and from a pod it let go of at `pod_s`).
func _route_clear(label: String, route: BotRoute, plan: CargoFerryPlan, saturn: BotMeshField, trip: CargoTrip, pod_s: float) -> void:
	var low_hull: float = INF
	var low_saturn: float = INF
	var low_pod: float = INF
	var at: float = 0.0
	var pod_inverse: Transform3D = trip.pose_at(pod_s).affine_inverse() if trip != null else Transform3D()
	while at <= route.length_m:
		var p: Vector3 = route.point_at(at)
		at += 3.0
		if p.z > plan.wall_z - WALL_M:
			continue
		low_hull = minf(low_hull, hull.distance(p, 30.0))
		low_saturn = minf(low_saturn, saturn.distance(p, 30.0))
		if trip != null:
			low_pod = minf(low_pod, _box_distance(pod_inverse * p, trip.size))
	assert_gte(low_hull, HULL_CLEARANCE_M, "%s keeps %.1f m from the hull" % [label, low_hull])
	assert_gte(low_saturn, SATURN_CLEARANCE_M, "%s keeps %.1f m from the Saturn" % [label, low_saturn])
	if trip != null:
		assert_gte(low_pod, SATURN_CLEARANCE_M, "%s keeps %.1f m from the pod it let go of" % [label, low_pod])
	_note("bot hull", low_hull)
	_note("bot saturn", low_saturn)


# The carried pod (its surface, sampled) and its bots on the way in, from the end of the lift.
func _carry_clear(label: String, trip: CargoTrip, plan: CargoFerryPlan, saturn: BotMeshField) -> void:
	var surface: PackedVector3Array = _surface(trip.size)
	var low_hull: float = INF
	var low_bay: float = INF
	var low_saturn: float = INF
	var low_bot_hull: float = INF
	var low_bot_saturn: float = INF
	var s: float = trip.unberth_s
	while s <= trip.carry.length_m:
		var pose: Transform3D = trip.pose_at(s)
		var near_bay: bool = pose.origin.z + trip.size.z * 0.5 > plan.throat_z - BAY_REACH_M
		var near_saturn: bool = pose.origin.z - trip.size.z * 0.5 < plan.hold.z + 200.0
		for q: Vector3 in surface:
			var p: Vector3 = pose * q
			if p.z > plan.wall_z - WALL_M:
				continue
			if near_saturn:
				low_saturn = minf(low_saturn, saturn.distance(p, 20.0))
			if p.z > plan.throat_z - BAY_REACH_M:
				low_bay = minf(low_bay, hull.distance(p, 20.0))
			elif near_bay or p.z > plan.throat_z - 600.0:
				low_hull = minf(low_hull, hull.distance(p, 20.0))
		for k: int in trip.bot_count():
			if trip.grab_s[k] > s:
				continue
			var b: Vector3 = trip.bot_position(k, s)
			if b.z <= plan.wall_z - WALL_M:
				low_bot_hull = minf(low_bot_hull, hull.distance(b, 30.0))
				low_bot_saturn = minf(low_bot_saturn, saturn.distance(b, 30.0))
		s += STEP_M
	assert_gte(low_saturn, SATURN_CLEARANCE_M, "%s, carried, keeps %.1f m from the Saturn" % [label, low_saturn])
	assert_gte(low_hull, HULL_CLEARANCE_M, "%s, carried, keeps %.1f m from the hull outside the bay" % [label, low_hull])
	assert_gte(low_bay, POD_BAY_CLEARANCE_M, "%s, carried, keeps %.1f m from the bay's walls" % [label, low_bay])
	assert_gte(low_bot_hull, HULL_CLEARANCE_M, "%s, its bots keep %.1f m from the hull" % [label, low_bot_hull])
	assert_gte(low_bot_saturn, SATURN_CLEARANCE_M, "%s, its bots keep %.1f m from the Saturn" % [label, low_bot_saturn])
	_note("pod saturn", low_saturn)
	_note("pod hull", low_hull)
	_note("pod bay", low_bay)


# Points over a box's faces (its own frame, centred), every few metres.
static func _surface(size: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var h: Vector3 = size * 0.5
	var n: Vector3i = Vector3i(maxi(1, ceili(size.x / FACE_STEP_M)), maxi(1, ceili(size.y / FACE_STEP_M)), maxi(1, ceili(size.z / FACE_STEP_M)))
	for i: int in n.x + 1:
		for j: int in n.y + 1:
			for k: int in n.z + 1:
				var on_face: bool = i == 0 or i == n.x or j == 0 or j == n.y or k == 0 or k == n.z
				if on_face:
					out.append(Vector3(-h.x + size.x * i / n.x, -h.y + size.y * j / n.y, -h.z + size.z * k / n.z))
	return out


static func _box_distance(local: Vector3, size: Vector3) -> float:
	var h: Vector3 = size * 0.5
	return (local.abs() - h).max(Vector3.ZERO).length()


func _note(key: String, value: float) -> void:
	least[key] = minf(float(least.get(key, INF)), value)
