extends GutTest
## `BotFleet` and `MaintenanceBot` (M7-T11, Q11, D78) on bare parents standing for the station's frame and the drum's pivot: the
## bots fly their loops, ride the drum, go in when fighting starts near them and come out after a quiet, and are ambient only.
## The station itself is in tests/integration/test_bots_on_station.gd.

const DT: float = 1.0 / 60.0

var origin: Node3D
var frame_parent: Node3D
var drum_pivot: Node3D
var fleet: BotFleet


func before_each() -> void:
	origin = Node3D.new()
	frame_parent = Node3D.new()
	drum_pivot = Node3D.new()
	origin.add_child(frame_parent)
	origin.add_child(drum_pivot)
	drum_pivot.position = Vector3(0.0, 0.0, -1000.0)
	add_child_autofree(origin)
	fleet = BotFleet.new()
	var data: BotData = BotData.load_file()
	assert_true(fleet.build_on(origin, frame_parent, drum_pivot, data, BoxMesh.new()), data.error)
	fleet.set_physics_process(false)  # stepped by hand below
	origin.add_child(fleet)


func _step(seconds: float) -> void:
	for i: int in int(seconds / DT):
		fleet._physics_process(DT)


func _bot(loop_name: String) -> MaintenanceBot:
	for bot: MaintenanceBot in fleet.bots:
		if bot.loop_name == loop_name:
			return bot
	return null


func test_a_handful_of_bots_fly_loops_on_the_frame_and_the_drum() -> void:
	assert_between(fleet.bots.size(), 6, 10)
	var on_drum: int = 0
	for bot: MaintenanceBot in fleet.bots:
		var parent: Node = bot.get_parent()
		assert_eq(parent, drum_pivot if bot.home_body == StationHardpoints.DRUM else frame_parent)
		on_drum += 1 if parent == drum_pivot else 0
		assert_eq(bot.motion.phase, BotMotion.Phase.PATROL)
	assert_gt(on_drum, 0)
	assert_lt(on_drum, fleet.bots.size())


func test_they_fly_slowly_and_smoothly() -> void:
	var last := {}
	var worst: float = 0.0
	for bot: MaintenanceBot in fleet.bots:
		last[bot] = bot.position
	for i: int in 600:
		fleet._physics_process(DT)
		for bot: MaintenanceBot in fleet.bots:
			worst = maxf(worst, bot.position.distance_to(last[bot]) / DT)
			last[bot] = bot.position
	assert_lte(worst, 5.0, "no bot moves faster than 5 m/s (%.2f)" % worst)
	assert_gt(worst, 2.0, "and they do move")


func test_a_bot_on_the_drum_rides_it() -> void:
	var bot: MaintenanceBot = _bot("cobra_alpha")
	assert_not_null(bot)
	var local: Vector3 = bot.position
	for turn: float in [0.0, 0.7, 2.0, 4.1]:
		drum_pivot.basis = Basis(Vector3.BACK, turn)
		var expected: Vector3 = origin.global_transform * (drum_pivot.transform * local)
		assert_almost_eq(bot.global_position, expected, Vector3.ONE * 1e-3, "turned %.1f rad with the drum" % turn)
	var frame_bot: MaintenanceBot = _bot("spine_modules")
	var before: Vector3 = frame_bot.global_position
	drum_pivot.basis = Basis(Vector3.BACK, 3.0)
	assert_eq(frame_bot.global_position, before, "a bot on the frame stands still while the drum turns")


func test_a_rebase_changes_nothing_on_screen() -> void:
	# The bots hang from the station, which the World shifts as one: every bot keeps its place against the station.
	_step(5.0)
	var before := {}
	for bot: MaintenanceBot in fleet.bots:
		before[bot] = origin.to_local(bot.global_position)
	origin.global_position += Vector3(-4000.0, 250.0, 9000.0)  # what a rebase does to a shiftable node
	for bot: MaintenanceBot in fleet.bots:
		assert_almost_eq(origin.to_local(bot.global_position), before[bot], Vector3.ONE * 1e-3, "%s keeps its place on the station" % bot.name)
		assert_almost_eq(bot.position, bot.motion.position, Vector3.ONE * 1e-6, "its own numbers never see the shift")


# Fighting that goes on for `seconds`: a shot every 10 s, at `point` in the World frame, or on the whole station without one.
func _fight(seconds: float, point: Variant = null) -> void:
	for i: int in int(seconds / 10.0):
		if point == null:
			fleet.note_combat_everywhere()
		else:
			fleet.note_combat_at(point as Vector3)
		_step(10.0)


func test_fighting_near_some_bots_sends_those_in_and_not_the_far_ones() -> void:
	var near: MaintenanceBot = _bot("bow_prong")
	var far: MaintenanceBot = _bot("reactor_top")
	_step(1.0)
	_fight(80.0, near.global_position + Vector3(0.0, 80.0, 0.0))
	assert_eq(near.motion.phase, BotMotion.Phase.HIDDEN, "the bot by the shots went in")
	assert_false(near.visible)
	assert_eq(far.motion.phase, BotMotion.Phase.PATROL, "the one 7 km off stayed out")
	assert_true(far.visible)


func test_a_single_hit_sends_a_bot_in_and_it_is_out_again_after_the_quiet() -> void:
	var bot: MaintenanceBot = _bot("cobra_alpha")
	fleet.note_combat_at(bot.global_position)
	_step(BotAlert.QUIET_S - 1.0)
	assert_gt(bot.motion.times_hidden + (1 if bot.motion.phase != BotMotion.Phase.PATROL else 0), 0, "it went for its hatch")
	_step(BotAlert.QUIET_S + BotMotion.MIN_HIDDEN_S + BotFleet.EMERGE_SPREAD_S * 8.0 + 30.0)
	assert_eq(bot.motion.phase, BotMotion.Phase.PATROL, "and flies again")
	assert_true(bot.visible)


func test_the_grid_going_weapons_free_sends_every_bot_in() -> void:
	_step(1.0)
	_fight(80.0)
	assert_eq(fleet.hidden_count(), fleet.bots.size())
	for bot: MaintenanceBot in fleet.bots:
		assert_false(bot.visible)


func test_after_a_quiet_they_come_out_and_fly_again() -> void:
	_fight(80.0)
	assert_eq(fleet.hidden_count(), fleet.bots.size())
	_step(BotAlert.QUIET_S + BotMotion.MIN_HIDDEN_S + BotFleet.EMERGE_SPREAD_S * float(fleet.bots.size()) + 30.0)
	assert_eq(fleet.hidden_count(), 0, "nobody left inside")
	for bot: MaintenanceBot in fleet.bots:
		assert_eq(bot.motion.phase, BotMotion.Phase.PATROL)
		assert_true(bot.visible)
		assert_gte(bot.motion.times_emerged, 1)
	var before: Vector3 = fleet.bots[0].position
	_step(2.0)
	assert_ne(fleet.bots[0].position, before, "flying again")


func test_they_do_not_all_come_out_at_once() -> void:
	_fight(80.0)
	var seen := {}
	for i: int in 60 * 120:
		fleet._physics_process(DT)
		seen[fleet.hidden_count()] = true
	assert_gt(seen.size(), 3, "they come out one after another (%s)" % str(seen.keys()))


func test_a_later_shot_keeps_them_in() -> void:
	_fight(80.0)
	_step(40.0)
	fleet.note_combat_everywhere()
	_step(40.0)
	assert_eq(fleet.hidden_count(), fleet.bots.size(), "the quiet restarts with every shot")


func test_bots_hide_and_bots_show_hold_them_in_and_let_them_out() -> void:
	DebugConsole.registry.execute("bots hide")
	_step(75.0)
	assert_true(fleet.held_in)
	assert_eq(fleet.hidden_count(), fleet.bots.size())
	_step(75.0)
	assert_eq(fleet.hidden_count(), fleet.bots.size(), "held in as long as it lasts")
	DebugConsole.registry.execute("bots show")
	_step(BotMotion.MIN_HIDDEN_S + BotFleet.EMERGE_SPREAD_S * float(fleet.bots.size()) + 30.0)
	assert_eq(fleet.hidden_count(), 0)
	var info: Array[ConsoleResult] = DebugConsole.registry.execute("bots info")
	assert_true(info[0].ok)
	assert_string_contains(info[0].lines[0], "bots")
	assert_eq(DebugConsole.registry.read("bots.count")["value"], fleet.bots.size())


func test_the_bots_are_ambient_only() -> void:
	# Nothing the game targets, shoots, rams or counts as a contact: no marker, no hull, no body, no collision, no row.
	for bot: MaintenanceBot in fleet.bots:
		assert_eq(bot.find_children("*", "Targetable", true, false).size(), 0)
		assert_eq(bot.find_children("*", "Damageable", true, false).size(), 0)
		assert_eq(bot.find_children("*", "CollisionObject3D", true, false).size(), 0)
		assert_eq(bot.find_children("*", "CollisionShape3D", true, false).size(), 0)
		assert_false(bot.is_in_group(WorldFrame.SHIFTABLE_GROUP), "moved by the station, not by a rebase of its own")
		for group: StringName in bot.get_groups():
			assert_false(String(group).begins_with("target"), "no targeting group: %s" % group)


func test_the_per_tick_cost_is_read() -> void:
	fleet.set_physics_process(true)
	await wait_physics_frames(5)
	assert_gt(fleet.tick_us_avg, 0.0)
	assert_lt(fleet.tick_us, 2000, "a handful of bots costs well under 2 ms a tick (%d us)" % fleet.tick_us)
