extends GutTest
## The maintainer's rule (2026-11-19, M8-T30): no single camera angle lasts 3 s or more, unless the shot is flagged
## `feature: true` (an interesting one), which may run to 5 s; the flagged shots are listed for the reviewer. None is shorter than
## 1 s. Every shot written as
## data is read here:
## any object with `keys` of camera frames, or `takes` of them, anywhere in `data/` (launch pools, scenario cinematics, docking
## shots, tour moves, gate pools) and in the mission fixtures, plus the shots the launch profiles and the tour build from them.
## A take of a shot is one camera angle; a long sequence is several takes cut together.

const ROOTS: PackedStringArray = ["res://data", "res://tests/fixtures/missions"]


func test_every_shot_in_the_data_keeps_each_angle_under_three_seconds() -> void:
	var checked: int = 0
	var featured := PackedStringArray()
	for path: String in _json_files():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		for found: Dictionary in _shots_in(data, path):
			var longest: float = 0.0
			for take: Array in found["takes"]:
				var last: Dictionary = take[-1]
				var length: float = float(last["t"]) - float((take[0] as Dictionary)["t"])
				longest = maxf(longest, length)
				assert_gte(length, CinematicShot.MIN_TAKE_S, "%s: an angle lasts only %.2f s" % [found["where"], length])
				if bool(found["feature"]):
					assert_lte(length, CinematicShot.MAX_FEATURE_S, "%s (feature): an angle lasts %.1f s" % [found["where"], length])
				else:
					assert_lt(length, CinematicShot.MAX_TAKE_S, "%s: an angle lasts %.1f s (flag it a feature if it earns it)" % [
							found["where"], length])
				checked += 1
			if bool(found["feature"]):
				featured.append("%s (%.1f s)" % [found["where"], longest])
	assert_gt(checked, 60, "the shots were found (%d angles)" % checked)
	gut.p("Feature shots allowed past 3 s, for the reviewer: %d\n  %s" % [featured.size(), "\n  ".join(featured)])
	print("[shot lengths] feature shots: ", ", ".join(featured))


func test_the_launch_pools_and_the_tour_build_short_angles() -> void:
	for path: String in [LaunchProfile.DEFAULT_PATH, LaunchDirector.EXTERIOR_PATH, SquadronLaunch.DEFAULT_PATH]:
		var made: Dictionary = LaunchProfile.load_file(path)
		assert_true(bool(made["ok"]), str(made.get("error", "")))
		if not bool(made["ok"]):
			continue
		var pool: LaunchProfile = made["profile"]
		assert_lt(pool.row_max_s, CinematicShot.MAX_TAKE_S, "%s: a row shot's hold" % path)
		for phase: Dictionary in pool.phases:
			for variant: Dictionary in phase["variants"]:
				assert_true((variant["shot"] as CinematicShot).keeps_length_rule(), "%s: %s, as held (%.1f s)" % [path, variant["id"],
						(variant["shot"] as CinematicShot).longest_take_s()])
	var made_tour: Dictionary = TourBook.load_file()
	assert_true(bool(made_tour["ok"]))
	var book: TourBook = made_tour["book"]
	var stop := {"position": Vector3.ZERO, "look_at": Vector3(0.0, 0.0, -500.0)}
	for point: String in book.points:
		for variant: String in book.points[point]["templates"]:
			var built: Dictionary = book.shot_for(point, variant, stop)
			assert_true(bool(built["ok"]), str(built.get("error", "")))
			var shot: CinematicShot = built["shot"]
			assert_lt(shot.longest_take_s(), CinematicShot.MAX_TAKE_S, "tour %s %s" % [point, variant])
			assert_gt(shot.take_count(), 1, "tour %s: the stop cuts between moves" % point)


func test_a_long_angle_is_refused_by_a_launch_profile() -> void:
	var raw: Dictionary = {"phases": [{"phase": "rack", "step": "door", "variants": [
		{"id": "long", "keys": [{"t": 0, "position": {"actor": "bay"}, "look_at": {"actor": "fighter"}},
				{"t": 3.5, "position": {"actor": "bay"}, "look_at": {"actor": "fighter"}}]}]}]}
	assert_false(bool(LaunchProfile.from_dict(raw)["ok"]), "a 3.5 s angle")
	raw["phases"][0]["variants"][0]["feature"] = true
	var featured: Dictionary = LaunchProfile.from_dict(raw)
	assert_true(bool(featured["ok"]), "a 3.5 s feature shot: %s" % featured.get("error", ""))
	raw["phases"][0]["variants"][0]["keys"][1]["t"] = 5.5
	assert_false(bool(LaunchProfile.from_dict(raw)["ok"]), "but not 5.5 s")


func _json_files() -> PackedStringArray:
	var out := PackedStringArray()
	var stack: Array[String] = []
	stack.append_array(ROOTS)
	while not stack.is_empty():
		var dir_path: String = stack.pop_back()
		for sub: String in DirAccess.get_directories_at(dir_path):
			stack.append(dir_path.path_join(sub))
		for file: String in DirAccess.get_files_at(dir_path):
			if file.ends_with(".json"):
				out.append(dir_path.path_join(file))
	return out


# Every camera shot in a parsed JSON value: `{where, takes: [[frame, ...], ...]}`. A frame has a time `t` and a place
# (`position`, or a tour move's `at`).
func _shots_in(value: Variant, where: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if value is Dictionary:
		var d: Dictionary = value
		var feature: bool = bool(d.get("feature", false))
		if _is_frames(d.get("keys")):
			out.append({"where": "%s %s" % [where, d.get("id", "")], "takes": [d["keys"]], "feature": feature})
		elif d.get("takes") is Array:
			var takes: Array = []
			for take: Variant in d["takes"]:
				if take is Dictionary and _is_frames((take as Dictionary).get("keys")):
					takes.append((take as Dictionary)["keys"])
			out.append({"where": where, "takes": takes, "feature": feature})
		else:
			for key: Variant in d:
				out.append_array(_shots_in(d[key], "%s/%s" % [where, key]))
	elif value is Array:
		for i: int in (value as Array).size():
			out.append_array(_shots_in((value as Array)[i], "%s[%d]" % [where, i]))
	return out


static func _is_frames(value: Variant) -> bool:
	if not value is Array or (value as Array).is_empty() or not (value as Array)[0] is Dictionary:
		return false
	var first: Dictionary = (value as Array)[0]
	return first.has("t") and (first.has("position") or first.has("at"))
