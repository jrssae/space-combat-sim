extends GutTest
## SkyManifest: the parser for the generator's manifest.json, which supplies the sky's centroid offset.

const TEMP_PATH: String = "user://test_sky_manifest.json"


func after_each() -> void:
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))


func test_reads_the_centroid_offset() -> void:
	var manifest: SkyManifest = SkyManifest.from_json_text('{"asset_id": "sky_default", "centroid_offset": [2238.5, 1124.25, -3971.75]}')
	assert_true(manifest.valid, manifest.error)
	assert_eq(manifest.error, "")
	assert_eq(manifest.centroid_offset, Vector3(2238.5, 1124.25, -3971.75))


func test_integers_are_accepted() -> void:
	var manifest: SkyManifest = SkyManifest.from_json_text('{"centroid_offset": [1, -2, 3]}')
	assert_true(manifest.valid, manifest.error)
	assert_eq(manifest.centroid_offset, Vector3(1.0, -2.0, 3.0))


func test_a_missing_offset_is_reported_and_stays_zero() -> void:
	var manifest: SkyManifest = SkyManifest.from_json_text('{"asset_id": "sky_default"}')
	assert_false(manifest.valid)
	assert_string_contains(manifest.error, "centroid_offset")
	assert_eq(manifest.centroid_offset, Vector3.ZERO)


func test_malformed_offsets_are_rejected() -> void:
	for text: String in [
		'{"centroid_offset": [1, 2]}',
		'{"centroid_offset": [1, 2, 3, 4]}',
		'{"centroid_offset": "1 2 3"}',
		'{"centroid_offset": [1, "2", 3]}',
		'{"centroid_offset": [1, null, 3]}',
		'{"centroid_offset": null}',
	]:
		var manifest: SkyManifest = SkyManifest.from_json_text(text)
		assert_false(manifest.valid, "should reject %s" % text)
		assert_ne(manifest.error, "", "should explain %s" % text)
		assert_eq(manifest.centroid_offset, Vector3.ZERO, "offset stays zero for %s" % text)


func test_broken_json_and_a_non_object_root_are_rejected() -> void:
	for text: String in ["", "{", "not json", "[1, 2, 3]", "42"]:
		var manifest: SkyManifest = SkyManifest.from_json_text(text)
		assert_false(manifest.valid, "should reject '%s'" % text)
		assert_ne(manifest.error, "", "should explain '%s'" % text)


func test_load_file_reads_a_manifest_from_disk() -> void:
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	assert_not_null(file, "user:// is writable")
	file.store_string('{"centroid_offset": [10.5, 20.5, -30.5]}')
	file.close()
	var manifest: SkyManifest = SkyManifest.load_file(TEMP_PATH)
	assert_true(manifest.valid, manifest.error)
	assert_eq(manifest.centroid_offset, Vector3(10.5, 20.5, -30.5))


func test_load_file_on_a_missing_file_points_at_gen_assets() -> void:
	var manifest: SkyManifest = SkyManifest.load_file("user://no_such_manifest.json")
	assert_false(manifest.valid)
	assert_string_contains(manifest.error, "gen_assets.sh")
	assert_eq(manifest.centroid_offset, Vector3.ZERO)
