extends TestSteps
## The mission runner in the real main scene (architecture §18 D51, D52, AC5, M5-T05), on `tests/fixtures/missions/test_mission.json`:
## it exists only for a scenario with a `mission` block; the test mission plays through on sim time to a success that reaches
## `Game`; the player's death, a failed primary and `m.end` end it; the player does not respawn; raiders jump in from the pool
## (no splat node added, a spawn past the pool is an error); the HUD lists the objectives in both views; the console works; and
## 20 live triggers stay inside a counted bound.

const MISSION_PATH: String = "res://tests/fixtures/missions/test_mission.json"
## The same mission with a scout placed at load (`spawns`), which no trigger watches.
const SCOUT_PATH: String = "res://tests/fixtures/missions/test_mission_scout.json"

var main: Main
var source: FakeInputSource
var _game_state: GameFlow.State
var _game_result: Dictionary


func before_each() -> void:
	get_tree().paused = false
	_game_state = Game.flow.state
	_game_result = Game.flow.last_result
	source = FakeInputSource.new()
	main = await _make_main(MISSION_PATH)


func after_each() -> void:
	get_tree().paused = false
	DebugConsole.flags.invulnerable = false
	Game.flow.state = _game_state
	Game.flow.last_result = _game_result


func _make_main(path: String) -> Main:
	var m := (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	m.input_source = source
	m.scenario_path = path
	add_child_autofree(m)
	await _ticks(2)
	return m


func _frames(n: int) -> void:
	for _i: int in n:
		await get_tree().process_frame


# Waits for a mission state (dialog lines hold on sim time), failing clearly if it never comes within `max_ticks`.
func _wait_for(what: String, reached: Callable, max_ticks: int = 1200) -> void:
	var waited: int = 0
	while not bool(reached.call()) and waited < max_ticks:
		await _ticks(1)
		waited += 1
	assert_true(bool(reached.call()), "waited %d ticks for: %s" % [waited, what])


func _tap(action: StringName) -> void:
	source.hold(action)
	await _ticks(2)
	source.release(action)
	await _ticks(2)


func _api() -> MissionApi:
	return main.mission.api


# Flies the player (by hand) next to NAV ALPHA: the brief's objective.
func _reach_the_buoy() -> void:
	main.ship.reset_to(Transform3D(main.ship.global_basis, main.world.universe_to_local(UniversePos.new(0.0, 0.0, -1750.0))))
	await _ticks(2)


func _kill_the_raiders() -> void:
	for combatant: Combatant in main.ships.alive(ShipPool.DEFAULT_TYPE):
		combatant.damageable.kill()
	await _ticks(2)


func _count(node: Node, type: Variant) -> int:
	var n: int = 1 if is_instance_of(node, type) else 0
	for child: Node in node.get_children():
		n += _count(child, type)
	return n


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


# --- which scenarios run one ---------------------------------------------------------------------------------------------


func test_a_mission_scenario_gets_a_runner_and_free_flight_none() -> void:
	assert_not_null(main.mission)
	assert_eq(main.mission.get_parent(), main, "a node under Main")
	assert_eq(main.mission.process_physics_priority, MissionRunner.PRIORITY)
	assert_gt(MissionRunner.PRIORITY, 300, "after the resolvers, the wings and the waves")
	assert_eq(main.mission.state_name(), "running")
	assert_eq(_api().step_name(), &"brief", "the first step started before the first tick")
	main.queue_free()
	await _frames(1)
	var free_flight: Main = await _make_main(ScenarioLoader.FREE_FLIGHT_PATH)
	assert_null(free_flight.mission)
	assert_eq(free_flight.objectives(), [] as Array[Dictionary])
	assert_false(_run("mission").ok, "no mission command outside a mission")


# --- playing it through ----------------------------------------------------------------------------------------------------


func test_the_test_mission_plays_through_to_a_success_that_reaches_game() -> void:
	assert_eq(_api().objective_state(&"reach"), ObjectiveBook.ACTIVE)
	assert_eq(_api().waypoint_name, "NAV ALPHA")
	await _ticks(30)
	assert_eq(_api().step_name(), &"brief", "it waits for the player")
	await _reach_the_buoy()
	assert_eq(_api().objective_state(&"reach"), ObjectiveBook.DONE)
	assert_eq(_api().step_name(), &"raid")
	assert_eq(main.ships.alive(ShipPool.DEFAULT_TYPE).size(), 2, "two raiders from the pool")
	var raider: Combatant = main.ships.alive(ShipPool.DEFAULT_TYPE)[0]
	assert_eq((raider.driver.brain as AiPilot).context.objective_name, "NAV ALPHA", "m.send set the pilot objective")
	await _kill_the_raiders()
	assert_eq(_api().objective_state(&"raiders"), ObjectiveBook.DONE)
	assert_eq(_api().step_name(), &"report")
	await _ticks(70)
	assert_false(_api().has_ended(), "it waits for the assist toggle")
	await _tap(InputAdapter.TOGGLE_ASSIST)
	assert_true(_api().has_ended())
	assert_true(bool(_api().result["success"]), str(_api().result))
	assert_eq(main.mission.state_name(), "success")
	assert_true(bool(Game.flow.last_result.get("success", false)), "Game keeps the result for the debrief")
	assert_eq(Game.flow.last_result["scenario_id"], &"test_mission")
	await _frames(2)
	assert_eq(main.hud.frame.status_line, "MISSION COMPLETE")


func test_mission_time_is_sim_time_and_stops_while_paused() -> void:
	await _ticks(30)
	var t: float = _api().time_s()
	assert_almost_eq(t, 30.0 / Engine.physics_ticks_per_second, 2.0 / Engine.physics_ticks_per_second)
	main.set_paused(true)
	await _ticks(20)
	assert_eq(_api().time_s(), t, "paused: no mission time")
	main.set_paused(false)


# --- how it ends --------------------------------------------------------------------------------------------------------------


func test_the_player_destroyed_fails_the_mission_and_there_is_no_respawn() -> void:
	main.combatant.damageable.kill()
	await _ticks(2)
	assert_true(_api().has_ended())
	assert_false(bool(_api().result["success"]))
	assert_eq(_api().result["reason"], "player destroyed")
	assert_eq(Game.flow.last_result["reason"], "player destroyed")
	assert_false(main.director.respawn_pending(), "the runner cancelled the respawn")
	await _ticks(ceili(DestructionDirector.RESPAWN_DELAY_S * Engine.physics_ticks_per_second) + 20)
	assert_false(main.player_alive, "no respawn in a mission")
	await _tap(InputAdapter.RESET_SHIP)
	assert_false(main.player_alive, "Back does not bring the ship back either")


func test_the_console_respawn_is_refused_in_a_mission() -> void:
	main.combatant.damageable.kill()
	await _ticks(2)
	var result: ConsoleResult = _run("respawn")
	assert_false(result.ok)
	assert_string_contains(result.error, "no respawn in a mission")
	assert_false(main.player_alive)


func test_back_does_not_reset_the_ship_in_a_mission() -> void:
	main.ship.linear_velocity = Vector3(0.0, 0.0, -40.0)
	await _ticks(20)
	await _tap(InputAdapter.RESET_SHIP)
	assert_gt(main.ship.linear_velocity.length(), 30.0, "still flying: Back is no reset in a mission")


func test_a_failed_primary_fails_the_mission() -> void:
	_api().objective_fail(&"reach")
	assert_true(_api().has_ended())
	assert_false(bool(_api().result["success"]))
	assert_eq(_api().result["reason"], "objective failed: reach")
	assert_eq(main.mission.state_name(), "failure")


func test_a_failed_optional_does_not() -> void:
	await _reach_the_buoy()
	main.buoys[0].damageable.kill()
	await _ticks(3)
	assert_eq(_api().objective_state(&"protect"), ObjectiveBook.FAILED, "its fail trigger saw the buoy go")
	assert_false(_api().has_ended(), "protect is optional")


func test_the_script_ending_it() -> void:
	_api().end(false, "scripted")
	assert_eq(Game.flow.last_result["reason"], "scripted")
	await _ticks(5)
	assert_eq(_api().step_name(), &"brief", "the steps stop where they were")


# --- ships lost before any trigger watched them (review round 2) ------------------------------------------------------------


func _with_the_scout_lost() -> Combatant:
	main.queue_free()
	await _frames(1)
	main = await _make_main(SCOUT_PATH)
	var scout: Combatant = null
	for combatant: Combatant in main.ships.alive(ShipPool.DEFAULT_TYPE):
		if combatant.display_name == "SCOUT 1":
			scout = combatant
	assert_not_null(scout, "the scenario placed it at load")
	assert_false(_api().watched().has("scout 1"), "no trigger watches it")
	scout.damageable.kill()
	await _ticks(2)
	return scout


func test_an_objective_naming_a_scenario_ship_lost_earlier_fails_when_shown() -> void:
	await _with_the_scout_lost()
	_api().book.add(&"guard", "Keep SCOUT 1 alive", false, null, TriggerSpec.destroyed(["SCOUT 1"]))
	_api().objective_add(&"guard")
	await _ticks(1)
	assert_eq(_api().objective_state(&"guard"), ObjectiveBook.FAILED, "the scout was in play and is gone")


func test_until_destroyed_on_a_scenario_ship_lost_earlier_resolves() -> void:
	await _with_the_scout_lost()
	var done: Array[bool] = [false, false]
	var wait_scout := func() -> void:
		await _api().until(TriggerSpec.destroyed(["SCOUT 1"]))
		done[0] = true
	var wait_ghost := func() -> void:
		await _api().until(TriggerSpec.destroyed(["GHOST 1"]))
		done[1] = true
	wait_scout.call()
	wait_ghost.call()
	await _ticks(2)
	assert_true(done[0], "the lost scout counts as destroyed")
	assert_false(done[1], "a name the game never had is still not arrived")


# --- spawns: pools and jump arrivals ---------------------------------------------------------------------------------------


func test_raiders_jump_in_from_the_pool_without_a_new_ship() -> void:
	var ships_before: int = _count(main, Ship)
	# The far-dot multimesh is made for the first ship that needs it (M4-T11): shared by every ship, not the arrival's.
	FarDots.attach(main.world)
	var nodes_before: int = _count(main, Node)
	await _reach_the_buoy()
	assert_eq(_count(main, Ship), ships_before, "D22: pooled ships only")
	assert_eq(main.mission.jumps.opened, 1, "the pair 300 m apart came out of one jump point")
	assert_eq(main.mission.jumps.open_count(), 1)
	var point: JumpArrival = null
	for child: Node in main.mission.jumps.get_children():
		if (child as JumpArrival).is_open():
			point = child as JumpArrival
	assert_not_null(point)
	assert_true(point.visible)
	assert_true(point.is_in_group(WorldFrame.SHIFTABLE_GROUP))
	var raider: Combatant = main.ships.alive(ShipPool.DEFAULT_TYPE)[0]
	assert_lt(raider.ship.global_position.distance_to(point.global_position), 400.0, "the ship comes out of it")
	assert_eq(_count(main, Node), nodes_before, "no node entered the tree for the arrival")
	point.advance(JumpArrival.LIFETIME_S)
	assert_false(point.is_open(), "it closes on its own")
	assert_false(point.visible)


func test_a_spawn_past_its_pool_is_an_error() -> void:
	await _reach_the_buoy()
	var third: Combatant = _api().spawn({"type": "raider_fighter", "name": "RAIDER 3", "anchor": "origin", "offset": [0, 0, -8000]})
	assert_not_null(third, "the pool holds three")
	var fourth: Combatant = _api().spawn({"type": "raider_fighter", "name": "RAIDER 4", "anchor": "origin", "offset": [0, 0, -8000]})
	assert_null(fourth)
	assert_push_error("no free raider_fighter")
	assert_eq(main.ships.pool_size(ShipPool.DEFAULT_TYPE), 3, "nothing was built")


# --- the HUD and the pause menu's source -----------------------------------------------------------------------------------


func test_the_hud_lists_the_active_objectives_in_both_views() -> void:
	await _frames(3)
	assert_has(main.hud.frame.items, HudSurface.OBJECTIVES, "chase view")
	assert_eq(main.hud.frame.objective_lines.size(), 1, "only the active one")
	assert_eq(main.hud.frame.objective_lines[0]["text"], "FLY TO NAV ALPHA")
	assert_true(main.hud.frame.waypoint_present, "the mission's waypoint")
	assert_eq(main.hud.frame.waypoint_label, "NAV ALPHA")
	main.camera_rig.set_mode(CameraRig.Mode.COCKPIT)
	await _frames(3)
	assert_has(main.hud.frame.items, HudSurface.OBJECTIVES, "cockpit view: on the window as well")
	assert_has(main.hud.painted_items(), HudSurface.OBJECTIVES)
	main.camera_rig.set_mode(CameraRig.Mode.CHASE)


func test_objectives_are_offered_for_the_pause_menu() -> void:
	var listed: Array[Dictionary] = main.objectives()
	assert_eq(listed.size(), 4)
	assert_eq_deep(listed[0], {"id": &"reach", "text": "Fly to NAV ALPHA", "primary": true, "state": &"active"})
	assert_eq(listed[3]["state"], &"hidden")


# --- console -----------------------------------------------------------------------------------------------------------------


func test_console_provider_and_commands() -> void:
	assert_true(_run("state mission").ok)
	assert_string_contains(DebugConsole.registry.execute("get mission.step")[0].lines[0], "brief (1/3)")
	var objectives: ConsoleResult = _run("mission objectives")
	assert_true(objectives.ok)
	assert_string_contains(objectives.lines[0], "[active] reach")
	assert_true(_run("mission").ok)
	assert_true(_run("mission journal").ok)
	var skipped: ConsoleResult = _run("mission skip")
	assert_true(skipped.ok, skipped.error)
	assert_string_contains(skipped.lines[0], "now raid")
	var went: ConsoleResult = _run("mission goto report")
	assert_true(went.ok, went.error)
	assert_eq(_api().step_name(), &"report")


func test_console_rejects_bad_arguments() -> void:
	for line: String in ["mission goto", "mission goto nowhere", "mission goto brief", "mission skip now", "mission frob",
			"mission objectives raid"]:
		assert_false(_run(line).ok, line)
	assert_eq(_api().step_name(), &"brief", "nothing moved")


# --- cost ---------------------------------------------------------------------------------------------------------------------


func test_twenty_live_triggers_stay_inside_a_counted_bound() -> void:
	await _reach_the_buoy()
	# The raid step has finished its dialog line and is awaiting `destroyed` (it is live on top of the objectives' triggers).
	await _wait_for("the raid step to await the raiders", func() -> bool:
			return _api().live_trigger_count() > _api().book.live_triggers().size())
	for i: int in 17:
		_api().book.add(StringName("extra_%d" % i), "x", false, TriggerSpec.proximity("player", "NAV ALPHA", 10.0),
				TriggerSpec.destroyed(["RAIDER 1"]))
		_api().objective_add(StringName("extra_%d" % i))
	await _ticks(1)
	var live: int = _api().live_trigger_count()
	var watched: int = _api().watched().size()
	gut.p("live runner: %d live triggers, %d watched names: %d units of work in a tick" % [live, watched, _api().tick_work])
	assert_eq(live, 37, "17 extra objectives with two triggers each, raiders, protect and the awaited destroyed")
	assert_eq(watched, 4, "player, NAV ALPHA, RAIDER 1, RAIDER 2")
	assert_lte(_api().tick_work, 115, "absolute: a check and at most two lookups per trigger, one refresh per name")
