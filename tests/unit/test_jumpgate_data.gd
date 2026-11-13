extends GutTest
## The jumpgate's data seams (M6-T14): the scenario's `jumpgates[]`, the shipped scenes that place it from the star-system
## data, and the encounters' `gate` table (a share of each kind through the gate, none without the table).


func _scenario(gate: Dictionary) -> Dictionary:
	return ScenarioLoader.from_data({"scenario_id": "t", "system_id": "local",
			"player": {"position": [0, 0, 0], "forward": [0, 0, -1]}, "jumpgates": [gate]})


func test_a_gate_with_no_position_is_placed_from_the_system_data() -> void:
	var s: Dictionary = _scenario({"name": "GATE"})
	assert_true(s["ok"], s["error"])
	assert_eq((s["props"] as Array).size(), 0, "a gate is not one of the props (the buoys)")
	var entry: Dictionary = s["jumpgates"][0]
	assert_eq(entry["type"], ScenarioLoader.JUMPGATE)
	assert_null(entry["position"], "Main reads the distance from the star system")
	assert_eq(entry["place"], &"jumpgate")
	assert_eq(entry["from"], &"babylon5")
	assert_eq(entry["bearing"], Vector3(0.0, 0.0, -1.0))
	assert_eq(entry["facing"], Vector3(0.0, 0.0, 1.0), "its front faces back at the station")


func test_a_gate_may_be_given_a_position_and_facing() -> void:
	var s: Dictionary = _scenario({"name": "GATE", "position": [100, 0, -9000], "facing": [1, 0, 0]})
	assert_true(s["ok"], s["error"])
	assert_eq((s["jumpgates"][0]["position"] as UniversePos).z, -9000.0)
	assert_eq(s["jumpgates"][0]["facing"], Vector3.RIGHT)


func test_a_broken_gate_says_why() -> void:
	assert_string_contains(_scenario({"name": "G", "bearing": [0, 0, 0]})["error"], "bearing")
	assert_string_contains(_scenario({"name": "G", "facing": "up"})["error"], "facing")
	assert_string_contains(_scenario({"name": "G", "from": ""})["error"], "from")
	assert_string_contains(_scenario({"name": ""})["error"], "name")


func test_free_flight_and_the_sandbox_place_the_gate_50_km_from_the_station() -> void:
	var system: StarSystem = StarSystem.load_system(&"local")
	assert_true(system.is_valid(), "; ".join(system.errors))
	assert_almost_eq(system.distance_m(&"jumpgate", &"babylon5", 0.0), 50000.0, 10.0, "Q3: about 50 km on the same orbit")
	for path: String in [ScenarioLoader.FREE_FLIGHT_PATH, ScenarioLoader.SANDBOX_PATH]:
		var s: Dictionary = ScenarioLoader.load(path)
		assert_true(s["ok"], s["error"])
		assert_eq((s["jumpgates"] as Array).size(), 1, path)
		assert_null(s["jumpgates"][0]["position"], "%s: placed from the system data" % path)


func test_the_gate_table_splits_each_kind() -> void:
	var plan := EncounterPlan.new(7)
	assert_eq(plan.gate_use(0, &"traffic"), &"", "no table: nothing uses the gate")
	plan.gate_shares = EncounterPlan.parse_gate_shares({"arrive": {"raid": 1.0, "traffic": 0.5}, "depart": {"raid": 1.0, "traffic": 0.5}})
	var arrive: int = 0
	var depart: int = 0
	for i: int in 400:
		assert_eq(plan.gate_use(i, &"raid"), EncounterPlan.GATE_ARRIVE, "every raid arrives; a raid never departs")
		match plan.gate_use(i, &"traffic"):
			EncounterPlan.GATE_ARRIVE:
				arrive += 1
			EncounterPlan.GATE_DEPART:
				depart += 1
		assert_eq(plan.gate_use(i, &"patrol"), &"", "a kind the table leaves out stays as it was")
	assert_eq(arrive + depart, 400, "a half and a half fill the traffic")
	assert_between(arrive, 160, 240)
	assert_eq(plan.gate_use(3, &"traffic"), plan.gate_use(3, &"traffic"), "the same seed and event, the same choice")


func test_the_gate_table_leaves_the_plan_as_it_was() -> void:
	var before: Dictionary = EncounterPlan.new(11).event(5).describe()
	var plan := EncounterPlan.new(11)
	plan.gate_shares = EncounterPlan.parse_gate_shares({"arrive": {"raid": 1.0}})
	assert_eq_deep(plan.event(5).describe(), before)
	assert_true(EncounterPlan.parse_gate_shares({"arrive": "all"}).is_empty(), "a malformed table is no table")
