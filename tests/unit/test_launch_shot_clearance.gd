extends GutTest
## Every launch camera variant keeps the camera out of the station's walls (M7-T12, from the maintainer: "the camera is clipping through
## the Cobra bay walls"). Each variant of `data/launch/cobra_launch.json` is played where its phase plays it, on launches from several
## wings, doors and drum angles run through the pure `LaunchSequence`, and the camera's path is read against the drawn hull (the frame's
## and the drum's meshes, the drum turned as it was at that moment) and the open door leaves. The fighter's own hull is not counted: a
## shot may sit close to the fighter it films.

const DT: float = 1.0 / 60.0
const SPIN: float = 0.148
## The least distance the camera keeps from any wall or leaf, metres (the near plane is 0.05).
const CLEAR_M: float = 2.0
const SAMPLE_EVERY: int = 3
const LAUNCH_S: float = 50.0
## The seconds after the release over which the fighter's own distance from the hull is read, and what counts as a graze, metres.
const FLIGHT_S: float = 6.0
const GRAZE_M: float = 6.0
const IDS: Array[String] = ["PLAYER", "W2", "W3", "W4"]

var hp: StationHardpoints
var profile: LaunchProfile
var field: StationClearance
var timelines: Array[Dictionary] = []


func before_all() -> void:
	var manifest: Dictionary = MeshAssets.read_manifest(Station.ASSET_ID)
	field = StationClearance.load_station()
	if field == null or not manifest.has("hardpoints"):
		return
	hp = StationHardpoints.from_manifest(manifest)
	var made: Dictionary = LaunchProfile.load_file()
	assert_true(bool(made["ok"]), str(made.get("error", "")))
	profile = made["profile"]
	for combo: Array in [["alpha", 1], ["alpha", 2], ["alpha", 3], ["alpha", 4], ["alpha", 5], ["alpha", 6], ["beta", 3], ["delta", 3], ["zeta", 3]]:
		for start_deg: float in [0.0, 60.0, 120.0, 180.0, 240.0, 300.0]:
			timelines.append(_timeline(combo[0], combo[1], deg_to_rad(start_deg), hash([combo[0], combo[1], start_deg])))


# One launch of the player and three wingmen, recorded every tick: the drum's angle, the player's step, its pose and its door's, and
# each door leaf of the arm as a rectangle.
func _timeline(wing: String, door: int, start_angle: float, seed_value: int) -> Dictionary:
	var ids := PackedStringArray(IDS)
	var seq: LaunchSequence = LaunchSequence.create(hp, wing, ids, profile, door, start_angle, SPIN, seed_value)
	assert_true(seq.valid, seq.error)
	var ticks: Array[Dictionary] = []
	var angle: float = start_angle
	var released_at: int = -1
	var handoff: Dictionary = {}
	for i: int in roundi(LAUNCH_S / DT):
		angle += SPIN * DT
		seq.advance(DT, angle, SPIN)
		var f: Dictionary = seq.fighter("PLAYER")
		if released_at < 0 and f["phase"] == LaunchSequence.Phase.RELEASED:
			released_at = i
			handoff = seq.handoff_of("PLAYER", field.pivot)
		var bay: Dictionary = seq.bays[f["bay"]]
		var drum := Transform3D(Basis(Vector3.BACK, angle), field.pivot)
		var xf: Transform3D
		if released_at >= 0:
			# Let go, it flies straight on in the station's frame at its hand-off velocity.
			var h: Transform3D = handoff["transform"]
			xf = Transform3D(h.basis, h.origin + (handoff["velocity"] as Vector3) * float(i - released_at) * DT)
		else:
			xf = seq.state_of("PLAYER", field.pivot)["transform"]
		ticks.append({"angle": angle, "step": seq.step_of("PLAYER"), "step_time": seq.step_time("PLAYER"), "fighter": xf,
				"bay": drum * LaunchSequence.door_frame(bay), "leaves": _leaves(seq, drum), "time": seq.time_s})
	# How near the hull the fighter itself flies in its first seconds out (the hold keeps it off the spine).
	var graze: float = INF
	if released_at >= 0:
		for i: int in range(released_at, mini(released_at + roundi(FLIGHT_S / DT), ticks.size()), SAMPLE_EVERY):
			graze = minf(graze, field.distance((ticks[i]["fighter"] as Transform3D).origin, float(ticks[i]["angle"]), GRAZE_M * 2.0))
	return {"wing": wing, "door": door, "start_deg": rad_to_deg(start_angle), "ticks": ticks, "graze_m": graze}


# The door leaves of the player's arm as rectangles in the station's frame (their hinge, swung outward by the door's angle).
func _leaves(seq: LaunchSequence, drum: Transform3D) -> Array[PackedVector3Array]:
	var out: Array[PackedVector3Array] = []
	for k: int in seq.bays.size():
		var open_deg: float = seq.door_angle_deg(k)
		if open_deg < 1.0:
			continue
		var bay: Dictionary = seq.bays[k]
		var normal: Vector3 = (bay["normal"] as Vector3).normalized()
		for leaf: Dictionary in bay["leaves"] as Array:
			var hinge: Vector3 = leaf["point"]
			var axis: Vector3 = (leaf["axis"] as Vector3).normalized()
			var inward: Vector3 = ((bay["door"] as Vector3) - hinge)
			inward = (inward - axis * inward.dot(axis)).normalized()
			var sign: float = 1.0 if axis.cross(inward).dot(normal) > 0.0 else -1.0
			var edge: Vector3 = Basis(axis, deg_to_rad(open_deg) * sign) * inward * LEAF_WIDTH_M
			var half: Vector3 = axis * LEAF_HALF_LENGTH_M
			out.append(PackedVector3Array([drum * (hinge - half), drum * (hinge + half), drum * (hinge + half + edge), drum * (hinge - half + edge)]))
	return out


const LEAF_WIDTH_M: float = 9.6
const LEAF_HALF_LENGTH_M: float = 6.6


func _leaf_distance(point: Vector3, leaves: Array[PackedVector3Array]) -> float:
	var best: float = INF
	for quad: PackedVector3Array in leaves:
		for tri: Array in [[0, 1, 2], [0, 2, 3]]:
			best = minf(best, point.distance_to(BotMeshField.closest_point(point, quad[tri[0]], quad[tri[1]], quad[tri[2]])))
	return best


# The camera of `variant` played from tick `start` of a timeline: the least distance to the walls and leaves, and when.
func _closest(shot: CinematicShot, timeline: Dictionary, start: int, end: int) -> Dictionary:
	var ticks: Array[Dictionary] = timeline["ticks"]
	var best: float = INF
	var at_s: float = 0.0
	var steps: int = mini(ceili(shot.duration_s / DT), end - start)
	for k: int in range(0, steps + 1, SAMPLE_EVERY):
		var tick: Dictionary = ticks[mini(start + k, ticks.size() - 1)]
		var poser: Callable = func(actor: String) -> Variant:
			if actor == "fighter" or actor == "player":
				return tick["fighter"]
			if actor == "bay":
				return tick["bay"]
			return null
		var pose: CinematicShot.Pose = shot.pose_at(minf(float(k) * DT, shot.duration_s), poser, func(_o: PackedFloat64Array) -> Vector3: return Vector3.ZERO)
		if pose == null:
			return {"gap": -1.0, "at_s": float(k) * DT}
		var p: Vector3 = pose.transform.origin
		var gap: float = minf(field.distance(p, float(tick["angle"]), CLEAR_M * 6.0), _leaf_distance(p, tick["leaves"]))
		if gap < best:
			best = gap
			at_s = float(k) * DT
	return {"gap": best, "at_s": at_s}


# The tick the next phase of a cut that cannot be left out starts, and so the latest the shot of phase `index` plays to (never under
# the least hold): a hold shot is only on screen while the fighter holds.
func _end_of(timeline: Dictionary, index: int, start: int) -> int:
	for later: int in range(index + 1, profile.phases.size()):
		var phase: Dictionary = profile.phases[later]
		if float(phase["optional"]) > 0.0:
			continue
		var tick: int = _start_of(timeline, phase["step"], float(phase["at_s"]))
		if tick >= 0:
			return maxi(tick, start + ceili(profile.min_shot_s / DT))
	return (timeline["ticks"] as Array).size() - 1


# The first tick the player's fighter has been `at_s` into `step`, or -1 when the launch never gets there.
func _start_of(timeline: Dictionary, step: StringName, at_s: float) -> int:
	var ticks: Array[Dictionary] = timeline["ticks"]
	for i: int in ticks.size():
		if ticks[i]["step"] == step and float(ticks[i]["step_time"]) >= at_s - LaunchSequence.EPS_S:
			return i
	return -1


# The fighter itself never skims the hull after its release (M7-T12 found one 0.9 m from the spine; the hold now checks its path).
func test_a_released_fighter_keeps_clear_of_the_hull() -> void:
	if field == null:
		pass_test("the station is not generated here")
		return
	for timeline: Dictionary in timelines:
		assert_gte(float(timeline["graze_m"]), GRAZE_M, "%s door %d, drum %.0f deg at the start: the fighter comes within %.1f m of the hull" % [timeline["wing"], timeline["door"], timeline["start_deg"], timeline["graze_m"]])


func test_every_launch_shot_keeps_the_camera_clear_of_the_walls() -> void:
	if field == null:
		pass_test("the station is not generated here")
		return
	var checked: int = 0
	for index: int in profile.phases.size():
		var phase: Dictionary = profile.phases[index]
		for variant: Dictionary in phase["variants"]:
			var shot: CinematicShot = variant["shot"]
			var worst: float = INF
			var where: String = ""
			for timeline: Dictionary in timelines:
				var start: int = _start_of(timeline, phase["step"], float(phase["at_s"]))
				if start < 0:
					continue
				var result: Dictionary = _closest(shot, timeline, start, _end_of(timeline, index, start))
				checked += 1
				if float(result["gap"]) < worst:
					worst = float(result["gap"])
					where = "%s door %d, drum %.0f deg at the start, %.2f s in" % [timeline["wing"], timeline["door"], timeline["start_deg"], result["at_s"]]
			assert_gte(worst, CLEAR_M, "%s (%s): the camera comes %.2f m from a wall or leaf (%s)" % [variant["id"], phase["phase"], worst, where])
	assert_gt(checked, 100, "the variants were played on many launches")
