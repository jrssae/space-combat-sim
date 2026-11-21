extends GutTest
## Ship names by class (M10-T21, `ShipNames`): the Omegas' Greek list from `data/ships/names.json`, the faction prefix, the count
## once a list has gone round, and nothing for a type with no list.

const LISTS_JSON: String = '{"prefixes": {"earth_alliance": "EAS"}, "names": {"hull_a": ["One", "Two"], "hull_b": [], "hull_c": "x"}}'


func test_the_omegas_carry_twenty_greek_names_led_by_the_agamemnon() -> void:
	var names: PackedStringArray = ShipNames.names_for(&"ea_omega")
	assert_eq(names.size(), 20)
	assert_eq(names[0], "Agamemnon", "the show's Omega first")
	var unique: Dictionary = {}
	for n: String in names:
		unique[n] = true
	assert_eq(unique.size(), names.size(), "no name twice")
	assert_eq(ShipNames.pick(&"ea_omega", Factions.EARTH_ALLIANCE, 0), "EAS Agamemnon")
	assert_eq(ShipCatalog.data().faction(&"ea_omega"), Factions.EARTH_ALLIANCE, "every Omega is Earth Alliance")


func test_a_list_goes_round_with_a_number_and_a_prefix_by_faction() -> void:
	var lists: Dictionary = ShipNames.parse(LISTS_JSON)
	assert_eq(ShipNames.pick(&"hull_a", Factions.EARTH_ALLIANCE, 1, lists), "EAS Two")
	assert_eq(ShipNames.pick(&"hull_a", Factions.EARTH_ALLIANCE, 2, lists), "EAS One 2", "round again, numbered")
	assert_eq(ShipNames.pick(&"hull_a", Factions.RAIDERS, 0, lists), "One", "a faction with no prefix")


func test_a_type_without_a_list_has_no_names() -> void:
	var lists: Dictionary = ShipNames.parse(LISTS_JSON)
	assert_eq(ShipNames.pick(&"hull_b", Factions.EARTH_ALLIANCE, 0, lists), "", "an empty list")
	assert_eq(ShipNames.pick(&"hull_c", Factions.EARTH_ALLIANCE, 0, lists), "", "not a list")
	assert_eq(ShipNames.pick(&"nothing", Factions.EARTH_ALLIANCE, 0, lists), "")
	assert_eq(ShipNames.parse("not json")["names"], {}, "a broken file names nothing")
