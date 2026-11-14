extends GutTest
## The station's exterior tour as data (M7-T12): `data/tour/station_tour.json` read into `TourBook`, every stop one of the station's tour
## hardpoints, every shot at least a second long, the subject of each shot in frame, the draws a seeded shuffle bag, and the shots
## riding the drum for the Cobra arm's stop and surviving a rebase.

# The generated station's tour points (docs/assets-station.md), so the tests run before the asset is generated.
const POINTS: Array[Dictionary] = [
	{"name": "bow", "body": "frame", "position": [260.0, 520.0, -4700.0], "look_at": [0.0, 250.0, -3550.0], "direction": [-0.215, -0.2232, 0.9508]},
	{"name": "main_docking_bay", "body": "frame", "position": [60.0, -40.0, -3880.0], "look_at": [0.0, 0.0, -3530.0], "direction": [-0.1679, 0.1119, 0.9794]},
	{"name": "cargo_bay", "body": "frame", "position": [120.0, 420.0, -3750.0], "look_at": [0.0, 345.0, -3550.0], "direction": [-0.4898, -0.3061, 0.8163]},
	{"name": "cobra_arm", "body": "drum", "position": [160.0, 215.0, -1990.0], "look_at": [0.0, 243.0, -1840.0], "direction": [-0.7237, 0.1266, 0.6784]},
	{"name": "grid_tower", "body": "frame", "position": [180.0, 520.0, -3670.0], "look_at": [0.0, 410.0, -3480.0], "direction": [-0.634, -0.3875, 0.6692]},
	{"name": "drum", "body": "frame", "position": [1100.0, -350.0, -1700.0], "look_at": [0.0, 0.0, -800.0], "direction": [-0.7515, 0.2391, 0.6149]},
	{"name": "vanes", "body": "frame", "position": [1500.0, 700.0, -100.0], "look_at": [535.0, 600.0, 800.0], "direction": [-0.7292, -0.0756, 0.6801]},
	{"name": "reactor", "body": "frame", "position": [420.0, 260.0, 4450.0], "look_at": [0.0, 0.0, 3700.0], "direction": [-0.4677, -0.2895, -0.8351]},
]
# The two light turrets on Alpha's prong (the defence grid stop shows them) and the four Cobra arms with the launch-blocked sector.
const MOUNTS: Array[Dictionary] = [
	{"name": "L1", "kind": "light_pulse", "body": "drum", "position": [-41.0, 292.0, -2310.0], "up": [0.0, 1.0, 0.0]},
	{"name": "L2", "kind": "light_pulse", "body": "drum", "position": [41.0, 292.0, -2310.0], "up": [0.0, 1.0, 0.0]},
]
const ARMS: Array[Dictionary] = [
	{"name": "top", "wing": "alpha", "angle_deg": 90.0}, {"name": "starboard", "wing": "beta", "angle_deg": 0.0},
	{"name": "bottom", "wing": "delta", "angle_deg": 270.0}, {"name": "port", "wing": "zeta", "angle_deg": 180.0},
]
const SPIN: float = 0.148
const STATION_XF: Transform3D = Transform3D(Basis.IDENTITY, Vector3.ZERO)
const PIVOT: Vector3 = Vector3(0.0, 0.0, -1000.0)


func _book() -> TourBook:
	var made: Dictionary = TourBook.load_file()
	assert_true(bool(made["ok"]), str(made.get("error", "")))
	return made["book"]


func _hardpoints(points: Array = POINTS) -> StationHardpoints:
	var hp := StationHardpoints.from_manifest({"hardpoints": {"spin_rad_s": SPIN, "cobra_bays": [], "grid_mounts": MOUNTS, "lights": [],
			"tour_points": points, "damage_sections": [], "main_docking_bay": {"name": "main_docking_bay", "body": "drum"},
			"cargo_bay": {"name": "cargo_bay", "body": "frame"}, "cobra_arm": {"arms": ARMS},
			"launch_clearance": {"blocked_sectors_deg": [[56.5, 124.0]], "clear_distance_m": 240.0, "margin_deg": 10.0}}})
	assert_true(hp.valid, hp.error)
	return hp


# The generated station's hardpoints when the asset is built here, else the fixture's.
func _real_or_fixture() -> StationHardpoints:
	var manifest: Dictionary = MeshAssets.read_manifest("babylon5_station")
	if not manifest.is_empty() and manifest.has("hardpoints"):
		var real: StationHardpoints = StationHardpoints.from_manifest(manifest)
		if real.valid:
			return real
	return _hardpoints()


func _drum_xf(angle: float, pivot: Vector3 = PIVOT) -> Transform3D:
	return Transform3D(Basis(Vector3.BACK, angle), pivot)


func _poser(book: TourBook, hp: StationHardpoints, station_xf: Transform3D, drum_xf: Transform3D, turns: Dictionary = {}) -> Callable:
	return func(actor: String) -> Variant: return book.pose_of(actor, hp, station_xf, drum_xf, turns)


func _no_origin(_offset: PackedFloat64Array) -> Vector3:
	return Vector3.ZERO


func test_the_tour_file_reads() -> void:
	var book: TourBook = _book()
	assert_true(book.valid)
	assert_eq(book.order.size(), 7, "seven stops")
	for stop_name: String in ["bow", "main_docking_bay", "cobra_arm", "defence_grid", "drum", "vanes", "cargo_bay"]:
		assert_true(book.order.has(stop_name), stop_name)
		assert_false(String(book.points[stop_name]["caption"]).is_empty(), "%s has a caption" % stop_name)
	for dropped: String in ["reactor", "grid_tower"]:
		assert_false(book.order.has(dropped), "%s is not toured (maintainer)" % dropped)
	assert_gte(book.min_shot_s, 1.0, "the least hold is the maintainer's second")
	assert_gte(book.templates.size(), 4, "a small pool of moves")


func test_every_stop_is_a_tour_point_of_the_station() -> void:
	var book: TourBook = _book()
	assert_eq(book.missing_points(_hardpoints()), PackedStringArray(), "the fixture has them all")
	assert_eq(book.missing_points(_real_or_fixture()), PackedStringArray(), "so does the generated station")
	var short: Array = POINTS.filter(func(p: Dictionary) -> bool: return p["name"] != "vanes")
	assert_eq(book.missing_points(_hardpoints(short)), PackedStringArray(["vanes"]))
	assert_true(book.plan(_hardpoints(short), 1).is_empty(), "no tour with a stop missing")
	var no_arm_hardpoint: Array = POINTS.filter(func(p: Dictionary) -> bool: return p["name"] != "cobra_arm")
	assert_eq(book.missing_points(_hardpoints(no_arm_hardpoint)), PackedStringArray(["cobra_arm"]),
			"a stop with its own view still needs its hardpoint")
	var hp_no_mount: StationHardpoints = StationHardpoints.from_manifest({"hardpoints": {"spin_rad_s": SPIN, "cobra_bays": [],
			"grid_mounts": [MOUNTS[0]], "lights": [], "tour_points": POINTS, "damage_sections": [],
			"main_docking_bay": {"name": "main_docking_bay", "body": "drum"}, "cargo_bay": {"name": "cargo_bay", "body": "frame"}}})
	assert_eq(book.missing_points(hp_no_mount), PackedStringArray(["defence_grid:L2"]), "the mounts the grid stop shows must exist")


func test_every_shot_holds_at_least_a_second_and_is_smooth() -> void:
	var book: TourBook = _book()
	var hp: StationHardpoints = _real_or_fixture()
	for stop_name: String in book.order:
		for variant: String in book.points[stop_name]["templates"]:
			var made: Dictionary = book.shot_for(stop_name, variant, book.resolve(stop_name, hp))
			assert_true(bool(made["ok"]), str(made.get("error", "")))
			var shot: CinematicShot = made["shot"]
			assert_gte(shot.duration_s, 1.0, "%s / %s runs %.1f s" % [stop_name, variant, shot.duration_s])
			assert_gte(shot.keys.size(), 2, "%s / %s moves" % [stop_name, variant])
			for i: int in range(1, shot.keys.size()):
				assert_gte(shot.keys[i].t - shot.keys[i - 1].t, 1.0, "%s / %s: no key flick shorter than a second" % [stop_name, variant])


func test_a_file_with_a_short_shot_or_a_missing_piece_is_refused() -> void:
	var good: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TourBook.DEFAULT_PATH))
	var short: Dictionary = good.duplicate(true)
	short["templates"]["push_in"]["keys"] = [{"t": 0.0, "at": [0, 0, 0], "aim": [0, 0, 0], "fov": 60.0},
			{"t": 0.5, "at": [0, 0, -0.1], "aim": [0, 0, 0], "fov": 60.0}]
	assert_string_contains(str(TourBook.from_dict(short)["error"]), "least hold")
	var low: Dictionary = good.duplicate(true)
	low["min_shot_s"] = 0.5
	assert_false(bool(TourBook.from_dict(low)["ok"]), "the second is a floor, not a default")
	var no_point: Dictionary = good.duplicate(true)
	no_point["points"].erase("vanes")
	assert_string_contains(str(TourBook.from_dict(no_point)["error"]), "points.vanes")
	var unknown_move: Dictionary = good.duplicate(true)
	unknown_move["points"]["vanes"]["templates"] = ["spin"]
	assert_string_contains(str(TourBook.from_dict(unknown_move)["error"]), "unknown move")
	assert_false(bool(TourBook.from_dict([])["ok"]))


func test_a_plan_is_the_stops_in_order_each_with_a_shot() -> void:
	var book: TourBook = _book()
	var plan: Array[Dictionary] = book.plan(_hardpoints(), 5)
	assert_eq(plan.size(), 7)
	for i: int in plan.size():
		assert_eq(plan[i]["point"], book.order[i])
		assert_not_null(plan[i]["shot"])
		assert_almost_eq(float(plan[i]["duration_s"]), (plan[i]["shot"] as CinematicShot).duration_s, 1e-6)
	var one: Array[Dictionary] = book.plan(_hardpoints(), 5, "defence_grid")
	assert_eq(one.size(), 1)
	assert_eq(one[0]["point"], "defence_grid")
	assert_true(book.plan(_hardpoints(), 5, "nowhere").is_empty())


func test_the_moves_come_from_a_seeded_shuffle_bag() -> void:
	var book: TourBook = _book()
	var hp: StationHardpoints = _hardpoints()
	var pool: int = (book.points["bow"]["templates"] as PackedStringArray).size()
	var seen: Array[String] = []
	var last: String = ""
	for tour: int in pool * 3:
		var variant: String = book.plan(hp, 11, "bow")[0]["variant"]
		assert_ne(variant, last, "never the same move twice in a row")
		last = variant
		seen.append(variant)
		if (tour + 1) % pool == 0:
			var round_moves: Array = seen.slice(tour + 1 - pool, tour + 1)
			var unique: Dictionary = {}
			for v: String in round_moves:
				unique[v] = true
			assert_eq(unique.size(), pool, "every move plays once before any plays again: %s" % [round_moves])
	var again: TourBook = _book()
	var replay: Array[String] = []
	for tour: int in pool * 3:
		replay.append(again.plan(hp, 11, "bow")[0]["variant"])
	assert_eq(replay, seen, "the same seed draws the same moves")
	var other: TourBook = _book()
	var differs: bool = false
	for tour: int in pool:
		differs = differs or other.plan(hp, 12, "bow")[0]["variant"] != seen[tour]
	assert_true(differs, "another seed draws another order")


# Whether `world_point` is inside the central `share` of a 16:9 frame seen from `pose`.
func _in_frame(pose: CinematicShot.Pose, world_point: Vector3, share: float) -> bool:
	var local: Vector3 = pose.transform.affine_inverse() * world_point
	var half_v: float = tan(deg_to_rad(pose.fov) * 0.5)
	return local.z < 0.0 and absf(local.y / local.z) <= half_v * share and absf(local.x / local.z) <= half_v * (16.0 / 9.0) * share


func test_the_subject_stays_in_frame_in_every_shot() -> void:
	var book: TourBook = _book()
	var station_xf := Transform3D(Basis(Vector3.UP, 0.7) * Basis(Vector3.RIGHT, 0.2), Vector3(2300.0, -140.0, 900.0))
	for hp: StationHardpoints in [_hardpoints(), _real_or_fixture()]:
		for angle: float in [0.0, 1.3, 2.9]:
			for turn: float in [0.0, PI * 0.5, PI]:
				var turns: Dictionary = {"cobra_arm": turn}
				var poser: Callable = _poser(book, hp, station_xf, _drum_xf(angle), turns)
				for stop_name: String in book.order:
					var subject: Vector3 = (book.pose_of(TourBook.subject_actor(stop_name), hp, station_xf, _drum_xf(angle), turns) as Transform3D).origin
					for variant: String in book.points[stop_name]["templates"]:
						var shot: CinematicShot = book.shot_for(stop_name, variant, book.resolve(stop_name, hp))["shot"]
						var t: float = 0.0
						while t <= shot.duration_s + 0.001:
							var pose: CinematicShot.Pose = shot.pose_at(minf(t, shot.duration_s), poser, _no_origin)
							assert_not_null(pose, "%s / %s at %.2f s can be placed" % [stop_name, variant, t])
							if pose == null:
								return
							var ok: bool = _in_frame(pose, subject, 0.6)
							assert_true(ok, "%s / %s at %.2f s: the subject is inside the central 60 percent of a 16:9 frame" % [stop_name, variant, t])
							if not ok:
								return
							t += 0.5


func test_the_defence_grid_stop_shows_its_mounts_in_every_shot() -> void:
	var book: TourBook = _book()
	var station_xf := Transform3D(Basis(Vector3.UP, 0.7), Vector3(-900.0, 300.0, 100.0))
	assert_gte((book.points["defence_grid"]["shows"] as PackedStringArray).size(), 2, "it points out more than one turret")
	var tour_point: Dictionary = {}
	for hp: StationHardpoints in [_hardpoints(), _real_or_fixture()]:
		tour_point = book.resolve("defence_grid", hp)
		for start_angle: float in [0.0, 1.9, 4.0]:
			var turn: float = book.arm_turn(hp, tour_point, start_angle, SPIN, 0.0, 9.0, 4)["turn_rad"]
			var turns: Dictionary = {"defence_grid": turn}
			for variant: String in book.points["defence_grid"]["templates"]:
				var shot: CinematicShot = book.shot_for("defence_grid", variant, tour_point)["shot"]
				var t: float = 0.0
				while t <= shot.duration_s + 0.001:
					var drum: Transform3D = _drum_xf(start_angle + SPIN * t)
					var pose: CinematicShot.Pose = shot.pose_at(minf(t, shot.duration_s), _poser(book, hp, station_xf, drum, turns), _no_origin)
					for mount_name: String in book.points["defence_grid"]["shows"]:
						var world: Variant = book.mount_point("defence_grid", mount_name, hp, station_xf, drum, turns)
						assert_not_null(world, mount_name)
						assert_true(_in_frame(pose, world as Vector3, 0.9), "defence_grid / %s at %.1f s (drum %.0f deg): mount %s is on screen" % [variant, t, rad_to_deg(start_angle), mount_name])
					t += 0.5


func test_the_arm_stop_takes_an_arm_clear_of_the_spine_for_its_whole_shot() -> void:
	var book: TourBook = _book()
	var hp: StationHardpoints = _hardpoints()
	var seen_wings: Dictionary = {}
	var tour_point: Dictionary = book.resolve("cobra_arm", hp)
	for step: int in 72:
		var drum_angle: float = TAU * float(step) / 72.0
		var pick: Dictionary = book.arm_turn(hp, tour_point, drum_angle, SPIN, 12.0, 9.0, step)
		var wing: String = pick["wing"]
		seen_wings[wing] = true
		var arm_deg: float = 0.0
		for arm: Dictionary in ARMS:
			if arm["wing"] == wing:
				arm_deg = arm["angle_deg"]
		var t: float = 0.0
		while t <= 9.0:
			for margin: float in [-20.0, 0.0, 20.0]:
				assert_false(hp.launch_blocked(arm_deg + rad_to_deg(drum_angle + SPIN * (12.0 + t)) + margin),
						"drum at %.0f deg: wing %s is clear %.1f s into its shot" % [rad_to_deg(drum_angle), wing, t])
			t += 0.5
	assert_gte(seen_wings.size(), 3, "different wings come up: %s" % [seen_wings.keys()])
	# The stop's own arm (Alpha, nearest its camera) turns by the difference of the arms' angles.
	var turned: Dictionary = book.arm_turn(hp, tour_point, 0.0, 0.0, 0.0, 9.0, 3)
	var delta_deg: float = 0.0
	for arm: Dictionary in ARMS:
		if arm["wing"] == turned["wing"]:
			delta_deg = arm["angle_deg"] - 90.0
	assert_almost_eq(rad_to_deg(float(turned["turn_rad"])), delta_deg, 0.01)
	var plan: Array[Dictionary] = book.plan(hp, 3, "cobra_arm", 0.0, 0.0)
	assert_string_contains(plan[0]["caption"], String(plan[0]["wing"]).to_upper())
	assert_false(String(plan[0]["caption"]).contains("{"), "the wing fills the caption")


func test_the_arm_stop_frames_the_strip_and_stays_upright_on_every_arm() -> void:
	var book: TourBook = _book()
	var hp: StationHardpoints = _hardpoints()
	var station_xf := Transform3D(Basis(Vector3.UP, 0.4), Vector3(100.0, 50.0, -300.0))
	var shot: CinematicShot = book.shot_for("cobra_arm", "drift_right", book.resolve("cobra_arm", hp))["shot"]
	for turn: float in [0.0, PI * 0.5, PI, PI * 1.5]:
		var drum: Transform3D = _drum_xf(0.9)
		var turns: Dictionary = {"cobra_arm": turn}
		var pose: CinematicShot.Pose = shot.pose_at(4.0, _poser(book, hp, station_xf, drum, turns), _no_origin)
		var arm_up: Vector3 = (station_xf * drum).basis * Basis(Vector3.BACK, turn) * Vector3.UP
		assert_gt(pose.transform.basis.y.dot(arm_up), 0.95, "turn %.0f deg: the picture is upright against its arm" % rad_to_deg(turn))
		# Several doors: the strip (138 m) is in view, both of its ends.
		for z: float in [-1956.0, -1818.0]:
			var end: Vector3 = station_xf * drum * Transform3D(Basis(Vector3.BACK, turn), Vector3.ZERO) * Vector3(0.0, 240.0, z)
			assert_true(_in_frame(pose, end, 0.95), "turn %.0f deg: the door strip's end at z %.0f is in frame" % [rad_to_deg(turn), z])


func test_a_drum_stop_rides_the_drum() -> void:
	var book: TourBook = _book()
	var hp: StationHardpoints = _hardpoints()
	var station_xf := Transform3D(Basis(Vector3.UP, 0.4), Vector3(100.0, 50.0, -300.0))
	var shot: CinematicShot = book.shot_for("cobra_arm", "drift_right", book.resolve("cobra_arm", hp))["shot"]
	var rel: Array[Transform3D] = []
	for angle: float in [0.0, 1.1, 2.6]:
		var drum: Transform3D = _drum_xf(angle)
		var pose: CinematicShot.Pose = shot.pose_at(3.0, _poser(book, hp, station_xf, drum), _no_origin)
		rel.append((station_xf * drum).affine_inverse() * pose.transform)
	for i: int in range(1, rel.size()):
		assert_almost_eq(rel[i].origin, rel[0].origin, Vector3.ONE * 0.01, "the camera is fixed in the drum's frame")
		assert_almost_eq(rel[i].basis.y, rel[0].basis.y, Vector3.ONE * 1e-4, "and keeps the arm's up")
	var frame_shot: CinematicShot = book.shot_for("bow", "drift_right", book.resolve("bow", hp))["shot"]
	var a: CinematicShot.Pose = frame_shot.pose_at(3.0, _poser(book, hp, station_xf, _drum_xf(0.0)), _no_origin)
	var b: CinematicShot.Pose = frame_shot.pose_at(3.0, _poser(book, hp, station_xf, _drum_xf(2.0)), _no_origin)
	assert_almost_eq(a.transform.origin, b.transform.origin, Vector3.ONE * 0.01, "a stop on the frame does not turn with the drum")


func test_a_rebase_moves_every_shot_by_the_shift_and_nothing_else() -> void:
	var book: TourBook = _book()
	var hp: StationHardpoints = _hardpoints()
	var station_xf := Transform3D(Basis(Vector3.UP, 1.0), Vector3(10.0, 20.0, 30.0))
	var shift := Vector3(-3000.0, 450.0, 1200.0)
	var shifted := Transform3D(station_xf.basis, station_xf.origin + shift)
	for stop_name: String in book.order:
		var shot: CinematicShot = book.shot_for(stop_name, "crane_up", book.resolve(stop_name, hp))["shot"]
		var before: CinematicShot.Pose = shot.pose_at(4.0, _poser(book, hp, station_xf, _drum_xf(0.5)), _no_origin)
		var after: CinematicShot.Pose = shot.pose_at(4.0, _poser(book, hp, shifted, Transform3D(Basis(Vector3.BACK, 0.5), PIVOT)), _no_origin)
		assert_almost_eq(after.transform.origin - before.transform.origin, shift, Vector3.ONE * 0.01, stop_name)
		assert_almost_eq(after.transform.basis.z, before.transform.basis.z, Vector3.ONE * 1e-4, "%s: the same aim" % stop_name)


func test_unknown_actors_have_no_pose() -> void:
	var book: TourBook = _book()
	var hp: StationHardpoints = _hardpoints()
	assert_null(book.pose_of("nowhere.stop", hp, STATION_XF, Transform3D.IDENTITY))
	assert_null(book.pose_of("bow.side", hp, STATION_XF, Transform3D.IDENTITY))
	assert_null(book.pose_of("fighter", hp, STATION_XF, Transform3D.IDENTITY))


# The camera's path keeps this far from the drawn hull (more than the near plane), in every shot, for every arm the tour may film,
# with the drum at any angle when the shot starts and turning as it plays (M7-T12, the maintainer saw a camera in a bay's walls).
const CLEAR_M: float = 2.0


func test_every_shot_keeps_the_camera_clear_of_the_hull() -> void:
	var field: StationClearance = StationClearance.load_station()
	if field == null:
		pass_test("the station is not generated here")
		return
	var book: TourBook = _book()
	var hp: StationHardpoints = _real_or_fixture()
	var worst: float = INF
	var worst_at: String = ""
	for stop_name: String in book.order:
		var tour_point: Dictionary = book.resolve(stop_name, hp)
		var turns_for: Array = [0.0]
		var angles: Array = [0.0]
		if bool(book.points[stop_name]["arm"]) or String(tour_point["body"]) == StationHardpoints.DRUM:
			angles = []
			for step: int in 24:
				angles.append(TAU * float(step) / 24.0)
		for start_angle: float in angles:
			var turns: Dictionary = {}
			if bool(book.points[stop_name]["arm"]):
				turns[stop_name] = book.arm_turn(hp, tour_point, start_angle, SPIN, 0.0, 9.0, 1)["turn_rad"]
			else:
				turns_for = [0.0]
			for variant: String in book.points[stop_name]["templates"]:
				var shot: CinematicShot = book.shot_for(stop_name, variant, tour_point)["shot"]
				var t: float = 0.0
				while t <= shot.duration_s + 0.001:
					var angle: float = start_angle + SPIN * t
					var poser: Callable = _poser(book, hp, Transform3D.IDENTITY, _drum_xf(angle, field.pivot), turns)
					var pose: CinematicShot.Pose = shot.pose_at(minf(t, shot.duration_s), poser, _no_origin)
					var gap: float = field.distance(pose.transform.origin, angle, CLEAR_M * 4.0)
					if gap < worst:
						worst = gap
						worst_at = "%s / %s at %.2f s, drum %.0f deg" % [stop_name, variant, t, rad_to_deg(start_angle)]
					assert_gte(gap, CLEAR_M, "%s / %s at %.2f s (drum %.0f deg at the start): the camera is %.2f m from the hull" % [stop_name, variant, t, rad_to_deg(start_angle), gap])
					t += 0.25
	gut.p("closest approach %.2f m (%s)" % [worst, worst_at])


# The field itself reads the hull: the doors of the Cobra bays are within their opening's half height of it, open space is not.
func test_the_clearance_field_reads_the_hull() -> void:
	var field: StationClearance = StationClearance.load_station()
	var manifest: Dictionary = MeshAssets.read_manifest("babylon5_station")
	if field == null or not manifest.has("hardpoints"):
		pass_test("the station is not generated here")
		return
	var hp: StationHardpoints = StationHardpoints.from_manifest(manifest)
	for bay_name: String in ["cobra_bay_alpha_3", "cobra_bay_beta_1", "cobra_bay_zeta_6"]:
		var door: Vector3 = hp.bay(bay_name)["door"]
		assert_lt(field.distance(field.pivot + door, 0.0, 30.0), 10.0, "%s's door is at the hull" % bay_name)
	assert_gte(field.distance(Vector3(3000.0, 3000.0, 0.0), 0.0, 30.0), 30.0, "open space is clear")
