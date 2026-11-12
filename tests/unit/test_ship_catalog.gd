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
