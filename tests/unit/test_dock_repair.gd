extends GutTest
## DockRepair (M8-T06, D82; maintainer, 2026-11-18): an AI wingman waits a fixed time in the bay, the player none.


func test_an_ai_wingman_waits_a_fixed_time_and_the_player_none() -> void:
	var repair := DockRepair.new()
	assert_eq(repair.time_s(false), 30.0)
	assert_eq(repair.time_s(true), 0.0, "the player is repaired on the way through")


func test_the_times_are_data() -> void:
	var repair := DockRepair.from_dict({"wingman_s": 12.0, "player_s": 2.0})
	assert_eq(repair.time_s(false), 12.0)
	assert_eq(repair.time_s(true), 2.0)
	assert_eq(DockRepair.from_dict({"wingman_s": -5.0}).time_s(false), 0.0, "never below zero")


func test_the_game_data_loads() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DockingDirector.DATA_PATH))
	var repair := DockRepair.from_dict(data["repair"])
	assert_eq(repair.time_s(false), 30.0, "30 s for an AI wingman")
	assert_eq(repair.time_s(true), 0.0, "no wait for the player")
	assert_almost_eq(float((data["wingman"] as Dictionary)["hull_below"]), 0.25, 1e-6, "the self-dock threshold is data")


func test_bad_data_keeps_the_defaults() -> void:
	var repair := DockRepair.from_dict("nonsense")
	assert_eq(repair.wingman_s, DockRepair.new().wingman_s)
