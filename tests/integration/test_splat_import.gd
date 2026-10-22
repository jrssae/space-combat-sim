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
##
## Lower LODs (M3-T03: `starfury_aurora_lod1.ply`) are centred on their own centroid and keep LOD0's box within
## `LOD_AABB_TOLERANCE_M`. Break-up chunks partition the LOD named by the manifest's `chunk_lod` (0 when absent: the
## raider's chunks are its LOD0, the Starfury's its LOD1).

const GENERATED_DIR: String = "res://assets/generated"
const GEN_ASSETS_HINT: String = "run scripts/gen_assets.sh, then scripts/run_tests.sh (it imports first)"
## AC4: the imported AABB matches the manifest within 1 cm.
const AABB_TOLERANCE_M: float = 0.01
## M3 AC6: a lower LOD's imported AABB matches LOD0's (the manifest's) within 0.3 m.
const LOD_AABB_TOLERANCE_M: float = 0.3
## M3 AC6: the Starfury's LOD1 and the chunks made from it.
const STARFURY_ID: String = "starfury_aurora"
const STARFURY_LOD1_FILE: String = "starfury_aurora_lod1.ply"
const STARFURY_LOD1_SHARE: Vector2 = Vector2(0.2, 0.3)
const STARFURY_CHUNKS: PackedStringArray = ["cabin", "arm_ur", "arm_lr", "arm_ul", "arm_ll"]
## A mesh or hardpoint is in the splat frame when its bounds sit within this of the splat bounds (or twice the splat
## spacing, if larger): surface samples are not placed exactly on the extremes.
const FRAME_SLACK_M: float = 0.05
## Assets that must exist after gen_assets.sh (AC3), with the manifest `files` roles each must provide. A missing
## directory is a failure even though other assets exist. M1-T14 adds nav_buoy here.
const REQUIRED_ROLES: Dictionary = {
	"sky_default": [],
	"starfury_aurora": ["fallback_mesh", "cockpit_mesh", "hardpoints"],
	"nav_buoy": ["hardpoints"],
	"raider_fighter": ["fallback_mesh", "hardpoints"],
	"sfx_combat": [],
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
		# Break-up chunks (hardpoints `chunks[]`, M2-T04) are the other PLYs an asset may have.
		var chunk_files: PackedStringArray = PackedStringArray()
		for entry: Dictionary in _chunk_entries(reader):
			chunk_files.append(String(entry["ply"]))
			for key: String in ["ply", "obj"]:
				assert_true(FileAccess.file_exists("%s/%s" % [reader.directory, entry[key]]), "%s chunk %s %s is missing: %s" % [reader.asset_id, entry["name"], key, GEN_ASSETS_HINT])
		for file_name: String in DirAccess.get_files_at(reader.directory):
			if file_name.ends_with(".ply"):
				assert_true(lod_files.has(file_name) or chunk_files.has(file_name), "%s/%s is a PLY that no manifest lod or hardpoints chunk lists" % [reader.asset_id, file_name])


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


func test_chunk_plys_import_with_their_counts_and_partition_the_hull() -> void:
	var assets_with_chunks: int = 0
	for reader: ManifestReader in _valid_readers():
		var entries: Array[Dictionary] = _chunk_entries(reader)
		if entries.is_empty():
			continue
		assets_with_chunks += 1
		var lod: Dictionary = _lod(reader, _chunk_lod(reader))
		assert_false(lod.is_empty(), "%s: chunk_lod %d is one of its lods" % [reader.asset_id, _chunk_lod(reader)])
		if lod.is_empty():
			continue
		var hull: GaussianResource = _gaussian(reader.lod_path(lod))
		if hull == null:
			continue
		var total: int = 0
		# The box of the LOD the chunks were cut from, back in the Godot frame (for LOD0 that is the manifest box).
		var hull_box: AABB = ManifestReader.godot_to_imported_aabb(hull.aabb).grow(AABB_TOLERANCE_M)
		for entry: Dictionary in entries:
			var label: String = "%s chunk %s" % [reader.asset_id, entry["name"]]
			var gaussian: GaussianResource = _gaussian("%s/%s" % [reader.directory, entry["ply"]])
			if gaussian == null:
				continue
			assert_eq(gaussian.point_count, int(entry["splats"]), "%s: point_count vs hardpoints splats" % label)
			total += gaussian.point_count
			# Re-centred on its own centroid: the imported box sits around the origin ...
			assert_true(gaussian.aabb.grow(0.5).has_point(Vector3.ZERO), "%s: the imported box %s contains its own origin" % [label, gaussian.aabb])
			# ... and placed at `offset` (x and y re-negated: the import keeps the 3DGS frame) it lies inside the hull's box.
			var offset := Vector3(float(entry["offset"][0]), float(entry["offset"][1]), float(entry["offset"][2]))
			var godot_box: AABB = ManifestReader.godot_to_imported_aabb(gaussian.aabb)
			godot_box.position += offset
			assert_true(hull_box.encloses(godot_box), "%s: box %s at offset %s lies inside the hull's %s" % [label, godot_box, offset, hull_box])
		assert_eq(total, int(lod["splats"]), "%s: the chunks hold exactly the splats of lod %d" % [reader.asset_id, lod["level"]])
	assert_gt(assets_with_chunks, 1, "assets with chunks exist (raider_fighter, starfury_aurora): %s" % GEN_ASSETS_HINT)


func test_lower_lods_keep_the_lod0_box() -> void:
	for reader: ManifestReader in _valid_readers():
		for lod: Dictionary in reader.lods.slice(1):
			var gaussian: GaussianResource = _gaussian(reader.lod_path(lod))
			if gaussian == null:
				continue
			var label: String = "%s lod %d" % [reader.asset_id, lod["level"]]
			assert_lt(int(lod["splats"]), int(reader.lods[0]["splats"]), "%s: lighter than lod 0" % label)
			assert_gt(float(lod["spacing_m"]), float(reader.lods[0]["spacing_m"]), "%s: coarser than lod 0" % label)
			_assert_aabb_near(gaussian.aabb, reader.imported_aabb(), LOD_AABB_TOLERANCE_M, "%s: imported AABB vs the lod 0 manifest box" % label)


## M3 AC6, the Godot half: the Starfury has a LOD1 with 20-30 % of LOD0's splats, and its five chunks come from it.
func test_starfury_lod1_and_its_chunks() -> void:
	var reader: ManifestReader = _reader_for(STARFURY_ID)
	if reader == null or not reader.is_valid():
		return  # reported by the tests above
	assert_gt(reader.lods.size(), 1, "%s has a lod 1: %s" % [STARFURY_ID, GEN_ASSETS_HINT])
	if reader.lods.size() < 2:
		return
	var lod1: Dictionary = reader.lods[1]
	assert_eq(lod1["level"], 1)
	assert_eq(lod1["file"], STARFURY_LOD1_FILE)
	var share: float = float(lod1["splats"]) / float(reader.lods[0]["splats"])
	assert_between(share, STARFURY_LOD1_SHARE.x, STARFURY_LOD1_SHARE.y, "LOD1 share of LOD0's splats")
	assert_eq(_chunk_lod(reader), 1, "the Starfury's chunks are cut from LOD1")
	var names: PackedStringArray = PackedStringArray()
	var total: int = 0
	for entry: Dictionary in _chunk_entries(reader):
		names.append(String(entry["name"]))
		total += int(entry["splats"])
	assert_eq(names, STARFURY_CHUNKS, "the cabin and the four arms, in file order")
	assert_eq(total, int(lod1["splats"]), "the chunks partition LOD1")


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


## `chunks[]` of the asset's hardpoints.json (empty when it has none).
func _chunk_entries(reader: ManifestReader) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var path: String = reader.file_path("hardpoints")
	if path.is_empty() or not FileAccess.file_exists(path):
		return out
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary):
		return out
	for entry: Variant in (data as Dictionary).get("chunks", []) as Array:
		if entry is Dictionary:
			out.append(entry as Dictionary)
	return out


## The LOD whose splats the chunks partition: the manifest's `chunk_lod`, 0 when it has none.
func _chunk_lod(reader: ManifestReader) -> int:
	return int(reader.data.get("chunk_lod", 0))


## The `lods` entry of `level`, or an empty Dictionary.
func _lod(reader: ManifestReader, level: int) -> Dictionary:
	for lod: Dictionary in reader.lods:
		if int(lod["level"]) == level:
			return lod
	return {}


func _reader_for(asset_id: String) -> ManifestReader:
	for reader: ManifestReader in _readers:
		if reader.asset_id == asset_id:
			return reader
	return null


## Readers whose manifest parsed; the rest are reported by test_manifests_are_valid.
func _valid_readers() -> Array[ManifestReader]:
	var valid: Array[ManifestReader] = []
	for reader: ManifestReader in _readers:
		if reader.is_valid() and reader.kind == "splat":  # sound sets have their own test below
			valid.append(reader)
	return valid


func test_audio_assets_import_as_wav_streams_with_the_manifest_length() -> void:
	var seen: int = 0
	for reader: ManifestReader in _readers:
		if not reader.is_valid() or reader.kind != "audio":
			continue
		seen += 1
		assert_eq(reader.lods.size(), 0, "no lods in an audio manifest")
		for sound_name: String in reader.sounds:
			var entry: Dictionary = reader.sounds[sound_name]
			var path: String = "%s/%s" % [reader.directory, entry["file"]]
			assert_true(FileAccess.file_exists(path), "%s exists: %s" % [path, GEN_ASSETS_HINT])
			if not _is_imported(path):
				continue
			var stream := load(path) as AudioStreamWAV
			assert_not_null(stream, "%s loads as an AudioStreamWAV" % path)
			if stream == null:
				continue
			assert_eq(stream.mix_rate, int(entry["sample_rate"]), "%s: sample rate" % sound_name)
			assert_almost_eq(stream.get_length(), float(entry["duration_s"]), 0.002, "%s: length" % sound_name)
	assert_gt(seen, 0, "an audio asset exists (sfx_combat): %s" % GEN_ASSETS_HINT)


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
