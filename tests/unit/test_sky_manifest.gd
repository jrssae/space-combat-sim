extends GutTest
## SkyManifest: the parser for the generator's manifest.json, which describes the star file and the panorama (M4-T30c).

const TEMP_PATH: String = "user://test_sky_manifest.json"
const STAR_FIELD: String = '"star_field": {"file": "sky_default_stars.f32", "count": 12000, "format": "float32 little-endian", "record": ["dir_x", "dir_y", "dir_z", "red", "green", "blue", "brightness"], "radius_mrad": 0.5, "floor_px": 1.0}'


func after_each() -> void:
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))


func _with_field(replace_from: String, replace_to: String) -> String:
	return "{%s}" % STAR_FIELD.replace(replace_from, replace_to)


func test_reads_the_star_field_and_the_panorama() -> void:
	var manifest: SkyManifest = SkyManifest.from_json_text('{"asset_id": "sky_default", "files": {"panorama": "sky_default_panorama.png", "stars": "sky_default_stars.f32"}, %s}' % STAR_FIELD)
	assert_true(manifest.valid, manifest.error)
	assert_eq(manifest.error, "")
	assert_eq(manifest.star_file, "sky_default_stars.f32")
	assert_eq(manifest.star_count, 12000)
	assert_almost_eq(manifest.star_radius_mrad, 0.5, 1e-6)
	assert_almost_eq(manifest.star_floor_px, 1.0, 1e-6)
	assert_eq(manifest.panorama_file, "sky_default_panorama.png")


func test_the_panorama_is_optional() -> void:
	var manifest: SkyManifest = SkyManifest.from_json_text("{%s}" % STAR_FIELD)
	assert_true(manifest.valid, manifest.error)
	assert_eq(manifest.panorama_file, "")


func test_a_manifest_without_a_star_field_is_reported() -> void:
	var manifest: SkyManifest = SkyManifest.from_json_text('{"asset_id": "sky_default", "centroid_offset": [1, 2, 3]}')
	assert_false(manifest.valid)
	assert_string_contains(manifest.error, "star_field")
	assert_eq(manifest.star_count, 0)


func test_malformed_star_fields_are_rejected() -> void:
	for text: String in [
		_with_field('"count": 12000', '"count": 0'),
		_with_field('"count": 12000', '"count": "many"'),
		_with_field('"file": "sky_default_stars.f32"', '"file": 3'),
		_with_field('"radius_mrad": 0.5', '"radius_mrad": -1'),
		_with_field('"floor_px": 1.0', '"floor_px": 0'),
		_with_field('"blue", "brightness"', '"brightness", "blue"'),
		_with_field('"float32 little-endian"', '"float64"'),
		'{"star_field": null}',
	]:
		var manifest: SkyManifest = SkyManifest.from_json_text(text)
		assert_false(manifest.valid, "should reject %s" % text)
		assert_ne(manifest.error, "", "should explain %s" % text)


func test_broken_json_and_a_non_object_root_are_rejected() -> void:
	for text: String in ["", "{", "not json", "[1, 2, 3]", "42"]:
		var manifest: SkyManifest = SkyManifest.from_json_text(text)
		assert_false(manifest.valid, "should reject '%s'" % text)
		assert_ne(manifest.error, "", "should explain '%s'" % text)


func test_load_file_reads_a_manifest_from_disk() -> void:
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	assert_not_null(file, "user:// is writable")
	file.store_string("{%s}" % STAR_FIELD)
	file.close()
	var manifest: SkyManifest = SkyManifest.load_file(TEMP_PATH)
	assert_true(manifest.valid, manifest.error)
	assert_eq(manifest.star_count, 12000)


func test_load_file_on_a_missing_file_points_at_gen_assets() -> void:
	var manifest: SkyManifest = SkyManifest.load_file("user://no_such_manifest.json")
	assert_false(manifest.valid)
	assert_string_contains(manifest.error, "gen_assets.sh")
	assert_eq(manifest.star_count, 0)
