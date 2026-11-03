extends GutTest
## BattleMix (M4-T07, Q19 and Q21): the load a `typical` mission and the grand multi-side battle put on the tick, per entity
## type, from the ship count. The numbers are the milestone's table ("What the battle is"); every one is a profile parameter.


func _c(profile: StringName, n: int) -> Dictionary:
	return BattleMix.counts(BattleMix.profile(profile), n)


func test_typical_at_58_is_the_usual_mission() -> void:
	var c: Dictionary = _c(BattleMix.TYPICAL, 58)
	assert_eq(int(c["ships"]), 58)
	assert_eq(int(c["fighters"]), 50)
	assert_eq(int(c["capitals"]), 8, "under 10 capitals (Q21)")
	assert_eq([int(c["carriers"]), int(c["destroyers"]), int(c["cruisers"])], [2, 3, 3])
	assert_eq(int(c["turrets"]), 78, "carrier 12, destroyer 10, cruiser 8")
	assert_eq(int(c["beams"]), 16)
	assert_eq(int(c["interceptors"]), 32)
	assert_eq(int(c["missiles"]), 20)
	assert_eq(int(c["mines"]), 100, "at least 100")
	assert_eq(int(c["asteroids"]), 1000)
	assert_eq(int(c["sides"]), 2)
	assert_eq(int(c["gravity_sources"]), 1)
	assert_eq(c["area_m"] as Vector3, Vector3(20000.0, 10000.0, 20000.0))


func test_the_grand_battle_at_100_500_and_1000() -> void:
	var expected: Dictionary = {
		100: {"capitals": 15, "fighters": 85, "classes": [3, 5, 7], "turrets": 142, "beams": 30, "interceptors": 60, "missiles": 34,
				"mines": 100},
		500: {"capitals": 75, "fighters": 425, "classes": [15, 25, 35], "turrets": 710, "beams": 150, "interceptors": 300,
				"missiles": 170, "mines": 500},
		1000: {"capitals": 150, "fighters": 850, "classes": [30, 50, 70], "turrets": 1420, "beams": 300, "interceptors": 600,
				"missiles": 340, "mines": 1000},
	}
	for n: int in expected:
		var want: Dictionary = expected[n]
		var c: Dictionary = _c(BattleMix.GRAND, n)
		assert_eq(int(c["ships"]), n)
		assert_eq(int(c["capitals"]), int(want["capitals"]), "%d: round(0.15 n) capitals" % n)
		assert_eq(int(c["fighters"]), int(want["fighters"]), "%d: the rest are fighters" % n)
		assert_eq([int(c["carriers"]), int(c["destroyers"]), int(c["cruisers"])], want["classes"], "%d: the classes" % n)
		for key: String in ["turrets", "beams", "interceptors", "missiles", "mines"]:
			assert_eq(int(c[key]), int(want[key]), "%d: %s" % [n, key])
		assert_eq(int(c["sides"]), 4, "four sides, every pair hostile")
		assert_eq(int(c["asteroids"]), 1000)
	assert_eq(_c(BattleMix.GRAND, 500)["area_m"] as Vector3, Vector3(60000.0, 20000.0, 60000.0), "60 by 60 by 20 km at 500")
	var stretch: Vector3 = _c(BattleMix.GRAND, 1000)["area_m"]
	assert_almost_eq(stretch.x, 85000.0, 500.0, "about 85 km across at the 1 000 stretch")
	assert_eq(stretch.y, 20000.0, "the battle stays 20 km deep")


func test_counts_scale_with_n() -> void:
	var p: Dictionary = BattleMix.profile(BattleMix.GRAND)
	var last: Dictionary = BattleMix.counts(p, 10)
	for n: int in [25, 50, 100, 150, 200, 300, 400, 500, 1000]:
		var c: Dictionary = BattleMix.counts(p, n)
		assert_eq(int(c["fighters"]) + int(c["capitals"]), n, "%d: fighters and capitals make N" % n)
		assert_eq(int(c["carriers"]) + int(c["destroyers"]) + int(c["cruisers"]), int(c["capitals"]), "%d: every capital has a class" % n)
		for key: String in ["capitals", "fighters", "turrets", "interceptors", "beams", "missiles", "mines"]:
			assert_gte(int(c[key]), int(last[key]), "%d: %s never falls as N grows" % [n, key])
		last = c


func test_every_number_is_a_parameter() -> void:
	var p: Dictionary = BattleMix.profile(BattleMix.GRAND)
	p["capital_share"] = 0.2  # the stretch's upper edge (Q21: 100 to 200 capitals at 1 000)
	p["turrets_per_class"] = {"carrier": 6, "destroyer": 5, "cruiser": 4}
	p["mines_min"] = 0
	p["mines_per_ship"] = 0.5
	var c: Dictionary = BattleMix.counts(p, 1000)
	assert_eq(int(c["capitals"]), 200)
	assert_eq(int(c["fighters"]), 800)
	assert_eq(int(c["turrets"]), int(c["carriers"]) * 6 + int(c["destroyers"]) * 5 + int(c["cruisers"]) * 4)
	assert_eq(int(c["mines"]), 500)
	assert_eq(int(BattleMix.counts(BattleMix.profile(BattleMix.GRAND), 1000)["capitals"]), 150, "a profile is a copy: the table is unchanged")


func test_no_ships_no_load_and_unknown_profiles_are_empty() -> void:
	var c: Dictionary = _c(BattleMix.GRAND, 0)
	assert_eq(int(c["ships"]), 0)
	assert_eq(int(c["turrets"]), 0)
	assert_eq(int(c["mines"]), 0, "no battle, no mines")
	assert_true(BattleMix.profile(&"parade").is_empty())
	assert_eq(BattleMix.counts({}, 50), {}, "an empty profile counts nothing")


func test_the_mix_prints_as_one_line() -> void:
	var line: String = BattleMix.describe(_c(BattleMix.TYPICAL, 58))
	for word: String in ["50 fighters", "8 capitals", "78 turrets", "32 interceptors", "1000 asteroids", "2 sides"]:
		assert_true(line.contains(word), "'%s' in: %s" % [word, line])
