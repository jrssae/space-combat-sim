extends GutTest
## Every way the maintenance crew flies keeps its distance from the station's drawn hull (M7-T35, after T11's loops): the roads,
## every peace patrol (each vane up and down, the drum's whole riding line, the spine) and every repair trip (each damage section
## and grid mount), measured to the generated triangles. A frame point near the drum clears it at every turn; a bot riding the
## drum clears the frame all the way round and the drum at any landing angle. The gate's arm route clears the gate's mesh.

const DIR: String = "res://assets/generated/babylon5_station/"
const GATE_GLB: String = "res://assets/generated/jumpgate/jumpgate.glb"
## Spacing of the tested points along a route, metres; how far round the drum's turn is sampled, degrees.
const STEP_M: float = 6.0
const TURN_STEP_DEG: float = 10.0
const REACH_M: float = 40.0

var _data: BotData = null
var _frames := BotFrames.new()
var _frame: BotMeshField = null
var _drum: BotMeshField = null
var _planner: BotTripPlanner = null
var _seen := {}


func before_all() -> void:
	_data = BotData.load_file()
	var manifest: Dictionary = MeshAssets.read_manifest(Station.ASSET_ID)
	var pieces: Dictionary = manifest.get("pieces", {})
	assert_true(pieces.has("drum") and pieces.has("frame"), "the station is generated")
	if not pieces.has("drum"):
		return
	_frame = BotMeshField.of_faces(BotMeshField.faces_of_glb(DIR + "babylon5_station_frame.glb"))
	_drum = BotMeshField.of_faces(BotMeshField.faces_of_glb(DIR + "babylon5_station_drum.glb"))
	var pivot: Array = (pieces["drum"] as Dictionary).get("pivot", [0.0, 0.0, 0.0])
	_frames.pivot = Vector3(float(pivot[0]), float(pivot[1]), float(pivot[2]))
	var hardpoints := StationHardpoints.from_manifest(manifest)
	var sections := StationSections.from_hardpoints(hardpoints)
	var mounts := GridMountHealth.from_mounts(hardpoints.grid_mounts,
			func(kind_name: String) -> int: return StationGrid.KIND_OF.get(kind_name, StationGrid.Kind.LIGHT))
	_planner = BotTripPlanner.make(_data, _frames, BotRepairAreas.make(sections, mounts, hardpoints.grid_mounts))


func test_every_peace_patrol_clears_the_hull() -> void:
	assert_true(_data.valid, _data.error)
	for area: Dictionary in _data.peace:
		match String(area["kind"]):
			"fins":
				# Every vane, up and down: the trip number picks them, so enough trips cover all six.
				var seen := {}
				for n: int in 64:
					var trip: BotTrip = _planner.peace_trip(area, n)
					var key: String = str((trip.steps[1]["route"] as BotRoute).point_at(1e9).round())
					if not seen.has(key):
						seen[key] = true
						_check_trip(trip)
				assert_eq(seen.size(), (area["vanes_z"] as Array).size() * 2, "%s: every vane up and down" % area["name"])
			"drum":
				var span: Array = area["z"]
				_check_drum_line(float(span[0]), float(span[1]), String(area["name"]))
				_check_trip(_planner.peace_trip(area, 0))
			"spine":
				_check_trip(_planner.peace_trip(area, 0))


func test_every_repair_trip_clears_the_hull() -> void:
	var areas: BotRepairAreas = _planner.areas
	assert_gt(areas.count(), 30, "11 sections and 23 mounts")
	for a: int in areas.count():
		var trip: BotTrip = _planner.repair_trip(a)
		assert_not_null(trip, "a trip to %s" % areas.name_of(a))
		if trip != null:
			_check_trip(trip)


func test_the_gate_arm_route_clears_the_gate() -> void:
	var gate := BotMeshField.of_faces(BotMeshField.faces_of_glb(GATE_GLB))
	_frames.has_gate = true
	var area: Dictionary = _data.peace_area("gate")
	var arms := {}
	for n: int in 32:
		var trip: BotTrip = _planner.peace_trip(area, n)
		var route: BotRoute = trip.steps[2]["route"]
		var key: String = str(route.point_at(1e9).round())
		if arms.has(key):
			continue
		arms[key] = true
		var least: float = REACH_M
		for p: Vector3 in _points(route):
			least = minf(least, gate.distance(p, REACH_M))
		assert_gte(least, _data.clearance_m, "the arm route to %s keeps %.1f m from the gate" % [key, least])
	assert_eq(arms.size(), 4, "all four arms")
	_frames.has_gate = false


func _check_trip(trip: BotTrip) -> void:
	for i: int in trip.middle + 1:
		var s: Dictionary = trip.steps[i]
		match int(s["kind"]):
			BotTrip.Kind.FLY:
				var route: BotRoute = s["route"]
				if int(s["frame"]) == BotTrip.Frame.STATION:
					var least: float = REACH_M
					for p: Vector3 in _points(route):
						least = minf(least, _frame_point(p))
					assert_gte(least, _data.clearance_m, "%s step %d keeps %.1f m from the hull" % [trip.label, i, least])
			BotTrip.Kind.SPIN_UP:
				var least: float = _ring(float(s["radius"]), float(s["z"]), s["psi"])
				assert_gte(least, _data.clearance_m, "%s riding the drum at %.0f m keeps %.1f m" % [trip.label, float(s["radius"]), least])


# The whole riding line of a drum patrol, all the way round.
func _check_drum_line(z_from: float, z_to: float, label: String) -> void:
	var least: float = REACH_M
	var z: float = z_from
	while z <= z_to:
		least = minf(least, _ring(_data.drum_radius(z), z, NAN))
		z += 25.0
	assert_gte(least, _data.clearance_m, "%s's riding line keeps %.1f m from the hull" % [label, least])


# A frame point: the frame, and the drum at every turn when it is near it.
func _frame_point(p: Vector3) -> float:
	var key: Vector3i = Vector3i(p.round())
	if _seen.has(key):
		return _seen[key]
	var least: float = _frame.distance(p, REACH_M)
	var q: Vector3 = p - _frames.pivot
	if Vector2(q.x, q.y).length() < 480.0 and q.z > -2600.0 and q.z < 2560.0:
		var turn: float = 0.0
		while turn < 360.0:
			least = minf(least, _drum.distance(Basis(Vector3.BACK, deg_to_rad(turn)).inverse() * q, REACH_M))
			turn += TURN_STEP_DEG
	_seen[key] = least
	return least


# A bot riding the drum at `radius`, station `z`: the frame all the way round, and the drum at its landing angle (any, for NAN).
func _ring(radius: float, z: float, psi: Variant) -> float:
	var least: float = REACH_M
	var zd: float = z - _frames.pivot.z
	var turn: float = 0.0
	while turn < 360.0:
		var phi: float = deg_to_rad(turn)
		least = minf(least, _frame.distance(_frames.on_circle(radius, z, phi), REACH_M))
		turn += TURN_STEP_DEG
	var angles: Array[float] = []
	if psi == null or is_nan(float(psi)):
		for k: int in 12:
			angles.append(TAU * float(k) / 12.0)
	else:
		angles.append(float(psi))
	for a: float in angles:
		least = minf(least, _drum.distance(Vector3(radius * cos(a), radius * sin(a), zd), REACH_M))
	return least


func _points(route: BotRoute) -> PackedVector3Array:
	var out := PackedVector3Array()
	var s: float = 0.0
	while s <= route.length_m:
		out.append(route.point_at(s))
		s += STEP_M
	out.append(route.point_at(route.length_m))
	return out
