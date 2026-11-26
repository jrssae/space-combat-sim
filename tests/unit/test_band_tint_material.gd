extends GutTest
## The Asimov liners' band liveries and bars (M10-T53, Q86, Q88, Q95; `BandTintMaterial`): a liner's livery and its six or eight
## bars follow its name's place in the science-fiction authors' list (`data/ships/names.json`), the show's Asimov first in the
## green with six, the same ship always the same.

const TINT: Dictionary = {"base": [0.03, 0.35, 0.04], "liveries": ["green", "blue", "maroon", "amber", "teal"],
		"colours": [[0.03, 0.35, 0.04], [0.02, 0.08, 0.48], [0.26, 0.02, 0.03], [0.69, 0.33, 0.01], [0.01, 0.29, 0.26]],
		"white": [0.66, 0.64, 0.58], "bar_counts": [6, 8], "names_type": "ea_asimov"}


func test_the_asimov_is_first_and_wears_the_green() -> void:
	var names: PackedStringArray = ShipNames.names_for(&"ea_asimov")
	assert_gt(names.size(), 14, "about twenty authors")
	assert_eq(names[0], "Asimov", "the show's liner first")
	assert_eq(names[1], "Callisto", "the show's other liner, the one name that is no author (Q88)")
	assert_eq(ShipNames.pick(&"ea_asimov", Factions.EARTH_ALLIANCE, 0), "EAS Asimov")
	assert_eq(BandTintMaterial.livery_index(TINT, "EAS Asimov"), 0)
	assert_eq(BandTintMaterial.livery_key(TINT, 0), "green", "the default livery")


func test_each_livery_resolves_from_a_name_in_list_order() -> void:
	var names: PackedStringArray = ShipNames.names_for(&"ea_asimov")
	var seen: Dictionary = {}
	for i: int in TINT["liveries"].size():
		var index: int = BandTintMaterial.livery_index(TINT, "EAS %s" % names[i])
		assert_eq(index, i, names[i])
		seen[BandTintMaterial.livery_key(TINT, index)] = true
	assert_eq(seen.size(), TINT["liveries"].size(), "every livery is worn by a listed name")
	assert_eq(BandTintMaterial.livery_index(TINT, "EAS %s" % names[5]), 0, "the list goes round the liveries")


func test_the_same_ship_always_wears_the_same() -> void:
	assert_eq(BandTintMaterial.livery_index(TINT, "EAS Heinlein 2"), BandTintMaterial.livery_index(TINT, "EAS Heinlein"), "a repeat is its first's")
	var off_list: int = BandTintMaterial.livery_index(TINT, "EAS Gernsback")
	assert_eq(BandTintMaterial.livery_index(TINT, "EAS Gernsback"), off_list, "a name off the list is stable")
	assert_between(off_list, 0, TINT["liveries"].size() - 1)
	assert_eq(BandTintMaterial.livery_index(TINT, ""), 0, "no name: the default")
	assert_eq(BandTintMaterial.livery_index({"colours": [[0.1, 0.5, 0.1]]}, "EAS Clarke"), 0, "one livery only")


func test_six_or_eight_bars_by_the_name_apart_from_the_colour() -> void:
	var names: PackedStringArray = ShipNames.names_for(&"ea_asimov")
	assert_eq(BandTintMaterial.bar_count(TINT, "EAS Asimov"), 6, "the show's Asimov has six")
	var pairs: Dictionary = {}
	for i: int in 10:
		var ship: String = "EAS %s" % names[i]
		assert_eq(BandTintMaterial.bar_count(TINT, ship), 6 if i % 2 == 0 else 8, ship)
		pairs[[BandTintMaterial.livery_index(TINT, ship), BandTintMaterial.bar_count(TINT, ship)]] = true
		assert_eq(BandTintMaterial.variant(TINT, ship), BandTintMaterial.livery_index(TINT, ship)
				+ BandTintMaterial.MAX_LIVERIES * BandTintMaterial.bar_choice(TINT, ship), ship)
	assert_eq(pairs.size(), 10, "ten names give every colour with both counts")
	assert_eq(BandTintMaterial.bar_count(TINT, "EAS Heinlein 2"), BandTintMaterial.bar_count(TINT, "EAS Heinlein"), "a repeat is its first's")
	assert_eq(BandTintMaterial.bar_count(TINT, ""), 6, "no name: the first count")
	assert_eq(BandTintMaterial.bar_count({"colours": TINT["colours"]}, "EAS Clarke"), 0, "a hull without bars")


func test_a_surface_with_band_bars_gets_them_drawn() -> void:
	var bars: Dictionary = {"radius_m": 173.7, "span_m": [-93.0, 94.0], "half_width_m": 12.5}
	var band: ShaderMaterial = BandTintMaterial.make("res://missing", {"name": "band", "band_tint": TINT, "band_bars": bars})
	assert_almost_eq(float(band.get_shader_parameter(&"bar_radius")), 173.7, 0.001)
	assert_eq(band.get_shader_parameter(&"bar_span"), Vector2(-93.0, 94.0))
	assert_eq(int(band.get_shader_parameter(&"bar_count_choices")), 2)
	assert_eq(Array(band.get_shader_parameter(&"bar_counts") as PackedInt32Array).slice(0, 2), [6, 8])
	var hull: ShaderMaterial = BandTintMaterial.make("res://missing", {"name": "hull", "band_tint": TINT})
	assert_null(hull.get_shader_parameter(&"bar_radius"), "no bars off the band: the shader's own zero stands")


func test_a_mesh_entry_gives_the_ships_livery_as_its_skin_variant() -> void:
	var entry: Dictionary = {"surfaces": [{"name": "hull", "blend": false, "band_tint": TINT}]}
	assert_eq(HullSheenMaterial.variant_of_mesh(entry, "EAS Clarke"), 3.0 + BandTintMaterial.MAX_LIVERIES,
			"the capitals' per-ship value carries the livery (amber) and the bar count (the second, eight)")
	assert_eq(HullSheenMaterial.variant_of_mesh(entry, "EAS Asimov"), 0.0, "the show's liner: green, six bars")
	assert_eq(HullSheenMaterial.variant_of_mesh({"surfaces": [{"name": "hull"}]}, "EAS Clarke"), 0.0, "a hull without liveries")
	assert_true(BandTintMaterial.wants(entry["surfaces"][0]))
