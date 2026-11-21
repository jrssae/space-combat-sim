extends GutTest
## `FlightRules` (M8-T19, D85): the flights' numbers from `data/wings/flights.json`, and which flight and place a squadron's
## nth fighter takes.


func test_the_games_rules_are_flights_of_three_with_a_cohesion_distance() -> void:
	var rules: FlightRules = FlightRules.from_file()
	assert_eq(rules.size, 3, "a lead and two wingmen")
	assert_eq(rules.wingmen(), 2)
	assert_gt(rules.cohesion_m, rules.rejoined_m, "a wingman rejoins nearer than where it broke off")
	assert_gt(rules.rejoined_m, BehaviourFormation.ALIGN_RANGE_M, "and is back before it is on its slot")
	assert_lt(rules.cohesion_m, ContactScan.SENSOR_RANGE_M, "the lead is still in sight where the wingman breaks off")
	assert_gt(rules.lead_spacing, 1.0, "the flights' leads form up wider apart than their wingmen")
	assert_same(FlightRules.shared(), FlightRules.shared(), "read once")


func test_a_squadron_of_twelve_splits_into_four_flights_whose_leads_are_1_4_7_and_10() -> void:
	var rules := FlightRules.new()
	var places: Array[Vector2i] = []
	for i: int in 12:
		places.append(rules.split(i))
	assert_eq(places[0], Vector2i(1, 0), "the first leads flight 1")
	assert_eq(places[2], Vector2i(1, 2))
	assert_eq(places[3], Vector2i(2, 0), "the fourth leads flight 2")
	assert_eq(places[11], Vector2i(4, 2))
	for flight: int in range(1, 5):
		assert_eq(rules.first_number(flight), [1, 4, 7, 10][flight - 1])
	# Behind the player's own flight the others count from 2: nine ships are flights 2, 3 and 4.
	assert_eq(rules.split(0, 2), Vector2i(2, 0))
	assert_eq(rules.split(8, 2), Vector2i(4, 2))
	# A count that does not divide leaves the last flight short.
	assert_eq(rules.split(3), Vector2i(2, 0), "a fourth ship of four leads a flight of one")


func test_bad_numbers_keep_the_defaults_and_say_so() -> void:
	var rules: FlightRules = FlightRules.from_dict({"size": 1, "cohesion_m": -5, "rejoined_m": "near", "lead_spacing": 0}, "test")
	assert_eq(rules.size, 3)
	assert_eq(rules.cohesion_m, 2500.0)
	assert_eq(rules.rejoined_m, 1000.0)
	assert_eq(rules.lead_spacing, 4.0)
	assert_push_warning_count(4, "one line per bad number")
	# A rejoin distance that is not inside the cohesion distance would never let a wingman fight again.
	var crossed: FlightRules = FlightRules.from_dict({"cohesion_m": 800.0, "rejoined_m": 900.0}, "test")
	assert_eq(crossed.rejoined_m, 400.0)
	assert_push_warning("rejoined_m must be less than cohesion_m")
	var good: FlightRules = FlightRules.from_dict({"size": 4, "cohesion_m": 3000, "rejoined_m": 500, "lead_spacing": 2.5})
	assert_eq(good.size, 4)
	assert_eq(good.first_number(3), 9)
	assert_eq(good.cohesion_m, 3000.0)
	assert_eq(good.rejoined_m, 500.0)
	assert_eq(good.lead_spacing, 2.5)
	assert_eq(FlightRules.from_file("res://data/wings/no_such_file.json").size, 3, "a missing file gives the defaults")
	assert_push_warning("is missing or not a JSON object")
