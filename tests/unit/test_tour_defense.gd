extends GutTest
## The station tour's "Defense" stop (M7-T57): player-visible text spells it with an s, and the grid stop films the guns from the
## side they face (the bow side), not from behind.

const SHOWN_DIRS: Array[String] = ["res://data", "res://src"]
# The guns of an arm's head face the bow (-Z in the drum's frame): their facets tilt that way.
const GUNS_FACING: Vector3 = Vector3(0.0, 0.0, -1.0)


# Every file under `dir` with one of `extensions`, recursively.
func _files(dir: String, extensions: PackedStringArray, out: PackedStringArray) -> void:
	for sub: String in DirAccess.get_directories_at(dir):
		_files(dir.path_join(sub), extensions, out)
	for file: String in DirAccess.get_files_at(dir):
		if extensions.has(file.get_extension()):
			out.append(dir.path_join(file))


func test_no_player_visible_text_uses_the_british_spelling() -> void:
	var files := PackedStringArray()
	for dir: String in SHOWN_DIRS:
		_files(dir, PackedStringArray(["json", "tscn", "tres", "gd", "txt", "cfg"]), files)
	assert_gt(files.size(), 100, "the scan found the project's files")
	var found := PackedStringArray()
	var british: String = "defen" + "ce"  # spelled apart so the repository-wide rename check stays clean
	for path: String in files:
		var is_code: bool = path.get_extension() == "gd"
		var number: int = 0
		for line: String in FileAccess.get_file_as_string(path).split("\n"):
			number += 1
			# Comments are code, not text on screen.
			if is_code and line.strip_edges().begins_with("#"):
				continue
			if line.to_lower().contains(british):
				found.append("%s:%d" % [path, number])
	assert_eq(found, PackedStringArray(), "player-visible text uses the British spelling")


func test_the_grid_stop_caption_says_defense() -> void:
	var made: Dictionary = TourBook.load_file()
	assert_true(bool(made["ok"]), str(made.get("error", "")))
	var book: TourBook = made["book"]
	assert_string_contains(String(book.points["defense_grid"]["caption"]), "DEFENSE GRID")


# The grid stops, from the front: the arm head's light turrets and interceptor battery, then the bow tower's cannons and battery.
const GRID_STOPS: Array[String] = ["defense_grid", "heavy_cannons"]
# The widest field of view a stop's moves open with (station_tour.json's push_in) and the picture's aspect.
const WIDEST_FOV_DEG: float = 62.0
const ASPECT: float = 16.0 / 9.0


func test_the_grid_stop_cameras_are_on_the_guns_front_side() -> void:
	var made: Dictionary = TourBook.load_file()
	var book: TourBook = made["book"]
	var manifest: Dictionary = MeshAssets.read_manifest("babylon5_station")
	var hp: StationHardpoints = StationHardpoints.from_manifest(manifest) if manifest.has("hardpoints") else null
	if hp == null or not hp.valid:
		pending("the station asset is not built here")
		return
	for stop_name: String in GRID_STOPS:
		var entry: Dictionary = book.points[stop_name]
		var camera: Vector3 = entry["camera"]
		var look: Vector3 = ((entry["subject"] as Vector3) - camera).normalized()
		var half_v: float = tan(deg_to_rad(WIDEST_FOV_DEG) * 0.5)
		var kinds := PackedStringArray()
		for mount_name: String in entry["shows"]:
			var mount: Dictionary = hp.mount(mount_name)
			var at: Vector3 = mount["position"]
			kinds.append(String(mount["kind"]))
			# A light turret's facets tilt toward the bow, the side its guns face; the others stand level on the bow side of the head.
			if String(mount["kind"]) == "light_pulse":
				assert_gt((mount["up"] as Vector3).dot(GUNS_FACING), 0.0, "mount %s tilts toward the bow" % mount_name)
			assert_gt((camera - at).dot(GUNS_FACING), 0.0, "%s: the camera stands in front of %s" % [stop_name, mount_name])
			# The mount is inside the opening picture (90 percent of it, so the moves' drift keeps it).
			var local: Vector3 = Basis.looking_at(look, Vector3.UP).inverse() * (at - camera)
			assert_lt(local.z, 0.0, "%s: %s is ahead of the camera" % [stop_name, mount_name])
			assert_lte(absf(local.y / local.z), half_v * 0.9, "%s: %s is inside the frustum vertically" % [stop_name, mount_name])
			assert_lte(absf(local.x / local.z), half_v * ASPECT * 0.9, "%s: %s is inside the frustum sideways" % [stop_name, mount_name])
		if stop_name == "defense_grid":
			assert_true(kinds.has("light_pulse") and kinds.has("interceptor"), "the arm head's turrets and battery")
		else:
			assert_true(kinds.has("heavy_cannon") and kinds.has("interceptor"), "the heavy cannons and the tower's battery")
		assert_lt(look.dot(GUNS_FACING), 0.0, "%s looks back at the guns" % stop_name)


func test_the_grid_stop_captions_name_what_they_show() -> void:
	var made: Dictionary = TourBook.load_file()
	var book: TourBook = made["book"]
	assert_string_contains(String(book.points["defense_grid"]["caption"]), "INTERCEPTOR")
	assert_string_contains(String(book.points["heavy_cannons"]["caption"]), "HEAVY CANNONS")
	assert_string_contains(String(book.points["heavy_cannons"]["caption"]), "DEFENSE GRID")
