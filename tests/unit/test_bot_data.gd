extends GutTest
## `BotData` (M7-T35): the crew's file: its tunables, the roads out of the cargo bay, the peace areas and the work spots.


func test_the_file_reads() -> void:
	var data: BotData = BotData.load_file()
	assert_true(data.valid, data.error)
	assert_eq(data.pool, 12)
	assert_eq(data.peace_min, 3)
	assert_eq(data.peace_max, 6)
	assert_eq(data.battle_max, 12)
	assert_eq(data.repair_hp_s, 10.0, "the maintainer's rate")
	assert_gte(data.peace.size(), data.peace_max, "enough areas for one bot each at the most")
	var kinds := {}
	for a: Dictionary in data.peace:
		kinds[a["kind"]] = true
	for kind: String in BotData.PEACE_KINDS:
		assert_true(kinds.has(kind), "a %s patrol" % kind)
	for s: String in ["command", "docking_sphere", "cobra_bays", "forward_drum", "green_zone", "aft_drum", "spine", "cargo",
			"vanes", "hub", "reactor"]:
		assert_true(data.sections.has(s), "a work spot for %s" % s)
	assert_eq(data.bot_count(), data.pool)


func test_the_drum_radius_follows_the_profile() -> void:
	var data: BotData = BotData.load_file()
	assert_almost_eq(data.drum_radius(-1000.0), 355.0, 0.01)
	assert_almost_eq(data.drum_radius(-5000.0), data.drum_profile[0].y, 0.01, "held at the ends")
	assert_almost_eq(data.drum_radius(-1350.0), 360.0, 0.01)


func test_a_broken_file_says_why() -> void:
	assert_false(BotData.from_dict({}).valid)
	var good: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BotData.PATH))
	assert_true(BotData.from_dict(good).valid, BotData.from_dict(good).error)
	var no_peace: Dictionary = good.duplicate(true)
	no_peace["peace"] = []
	assert_string_contains(BotData.from_dict(no_peace).error, "peace")
	var bad_kind: Dictionary = good.duplicate(true)
	bad_kind["peace"][0]["kind"] = "moon"
	assert_string_contains(BotData.from_dict(bad_kind).error, "kind")
	var no_trunk: Dictionary = good.duplicate(true)
	no_trunk["roads"]["trunk"] = [[0, 0, 0]]
	assert_string_contains(BotData.from_dict(no_trunk).error, "trunk")
	var bad_rate: Dictionary = good.duplicate(true)
	bad_rate["crew"]["repair_hp_s"] = 0
	assert_string_contains(BotData.from_dict(bad_rate).error, "crew")
