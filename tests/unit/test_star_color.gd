extends GutTest
## A star's colour from its temperature (Q30): what the lens flare and the key star light both show.


func test_an_orange_dwarf_is_warm() -> void:
	var c: Color = StarColor.linear_from_kelvin(5084.0)
	assert_almost_eq(c.r, 1.0, 1e-6, "the largest channel is 1")
	assert_gt(c.r, c.g + 0.1, "more red than green")
	assert_gt(c.g, c.b + 0.05, "more green than blue: orange, not pink")


func test_it_agrees_with_the_sky_generators_blackbody() -> void:
	# tools/procgen/core/color.py blackbody_rgb, computed once, so a star and the sky's stars of one temperature match.
	for sample: Array in [[3000.0, 0.484, 0.155], [5084.0, 0.805, 0.651], [6500.0, 0.944, 0.993]]:
		var c: Color = StarColor.linear_from_kelvin(sample[0])
		assert_almost_eq(c.g, float(sample[1]), 0.03, "green at %d K" % int(sample[0]))
		assert_almost_eq(c.b, float(sample[2]), 0.03, "blue at %d K" % int(sample[0]))


func test_a_red_star_is_redder_than_an_orange_one() -> void:
	var red: Color = StarColor.linear_from_kelvin(3000.0)
	var orange: Color = StarColor.linear_from_kelvin(5084.0)
	assert_lt(red.g, orange.g)
	assert_lt(red.b, orange.b)


func test_outside_the_fit_it_holds_the_nearest_end() -> void:
	assert_eq(StarColor.linear_from_kelvin(100.0), StarColor.linear_from_kelvin(StarColor.MIN_K))
	assert_eq(StarColor.linear_from_kelvin(1.0e6), StarColor.linear_from_kelvin(StarColor.MAX_K))


func test_the_catalog_names_the_current_systems_star() -> void:
	assert_almost_eq(StarCatalog.temperature_k(&"local"), 5084.0, 1e-6, "Epsilon Eridani")


func test_an_unknown_system_falls_back_to_the_default_star() -> void:
	var table: Dictionary = StarCatalog.parse('{"default": "a", "systems": {"a": {"temperature_k": 3000.0}}}')
	assert_almost_eq(StarCatalog.temperature_in(table, &"nowhere"), 3000.0, 1e-6)


func test_a_broken_table_gives_an_error_and_the_fallback_temperature() -> void:
	for text: String in ["not json", '{"systems": {}}', '{"default": "a", "systems": {"a": {}}}']:
		var table: Dictionary = StarCatalog.parse(text)
		assert_false(String(table.get("error", "")).is_empty(), text)
		assert_almost_eq(StarCatalog.temperature_in(table, &"a"), StarCatalog.FALLBACK_K, 1e-6)
