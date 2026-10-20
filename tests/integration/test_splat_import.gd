extends GutTest
## AC4 (M1-T05): every generated asset under res://assets/generated/ imports headless and agrees with its
## manifest. The directories are discovered, not listed, so `nav_buoy` (T14) is covered the day it is generated.
##
## Frames, checked against the real files (raw PLY bytes, the GDGS importer and the manifest agree to < 1e-4 m):
##   - The generator writes the PLY with x and y negated (Rz 180 deg of the Godot frame), centred on the splat
##     centroid, so the mean GDGS subtracts is ~0 (sky_default 2e-6 m, starfury_aurora 5e-10 m).
##   - GDGS imports positions as written, minus their mean, and does not flip: the Rz(180) is applied later by
##     `GaussianSplatNode._enter_tree` at identity basis. So `GaussianResource.aabb` is the manifest AABB with x and
##     y negated and min/max re-sorted: min' = (-max.x, -max.y, min.z), max' = (-min.x, -min.y, max.z), no
##     translation.
##   - sky_default is the asymmetric witness (manifest x -22228.8..17759.8 imports as -17759.8..22228.8);
##     starfury_aurora is x/y symmetric, so only the sky would catch a missing flip.
## Fallback OBJs and hardpoints.json stay in the Godot frame (no flip). Nothing here needs a GPU.

const GENERATED_DIR: String = "res://assets/generated"
const GEN_ASSETS_HINT: String = "run scripts/gen_assets.sh, then scripts/run_tests.sh (it imports first)"
## AC4: the imported AABB matches the manifest within 1 cm.
const AABB_TOLERANCE_M: float = 0.01
## A mesh or hardpoint is in the splat frame when its bounds sit within this of the splat bounds (or twice the splat
## spacing, if larger): surface samples are not placed exactly on the extremes.
const FRAME_SLACK_M: float = 0.05
## Assets that must exist after gen_assets.sh (AC3), with the manifest `files` roles each must provide. A missing
## directory is a failure even though other assets exist. M1-T14 adds nav_buoy here.
const REQUIRED_ROLES: Dictionary = {
	"sky_default": [],
	"starfury_aurora": ["fallback_mesh", "cockpit_mesh", "hardpoints"],
	"nav_buoy": ["hardpoints"],
}

var _readers: Array[ManifestReader] = []
var _gaussians: Dictionary[String, GaussianResource] = {}


func before_all() -> void:
	_readers.clear()
	if not DirAccess.dir_exists_absolute(GENERATED_DIR):
		return
	var names: PackedStringArray = DirAccess.get_directories_at(GENERATED_DIR)
	names.sort()
	for dir_name: String in names:
		_readers.append(ManifestReader.load_dir("%s/%s" % [GENERATED_DIR, dir_name]))


func after_all() -> void:
	_readers.clear()
	_gaussians.clear()


# --- discovery and manifests -------------------------------------------------------------------------------------


func test_generated_assets_exist() -> void:
	assert_false(_readers.is_empty(), "no asset directories under %s: %s" % [GENERATED_DIR, GEN_ASSETS_HINT])
	for asset_id: String in REQUIRED_ROLES:
		assert_true(_reader_for(asset_id) != null, "%s has not been generated: %s" % [asset_id, GEN_ASSETS_HINT])


func test_manifests_are_valid() -> void:
	for reader: ManifestReader in _readers:
		assert_true(reader.is_valid(), "%s manifest: %s" % [reader.asset_id, reader.errors_text()])


func test_required_assets_provide_their_files() -> void:
	for asset_id: String in REQUIRED_ROLES:
		var reader: ManifestReader = _reader_for(asset_id)
		if reader == null or not reader.is_valid():
			continue  # reported by the tests above
		for role: String in REQUIRED_ROLES[asset_id]:
			assert_true(reader.files.has(role), "%s manifest has no files.%s (AC3)" % [asset_id, role])


func test_every_listed_file_exists_and_every_ply_is_a_lod() -> void:
	for reader: ManifestReader in _valid_readers():
		var lod_files: PackedStringArray = PackedStringArray()
		for lod: Dictionary in reader.lods:
			lod_files.append(lod["file"])
			assert_true(FileAccess.file_exists(reader.lod_path(lod)), "%s lod %s is missing: %s" % [reader.asset_id, lod["file"], GEN_ASSETS_HINT])
		for role: String in reader.files:
			assert_true(FileAccess.file_exists(reader.file_path(role)), "%s files.%s (%s) is missing: %s" % [reader.asset_id, role, reader.files[role], GEN_ASSETS_HINT])
		for file_name: String in DirAccess.get_files_at(reader.directory):
			if file_name.ends_with(".ply"):
				assert_true(lod_files.has(file_name), "%s/%s is a PLY that no manifest lod lists" % [reader.asset_id, file_name])


# --- splats ------------------------------------------------------------------------------------------------------


func test_plys_import_with_the_manifest_splat_count() -> void:
	for reader: ManifestReader in _valid_readers():
		for lod: Dictionary in reader.lods:
			var gaussian: GaussianResource = _gaussian(reader.lod_path(lod))
			if gaussian == null:
				continue
			var label: String = "%s lod %d" % [reader.asset_id, lod["level"]]
			assert_eq(gaussian.point_count, lod["splats"], "%s: point_count vs manifest splats" % label)
			assert_eq(gaussian.xyz.size(), gaussian.point_count, "%s: one position per splat" % label)
			assert_eq(gaussian.point_data_float.size(), gaussian.point_count * 60, "%s: 60 floats per splat" % label)


func test_ply_aabb_is_the_manifest_aabb_rotated_180_about_z() -> void:
	for reader: ManifestReader in _valid_readers():
		var gaussian: GaussianResource = _gaussian(reader.lod_path(reader.lods[0]))
		if gaussian == null:
			continue
		assert_true(gaussian.aabb.has_volume(), "%s: the imported AABB has volume" % reader.asset_id)
		_assert_aabb_near(gaussian.aabb, reader.imported_aabb(), AABB_TOLERANCE_M, "%s: imported AABB vs manifest with x and y negated" % reader.asset_id)


func test_sky_manifest_parser_reads_the_real_sky_manifest() -> void:
	var reader: ManifestReader = _reader_for("sky_default")
	if reader == null or not reader.is_valid():
		return  # reported by the tests above
	var sky: SkyManifest = SkyManifest.load_file(reader.directory + "/manifest.json")
	assert_true(sky.valid, "SkyManifest accepts the generated manifest: %s" % sky.error)
	assert_eq(sky.centroid_offset, reader.centroid_offset, "SkyManifest and the reader agree on centroid_offset")


# --- fallback meshes, textures, hardpoints -----------------------------------------------------------------------


func test_obj_meshes_import_as_meshes() -> void:
	for reader: ManifestReader in _valid_readers():
		for file_name: String in DirAccess.get_files_at(reader.directory):
			if not file_name.ends_with(".obj"):
				continue
			var mesh: Mesh = _mesh("%s/%s" % [reader.directory, file_name])
			if mesh == null:
				continue
			var label: String = "%s/%s" % [reader.asset_id, file_name]
			assert_gt(mesh.get_surface_count(), 0, "%s has surfaces" % label)
			var vertices: int = 0
			for surface: int in mesh.get_surface_count():
				vertices += mesh.surface_get_array_len(surface)
			assert_gt(vertices, 0, "%s has vertices" % label)
			assert_true(mesh.get_aabb().has_volume(), "%s has a bounding box with volume, got %s" % [label, mesh.get_aabb()])


func test_obj_meshes_share_the_splat_frame() -> void:
	for reader: ManifestReader in _valid_readers():
		var slack: float = maxf(FRAME_SLACK_M, 2.0 * float(reader.lods[0]["spacing_m"]))
		for role: String in reader.files:
			if not reader.files[role].ends_with(".obj"):
				continue
			var mesh: Mesh = _mesh(reader.file_path(role))
			if mesh == null:
				continue
			var label: String = "%s files.%s" % [reader.asset_id, role]
			if role == "fallback_mesh":
				# The whole hull: same bounds as the splat centres, in the Godot frame (not flipped).
				_assert_aabb_near(mesh.get_aabb(), reader.aabb, slack, "%s: mesh AABB vs manifest AABB" % label)
			else:
				assert_true(reader.aabb.grow(slack).encloses(mesh.get_aabb()), "%s: mesh AABB %s lies inside the manifest AABB %s" % [label, mesh.get_aabb(), reader.aabb])


func test_png_files_import_as_textures() -> void:
	for reader: ManifestReader in _valid_readers():
		for role: String in reader.files:
			if not reader.files[role].ends_with(".png"):
				continue
			var path: String = reader.file_path(role)
			if not _is_imported(path):
				continue
			var texture: Texture2D = load(path) as Texture2D
			assert_not_null(texture, "%s files.%s (%s) loads as a Texture2D" % [reader.asset_id, role, path])
			if texture != null:
				assert_gt(texture.get_width() * texture.get_height(), 0, "%s files.%s has pixels" % [reader.asset_id, role])


func test_hardpoints_parse_and_share_the_splat_frame() -> void:
	for reader: ManifestReader in _valid_readers():
		var path: String = reader.file_path("hardpoints")
		if path.is_empty():
			continue
		var json := JSON.new()
		var status: Error = json.parse(FileAccess.get_file_as_string(path))
		assert_eq(status, OK, "%s hardpoints.json parses (line %d: %s)" % [reader.asset_id, json.get_error_line(), json.get_error_message()])
		if status != OK:
			continue
		assert_true(json.data is Dictionary, "%s hardpoints.json root is an object" % reader.asset_id)
		if not (json.data is Dictionary):
			continue
		var hardpoints: Dictionary = json.data
		assert_eq(hardpoints.get("asset_id"), reader.asset_id, "%s hardpoints asset_id" % reader.asset_id)
		assert_eq(hardpoints.get("frame"), ManifestReader.GODOT_FRAME, "%s hardpoints frame" % reader.asset_id)
		assert_eq(hardpoints.get("units"), ManifestReader.METRES, "%s hardpoints units" % reader.asset_id)
		if hardpoints.has("center_of_mass"):
			var parts: Variant = hardpoints["center_of_mass"]
			assert_true(parts is Array and (parts as Array).size() == 3, "%s center_of_mass is [x, y, z]" % reader.asset_id)
			if parts is Array and (parts as Array).size() == 3:
				var com := Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
				var slack: float = maxf(FRAME_SLACK_M, 2.0 * float(reader.lods[0]["spacing_m"]))
				assert_true(reader.aabb.grow(slack).has_point(com), "%s center_of_mass %s lies inside the splat AABB %s (same centred frame)" % [reader.asset_id, com, reader.aabb])


# --- helpers -----------------------------------------------------------------------------------------------------


func _reader_for(asset_id: String) -> ManifestReader:
	for reader: ManifestReader in _readers:
		if reader.asset_id == asset_id:
			return reader
	return null


## Readers whose manifest parsed; the rest are reported by test_manifests_are_valid.
func _valid_readers() -> Array[ManifestReader]:
	var valid: Array[ManifestReader] = []
	for reader: ManifestReader in _readers:
		if reader.is_valid():
			valid.append(reader)
	return valid


## An imported resource exists at `path`; fails the test with the remedy when it does not.
func _is_imported(path: String) -> bool:
	if ResourceLoader.exists(path):
		return true
	fail_test("%s has no imported resource: %s" % [path, GEN_ASSETS_HINT])
	return false


## The imported GaussianResource for a PLY, cached across tests (the big ones are tens of MB). Null after a failure.
func _gaussian(path: String) -> GaussianResource:
	if _gaussians.has(path):
		return _gaussians[path]
	if not _is_imported(path):
		return null
	var gaussian: GaussianResource = load(path) as GaussianResource
	assert_not_null(gaussian, "%s loads as a GaussianResource (is the gdgs plugin enabled and the file imported?)" % path)
	if gaussian != null:
		_gaussians[path] = gaussian
	return gaussian


func _mesh(path: String) -> Mesh:
	if not _is_imported(path):
		return null
	var mesh: Mesh = load(path) as Mesh
	assert_not_null(mesh, "%s loads as a Mesh" % path)
	return mesh


func _assert_aabb_near(actual: AABB, expected: AABB, tolerance: float, label: String) -> void:
	var worst: float = maxf(_max_component((actual.position - expected.position).abs()), _max_component((actual.end - expected.end).abs()))
	assert_true(worst <= tolerance, "%s: min %s max %s, expected min %s max %s (worst corner error %.4f m, tolerance %.3f m)" % [
		label, actual.position, actual.end, expected.position, expected.end, worst, tolerance])


func _max_component(v: Vector3) -> float:
	return maxf(maxf(v.x, v.y), v.z)
