extends GutTest
## ManifestReader (tests/fixtures): the manifest.json parser and the Godot-to-imported AABB transform behind the
## asset import tests.

const VALID: String = """{
	"asset_id": "thing", "generator_version": 1, "seed": 42, "frame": "godot", "units": "m",
	"lods": [{"level": 0, "file": "thing.ply", "splats": 1200, "spacing_m": 0.05},
	         {"level": 1, "file": "thing_lod1.ply", "splats": 300, "spacing_m": 0.1}],
	"aabb_min": [-3.0, -2.0, -6.0], "aabb_max": [1.0, 4.0, 2.5],
	"centroid_offset": [0.0, 0.5, 1.25],
	"files": {"fallback_mesh": "thing.obj", "hardpoints": "hardpoints.json"}
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
	assert_eq(reader.lods.size(), 2)
	assert_eq(reader.lods[0]["splats"], 1200)
	assert_eq(reader.lods[0]["file"], "thing.ply")
	assert_eq(reader.lods[1]["level"], 1)
	assert_almost_eq(float(reader.lods[0]["spacing_m"]), 0.05, 1e-9)
	assert_eq(reader.aabb.position, Vector3(-3.0, -2.0, -6.0))
	assert_eq(reader.aabb.end, Vector3(1.0, 4.0, 2.5))
	assert_eq(reader.centroid_offset, Vector3(0.0, 0.5, 1.25))
	assert_eq(reader.files["hardpoints"], "hardpoints.json")


func test_paths_join_the_directory_and_file_names() -> void:
	var reader: ManifestReader = _read()
	reader.directory = "res://assets/generated/thing"
	assert_eq(reader.lod_path(reader.lods[1]), "res://assets/generated/thing/thing_lod1.ply")
	assert_eq(reader.file_path("fallback_mesh"), "res://assets/generated/thing/thing.obj")
	assert_eq(reader.file_path("panorama"), "", "an absent role has no path")


func test_the_imported_aabb_negates_x_and_y_and_keeps_z() -> void:
	var imported: AABB = _read().imported_aabb()
	assert_eq(imported.position, Vector3(-1.0, -4.0, -6.0), "min' = (-max.x, -max.y, min.z)")
	assert_eq(imported.end, Vector3(3.0, 2.0, 2.5), "max' = (-min.x, -min.y, max.z)")
	assert_eq(imported.size, _read().aabb.size, "a rotation keeps the size")


func test_a_symmetric_box_is_unchanged_and_the_flip_is_its_own_inverse() -> void:
	var symmetric := AABB(Vector3(-3.8, -3.8, -6.5), Vector3(7.6, 7.6, 9.65))
	assert_eq(ManifestReader.godot_to_imported_aabb(symmetric), symmetric)
	var box := AABB(Vector3(-22228.8, -21111.2, -17875.7), Vector3(39988.6, 39986.7, 41847.1))
	assert_true(ManifestReader.godot_to_imported_aabb(ManifestReader.godot_to_imported_aabb(box)).is_equal_approx(box), "Rz(180) twice is the identity")
	assert_false(ManifestReader.godot_to_imported_aabb(box).is_equal_approx(box), "an asymmetric box changes")


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


func test_bad_lods_are_rejected() -> void:
	assert_false(_read({'"splats": 1200': '"splats": 1200.5'}).is_valid(), "fractional splat count")
	assert_false(_read({'"splats": 1200': '"splats": 0'}).is_valid(), "empty lod")
	assert_false(_read({'"file": "thing.ply"': '"file": "thing.splat"'}).is_valid(), "lod is not a PLY")
	assert_false(_read({'"level": 0': '"level": 1'}).is_valid(), "levels must start at 0")
	assert_false(_read({'"level": 1': '"level": 0'}).is_valid(), "levels must increase")
	assert_false(_read({'"lods": [': '"nolods": ['}).is_valid(), "lods is required")


func test_bad_vectors_are_rejected() -> void:
	assert_false(_read({'[-3.0, -2.0, -6.0]': '[-3.0, -2.0]'}).is_valid(), "aabb_min needs three numbers")
	assert_false(_read({'[0.0, 0.5, 1.25]': '[0.0, "0.5", 1.25]'}).is_valid(), "centroid_offset needs numbers")
	assert_false(_read({'[1.0, 4.0, 2.5]': '[-4.0, 4.0, 2.5]'}).is_valid(), "aabb_max must be above aabb_min")


func test_bad_files_are_rejected() -> void:
	assert_false(_read({'"fallback_mesh": "thing.obj"': '"fallback_mesh": 7'}).is_valid(), "file names are strings")
	assert_false(_read({'"files": {': '"nofiles": {'}).is_valid(), "files is required")
