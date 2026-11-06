extends GutTest
## ManifestReader (tests/fixtures): the manifest.json parser behind the asset tests.

const VALID: String = """{
	"asset_id": "thing", "generator_version": 1, "seed": 42, "frame": "godot", "units": "m",
	"aabb_min": [-3.0, -2.0, -6.0], "aabb_max": [1.0, 4.0, 2.5],
	"centroid_offset": [0.0, 0.5, 1.25],
	"files": {"obj": "thing.obj", "mesh": "thing.glb", "hardpoints": "hardpoints.json"}
}"""


func _read(replacements: Dictionary = {}) -> ManifestReader:
	var text: String = VALID
	for from: String in replacements:
		assert_true(text.contains(from), "test bug: VALID has no '%s'" % from)
		text = text.replace(from, str(replacements[from]))
	return ManifestReader.from_json_text(text, "thing")


func test_reads_a_valid_manifest() -> void:
	var reader: ManifestReader = _read()
	assert_true(reader.is_valid(), reader.errors_text())
	assert_eq(reader.asset_id, "thing")
	assert_eq(reader.kind, "asset")
	assert_eq(reader.aabb.position, Vector3(-3.0, -2.0, -6.0))
	assert_eq(reader.aabb.end, Vector3(1.0, 4.0, 2.5))
	assert_eq(reader.centroid_offset, Vector3(0.0, 0.5, 1.25))
	assert_eq(reader.files["hardpoints"], "hardpoints.json")


func test_paths_join_the_directory_and_file_names() -> void:
	var reader: ManifestReader = _read()
	reader.directory = "res://assets/generated/thing"
	assert_eq(reader.file_path("mesh"), "res://assets/generated/thing/thing.glb")
	assert_eq(reader.file_path("obj"), "res://assets/generated/thing/thing.obj")
	assert_eq(reader.file_path("panorama"), "", "an absent role has no path")


func test_load_dir_on_a_missing_directory_points_at_gen_assets() -> void:
	var reader: ManifestReader = ManifestReader.load_dir("res://assets/generated/no_such_asset/")
	assert_false(reader.is_valid())
	assert_eq(reader.asset_id, "no_such_asset")
	assert_string_contains(reader.errors_text(), "gen_assets.sh")


func test_broken_json_and_a_non_object_root_are_rejected() -> void:
	for text: String in ["", "{", "[1, 2]", "42"]:
		var reader: ManifestReader = ManifestReader.from_json_text(text, "thing")
		assert_false(reader.is_valid(), "should reject '%s'" % text)
		assert_false(reader.errors_text().is_empty(), "should explain '%s'" % text)


func test_wrong_identity_frame_or_units_are_rejected() -> void:
	assert_false(_read({'"asset_id": "thing"': '"asset_id": "other"'}).is_valid(), "asset_id must match the directory")
	assert_false(_read({'"frame": "godot"': '"frame": "3dgs"'}).is_valid(), "frame must be godot")
	assert_false(_read({'"units": "m"': '"units": "cm"'}).is_valid(), "units must be metres")


func test_an_unknown_kind_is_rejected() -> void:
	assert_false(_read({'"units": "m",': '"units": "m", "kind": "points",'}).is_valid(), "asset or audio only")


func test_bad_vectors_are_rejected() -> void:
	assert_false(_read({'[-3.0, -2.0, -6.0]': '[-3.0, -2.0]'}).is_valid(), "aabb_min needs three numbers")
	assert_false(_read({'[0.0, 0.5, 1.25]': '[0.0, "0.5", 1.25]'}).is_valid(), "centroid_offset needs numbers")
	assert_false(_read({'[1.0, 4.0, 2.5]': '[-4.0, 4.0, 2.5]'}).is_valid(), "aabb_max must be above aabb_min")


func test_bad_files_are_rejected() -> void:
	assert_false(_read({'"obj": "thing.obj"': '"obj": 7'}).is_valid(), "file names are strings")
	assert_false(_read({'"files": {': '"nofiles": {'}).is_valid(), "files is required")
