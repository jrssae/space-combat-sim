extends GutTest
## The maintenance bots on the real station in the real main scene (M7-T11, M7-T35, Q11, D78, AC9): the crew waits in the cargo
## bay, patrols in peace (out to the jumpgate too), rides the drum, stays put on the station across rebases, goes home when the grid
## goes weapons free, and in a fight repairs: a knocked-out turret comes back, a lost section is repaired; none is a target.

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


func test_the_station_has_its_crew_hidden_in_the_cargo_bay() -> void:
	await _start()
	assert_not_null(station.bots, "the station builds its bots")
	var fleet: BotFleet = station.bots
	assert_eq(fleet.bots.size(), BotData.load_file().pool)
	for bot: MaintenanceBot in fleet.bots:
		assert_eq(bot.get_parent(), station, "on the station's own node, never its far-drawn pieces")
		assert_not_null((bot.get_node(^"Body") as MeshInstance3D).mesh, "the generated bot mesh is on it")


func test_in_peace_the_patrols_go_out_and_one_reaches_for_the_gate() -> void:
	await _start()
	var fleet: BotFleet = station.bots
	fleet.set_physics_process(false)
	_run_fleet(40.0)
	assert_between(fleet.out_count(), 3, 6, "3 to 6 out in peace")
	assert_true(fleet.frames.has_gate, "the scene's jumpgate is placed for the crew")
	var gate_bot: int = fleet.crew.peace_bot[_peace_index(fleet, "gate")]
	if gate_bot < 0:
		var sent: Array[ConsoleResult] = DebugConsole.registry.execute("bots send gate")
		assert_true(sent[0].ok, "; ".join(sent[0].lines))
		gate_bot = fleet.crew.peace_bot[_peace_index(fleet, "gate")]
	var gate: Jumpgate = main.gates.gate()
	var before: float = fleet.bots[gate_bot].global_position.distance_to(gate.global_position)
	_run_fleet(120.0)
	assert_lt(fleet.bots[gate_bot].global_position.distance_to(gate.global_position), before - 5000.0, "on its way out to the gate")


func test_a_bot_on_the_drum_stays_put_on_the_hull_as_it_turns() -> void:
	await _start()
	var fleet: BotFleet = station.bots
	fleet.set_physics_process(false)
	DebugConsole.registry.execute("bots peace off")
	var sent: Array[ConsoleResult] = DebugConsole.registry.execute("bots send drum_fore")
	assert_true(sent[0].ok, "; ".join(sent[0].lines))
	var bot: MaintenanceBot = fleet.bots[fleet.crew.peace_bot[_peace_index(fleet, "drum_fore")]]
	var m: BotCrewMotion = bot.motion
	for i: int in int(400.0 / DT):
		station.bots._physics_process(DT)
		if int(m.current().get("kind", -1)) == BotTrip.Kind.HOLD:
			break
	assert_eq(int(m.current().get("kind", -1)), BotTrip.Kind.HOLD, "it got on the drum and stopped there")
	var on_hull: Vector3 = station.drum_pivot.to_local(bot.global_position)
	for angle: float in [0.4, 1.9, 3.5, 5.6]:
		station.set_drum_angle(angle)
		station.bots._physics_process(DT)
		assert_almost_eq(station.drum_pivot.to_local(bot.global_position), on_hull, Vector3.ONE * 0.05,
				"the same spot on the drum at %.1f rad" % angle)


func test_a_rebase_changes_nothing_on_screen() -> void:
	await _start()
	station.bots.set_physics_process(false)
	_run_fleet(40.0)
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


func test_battle_sends_a_bot_to_each_damaged_area_and_a_turret_comes_back() -> void:
	await _start()
	var fleet: BotFleet = station.bots
	fleet.set_physics_process(false)
	var repaired: Array[String] = []
	station.grid.mount_repaired.connect(func(mount_name: String) -> void: repaired.append(mount_name))
	var results: Array[ConsoleResult] = DebugConsole.registry.execute("bots battle 6")
	assert_true(results[0].ok, "; ".join(results[0].lines))
	var l10: int = station.grid.health.index_of("L10")
	assert_true(station.grid.mounts[l10].knocked_out, "the battle knocked L10 out")
	_run_fleet(1.0)
	assert_eq(fleet.crew.repair_out(), 6, "one bot for each of the six damaged areas")
	_run_fleet(300.0)
	assert_false(station.grid.mounts[l10].knocked_out, "repaired above zero, L10 works again")
	assert_has(repaired, "L10")
	assert_gt(fleet.crew.repaired_hp, 0.0)


func test_a_lost_section_is_repaired_and_can_be_lost_again() -> void:
	await _start()
	var fleet: BotFleet = station.bots
	fleet.set_physics_process(false)
	var lost: Array[String] = []
	station.section_lost.connect(func(_i: int, n: String) -> void: lost.append(n))
	var green: int = station.sections.index_of("green_zone")
	station.damage_section(green, StationSections.SECTION_HEALTH)
	assert_true(station.sections.is_lost(green))
	_run_fleet(400.0)
	assert_false(station.sections.is_lost(green), "a bot repaired it above zero")
	station.damage_section(green, StationSections.SECTION_HEALTH)
	assert_eq(lost.size(), 2, "and it was lost again")


func test_the_grid_going_weapons_free_sends_the_patrols_home() -> void:
	await _start()
	var fleet: BotFleet = station.bots
	fleet.set_physics_process(false)
	_run_fleet(40.0)
	assert_gt(fleet.out_count(), 0)
	station.grid.set_free(Factions.RAIDERS, true)
	_run_fleet(1.0)
	for m: BotCrewMotion in fleet.crew.motions:
		assert_true(m.is_docked() or m.homeward(), "a hostile shot at the station: every patrol turns home")
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


func _peace_index(fleet: BotFleet, area_name: String) -> int:
	for a: int in fleet.crew.data.peace.size():
		if fleet.crew.data.peace[a]["name"] == area_name:
			return a
	return -1


func test_pods_cargo_backs_a_saturn_3_in_at_the_hold_point_and_starts_the_cargo_pods() -> void:
	await _start()
	var fleet: CargoPodFleet = station.cargo_pods
	assert_not_null(fleet, "the station has its cargo pods (M7-T34)")
	var bay: Dictionary = station.hardpoints.cargo_bay
	var results: Array[ConsoleResult] = DebugConsole.registry.execute("pods cargo")
	assert_true(results[0].ok, "; ".join(results[0].lines))
	assert_eq(fleet.pods.size(), CargoPodScene.DEFAULT_PODS, "five cargo pods by default")
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
	for craft: CargoPodCraft in fleet.pods:
		assert_eq(craft.get_parent(), station.frame_piece, "on the frame")
		assert_not_null(craft.rig.skeleton(), "the cargo pod's model with its arms")
	assert_eq(station.bots.bots.size(), BotData.load_file().pool, "the maintenance crew is untouched")
	var seen := {}
	for craft: CargoPodCraft in fleet.pods:
		seen[craft.motion.phase] = true
	assert_gte(seen.size(), 3, "staggered: the pods are in different phases at once")
	DebugConsole.registry.execute("bots cargo 3")
	assert_eq(fleet.pods.size(), 3, "bots cargo still works, and loading again replaces the scene")
	assert_not_null(fleet.cargo.freighter)
	var off: Array[ConsoleResult] = DebugConsole.registry.execute("pods cargo off")
	assert_true(off[0].ok)
	assert_eq(fleet.pods.size(), 0)
	assert_null(fleet.cargo.freighter)
	assert_gte(main.ships.free_count(&"saturn_3_freighter"), 1, "the Saturn went back to the pool")


func test_pods_cargo_view_puts_the_player_toward_the_bay_from_the_saturn() -> void:
	await _start()
	var results: Array[ConsoleResult] = DebugConsole.registry.execute("pods cargo view")
	assert_true(results[0].ok, "; ".join(results[0].lines))
	var hold: Vector3 = station.to_world(station.hardpoints.cargo_bay["cargo_bay_hold"], StationHardpoints.FRAME)
	assert_between(main.ship.global_position.distance_to(hold), 200.0, 300.0)
	var entry: Vector3 = station.to_world(station.hardpoints.cargo_bay["cargo_bay_entry"], StationHardpoints.FRAME)
	assert_lt(main.ship.global_position.distance_to(entry), hold.distance_to(entry), "on the bay's side of the hold point")
