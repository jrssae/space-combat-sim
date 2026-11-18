extends GutTest
## The station hull's material (M7-T24): each texel tier's surfaces draw with the station hull shader, its atlas and its two detail
## tiles, and `settings.texture_detail` swaps the atlas and the fine tile between the two sets, both at full resolution.

const ASSET: String = "babylon5_station"
const GEN_ASSETS_HINT: String = "run scripts/gen_assets.sh, then scripts/run_tests.sh (it imports first)"
var _before: Variant


func before_each() -> void:
	_before = Settings.get_value(&"texture_detail")


func after_each() -> void:
	Settings.set_value(&"texture_detail", _before)


func _surfaces() -> Array:
	var out: Array = []
	for piece: Dictionary in (MeshAssets.read_manifest(ASSET).get("pieces", {}) as Dictionary).values():
		out += (piece.get("mesh", {}) as Dictionary).get("surfaces", [])
	return out


func _dir() -> String:
	return ShipSpec.ASSET_ROOT.path_join(ASSET)


func test_every_tier_draws_with_the_station_hull_material() -> void:
	var surfaces: Array = _surfaces()
	if surfaces.is_empty():
		fail_test(GEN_ASSETS_HINT)
		return
	assert_gt(surfaces.size(), 2, "more than one tier a piece")
	for surface: Dictionary in surfaces:
		assert_true(StationHullMaterial.wants(surface), String(surface.get("name", "")))
		var material: ShaderMaterial = StationHullMaterial.make(_dir(), surface)
		assert_eq(material.shader, StationHullMaterial.SHADER)
		for key: String in StationHullMaterial.ATLAS_KEYS + StationHullMaterial.TILE_KEYS:
			assert_not_null(material.get_shader_parameter(StringName(key + "_map")), "%s %s" % [surface["name"], key])


func test_the_setting_swaps_the_atlas_and_the_fine_tile_at_full_resolution() -> void:
	var surfaces: Array = _surfaces()
	if surfaces.is_empty():
		fail_test(GEN_ASSETS_HINT)
		return
	var surface: Dictionary = surfaces[0]
	Settings.set_value(&"texture_detail", &"high")
	var material: ShaderMaterial = StationHullMaterial.make(_dir(), surface)
	var high: Dictionary = {}
	for key: String in StationHullMaterial.ATLAS_KEYS + StationHullMaterial.TILE_KEYS:
		high[key] = material.get_shader_parameter(StringName(key + "_map"))
	Settings.set_value(&"texture_detail", &"low")
	for key: String in ["albedo", "normal", "orm", "fine_colour", "fine_normal"]:
		var low: Texture2D = material.get_shader_parameter(StringName(key + "_map"))
		assert_ne(low, high[key], "%s swaps" % key)
		assert_eq(low.get_width(), (high[key] as Texture2D).get_width(), "%s keeps its resolution" % key)
	for key: String in ["panel_colour", "panel_normal"]:
		assert_eq(material.get_shader_parameter(StringName(key + "_map")), high[key], "%s is shared" % key)


func test_a_piece_without_the_station_tile_keeps_the_standard_material() -> void:
	assert_false(StationHullMaterial.wants({"name": "hull", "world_detail": {"albedo": "a.png", "normal": "n.png", "tile_m": 16.0}}))
	assert_false(StationHullMaterial.wants({"name": "hull"}))
