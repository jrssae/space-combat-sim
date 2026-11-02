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


func test_both_ships_list_lods_one_to_three() -> void:
	for asset: String in ["starfury_aurora", "raider_fighter"]:
		for level: int in [1, 2, 3]:
			var lod: Dictionary = SplatLod.resolve(asset, level)
			assert_eq(lod["level"], level, "%s LOD %d" % [asset, level])
			assert_true(FileAccess.file_exists(lod["path"]), GEN_ASSETS_HINT)


func test_a_level_the_manifest_lacks_falls_back_to_lod0_with_a_warning() -> void:
	for pair: Array in [["raider_fighter", 4], ["starfury_aurora", 7]]:  # both list LOD0-LOD3 (M3-T19)
		var lod: Dictionary = SplatLod.resolve(pair[0], pair[1])
		assert_eq(lod["path"], "res://assets/generated/%s/%s.ply" % [pair[0], pair[0]], "%s LOD %d: LOD0 instead" % pair)
		assert_eq(lod["level"], 0)
		assert_string_contains(lod["warning"], "lists no LOD %d" % pair[1])


func test_the_asset_root_is_the_ship_specs() -> void:
	assert_eq(SplatLod.ASSET_ROOT, ShipSpec.ASSET_ROOT)
	assert_eq(Ship.ASSET_ROOT, ShipSpec.ASSET_ROOT)
	assert_eq(DebrisPool.ASSET_ROOT, ShipSpec.ASSET_ROOT)
	assert_eq(ShipCatalog.spec_for(ShipCatalog.PLAYER_TYPE).hardpoints_path(), "res://assets/generated/starfury_aurora/hardpoints.json")


# --- lighting records (M3-T21) -----------------------------------------------------------------------------------


func test_the_manifest_names_each_levels_lighting_records() -> void:
	var manifest: Dictionary = {"lods": [
		{"level": 0.0, "file": "x.ply", "lighting": "x_lod0.light"},
		{"level": 1.0, "file": "x_lod1.ply", "lighting": "x_lod1.light"},
		{"level": 2.0, "file": "x_lod2.ply"},
	]}
	assert_eq(SplatLod.lighting_for(manifest, 0), "x_lod0.light")
	assert_eq(SplatLod.lighting_for(manifest, 1), "x_lod1.light")
	assert_eq(SplatLod.lighting_for(manifest, 2), "", "a level without records")
	assert_eq(SplatLod.lighting_for(manifest, 3), "", "a level the manifest does not list")
	assert_eq(SplatLod.lighting_for({}, 0), "")


func test_a_malformed_entry_is_skipped_by_the_lighting_lookup_like_the_file_lookup() -> void:
	var manifest: Dictionary = {"lods": [3, null, {"level": null, "lighting": "a.light"}, {"lighting": "b.light"}, {"level": "1", "lighting": "c.light"},
			{"level": 1, "file": "x_lod1.ply", "lighting": "x_lod1.light"}]}
	assert_eq(SplatLod.lighting_for(manifest, 1), "x_lod1.light", "the first entry that is a level 1 with a string")
	assert_eq(SplatLod.lighting_for(manifest, 0), "", "a null level is not level 0")
	assert_eq(SplatLod.file_for(manifest, 1), "x_lod1.ply")
	assert_eq(SplatLod.lighting_for({"lods": [{"level": null, "lighting": "a.light"}]}, 0), "")
	assert_eq(SplatLod.lighting_for({"lods": [{"level": 1, "lighting": 7}]}, 1), "", "records that are not a name")


func test_one_parsed_manifest_serves_every_levels_lighting_path() -> void:
	var manifest: Dictionary = SplatLod.read_manifest("starfury_aurora")
	assert_false(manifest.is_empty())
	for level: int in range(0, 4):
		assert_eq(SplatLod.lighting_path_in(manifest, "starfury_aurora", level), SplatLod.lighting_path("starfury_aurora", level))
	assert_eq(SplatLod.lighting_path_in({}, "starfury_aurora", 0), "")
	assert_eq(SplatLod.read_manifest("no_such_asset"), {})
	assert_eq(SplatLod.read_manifest("nothing_here", "res://no/such/root"), {})


# --- the hero level (M3-T24) --------------------------------------------------------------------------------------


func test_the_manifest_names_the_hero_file_and_lighting_outside_the_lods() -> void:
	var manifest: Dictionary = {
		"lods": [{"level": 0, "file": "x.ply", "lighting": "x_lod0.light"}],
		"hero": {"file": "x_hero.ply", "splats": 9, "spacing_m": 0.02, "lighting": "x_hero.light"},
	}
	assert_eq(SplatLod.hero_file_for(manifest), "x_hero.ply")
	assert_eq(SplatLod.hero_lighting_for(manifest), "x_hero.light")
	assert_eq(SplatLod.file_for(manifest, 1), "", "the hero is not a level of the ladder")
	for broken: Variant in [{}, {"hero": 3}, {"hero": {}}, {"hero": {"file": 4, "lighting": null}}]:
		assert_eq(SplatLod.hero_file_for(broken as Dictionary), "")
		assert_eq(SplatLod.hero_lighting_for(broken as Dictionary), "")


func test_the_hero_paths_of_a_generated_asset() -> void:
	var hero: Dictionary = SplatLod.hero_paths("starfury_aurora")
	assert_eq(hero["path"], "res://assets/generated/starfury_aurora/starfury_aurora_hero.ply", GEN_ASSETS_HINT)
	assert_eq(hero["lighting"], "res://assets/generated/starfury_aurora/starfury_aurora_hero.light")
	assert_true(FileAccess.file_exists(String(hero["path"])))
	assert_true(FileAccess.file_exists(String(hero["lighting"])))
	for asset: String in ["raider_fighter", "nav_buoy", "sky_default", "no_such_asset"]:
		assert_eq(SplatLod.hero_paths(asset), {"path": "", "lighting": ""}, "%s has no hero level" % asset)


func test_the_lighting_path_of_a_generated_asset() -> void:
	assert_eq(SplatLod.lighting_path("starfury_aurora", 0), "res://assets/generated/starfury_aurora/starfury_aurora_lod0.light")
	assert_eq(SplatLod.lighting_path("raider_fighter", 3), "res://assets/generated/raider_fighter/raider_fighter_lod3.light")
	assert_eq(SplatLod.lighting_path("nav_buoy", 0), "res://assets/generated/nav_buoy/nav_buoy_lod0.light")
	assert_eq(SplatLod.lighting_path("sky_default", 0), "", "the sky is not lit")
	assert_eq(SplatLod.lighting_path("no_such_asset", 0), "")
