extends GutTest
## The maintenance bots on the real station in the real main scene (M7-T11, Q11, D78, AC9): a handful of ambient drones hang from
## the station's frame and the drum's pivot, ride the drum, stay put on the station across rebases, go in when the hit resolver
## reports a hit or the grid goes weapons free near them, and come out again after a quiet; none is a target or a contact.

const DT: float = 1.0 / 60.0

var main: Main
var station: Station


func before_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()


func after_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()


func _start() -> void:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.raider_pool_size = 0
	main.ally_pool_size = 0
	main.waves_auto_start = false
	add_child_autofree(main)
	await _ticks(2)
	station = main.far_props.station


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


# Runs the fleet's own tick `seconds` of sim time without waiting for them.
func _run_fleet(seconds: float) -> void:
	for i: int in int(seconds / DT):
		station.bots._physics_process(DT)


func test_the_station_has_its_bots_on_the_frame_and_the_drum() -> void:
	await _start()
	assert_not_null(station.bots, "the station builds its bots")
	var fleet: BotFleet = station.bots
	assert_between(fleet.bots.size(), 6, 10)
	for bot: MaintenanceBot in fleet.bots:
		assert_eq(bot.get_parent(), station.drum_pivot if bot.home_body == StationHardpoints.DRUM else station.frame_piece)
		assert_not_null((bot.get_node(^"Body") as MeshInstance3D).mesh, "the generated bot mesh is on it")
		assert_true(bot.visible)


func test_a_bot_on_the_drum_turns_with_it_and_one_on_the_frame_does_not() -> void:
	await _start()
	station.set_spinning(false)
	var drum_bot: MaintenanceBot = null
	var frame_bot: MaintenanceBot = null
	for bot: MaintenanceBot in station.bots.bots:
		drum_bot = bot if bot.home_body == StationHardpoints.DRUM and drum_bot == null else drum_bot
		frame_bot = bot if bot.home_body == StationHardpoints.FRAME and frame_bot == null else frame_bot
	station.set_drum_angle(0.4)
	var frame_before: Vector3 = frame_bot.global_position
	var radius_before: float = Vector2(drum_bot.position.x, drum_bot.position.y).length()
	for angle: float in [0.4, 1.9, 3.5, 5.6]:
		station.set_drum_angle(angle)
		assert_almost_eq(drum_bot.global_position, station.to_world(drum_bot.position, StationHardpoints.DRUM), Vector3.ONE * 1e-2,
				"on the drum at %.1f rad (the hardpoints' own rule)" % angle)
		assert_almost_eq(Vector2(drum_bot.position.x, drum_bot.position.y).length(), radius_before, 2.0, "its own place unchanged")
	assert_eq(frame_bot.global_position, frame_before, "the frame's bot stands still while the drum turns")


func test_a_rebase_changes_nothing_on_screen() -> void:
	await _start()
	var before := {}
	var local := {}
	for bot: MaintenanceBot in station.bots.bots:
		before[bot] = main.world.to_universe(bot.global_position)
		local[bot] = station.to_local(bot.global_position)
	for offset: Vector3 in [Vector3(4000.0, 0.0, 0.0), Vector3(0.0, -6000.0, 2500.0)]:
		main.world.rebase(offset)
		for bot: MaintenanceBot in station.bots.bots:
			var u: UniversePos = main.world.to_universe(bot.global_position)
			var was: UniversePos = before[bot]
			assert_almost_eq(Vector3(u.x, u.y, u.z), Vector3(was.x, was.y, was.z), Vector3.ONE * 1e-2, "%s is where it was in the universe" % bot.name)
			assert_almost_eq(station.to_local(bot.global_position), local[bot], Vector3.ONE * 1e-2, "and where it was on the station")
	await _ticks(3)
	for bot: MaintenanceBot in station.bots.bots:
		assert_lt(bot.position.distance_to(bot.motion.position), 1e-4)


func test_a_hit_near_a_bot_sends_it_in_and_it_comes_out_after_the_quiet() -> void:
	await _start()
	var fleet: BotFleet = station.bots
	fleet.set_physics_process(false)
	var resolver := main.get_node(^"Combat/HitResolver") as HitResolver
	var target: MaintenanceBot = fleet.bots[0]
	for i: int in 8:
		resolver.hit_resolved.emit(HitInfo.new(0, 0, Factions.RAIDERS, 5.0, target.global_position + Vector3(0.0, 40.0, 0.0)))
		_run_fleet(10.0)
	assert_eq(target.motion.phase, BotMotion.Phase.HIDDEN, "the hit near it sent it in")
	assert_false(target.visible)
	assert_gt(fleet.hidden_count(), 0)
	_run_fleet(BotAlert.QUIET_S + BotMotion.MIN_HIDDEN_S + BotFleet.EMERGE_SPREAD_S * float(fleet.bots.size()) + 30.0)
	assert_eq(fleet.hidden_count(), 0, "all out again after the quiet")
	assert_true(target.visible)


func test_the_grid_going_weapons_free_sends_every_bot_in() -> void:
	await _start()
	var fleet: BotFleet = station.bots
	fleet.set_physics_process(false)
	station.grid.set_free(Factions.RAIDERS, true)
	_run_fleet(56.0)
	assert_eq(fleet.hidden_count(), fleet.bots.size(), "a hostile shot at the station: every bot goes in")
	station.grid.set_free(Factions.RAIDERS, false)


func test_no_bot_is_a_target_a_contact_or_a_body() -> void:
	await _start()
	for node: Node in get_tree().get_nodes_in_group(Targetable.GROUP):
		for bot: MaintenanceBot in station.bots.bots:
			assert_false(bot.is_ancestor_of(node), "no marker under a bot")
	for bot: MaintenanceBot in station.bots.bots:
		assert_eq(bot.find_children("*", "CollisionObject3D", true, false).size(), 0)
		assert_eq(bot.find_children("*", "Damageable", true, false).size(), 0)
	assert_eq(station.bots.get_parent(), station)


func test_bots_cargo_backs_a_saturn_3_in_at_the_hold_point_and_starts_the_ferry() -> void:
	await _start()
	var fleet: BotFleet = station.bots
	var bay: Dictionary = station.hardpoints.cargo_bay
	var results: Array[ConsoleResult] = DebugConsole.registry.execute("bots cargo")
	assert_true(results[0].ok, "; ".join(results[0].lines))
	assert_eq(fleet.ferry_bots.size(), BotCargoScene.DEFAULT_BOTS, "five ferry bots by default")
	var freighter: Combatant = fleet.cargo.freighter
	assert_not_null(freighter, "the Saturn is out of the pool")
	assert_eq(main.ships.type_of(freighter), &"saturn_3_freighter")
	await _ticks(90)
	var hold: Vector3 = station.to_world(bay["cargo_bay_hold"], StationHardpoints.FRAME)
	assert_almost_eq(freighter.ship.global_position, hold, Vector3.ONE * 2.0, "parked at cargo_bay_hold, held there by nothing but its idle brain")
	var nose: Vector3 = -freighter.ship.global_basis.z
	var to_bay: Vector3 = station.to_world(bay["cargo_bay_entry"], StationHardpoints.FRAME) - freighter.ship.global_position
	assert_lt(nose.normalized().dot(to_bay.normalized()), -0.99, "its forward points away from cargo_bay_entry: it backs in, stern to the bay")
	var rest: Vector3 = main.world.rest_velocity()
	assert_lt((freighter.ship.linear_velocity - rest).length(), 0.5, "at rest against the station")
	for bot: MaintenanceBot in fleet.ferry_bots:
		assert_eq(bot.get_parent(), station.frame_piece, "on the frame")
	var seen := {}
	for bot: MaintenanceBot in fleet.ferry_bots:
		seen[(bot.motion as BotFerryMotion).phase] = true
	assert_gte(seen.size(), 3, "staggered: the bots are in different phases at once")
	DebugConsole.registry.execute("bots cargo 3")
	assert_eq(fleet.ferry_bots.size(), 3, "loading again replaces the scene")
	assert_not_null(fleet.cargo.freighter)
	var off: Array[ConsoleResult] = DebugConsole.registry.execute("bots cargo off")
	assert_true(off[0].ok)
	assert_eq(fleet.ferry_bots.size(), 0)
	assert_null(fleet.cargo.freighter)
	assert_gte(main.ships.free_count(&"saturn_3_freighter"), 1, "the Saturn went back to the pool")


func test_bots_cargo_view_puts_the_player_toward_the_bay_from_the_saturn() -> void:
	await _start()
	var results: Array[ConsoleResult] = DebugConsole.registry.execute("bots cargo view")
	assert_true(results[0].ok, "; ".join(results[0].lines))
	var hold: Vector3 = station.to_world(station.hardpoints.cargo_bay["cargo_bay_hold"], StationHardpoints.FRAME)
	assert_between(main.ship.global_position.distance_to(hold), 200.0, 300.0)
	var entry: Vector3 = station.to_world(station.hardpoints.cargo_bay["cargo_bay_entry"], StationHardpoints.FRAME)
	assert_lt(main.ship.global_position.distance_to(entry), hold.distance_to(entry), "on the bay's side of the hold point")
