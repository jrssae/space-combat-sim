extends GutTest
## `BotData` (M7-T11): the loops' file, and how many bots it asks for (D78's handful).

func test_the_shipped_loops_are_valid() -> void:
	var data: BotData = BotData.load_file()
	assert_true(data.valid, data.error)
	assert_between(data.bot_count(), 6, 10, "a handful of bots (Q11, D78)")
	assert_gt(data.clearance_m, 5.0, "the file states the clearance the loops keep")
	var bodies := {}
	for loop: Dictionary in data.loops:
		bodies[loop["body"]] = true
		assert_lte(float(loop["speed_mps"]), 5.0, "%s: a slow loop" % loop["name"])
		assert_gte((loop["points"] as PackedVector3Array).size(), 3)
		for hatch: Dictionary in loop["hatches"]:
			assert_lt(int(hatch["at"]), (loop["points"] as PackedVector3Array).size())
	assert_true(bodies.has(StationHardpoints.FRAME) and bodies.has(StationHardpoints.DRUM), "some bots on the frame and some riding the drum")


func test_a_broken_file_says_why() -> void:
	assert_false(BotData.from_dict({}).valid)
	var good: Dictionary = {"loops": [{"name": "a", "body": "frame", "speed_mps": 3, "up": [0, 1, 0],
			"points": [[0, 0, 0], [10, 0, 0], [10, 0, 10]], "hatches": [{"at": 0, "inside": [0, -5, 0]}]}]}
	assert_true(BotData.from_dict(good).valid, BotData.from_dict(good).error)
	var no_hatch: Dictionary = good.duplicate(true)
	no_hatch["loops"][0]["hatches"] = []
	assert_string_contains(BotData.from_dict(no_hatch).error, "no hatch")
	var bad_body: Dictionary = good.duplicate(true)
	bad_body["loops"][0]["body"] = "wing"
	assert_string_contains(BotData.from_dict(bad_body).error, "body")
	var few: Dictionary = good.duplicate(true)
	few["loops"][0]["points"] = [[0, 0, 0], [1, 0, 0]]
	assert_string_contains(BotData.from_dict(few).error, "three points")
	var bad_hatch: Dictionary = good.duplicate(true)
	bad_hatch["loops"][0]["hatches"][0]["at"] = 9
	assert_string_contains(BotData.from_dict(bad_hatch).error, "hatch")
	assert_false(BotData.load_file("res://data/station/none.json").valid)
