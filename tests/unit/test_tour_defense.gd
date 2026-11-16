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


func test_no_player_visible_text_says_defence() -> void:
	var files := PackedStringArray()
	for dir: String in SHOWN_DIRS:
		_files(dir, PackedStringArray(["json", "tscn", "tres", "gd", "txt", "cfg"]), files)
	assert_gt(files.size(), 100, "the scan found the project's files")
	var found := PackedStringArray()
	for path: String in files:
		var is_code: bool = path.get_extension() == "gd"
		var number: int = 0
		for line: String in FileAccess.get_file_as_string(path).split("\n"):
			number += 1
			# Comments and the stop's id are code, not text on screen.
			if is_code and line.strip_edges().begins_with("#"):
				continue
			if line.replace("defence_grid", "").to_lower().contains("defence"):
				found.append("%s:%d" % [path, number])
	assert_eq(found, PackedStringArray(), "player-visible text says Defense")


func test_the_grid_stop_caption_says_defense() -> void:
	var made: Dictionary = TourBook.load_file()
	assert_true(bool(made["ok"]), str(made.get("error", "")))
	var book: TourBook = made["book"]
	assert_string_contains(String(book.points["defence_grid"]["caption"]), "DEFENSE GRID")


func test_the_grid_stop_camera_is_on_the_guns_front_side() -> void:
	var made: Dictionary = TourBook.load_file()
	var book: TourBook = made["book"]
	var entry: Dictionary = book.points["defence_grid"]
	var camera: Vector3 = entry["camera"]
	var centre := Vector3.ZERO
	var shown: PackedStringArray = entry["shows"]
	var manifest: Dictionary = MeshAssets.read_manifest("babylon5_station")
	var hp: StationHardpoints = StationHardpoints.from_manifest(manifest) if manifest.has("hardpoints") else null
	if hp == null or not hp.valid:
		pending("the station asset is not built here")
		return
	for mount_name: String in shown:
		var mount: Dictionary = hp.mount(mount_name)
		centre += mount["position"] as Vector3
		assert_gt((mount["up"] as Vector3).dot(GUNS_FACING), 0.0, "mount %s tilts toward the bow" % mount_name)
	centre /= float(shown.size())
	assert_gt((camera - centre).dot(GUNS_FACING), 0.0, "the camera stands in front of the guns")
	var look: Vector3 = (entry["subject"] as Vector3) - camera
	assert_lt(look.dot(GUNS_FACING), 0.0, "and looks back at them")
