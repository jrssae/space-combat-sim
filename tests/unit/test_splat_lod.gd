extends GutTest
## SplatLod (M3-T08, architecture §16 D35): which PLY a ship draws at a level of detail. Level 0 is the asset's own file; a
## lower level is the one the generator's manifest lists.

const GEN_ASSETS_HINT: String = "run scripts/gen_assets.sh, then scripts/run_tests.sh (it imports first)"

const MANIFEST: Dictionary = {
	"lods": [
		{"level": 0, "file": "ship.ply", "splats": 1000, "spacing_m": 0.04},
		{"level": 1, "file": "ship_lod1.ply", "splats": 250, "spacing_m": 0.08},
		{"level": 3, "file": "ship_lod3.ply", "splats": 40, "spacing_m": 0.3},
	],
}


func test_file_for_finds_the_entry_with_that_level() -> void:
	assert_eq(SplatLod.file_for(MANIFEST, 0), "ship.ply")
	assert_eq(SplatLod.file_for(MANIFEST, 1), "ship_lod1.ply")
	assert_eq(SplatLod.file_for(MANIFEST, 3), "ship_lod3.ply", "by level, not by position in the list")


func test_file_for_a_level_the_manifest_lacks_is_empty() -> void:
	assert_eq(SplatLod.file_for(MANIFEST, 2), "")
	assert_eq(SplatLod.file_for(MANIFEST, -1), "")


func test_file_for_reads_levels_that_json_parsed_as_floats() -> void:
	var parsed: Variant = JSON.parse_string('{"lods": [{"level": 1.0, "file": "a_lod1.ply"}]}')
	assert_eq(SplatLod.file_for(parsed as Dictionary, 1), "a_lod1.ply")


func test_file_for_survives_a_malformed_manifest() -> void:
	assert_eq(SplatLod.file_for({}, 1), "")
	assert_eq(SplatLod.file_for({"lods": "none"}, 1), "")
	assert_eq(SplatLod.file_for({"lods": [3, null, {"level": 1}, {"file": "x.ply"}, {"level": "1", "file": "y.ply"}]}, 1), "",
			"entries without an int level and a string file are skipped")


func test_level_zero_is_the_assets_own_file_and_reads_no_manifest() -> void:
	var lod: Dictionary = SplatLod.resolve("nothing_here", 0, "res://no/such/root")
	assert_eq(lod, {"path": "res://no/such/root/nothing_here/nothing_here.ply", "level": 0, "warning": ""})
	assert_eq(SplatLod.resolve("nothing_here", -2, "res://no/such/root"), lod)


func test_a_higher_level_with_no_manifest_gives_no_path_and_one_warning_that_says_so() -> void:
	var lod: Dictionary = SplatLod.resolve("nothing_here", 1, "res://no/such/root")
	assert_eq(lod["path"], "", "nothing to load, so the caller has nothing more to complain about")
	assert_eq(lod["level"], -1)
	assert_string_contains(lod["warning"], "res://no/such/root/nothing_here/manifest.json is missing")
	assert_string_contains(lod["warning"], "run scripts/gen_assets.sh")


func test_the_starfurys_lod1_is_listed_by_its_manifest() -> void:
	var lod: Dictionary = SplatLod.resolve("starfury_aurora", 1)
	assert_eq(lod["path"], "res://assets/generated/starfury_aurora/starfury_aurora_lod1.ply", GEN_ASSETS_HINT)
	assert_eq(lod["level"], 1)
	assert_eq(lod["warning"], "")
	assert_true(FileAccess.file_exists(lod["path"]), GEN_ASSETS_HINT)
	assert_eq(SplatLod.resolve("starfury_aurora", 0)["path"], "res://assets/generated/starfury_aurora/starfury_aurora.ply")


func test_a_level_the_manifest_lacks_falls_back_to_lod0_with_a_warning() -> void:
	for pair: Array in [["raider_fighter", 1], ["starfury_aurora", 7]]:
		var lod: Dictionary = SplatLod.resolve(pair[0], pair[1])
		assert_eq(lod["path"], "res://assets/generated/%s/%s.ply" % [pair[0], pair[0]], "%s LOD %d: LOD0 instead" % pair)
		assert_eq(lod["level"], 0)
		assert_string_contains(lod["warning"], "lists no LOD %d" % pair[1])


func test_the_asset_root_is_the_ship_specs() -> void:
	assert_eq(SplatLod.ASSET_ROOT, ShipSpec.ASSET_ROOT)
	assert_eq(Ship.ASSET_ROOT, ShipSpec.ASSET_ROOT)
	assert_eq(DebrisPool.ASSET_ROOT, ShipSpec.ASSET_ROOT)
	assert_eq(ShipCatalog.spec_for(ShipCatalog.PLAYER_TYPE).hardpoints_path(), "res://assets/generated/starfury_aurora/hardpoints.json")
