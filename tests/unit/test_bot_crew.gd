extends GutTest
## `BotCrew` (M7-T35): peace patrols one bot an area at a time, irregularly and 3 to 6 at once; in a fight one bot a damaged area
## (up to 12), each repairing 10 HP/s; a knocked-out turret comes back and a lost section can be repaired and lost again.

const DT: float = 1.0 / 60.0

var data: BotData
var frames: BotFrames
var sections: StationSections
var mounts: GridMountHealth
var areas: BotRepairAreas
var crew: BotCrew
var now_s: float = 0.0


func before_each() -> void:
	data = BotData.load_file()
	assert_true(data.valid, data.error)
	frames = BotFrames.new()
	frames.pivot = Vector3(0, 0, -1000)
	frames.spin_rate = 0.148
	frames.has_gate = true
	frames.gate = Transform3D(Basis.looking_at(Vector3(0, 0, 1)), Vector3(0, 0, -50000))
	sections = StationSections.new()
	for entry: Array in [["command", "frame"], ["spine", "frame"], ["green_zone", "drum"], ["docking_sphere", "drum"],
			["vanes", "frame"], ["hub", "frame"], ["reactor", "frame"], ["cargo", "frame"], ["cobra_bays", "drum"],
			["forward_drum", "drum"], ["aft_drum", "drum"]]:
		sections.sections.append({"name": entry[0], "body": entry[1], "aabb": AABB()})
		sections.max_health.append(5000.0)
	sections.health = sections.max_health.duplicate()
	var points: Array[Dictionary] = [
		{"name": "L10", "kind": "light_pulse", "body": "frame", "position": Vector3(0, 537, -1350), "up": Vector3.UP},
		{"name": "L3", "kind": "light_pulse", "body": "drum", "position": Vector3(292, 41, -2310), "up": Vector3.RIGHT},
		{"name": "I6", "kind": "interceptor", "body": "frame", "position": Vector3(40, 459, -2500), "up": Vector3.UP}]
	mounts = GridMountHealth.from_mounts(points, func(k: String) -> int: return 3 if k == "interceptor" else 1)
	areas = BotRepairAreas.make(sections, mounts, points)
	crew = BotCrew.make(data, frames, areas, data.trunk[0])
	now_s = 0.0


func _run(seconds: float, quiet: bool = true, alarmed := PackedByteArray()) -> void:
	var poll: float = 0.0
	for i: int in int(seconds / DT):
		now_s += DT
		frames.drum_angle = fposmod(frames.drum_angle + frames.spin_rate * DT, TAU)
		poll += DT
		if poll >= 0.25:
			poll = 0.0
			crew.decide(now_s, alarmed, quiet)
		for m: BotCrewMotion in crew.motions:
			m.step(DT, false)
		crew.work(DT, PackedByteArray())


func _jobs() -> Dictionary:
	var jobs := {}
	for i: int in crew.motions.size():
		var job: String = crew.job_of(i)
		if not job.is_empty():
			jobs[job] = int(jobs.get(job, 0)) + 1
	return jobs


func test_peace_keeps_three_to_six_out_one_an_area() -> void:
	var least: int = 99
	var most: int = 0
	var areas_seen := {}
	for k: int in 120:
		_run(10.0)
		var out: int = crew.peace_out()
		if now_s > 30.0:
			least = mini(least, out)
		most = maxi(most, out)
		for job: String in _jobs():
			assert_eq(int(_jobs()[job]), 1, "one bot on %s" % job)
			areas_seen[job] = true
	assert_gte(least, data.peace_min, "never fewer than %d out" % data.peace_min)
	assert_lte(most, data.peace_max, "never more than %d out" % data.peace_max)
	for name: String in ["spine", "fins_port", "fins_starboard", "drum_fore", "drum_aft", "gate"]:
		assert_true(areas_seen.has(name), "%s was patrolled" % name)


func test_peace_waits_are_irregular_and_seeded() -> void:
	var waits := {}
	for a: int in data.peace.size():
		for n: int in 3:
			waits[snappedf(lerpf(data.peace_wait_s.x, data.peace_wait_s.y, BotCrew.unit_of(data.peace[a]["name"], n)), 0.1)] = true
	assert_gt(waits.size(), 12, "the waits differ by area and trip")
	assert_eq(BotCrew.unit_of("spine", 4), BotCrew.unit_of("spine", 4), "the same seed gives the same wait")


func test_fighting_stops_new_patrols_and_sends_the_near_ones_home() -> void:
	_run(60.0)
	assert_gt(crew.peace_out(), 0)
	var alarmed := PackedByteArray()
	alarmed.resize(crew.motions.size())
	alarmed.fill(1)
	_run(1.0, false, alarmed)
	for i: int in crew.motions.size():
		if not crew.motions[i].is_docked():
			assert_true(crew.motions[i].homeward(), "Bot%d turned for home" % (i + 1))
	_run(900.0, false, alarmed)
	assert_eq(crew.out_count(), 0, "all home, none sent while the fight lasts")


func test_battle_sends_one_bot_a_damaged_area_up_to_twelve() -> void:
	crew.peace_on = false
	for i: int in sections.count():
		sections.damage(i, 1000.0)
	for j: int in mounts.count():
		mounts.wear(j, 50.0)
	_run(1.0, false)
	assert_eq(crew.repair_out(), mini(areas.count(), data.battle_max), "one bot per damaged area, at most %d" % data.battle_max)
	var jobs: Dictionary = _jobs()
	for job: String in jobs:
		assert_eq(int(jobs[job]), 1, "one bot on %s" % job)


func test_a_few_damaged_areas_get_a_bot_each_and_no_more() -> void:
	crew.peace_on = false
	sections.damage(sections.index_of("spine"), 300.0)
	sections.damage(sections.index_of("green_zone"), 300.0)
	mounts.wear(0, 300.0)
	_run(1.0, false)
	assert_eq(crew.repair_out(), 3)
	_run(30.0, false)
	assert_eq(crew.repair_out(), 3, "no second bot for an area already served")


func test_a_bot_repairs_ten_hp_a_second_at_its_spot() -> void:
	crew.peace_on = false
	var spine: int = sections.index_of("spine")
	sections.damage(spine, 2000.0)
	_run(0.5, false)
	var bot: int = crew.repair_bot[spine]
	assert_gte(bot, 0)
	for i: int in int(600.0 / DT):
		_run(DT, false)
		if crew.motions[bot].at_work():
			break
	assert_true(crew.motions[bot].at_work(), "at its work spot")
	var before: float = sections.health[spine]
	_run(30.0, false)
	assert_almost_eq(sections.health[spine] - before, 300.0, 1.0, "10 HP/s for 30 s")


func test_a_knocked_out_turret_comes_back_once_repaired() -> void:
	crew.peace_on = false
	mounts.wear(0, 1000.0)
	assert_true(mounts.is_out(0))
	areas.repair_mount = func(i: int, amount: float) -> void:
		if mounts.heal(i, amount):
			gut.p("mount back")
	_run(900.0, false)
	assert_false(mounts.is_out(0), "working again")
	assert_true(mounts.is_whole(0), "and whole: the bot stays until it is")
	_run(400.0, false)
	assert_eq(crew.repair_bot[sections.count()], -1, "its bot went home")


func test_a_lost_section_is_repaired_and_can_be_lost_again() -> void:
	var losses: Array[int] = []
	sections.lost.connect(func(i: int) -> void: losses.append(i))
	var green: int = sections.index_of("green_zone")
	assert_true(sections.damage(green, 6000.0))
	assert_true(sections.is_lost(green))
	assert_true(sections.repair(green, 10.0), "back above zero")
	assert_false(sections.is_lost(green))
	assert_true(sections.damage(green, 20.0), "and lost again")
	assert_eq(losses.size(), 2, "the loss is told each time")


func test_a_short_pool_calls_peace_bots_home() -> void:
	_run(60.0)
	var peace: int = crew.peace_out()
	assert_gt(peace, 0)
	for i: int in sections.count():
		sections.damage(i, 1000.0)
	for j: int in mounts.count():
		mounts.wear(j, 50.0)
	_run(0.5, false)
	for i: int in crew.motions.size():
		if crew.job_of(i) in ["spine", "fins_port", "fins_starboard", "drum_fore", "drum_aft", "gate"]:
			assert_true(crew.motions[i].homeward(), "the peace bots go home to free the pool")
	var served := {}
	for k: int in 240:
		_run(5.0, false)
		for a: int in areas.count():
			if crew.repair_bot[a] >= 0:
				served[a] = true
	assert_eq(served.size(), areas.count(), "every damaged area got its bot in the end")
	assert_eq(areas.damaged().size(), 0, "and all are whole")


func test_a_repair_bot_backs_off_while_hits_land_close_and_goes_back_after() -> void:
	crew.peace_on = false
	var spine: int = sections.index_of("spine")
	sections.damage(spine, 3000.0)
	_run(0.5, false)
	var bot: int = crew.repair_bot[spine]
	for i: int in int(600.0 / DT):
		_run(DT, false)
		if crew.motions[bot].at_work():
			break
	var spot: Vector3 = crew.motions[bot].position
	var duck := PackedByteArray()
	duck.resize(crew.motions.size())
	duck[bot] = 1
	var before: float = sections.health[spine]
	for i: int in int(15.0 / DT):
		for m: BotCrewMotion in crew.motions:
			m.step(DT, false)
		crew.work(DT, duck)
	assert_almost_eq(crew.motions[bot].position.distance_to(spot), data.duck_m, 0.5, "backed off its spot")
	assert_lt(sections.health[spine] - before, 25.0, "and no work while away")
	_run(20.0, false)
	assert_true(crew.motions[bot].at_work(), "back at work once the hits stop")
