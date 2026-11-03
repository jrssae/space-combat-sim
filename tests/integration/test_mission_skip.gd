extends GutTest
## Skipping a mission's steps in the real main scene (architecture §18 D51, AC5, M5-T05): a skipped run leaves the same spawns,
## objectives and world as one played by hand; a skipped `destroyed` releases its ships with no explosion and no kill credit; a
## skipped `proximity` places the player at the goal with its velocity kept; `mission goto` skips every step before the named one.

const MISSION_PATH: String = "res://tests/fixtures/missions/test_mission.json"

var main: Main
var source: FakeInputSource
var _game_state: GameFlow.State
var _game_result: Dictionary


func before_each() -> void:
	get_tree().paused = false
	_game_state = Game.flow.state
	_game_result = Game.flow.last_result
	source = FakeInputSource.new()
	main = await _make_main()


func after_each() -> void:
	get_tree().paused = false
	Game.flow.state = _game_state
	Game.flow.last_result = _game_result


func _make_main() -> Main:
	var m := (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	m.input_source = source
	m.scenario_path = MISSION_PATH
	add_child_autofree(m)
	await _ticks(2)
	return m


func _ticks(n: int) -> void:
	for _i: int in n:
		await get_tree().physics_frame


func _tap(action: StringName) -> void:
	source.hold(action)
	await _ticks(2)
	source.release(action)
	await _ticks(2)


func _api() -> MissionApi:
	return main.mission.api


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


func _explosions() -> int:
	var n: int = 0
	for child: Node in main.effects.get_children():
		n += 1 if child is Explosion else 0
	return n


# What a run leaves behind: its world changes in order, its objectives, the ships still in play, and how it ended.
func _outcome() -> Dictionary:
	var spawns := PackedStringArray()
	for line: String in _api().journal:
		if line.begins_with("spawn ") or line.begins_with("send "):
			spawns.append(line)
	return {"journal": _api().journal.duplicate(), "spawns": spawns, "objectives": _api().book.snapshot(),
			"raiders_in_play": main.ships.alive(ShipPool.DEFAULT_TYPE).size(), "result": GameFlow.describe_result(_api().result),
			"jump_points": main.mission.jumps.opened}


func test_a_skipped_run_leaves_the_same_spawns_and_objectives_as_a_played_one() -> void:
	# Played by hand: fly to the buoy, shoot both raiders down, wait, toggle the assist.
	main.ship.reset_to(Transform3D(main.ship.global_basis, main.world.universe_to_local(UniversePos.new(0.0, 0.0, -1750.0))))
	await _ticks(2)
	for combatant: Combatant in main.ships.alive(ShipPool.DEFAULT_TYPE):
		combatant.damageable.kill()
	await _ticks(70)
	await _tap(InputAdapter.TOGGLE_ASSIST)
	var played: Dictionary = _outcome()
	assert_eq(played["result"], "success: every primary objective done", "the played run finished")
	main.queue_free()
	await get_tree().process_frame

	# Skipped from the console: every step fast-forwarded.
	main = await _make_main()
	assert_true(_run("mission goto report").ok)
	assert_true(_run("mission skip").ok)
	var skipped: Dictionary = _outcome()
	gut.p("played: %s" % ", ".join(played["journal"]))
	assert_eq(skipped["spawns"], played["spawns"], "the same ships spawned and sent, in the same order")
	assert_eq_deep(skipped["objectives"], played["objectives"])
	assert_eq(skipped["journal"], played["journal"], "every world change the same, in the same order")
	assert_eq(skipped["raiders_in_play"], played["raiders_in_play"], "no skipped raider left alive")
	assert_eq(skipped["result"], played["result"])
	assert_eq(skipped["jump_points"], played["jump_points"])


func test_a_skipped_destroyed_releases_its_ships_without_explosion_or_credit() -> void:
	assert_true(_run("mission goto raid").ok)
	assert_eq(main.ships.alive(ShipPool.DEFAULT_TYPE).size(), 2)
	var explosions: int = _explosions()
	assert_true(_run("mission skip").ok)
	assert_eq(main.ships.alive(ShipPool.DEFAULT_TYPE).size(), 0, "released back to the pool")
	assert_eq(main.ships.free_count(ShipPool.DEFAULT_TYPE), 3)
	assert_eq(_explosions(), explosions, "no explosion")
	assert_eq(main.waves.kills, 0, "no kill")
	assert_eq(main.waves.credit.player_kills, 0, "no credit")
	assert_eq(_api().objective_state(&"raiders"), ObjectiveBook.DONE, "the objective whose trigger it made true completed")
	assert_eq(_api().step_name(), &"report")


func test_a_skipped_destroyed_takes_its_ships_out_of_their_wing_first() -> void:
	assert_true(_run("mission goto raid").ok)
	var raiders: Array[Combatant] = main.ships.alive(ShipPool.DEFAULT_TYPE)
	var red: Wing = main.wings.join("RED", raiders[0])
	main.wings.join("RED", raiders[1])
	assert_eq(red.leader, raiders[0])
	assert_eq(red.members().size(), 1)
	assert_true(_run("mission skip").ok)
	assert_eq(red.members().size(), 0, "no member left in a slot of a parked ship's wing")
	assert_false(red.is_lost(1), "released, not shot down: the slot is not marked lost")


func test_a_forced_release_of_a_wing_leader_hands_the_lead_to_the_member_left() -> void:
	assert_true(_run("mission goto raid").ok)
	var raiders: Array[Combatant] = main.ships.alive(ShipPool.DEFAULT_TYPE)
	var third: Combatant = _api().spawn({"type": "raider_fighter", "name": "RAIDER 3", "anchor": "origin",
			"offset": [600, 0, -9000], "behaviour": {"type": "ai", "profile": "raider"}})
	var red: Wing = main.wings.join("RED", raiders[0])
	main.wings.join("RED", raiders[1])
	main.wings.join("RED", third)
	assert_eq(red.leader, raiders[0])
	assert_eq(red.members().size(), 2)
	assert_true(_api().alive(raiders[0].display_name))
	TriggerSpec.destroyed([raiders[0].display_name]).make_true(_api().world)  # what a skipped step does
	assert_false(main.ships.alive().has(raiders[0]), "the leader went back to the pool")
	assert_ne(red.leader, raiders[0], "the lead passed on at once")
	assert_true(red.leader == raiders[1] or red.leader == third, "to the member that is left")
	assert_eq(red.members().size() + 1, 2, "one leader and one member remain")


func test_a_skipped_proximity_places_the_player_at_the_goal_with_its_velocity() -> void:
	main.ship.linear_velocity = Vector3(3.0, 0.0, -20.0)
	await _ticks(1)
	var velocity: Vector3 = main.ship.linear_velocity
	assert_true(_run("mission skip").ok)
	var nav: Vector3 = main.buoys[0].global_position
	assert_lt(main.ship.global_position.distance_to(nav), 400.0, "inside the objective's radius")
	assert_gt(main.ship.global_position.distance_to(nav), 50.0, "beside the buoy, not in it")
	assert_almost_eq(main.ship.linear_velocity.distance_to(velocity), 0.0, 1e-3, "velocity kept")
	assert_eq(_api().objective_state(&"reach"), ObjectiveBook.DONE)
	await _ticks(5)
	assert_eq(_api().objective_state(&"reach"), ObjectiveBook.DONE, "and stays done next tick")


func test_goto_runs_the_world_changes_of_the_steps_it_skips() -> void:
	assert_true(_run("mission goto report").ok)
	assert_eq(_api().step_name(), &"report")
	assert_false(_api().is_skipping(), "the named step runs normally")
	assert_eq(_api().objective_state(&"reach"), ObjectiveBook.DONE)
	assert_eq(_api().objective_state(&"raiders"), ObjectiveBook.DONE)
	assert_eq(_api().objective_state(&"report"), ObjectiveBook.ACTIVE)
	assert_has(_api().journal, "spawn RAIDER 1 raider_fighter")
	assert_has(_api().journal, "send RAIDER 2 -> NAV ALPHA")
	await _ticks(70)
	assert_false(_api().has_ended(), "the report step waits for the player as usual")
	await _tap(InputAdapter.TOGGLE_ASSIST)
	assert_true(bool(_api().result.get("success", false)))


func test_skip_and_goto_refuse_once_the_mission_has_ended() -> void:
	_api().end(true)
	assert_false(_run("mission skip").ok)
	assert_false(_run("mission goto report").ok)
