extends GutTest
## DockRepair (M8-T06, D82): the time a docked fighter spends in the bay follows the damage it came in with.


func test_a_whole_ship_takes_only_the_handling_time() -> void:
	var repair := DockRepair.new()
	assert_almost_eq(repair.time_s(1.0, 1.0, 1.0), repair.base_s, 1e-6)


func test_the_time_grows_with_the_hull_charge_and_fuel_missing() -> void:
	var repair := DockRepair.from_dict({"base_s": 5.0, "hull_s": 40.0, "rearm_s": 4.0, "refuel_s": 2.0, "max_s": 100.0})
	assert_almost_eq(repair.time_s(0.5), 25.0, 1e-6, "half a hull")
	assert_almost_eq(repair.time_s(0.5, 0.0, 0.5), 30.0, 1e-6, "and empty guns and half a tank")
	assert_gt(repair.time_s(0.2), repair.time_s(0.6), "more damage, longer")


func test_the_time_is_capped() -> void:
	var repair := DockRepair.from_dict({"base_s": 5.0, "hull_s": 400.0, "max_s": 30.0})
	assert_almost_eq(repair.time_s(0.0), 30.0, 1e-6)


func test_the_game_data_loads() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DockingDirector.DATA_PATH))
	var repair := DockRepair.from_dict(data["repair"])
	assert_gt(repair.hull_s, 0.0)
	assert_gt(repair.time_s(0.3), repair.time_s(0.9))
	assert_between(float((data["wingman"] as Dictionary)["hull_below"]), 0.05, 0.95, "the wingmen's hull threshold is data")


func test_bad_data_keeps_the_defaults() -> void:
	var repair := DockRepair.from_dict("nonsense")
	assert_eq(repair.base_s, DockRepair.new().base_s)
