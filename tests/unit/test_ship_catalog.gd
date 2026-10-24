extends GutTest
## ShipCatalog (architecture §15.2, M3-T08): type -> `ShipSpec`, and the faction each type flies for by default.


func test_every_type_loads_a_spec_and_has_a_faction() -> void:
	for type: StringName in ShipCatalog.types():
		var spec: ShipSpec = ShipCatalog.spec_for(type)
		assert_not_null(spec, "%s loads" % type)
		assert_true(ShipCatalog.FACTIONS.has(type), "%s has a default faction" % type)


func test_default_factions() -> void:
	assert_eq(ShipCatalog.faction_for(&"starfury_ally"), Factions.EARTH_ALLIANCE)
	assert_eq(ShipCatalog.faction_for(&"starfury_aurora"), Factions.EARTH_ALLIANCE)
	assert_eq(ShipCatalog.faction_for(&"raider_fighter"), Factions.RAIDERS)


func test_an_unknown_type_is_neutral() -> void:
	assert_false(ShipCatalog.has_type(&"battleship"))
	assert_eq(ShipCatalog.faction_for(&"battleship"), Factions.NEUTRAL)


func test_the_ally_type_is_listed() -> void:
	assert_true(ShipCatalog.has_type(&"starfury_ally"))
	assert_true(ShipCatalog.types().has(&"starfury_ally"))


func test_the_ally_flies_the_starfurys_numbers_with_lod1_and_no_cockpit() -> void:
	var starfury: ShipSpec = ShipCatalog.spec_for(&"starfury_aurora")
	var ally: ShipSpec = ShipCatalog.spec_for(&"starfury_ally")
	var differing: PackedStringArray = ["splat_lod", "has_cockpit_interior"]
	var checked: int = 0
	for property: Dictionary in ShipSpec.new().get_property_list():
		if not (int(property["usage"]) & PROPERTY_USAGE_STORAGE):
			continue
		var key: String = property["name"]
		if key == "script" or key.begins_with("metadata/") or differing.has(key):
			continue
		assert_eq(ally.get(key), starfury.get(key), "ShipSpec.%s is the Starfury's" % key)
		checked += 1
	assert_gt(checked, 15, "the whole spec was compared")
	assert_eq(ally.asset_id, starfury.asset_id, "the same asset: hardpoints, hull mesh and chunks")
	assert_eq(starfury.splat_lod, 0)
	assert_eq(ally.splat_lod, 1)
	assert_true(starfury.has_cockpit_interior)
	assert_false(ally.has_cockpit_interior)
