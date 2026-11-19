extends GutTest
## ShotPool and ShotSequencer (M8-T31): a cinematic whose stages last as long as the action is cut into short takes from a pool
## (docking's `data/station/docking_shots.json`): each take held to its longest (under 3 s, a feature under 5 s) and at least 1 s,
## a new stage cut at once or once the take on screen has had its second, never the same take twice in a row, never the last
## sequence's opening, only the takes the caller's clearance passes; one call stops it.

const DOCKING: String = "res://data/station/docking_shots.json"

var pool: ShotPool


func before_each() -> void:
	pool = ShotPool.load_file(DOCKING)


func test_the_docking_pool_holds_every_stage_with_takes_inside_the_rules() -> void:
	assert_eq(pool.error, "")
	for stage: StringName in [&"approach", &"lane", &"roll", &"entry", &"wait"]:
		assert_gte(pool.ids(stage).size(), 2, "%s has a choice" % stage)
	for stage: StringName in pool.stages():
		for id: String in pool.ids(stage):
			var keys: Array = pool.keys(stage, id)
			var length: float = float(keys[keys.size() - 1]["t"]) - float(keys[0]["t"])
			assert_lt(length, 5.0 if pool.is_feature(stage, id) else 3.0, "%s/%s as written" % [stage, id])
			assert_gt(length, pool.max_s(stage, id), "%s/%s outlasts its cut, so it never ends early" % [stage, id])
			assert_true(bool(CinematicShot.from_dict(&"t", {"keys": keys})["ok"]), "%s/%s is a valid shot" % [stage, id])
	assert_true(pool.is_feature(&"roll", "roll_drum"), "the roll match is a feature: it shows the ship turning with the drum")


# A whole sequence on its clock: takes between 1 s and their limit, a stage change waiting for the take's second.
func test_takes_are_held_between_a_second_and_their_limit_and_never_repeat_back_to_back() -> void:
	var seq := ShotSequencer.new(pool, "test")
	var starts: Array[float] = []
	var names: Array[String] = []
	var play: Callable = func(shot: CinematicShot) -> void:
		starts.append(seq.clock_s)
		names.append(String(shot.id))
	var dt: float = 1.0 / 60.0
	seq.begin(&"approach", play)
	var plan: Array = [[&"approach", 7.0], [&"lane", 0.3], [&"roll", 6.0], [&"entry", 4.0], [&"wait", 9.0]]
	for step: Array in plan:
		seq.to_stage(step[0], play)
		for i: int in roundi(float(step[1]) / dt):
			seq.tick(dt, play)
	for i: int in starts.size() - 1:
		var held: float = starts[i + 1] - starts[i]
		assert_gte(held, ShotPool.MIN_HOLD_S - dt, "%s held %.2f s" % [names[i], held])
		var limit: float = 5.0 if names[i].begins_with("roll_") else 3.0
		assert_lt(held, limit, "%s held %.2f s" % [names[i], held])
		assert_ne(names[i + 1], names[i], "%s twice in a row" % names[i])
	assert_true(names.any(func(n: String) -> bool: return n.begins_with("lane_")), "a short stage still gets its take (1 s)")
	var opening: String = seq.sequence()[0]
	seq.begin(&"approach", play)
	assert_ne(seq.sequence()[0], opening, "the next sequence opens differently")


func test_blocked_takes_are_skipped_and_one_call_stops_everything() -> void:
	var seq := ShotSequencer.new(pool, "test")
	seq.usable = func(stage: StringName, id: String) -> bool: return not (stage == &"approach" and id == "trail_close")
	var names: Array[String] = []
	var play: Callable = func(shot: CinematicShot) -> void: names.append(String(shot.id))
	seq.begin(&"approach", play)
	for i: int in 600:
		seq.tick(1.0 / 60.0, play)
	assert_false(names.has("approach_trail_close"), "a take that fails the clearance never plays")
	var stopped: Array[bool] = [false]
	seq.stop(func() -> void: stopped[0] = true)
	var count: int = names.size()
	seq.tick(10.0, play)
	seq.to_stage(&"lane", play)
	assert_true(stopped[0])
	assert_false(seq.is_running())
	assert_eq(names.size(), count, "nothing plays after the stop")
