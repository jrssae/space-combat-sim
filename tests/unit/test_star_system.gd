extends GutTest
## The star system's data and its binding to the native ephemeris (M6-T03): the file's answers, a reason for every
## rejection, and values that round-trip through the core.

const STATION_RADIUS_M: float = 2.75e7
const PLANET_GM: float = 1.68e14
const PLANET_RADIUS_M: float = 4.78e6


func _orbit(a_m: float = 2.75e7, e: float = 0.0) -> Dictionary:
	return {"a_m": a_m, "e": e}


# A small valid table that each test spoils in one way.
func _table() -> Dictionary:
	return {
		"bodies": [
			{"id": "sun", "kind": "star", "gm": 1.0e20, "radius_m": 5.0e8},
			{"id": "rock", "kind": "planet", "parent": "sun", "gm": PLANET_GM, "radius_m": PLANET_RADIUS_M,
					"orbit": _orbit(9.0e10)},
		],
		"places": [
			{"id": "post", "parent": "rock", "orbit": _orbit()},
			{"id": "gate", "same_orbit_as": "post", "phase_rad": 0.002},
		],
	}


func _build(table: Dictionary) -> StarSystem:
	var system := StarSystem.new()
	system.build(&"t", table)
	return system


func _rejected(table: Dictionary, reason: String) -> void:
	var system: StarSystem = _build(table)
	assert_false(system.is_valid(), "rejected: %s" % reason)
	assert_true("\n".join(system.errors).contains(reason), "says '%s', got %s" % [reason, system.errors])


func test_the_shipped_file_loads() -> void:
	var system: StarSystem = StarSystem.load_system(&"local")
	assert_true(system.is_valid(), "valid: %s" % system.errors)
	assert_eq(system.body_ids, [&"epsilon", &"epsilon_iii"] as Array[StringName], "the star and Epsilon III, no moons")
	assert_eq(system.place_ids, [&"babylon5", &"jumpgate"] as Array[StringName], "the station and the gate")
	assert_eq(system.a_min, 0.5, "the floor")
	var planet: Dictionary = system.info(&"epsilon_iii")
	assert_almost_eq(float(planet["radius_m"]), 4.78e6, 1.0, "9 560 km across")
	assert_almost_eq(float(planet["gm"]) / (float(planet["radius_m"]) * float(planet["radius_m"])), 0.75 * 9.80665, 0.1,
			"0.75 g at the surface")
	assert_gt(float(planet["atmosphere_top_m"]), 0.0, "a thin atmosphere")


func test_the_gate_stays_about_50_km_from_the_station_at_any_time() -> void:
	var system: StarSystem = StarSystem.load_system(&"local")
	for time_s: float in [0.0, 1234.5, 3.0e4, 7.0e4, 1.0e6, 3.2e7]:
		assert_almost_eq(system.distance_m(&"jumpgate", &"babylon5", time_s), 50000.0, 100.0, "gate at t=%s" % time_s)


func test_the_station_orbit_takes_19_4_hours_at_27_500_km() -> void:
	var system: StarSystem = StarSystem.load_system(&"local")
	assert_almost_eq(system.period_s(&"babylon5") / 3600.0, 19.4, 0.05, "period")
	assert_almost_eq(system.period_s(&"jumpgate"), system.period_s(&"babylon5"), 1.0e-6, "the gate rides the same orbit")
	var rel: PackedFloat64Array = system.relative_state(&"babylon5", &"epsilon_iii", 5000.0)
	var speed: float = Vector3(rel[3], rel[4], rel[5]).length()
	assert_almost_eq(speed, 2470.0, 10.0, "orbital speed")
	assert_almost_eq(Vector3(rel[0], rel[1], rel[2]).length(), 2.75e7, 1.0, "radius")


func test_positions_come_through_the_binding_in_64_bit() -> void:
	var system: StarSystem = StarSystem.load_system(&"local")
	var rel: PackedFloat64Array = system.relative_state(&"babylon5", &"epsilon_iii", 0.0)
	assert_eq(rel.size(), 6, "position and velocity")
	assert_almost_eq(rel[0], 2.75e7, 1.0e-6, "starts on the x axis")
	var far: PackedFloat64Array = system.state(&"epsilon_iii", 0.0)
	assert_almost_eq(far[0], 8.976e10, 1.0, "the planet at 0.6 AU")
	assert_eq(system.state(&"nobody", 0.0).size(), 0, "an unknown id answers nothing")


func test_the_dominant_body_and_the_zone() -> void:
	var system: StarSystem = StarSystem.load_system(&"local")
	assert_eq(system.dominant_body(PackedFloat64Array([1.0e7, 0.0, 0.0]), &"epsilon_iii", 0.0), &"epsilon_iii",
			"the planet holds a low orbit")
	assert_eq(system.dominant_body(PackedFloat64Array([-8.0e10, 0.0, 0.0]), &"epsilon_iii", 0.0), &"epsilon",
			"the star holds the space near it")
	# At a_min 0.5 the planet's pull (0.22 m/s^2 at 27 500 km) is under the floor, so nothing pulls at the station.
	assert_eq(system.dominant_body(PackedFloat64Array([STATION_RADIUS_M, 0.0, 0.0]), &"epsilon_iii", 0.0), &"",
			"the station sits outside every zone at the shipped floor")
	assert_almost_eq(system.zone_radius_m(&"epsilon_iii"), sqrt(PLANET_GM / 0.5), 1.0, "the zone ends at a_min")
	assert_eq(system.zone_radius_m(&"babylon5"), 0.0, "a place has no pull")


func test_a_good_table_loads() -> void:
	assert_true(_build(_table()).is_valid(), "the base table")


func test_rejections_carry_reasons() -> void:
	var t: Dictionary = _table()
	t["bodies"][1]["parent"] = "ghost"
	_rejected(t, "unknown parent 'ghost'")
	t = _table()
	t["bodies"][1]["orbit"]["e"] = 1.0
	_rejected(t, "orbit.e")
	t = _table()
	t["bodies"][1]["radius_m"] = -5.0
	_rejected(t, "radius_m must be a positive")
	t = _table()
	t["bodies"][1]["gm"] = -1.0
	_rejected(t, "gm must be a positive")
	t = _table()
	t["places"][1]["same_orbit_as"] = "nowhere"
	_rejected(t, "unknown 'nowhere'")
	t = _table()
	t["places"][0]["parent"] = "nowhere"
	_rejected(t, "unknown parent 'nowhere'")
	t = _table()
	t["bodies"][1]["id"] = "sun"
	_rejected(t, "duplicate id 'sun'")
	t = _table()
	t["places"][0]["id"] = "rock"
	_rejected(t, "duplicate id 'rock'")
	t = _table()
	t["bodies"][1]["kind"] = "comet"
	_rejected(t, "kind must be")
	t = _table()
	t["bodies"][1]["orbit"]["a_m"] = 1.0e6
	_rejected(t, "inside its parent")
	t = _table()
	t["places"][1]["same_orbit_as"] = "sun"
	_rejected(t, "needs an orbit to ride")
	t = _table()
	t["bodies"].remove_at(0)
	_rejected(t, "unknown parent 'sun'")
	t = _table()
	t["a_min"] = -1.0
	_rejected(t, "a_min")
	t = _table()
	t["bodies"] = []
	_rejected(t, "bodies must be")


func test_a_missing_system_or_file_says_why() -> void:
	assert_false(StarSystem.load_system(&"nowhere").is_valid(), "unknown system")
	assert_string_contains("\n".join(StarSystem.load_system(&"local", "res://data/none.json").errors), "cannot be read")


func test_the_star_catalog_still_reads_the_file() -> void:
	assert_eq(StarCatalog.temperature_k(&"local"), 5084.0, "temperature")
	assert_false(StarCatalog.parse(FileAccess.get_file_as_string(StarCatalog.PATH)).has("error"), "parses")
