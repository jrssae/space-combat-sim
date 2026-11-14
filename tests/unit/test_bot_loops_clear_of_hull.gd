extends GutTest
## The maintenance bots' loops keep their distance from the station's hull (M7-T11, Q11: "they never touch the hull"), measured to
## the generated station's drawn triangles: a bot on the frame's loop clears the drum at every turn of it, and a bot on the drum's
## loop clears the frame as it rides. The file's `clearance_m` is more than the bot's own radius, so what is measured here is the
## gap between the bot's body and the hull.

## How far round the drum's turn is sampled, degrees, and every how many samples of a loop is tested.
const TURN_STEP_DEG: float = 30.0
const EVERY: int = 5
const DIR: String = "res://assets/generated/babylon5_station/"

var _data: BotData = null
var _frame: BotMeshField = null
var _drum: BotMeshField = null
var _pivot: Vector3 = Vector3.ZERO


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
	_pivot = Vector3(float(pivot[0]), float(pivot[1]), float(pivot[2]))


func test_the_helper_measures_a_triangle() -> void:
	var field := BotMeshField.of_faces(PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(0, 10, 0),
			Vector3(100, 0, 0), Vector3(110, 0, 0), Vector3(100, 10, 0)]))
	assert_almost_eq(field.distance(Vector3(2, 2, 5), 50.0), 5.0, 1e-5, "above the face")
	assert_almost_eq(field.distance(Vector3(-3, -4, 0), 50.0), 5.0, 1e-5, "off a corner")
	assert_almost_eq(field.distance(Vector3(13, 0, 0), 50.0), 3.0, 1e-5, "beside an edge's end")
	assert_almost_eq(field.distance(Vector3(60, 0, 0), 50.0), 40.0, 1e-5, "between two triangles: the nearer one")
	assert_eq(field.distance(Vector3(0, 0, 400), 20.0), 20.0, "farther than the reach reads as the reach")
	assert_gt(_frame.triangle_count(), 10000)
	assert_gt(_drum.triangle_count(), 10000)


func test_every_loop_clears_the_hull_the_whole_way_round() -> void:
	assert_true(_data.valid, _data.error)
	for entry: Dictionary in _data.loops:
		var loop: BotLoop = BotLoop.from_points(entry["points"])
		var least: float = INF
		var samples: PackedVector3Array = loop.sample_points()
		for i: int in range(0, samples.size(), EVERY):
			least = minf(least, _clearance(samples[i], entry["body"] == StationHardpoints.DRUM))
		assert_gte(least, _data.clearance_m, "%s keeps %.1f m from the hull (the file says %.1f)" % [entry["name"], least, _data.clearance_m])


func test_each_hatch_leg_reaches_the_hull_without_meeting_the_other_body() -> void:
	# A bot flying a hatch's leg sinks into the hull it works on, by design, and must not meet the body that moves past it: a leg
	# on the drum's loop stays clear of the frame and a leg on the frame's stays clear of the drum at every turn.
	for entry: Dictionary in _data.loops:
		var loop: BotLoop = BotLoop.from_points(entry["points"])
		var on_drum: bool = entry["body"] == StationHardpoints.DRUM
		for hatch: Dictionary in entry["hatches"]:
			var start: Vector3 = loop.point_at(loop.control_s[hatch["at"]])
			var inside: Vector3 = hatch["inside"]
			var least: float = INF
			for k: int in 21:
				var p: Vector3 = start.lerp(inside, float(k) / 20.0)
				least = minf(least, _other_clearance(p, on_drum))
			assert_gte(least, _data.clearance_m, "%s's leg keeps %.1f m from the other body" % [hatch["name"], least])


# The least distance of a point to the body that is not its own, over a full turn of the drum.
func _other_clearance(point: Vector3, on_drum: bool) -> float:
	var reach: float = 60.0
	var least: float = reach
	var turn: float = 0.0
	while turn < 360.0:
		var rot := Basis(Vector3.BACK, deg_to_rad(turn))
		if on_drum:
			least = minf(least, _frame.distance(_pivot + rot * point, reach))
		else:
			least = minf(least, _drum.distance(rot.inverse() * (point - _pivot), reach))
		turn += TURN_STEP_DEG
	return least


# The least distance of a loop point in the drum's frame (`on_drum`) or the frame's, over a full turn of the drum.
func _clearance(point: Vector3, on_drum: bool) -> float:
	var reach: float = 60.0
	var least: float = reach
	var turn: float = 0.0
	while turn < 360.0:
		var rot := Basis(Vector3.BACK, deg_to_rad(turn))
		if on_drum:
			# The bot turns with the drum, the frame stands still: the point seen in the station's frame.
			least = minf(least, _frame.distance(_pivot + rot * point, reach))
			if turn == 0.0:
				least = minf(least, _drum.distance(point, reach))
		else:
			# The drum turned `turn` degrees: the frame's point is that much back in the drum's own frame.
			least = minf(least, _drum.distance(rot.inverse() * (point - _pivot), reach))
			if turn == 0.0:
				least = minf(least, _frame.distance(point, reach))
		turn += TURN_STEP_DEG
	return least
