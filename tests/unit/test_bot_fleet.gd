extends GutTest
## `BotFleet` and `MaintenanceBot` (M7-T11, M7-T35, Q11, D78) on bare nodes standing for the station: the crew waits hidden in the
## cargo bay, goes out on its patrols, rides rebases with the station, goes home when fighting comes near, stays in under `bots
## hide`, and is ambient only. The station itself is in tests/integration/test_bots_on_station.gd.

const DT: float = 1.0 / 60.0

var origin: Node3D
var frame_parent: Node3D
var fleet: BotFleet


func before_each() -> void:
	origin = Node3D.new()
	frame_parent = Node3D.new()
	origin.add_child(frame_parent)
	add_child_autofree(origin)
	fleet = BotFleet.new()
	fleet.frames.pivot = Vector3(0.0, 0.0, -1000.0)
	var data: BotData = BotData.load_file()
	assert_true(fleet.build_on(origin, origin, data, BoxMesh.new()), data.error)
	fleet.set_physics_process(false)  # stepped by hand below
	origin.add_child(fleet)


func _step(seconds: float) -> void:
	for i: int in int(seconds / DT):
		fleet._physics_process(DT)


func test_the_crew_waits_hidden_in_the_cargo_bay() -> void:
	assert_eq(fleet.bots.size(), BotData.load_file().pool)
	for bot: MaintenanceBot in fleet.bots:
		assert_eq(bot.get_parent(), origin, "on the station's own node, not its drawn pieces")
		assert_false(bot.visible, "docked")
		assert_almost_eq(bot.position, BotData.load_file().trunk[0], Vector3.ONE * 1e-3, "at the cargo bay")


func test_in_peace_three_to_six_go_out_on_patrol() -> void:
	_step(40.0)
	assert_between(fleet.out_count(), 3, 6)
	var shown: int = 0
	for bot: MaintenanceBot in fleet.bots:
		shown += 1 if bot.visible else 0
		assert_almost_eq(bot.position, bot.motion.position, Vector3.ONE * 1e-4, "the node follows its motion")
	assert_eq(shown, fleet.out_count(), "out means drawn")


func test_a_rebase_changes_nothing_on_the_station() -> void:
	_step(40.0)
	origin.global_position += Vector3(5000.0, -300.0, 12000.0)
	for bot: MaintenanceBot in fleet.bots:
		assert_almost_eq(origin.to_local(bot.global_position), bot.motion.position, Vector3.ONE * 1e-3)


func test_fighting_at_the_bay_sends_the_patrols_home_and_keeps_new_ones_in() -> void:
	_step(40.0)
	assert_gt(fleet.out_count(), 0)
	fleet.note_combat_everywhere()
	_step(1.0)
	for m: BotCrewMotion in fleet.crew.motions:
		assert_true(m.is_docked() or m.homeward(), "each patrol turned for home")
	for k: int in 12:
		fleet.note_combat_everywhere()
		_step(60.0)
	assert_eq(fleet.out_count(), 0, "all home while the fight lasts")
	_step(BotAlert.QUIET_S + 10.0)
	assert_gt(fleet.out_count(), 0, "out again after the quiet")


func test_bots_hide_and_bots_show() -> void:
	_step(40.0)
	var hide: Array[ConsoleResult] = DebugConsole.registry.execute("bots hide")
	assert_true(hide[0].ok)
	assert_true(fleet.held_in)
	_step(700.0)
	assert_eq(fleet.out_count(), 0, "all home and staying")
	DebugConsole.registry.execute("bots show")
	_step(5.0)
	assert_gt(fleet.out_count(), 0)


func test_bots_send_puts_a_bot_on_an_area_once() -> void:
	DebugConsole.registry.execute("bots peace off")
	var sent: Array[ConsoleResult] = DebugConsole.registry.execute("bots send spine")
	assert_true(sent[0].ok, "; ".join(sent[0].lines))
	var again: Array[ConsoleResult] = DebugConsole.registry.execute("bots send spine")
	assert_false(again[0].ok, "one bot an area")
	assert_eq(fleet.crew.peace_out(), 1)
	var info: Array[ConsoleResult] = DebugConsole.registry.execute("bots")
	assert_string_contains(info[0].lines[0], "spine")
	assert_eq(DebugConsole.registry.read("bots.peace_out")["value"], 1)


func test_the_bots_are_ambient_only() -> void:
	# Nothing the game targets, shoots, rams or counts as a contact: no marker, no hull, no body, no collision, no row.
	for bot: MaintenanceBot in fleet.bots:
		assert_eq(bot.find_children("*", "Targetable", true, false).size(), 0)
		assert_eq(bot.find_children("*", "Damageable", true, false).size(), 0)
		assert_eq(bot.find_children("*", "CollisionObject3D", true, false).size(), 0)
		assert_false(bot.is_in_group(WorldFrame.SHIFTABLE_GROUP), "moved by the station, not by a rebase of its own")


func test_the_per_tick_cost_is_read() -> void:
	fleet.set_physics_process(true)
	await wait_physics_frames(5)
	assert_gt(fleet.tick_us_avg, 0.0)
	assert_lt(fleet.tick_us, 2000, "a dozen bots costs well under 2 ms a tick (%d us)" % fleet.tick_us)
