extends GutTest
## The blast model's numbers (M10-T09, D12.6, Q18, Q53): T03's curve pinned, the push and its cap, the energy the far flashes
## read, the table's rows by source, class and section kind, a pooled hull's death by role and cargo, D12.6's three checks on
## the table, and a hull's nearest point to a blast. Pure.

const STARFURY_HULL: float = 300.0
const OMEGA_HULL: float = 30000.0


func before_each() -> void:
	BlastTable.reload()


func test_the_curve_is_one_at_the_centre_and_eases_to_nothing_at_the_radius() -> void:
	assert_eq(BlastSpec.falloff(0.0, 100.0), 1.0)
	assert_almost_eq(BlastSpec.falloff(50.0, 100.0), 0.5625, 1e-12, "(1 - 0.25)^2")
	assert_almost_eq(BlastSpec.falloff(80.0, 100.0), 0.1296, 1e-12, "(1 - 0.64)^2")
	assert_eq(BlastSpec.falloff(100.0, 100.0), 0.0, "nothing at the radius")
	assert_eq(BlastSpec.falloff(150.0, 100.0), 0.0, "nor beyond")
	assert_eq(BlastSpec.falloff(-3.0, 100.0), 1.0, "a centre inside the hull is at distance 0")
	assert_eq(BlastSpec.falloff(10.0, 0.0), 0.0, "no radius, no blast")
	assert_eq(BlastSpec.falloff(NAN, 100.0), 0.0)
	assert_lt(BlastSpec.falloff(99.0, 100.0), 4.1e-4, "smooth at the rim: nothing jumps there")
	var last: float = 2.0
	for d: int in range(0, 101, 5):
		var f: float = BlastSpec.falloff(float(d), 100.0)
		assert_lt(f, last, "falls all the way out (%d m)" % d)
		last = f


func test_damage_push_and_energy_follow_the_row() -> void:
	var b: BlastSpec = BlastSpec.make(&"test", 60.0, 100.0, 2000.0)
	assert_eq(b.damage_at(0.0), 60.0)
	assert_almost_eq(b.damage_at(50.0), 33.75, 1e-9)
	assert_eq(b.damage_at(120.0), 0.0)
	# A 10 x 4 x 12 m box: faces 40, 48, 120, mean 69.33 m^2; 48 t.
	var area: float = BlastSpec.mean_face_area(Vector3(10.0, 4.0, 12.0))
	assert_almost_eq(area, 208.0 / 3.0, 1e-9)
	assert_almost_eq(b.push_at(50.0, area, 48000.0), 2000.0 * 0.5625 * area / 48000.0, 1e-9)
	assert_eq(b.push_at(0.0, 1.0e6, 1.0), BlastSpec.PUSH_CAP_MPS, "capped")
	assert_eq(b.push_at(10.0, area, 0.0), 0.0, "no mass, no push")
	assert_eq(b.energy_j(), 60.0 * 5.0e6, "the flashes' energy: 5e6 J a point at the centre")
	var cargo: BlastSpec = b.scaled(1.5, 1.25, 2.0)
	assert_eq([cargo.d0, cargo.radius_m, cargo.impulse], [90.0, 125.0, 4000.0])


func test_a_starfurys_far_flash_lasts_as_long_as_before() -> void:
	var starfury: BlastSpec = BlastTable.hull_death("starfury_aurora")
	var before: float = 0.4 + 0.0001 * pow(48000.0 * 1.0e5, 1.0 / 3.0)  # M4-T23: 1e5 J a kilogram of its 48 t
	assert_almost_eq(ExplosionLod.flash_s(starfury.energy_j()), before, 1e-6, "T09 fitted the flash constant to it")


func test_the_table_holds_t03s_rows() -> void:
	var rows: Dictionary = {
		&"raider_death": [40.0, 80.0, 1500.0], &"fighter_death": [60.0, 100.0, 2000.0],
		&"heavy_fighter_death": [78.0, 100.0, 2000.0], &"small_craft_death": [100.0, 150.0, 2500.0],
		&"civilian_death": [400.0, 300.0, 3000.0], &"missile": [20.0, 20.0, 500.0], &"torpedo": [100.0, 60.0, 1500.0],
		&"mine_prox": [300.0, 120.0, 2000.0], &"mine_energy": [250.0, 300.0, 4000.0], &"mine_guided": [400.0, 60.0, 1500.0],
		&"cruiser_magazine": [900.0, 400.0, 6000.0], &"cruiser_fuel": [600.0, 500.0, 6000.0],
		&"cruiser_reactor": [1800.0, 1000.0, 6000.0], &"capital_magazine": [1800.0, 600.0, 1.0e4],
		&"capital_fuel": [1200.0, 800.0, 1.0e4], &"capital_reactor": [4500.0, 2500.0, 1.0e4],
		&"dreadnought_magazine": [2400.0, 800.0, 1.2e4], &"dreadnought_fuel": [1800.0, 1000.0, 1.2e4],
		&"dreadnought_reactor": [7500.0, 3500.0, 1.2e4], &"ancients_reactor": [9000.0, 3000.0, 1.2e4],
	}
	for name: StringName in rows:
		var b: BlastSpec = BlastTable.spec(name)
		assert_not_null(b, "%s is in the table" % name)
		if b != null:
			assert_eq([b.d0, b.radius_m, b.impulse], rows[name], String(name))
			assert_eq(b.push_cap_mps, 50.0)
	assert_null(BlastTable.spec(&"capital_bridge"), "a bridge does not blow")
	assert_null(BlastTable.spec(&"nothing"))
	assert_true(BlastTable.names().has("capital_reactor") and BlastTable.names().has("missile"), "the console's choices")


func test_a_capitals_class_comes_from_its_side_its_loadout_or_its_catalogue_class() -> void:
	assert_eq(BlastTable.capital_class(&"ea_omega", &"destroyer", Factions.EARTH_ALLIANCE), &"capital", "the loadouts' class")
	assert_eq(BlastTable.capital_class(&"capital_test_cruiser", &"cruiser", Factions.EARTH_ALLIANCE), &"cruiser")
	assert_eq(BlastTable.capital_class(&"", &"carrier", Factions.RAIDERS), &"capital", "a stand-in carrier")
	assert_eq(BlastTable.capital_class(&"", &"strike_carrier", Factions.RAIDERS), &"cruiser")
	assert_eq(BlastTable.capital_class(&"", &"cruiser", Factions.RAIDERS), &"cruiser")
	assert_eq(BlastTable.capital_class(&"", &"unheard_of", Factions.RAIDERS), &"capital", "the default")
	assert_eq(BlastTable.capital_class(&"ea_omega", &"destroyer", &"shadows"), &"ancients", "the ancients' own row")
	var omega_magazine: BlastSpec = BlastTable.capital_death(&"ea_omega", &"destroyer", Factions.EARTH_ALLIANCE, "magazine")
	assert_eq(omega_magazine.source, &"capital_magazine")
	assert_eq(BlastTable.capital_death(&"ea_omega", &"destroyer", Factions.EARTH_ALLIANCE, "bridge").source, &"capital_reactor",
			"a kind that does not blow: the reactor's")


func test_a_pooled_hulls_death_is_sized_by_its_role_and_its_cargo() -> void:
	assert_eq(BlastTable.hull_death("raider_fighter").source, &"raider_death")
	assert_eq(BlastTable.hull_death("starfury_aurora").source, &"fighter_death")
	assert_eq(BlastTable.hull_death("ea_shuttle").source, &"small_craft_death", "the loadouts call it a small craft")
	assert_eq(BlastTable.hull_death("saturn_3_freighter").source, &"civilian_death", "the catalogue's role")
	var tanker: BlastSpec = BlastTable.hull_death("saturn_4_tanker")
	assert_eq(tanker.source, &"civilian_death+fuel", "a tanker carries fuel")
	assert_eq([tanker.d0, tanker.radius_m, tanker.impulse], [600.0, 375.0, 3750.0])
	assert_eq(BlastTable.spec(&"civilian_death").d0, 400.0, "the shared row is untouched")
	assert_eq(BlastTable.hull_death("no_such_hull").source, &"fighter_death", "the default")


func test_d12_6s_three_checks_hold_on_the_table() -> void:
	var starfury: BlastSpec = BlastTable.spec(&"fighter_death")
	assert_almost_eq(starfury.damage_at(50.0) / STARFURY_HULL, 0.11, 0.005, "a Starfury's death takes 11 % from a wingman 50 m away")
	var reactor: BlastSpec = BlastTable.spec(&"capital_reactor")
	assert_gt(reactor.damage_at(2000.0), STARFURY_HULL, "a capital's reactor kills a fighter 2 km away")
	assert_lt(reactor.damage_at(2300.0), STARFURY_HULL, "but not much farther")
	assert_almost_eq(reactor.damage_at(500.0) / OMEGA_HULL, 0.14, 0.005, "and takes 14 % from a capital 500 m away")


func test_a_hit_volumes_nearest_point_to_a_blast() -> void:
	var box: HitShape = HitShape.make_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 5.0)), Vector3(4.0, 2.0, 10.0))
	assert_eq(box.nearest_point(Vector3(10.0, 0.0, 5.0)), Vector3(2.0, 0.0, 5.0))
	assert_eq(box.nearest_point(Vector3(1.0, 0.5, 6.0)), Vector3(1.0, 0.5, 6.0), "inside: the point itself")
	assert_eq(box.nearest_point(Vector3(10.0, 10.0, 30.0)), Vector3(2.0, 1.0, 10.0), "a corner")
	var capsule: HitShape = HitShape.make_capsule(Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3.ZERO), 1.0, 6.0)
	# Laid along z by the turn: its axis runs from z -2 to 2, radius 1.
	assert_true(capsule.nearest_point(Vector3(0.0, 0.0, 10.0)).is_equal_approx(Vector3(0.0, 0.0, 3.0)), "past its end cap")
	assert_true(capsule.nearest_point(Vector3(5.0, 0.0, 1.0)).is_equal_approx(Vector3(1.0, 0.0, 1.0)), "off its side")
