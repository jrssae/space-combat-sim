extends GutTest
## ShipCatalog (architecture §15.2, M3-T08, M10-T61): type -> `ShipSpec`, and the faction each type flies for by default, from
## the ship catalogue (`data/ships/catalogue.json`).

## A copy of the catalogue with the test hull added, for the registration test.
const WITH_TEST_HULL: String = "user://test_ship_catalog_with_test_hull.json"
const TEST_HULL: Dictionary = {"id": "test_hull", "spec": "res://tests/fixtures/ships/test_hull.tres", "asset": "test_hull",
		"faction": "narn", "role": "civilian", "ai_profile": "civilian", "name": "Test hull", "look_sheet": "pool",
		"docking": "tunnel", "callsign": "TESTER"}


func after_each() -> void:
	ShipCatalog.reset()


func test_the_catalogue_file_parses() -> void:
	assert_eq(ShipCatalog.data().error, "")
	assert_gt(ShipCatalog.types().size(), 10)


func test_every_type_loads_a_spec_and_has_a_faction() -> void:
	for type: StringName in ShipCatalog.types():
		var spec: ShipSpec = ShipCatalog.spec_for(type)
		assert_not_null(spec, "%s loads" % type)
		assert_true(Factions.is_known(ShipCatalog.faction_for(type)), "%s has a known default faction" % type)


func test_every_entry_matches_its_spec_and_names_known_profiles_and_factions() -> void:
	var data: ShipCatalogData = ShipCatalog.data()
	for id: StringName in data.ids():
		var spec: ShipSpec = load(data.spec_path(id)) as ShipSpec
		assert_not_null(spec, "%s: its spec loads" % id)
		if spec == null:
			continue
		assert_eq(data.text(id, "asset"), spec.asset_id, "%s: the entry's asset is its spec's" % id)
		assert_true(Factions.is_known(data.faction(id)), "%s: a known faction" % id)
		var profile: String = data.text(id, "ai_profile")
		assert_true(profile.is_empty() or AiProfile.PATHS.has(StringName(profile)), "%s: a known AI profile" % id)


func test_a_hull_registers_with_one_entry_and_one_tres() -> void:
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ShipCatalog.FILE))
	(parsed["ships"] as Array).append(TEST_HULL)
	var file := FileAccess.open(WITH_TEST_HULL, FileAccess.WRITE)
	file.store_string(JSON.stringify(parsed))
	file.close()
	assert_eq(ShipCatalog.use_file(WITH_TEST_HULL), "")
	var type: StringName = &"test_hull"
	assert_true(ShipCatalog.has_type(type))
	assert_true(ShipCatalog.types().has(type))
	var spec: ShipSpec = ShipCatalog.spec_for(type)
	assert_not_null(spec)
	assert_eq(spec.asset_id, "test_hull" if spec != null else "")
	assert_eq(ShipCatalog.faction_for(type), &"narn")
	assert_true(ShipCatalog.is_civilian(type))
	assert_eq(ShipCatalog.civilian_types().back(), type, "the civilian pool, last in catalogue order")
	assert_eq(ShipCatalog.entry_text(type, "ai_profile"), "civilian")
	assert_eq(DockingPlan.tunnel_types().back(), type, "fits the docking tunnel")
	assert_false(DockingPlan.freighter_types().has(type))
	assert_eq(LookScene.pool_types().get("test_hull"), type, "its look sheet parks one")
	assert_eq(TargetPreviewModel.class_text("test_hull"), "Test hull")
	assert_eq(EncounterDirector.civilian_callsign(type), "TESTER")
	ShipCatalog.reset()
	assert_false(ShipCatalog.has_type(type), "reset goes back to the game's catalogue")
	DirAccess.remove_absolute(WITH_TEST_HULL)


func test_a_refused_file_leaves_the_catalogue_as_it_was() -> void:
	assert_string_contains(ShipCatalog.use_file("res://no/such/catalogue.json"), "no such file")
	assert_true(ShipCatalog.has_type(&"raider_fighter"))


func test_hulls_built_another_way_are_listed_but_not_pooled() -> void:
	assert_false(ShipCatalog.has_type(&"raider_strike_carrier"), "the strike carrier rides CapitalStandin")
	assert_eq(ShipCatalog.entry_text(&"raider_strike_carrier", "capital_class"), String(CapitalStandin.STRIKE_CARRIER))
	assert_eq(ShipCatalog.entry_text(&"raider_strike_carrier", "spec"), CapitalStandin.CLASSES[CapitalStandin.STRIKE_CARRIER]["spec"])


func test_the_shuttles_are_civilians_only_missions_place() -> void:
	for type: StringName in [&"ea_shuttle", &"ea_atmo_shuttle"]:
		assert_true(ShipCatalog.has_type(type), "%s is pooled" % type)
		assert_true(ShipCatalog.is_civilian(type), "%s carries the civilian role" % type)
		assert_eq(ShipCatalog.faction_for(type), Factions.EARTH_ALLIANCE)
		assert_false(ShipCatalog.civilian_types().has(type), "%s stays out of random traffic and encounters" % type)
		assert_false(DockingPlan.tunnel_types().has(type), "%s is not station traffic" % type)
		assert_eq(LookScene.pool_types().get(String(type)), type, "its look sheet parks one")


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


func test_the_ally_flies_the_starfurys_numbers_and_hull_with_no_cockpit() -> void:
	var starfury: ShipSpec = ShipCatalog.spec_for(&"starfury_aurora")
	var ally: ShipSpec = ShipCatalog.spec_for(&"starfury_ally")
	var differing: PackedStringArray = ["has_cockpit_interior"]
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
	assert_true(starfury.has_cockpit_interior)
	assert_false(ally.has_cockpit_interior)



func test_the_saturn_4_and_8_share_one_engine_so_their_acceleration_follows_their_mass() -> void:
	# Q30 (the maintainer, 2026-11-07): one engine and one set of thrusters on all four, mass and inertia from each hull.
	var shared: Array[StringName] = [&"saturn_4_transport", &"saturn_4_tanker", &"saturn_8_transport", &"saturn_8_tanker"]
	var first: ShipSpec = ShipCatalog.spec_for(shared[0])
	var accel: Array[float] = []
	for type: StringName in shared:
		var spec: ShipSpec = ShipCatalog.spec_for(type)
		assert_eq(spec.pod_main_thrust, 2.1e7, "%s: the Saturn 4's main thrust" % type)
		assert_eq(spec.pod_retro_thrust, first.pod_retro_thrust, "%s: the same retros" % type)
		assert_eq(spec.rcs_force_max, first.rcs_force_max, "%s: the same RCS force" % type)
		assert_eq(spec.rcs_torque_max, first.rcs_torque_max, "%s: the same RCS torque" % type)
		var hp: Hardpoints = Hardpoints.load_file(spec.hardpoints_path())
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(spec.hardpoints_path())) if hp.valid else {}
		if not data.is_empty():
			assert_eq(spec.mass, float(data["mass_kg"]), "%s: the hull's mass" % type)
		accel.append(2.0 * spec.pod_main_thrust / spec.mass)
		# The assist's target rate is reached in 3 s from rest at the hull's angular acceleration.
		var alpha_deg: Vector3 = Vector3(rad_to_deg(spec.rcs_torque_max.x / spec.inertia.x),
				rad_to_deg(spec.rcs_torque_max.y / spec.inertia.y), rad_to_deg(spec.rcs_torque_max.z / spec.inertia.z))
		assert_almost_eq(spec.rate_max, alpha_deg * 3.0, Vector3.ONE * 0.06, "%s: rate_max is 3 s of its angular acceleration" % type)
	assert_eq(ShipCatalog.spec_for(&"saturn_4_transport").mass, 14092000.0, "the hull's mass, not 1.4e7 (with Q32's two flank pads)")
	for i: int in accel.size() - 1:
		assert_gt(accel[i], accel[i + 1], "%s out-accelerates %s" % [shared[i], shared[i + 1]])
	assert_almost_eq(accel[0] / 9.80665, 0.304, 0.001, "the Saturn 4 transport, 0.304 g")
	assert_almost_eq(accel[3] / 9.80665, 0.106, 0.001, "the Saturn 8 tanker, 0.106 g")
	var saturn_3: ShipSpec = ShipCatalog.spec_for(&"saturn_3_freighter")
	var a3: float = 2.0 * saturn_3.pod_main_thrust / saturn_3.mass
	assert_almost_eq(a3, accel[0], accel[0] * 0.05, "the Saturn 3's own slimmer engine (Q20) matches the Saturn 4 transport")
	assert_ne(saturn_3.pod_main_thrust, 2.1e7, "and is its own")
