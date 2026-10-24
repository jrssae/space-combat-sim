extends GutTest
## WaveDirector (M2-T09, AC11, architecture §15.10): on the real main scene with the combat sandbox, a headless run driven by
## `wave start`, `kill all` and waiting advances through three waves with the expected kills; spawns arrive where the scenario
## says, relative to the player's universe position at wave start; the status line reads out the state; the player's death
## does not end the wave; and `scenario` reloads the scene.

const DT: float = 1.0 / 60.0

var main: Main
var source: FakeInputSource
var _scale_backup: float = 1.0


func before_each() -> void:
	_scale_backup = Engine.time_scale
	get_tree().paused = false
	DebugConsole.flags.invulnerable = true  # nothing in these tests is about the player's hull
	source = FakeInputSource.new()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	main.waves_auto_start = false
	add_child_autofree(main)
	await _ticks(2)


func after_each() -> void:
	Engine.time_scale = _scale_backup
	DebugConsole.flags.invulnerable = false
	get_tree().paused = false


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _exec(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


func _wait_for_state(state: StringName, limit_s: float = 60.0) -> void:
	var t0: float = SimClock.now()
	while main.waves.plan.state_name() != state and SimClock.now() - t0 < limit_s:
		await _ticks(1)


func test_the_sandbox_is_the_default_scenario_and_waits_for_wave_start() -> void:
	assert_eq(main.waves.scenario_id, &"combat_sandbox")
	assert_eq(main.ships.pool_size(ShipPool.DEFAULT_TYPE), 6)
	assert_eq(main.waves.plan.state, WavePlan.State.IDLE, "auto start is off for tests")
	assert_eq(main.buoys.size(), 5, "the buoys stay as scenery")
	assert_eq(DebugConsole.registry.format_path("waves.scenario"), "waves.scenario = combat_sandbox")


func test_auto_start_begins_the_first_countdown() -> void:
	var auto: Main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	auto.input_source = FakeInputSource.new()
	add_child_autofree(auto)
	await _ticks(3)
	assert_eq(auto.waves.plan.state, WavePlan.State.COUNTDOWN)
	assert_eq(auto.waves.plan.current_name(), "TARGET PRACTICE")
	assert_eq(auto.status_line.begins_with("WAVE 1  TARGET PRACTICE   IN "), true, auto.status_line)


func test_wave_start_runs_the_countdown_then_spawns_the_waves_raiders() -> void:
	assert_true(_exec("wave start 1").ok)
	assert_eq(main.waves.plan.state, WavePlan.State.COUNTDOWN)
	Engine.time_scale = 4.0
	await _wait_for_state(&"active")
	await _ticks(3)
	Engine.time_scale = 1.0
	assert_eq(main.ships.alive().size(), 3, "TARGET PRACTICE: three raiders")
	for combatant: Combatant in main.ships.alive():
		assert_true(combatant.driver.brain is IdleBrain)
		assert_gt(combatant.ship.linear_velocity.length(), 4.0, "drifting")
		assert_lt(combatant.ship.linear_velocity.length(), 21.0)
		var ahead: float = (combatant.ship.global_position - main.ship.global_position).length()
		assert_true(ahead > 1000.0 and ahead < 2600.0, "1.2-2 km out: %.0f" % ahead)


func test_spawns_are_offsets_from_the_players_position_at_wave_start() -> void:
	main.ship.global_position = Vector3(500.0, 0.0, -300.0)
	main.ship.reset_physics_interpolation()
	var anchor: UniversePos = main.world.to_universe(main.ship.global_position)
	assert_true(_exec("wave start 1").ok)
	Engine.time_scale = 4.0
	await _wait_for_state(&"active")
	await _ticks(2)
	Engine.time_scale = 1.0
	var first: Combatant = main.ships.alive()[0]
	var expected := Vector3(-700.0, 60.0, -1300.0)
	var at: UniversePos = main.world.to_universe(first.ship.global_position)
	var drifted: Vector3 = first.ship.linear_velocity * 2.0 * DT * 4.0
	assert_lt(at.distance_to(anchor.plus_local(expected)), drifted.length() + 5.0, "the first raider's offset from the anchor")


func test_kill_all_clears_a_wave_and_the_next_one_comes() -> void:
	assert_true(_exec("wave start 1").ok)
	Engine.time_scale = 4.0
	await _wait_for_state(&"active")
	await _ticks(3)
	assert_eq(main.ships.alive().size(), 3)
	assert_true(_exec("kill all").ok)
	assert_eq(main.waves.kills, 3, "every raider destroyed counts")
	await _wait_for_state(&"cleared")
	assert_eq(main.waves.plan.state, WavePlan.State.CLEARED)
	assert_string_contains(main.status_line, "CLEARED")
	await _wait_for_state(&"countdown")
	assert_eq(main.waves.plan.wave_number, 2)
	assert_eq(main.waves.plan.current_name(), "PATROL")
	Engine.time_scale = 1.0


func test_three_waves_advance_with_the_expected_kills() -> void:
	assert_true(_exec("wave start 1").ok)
	Engine.time_scale = 5.0
	var expected_kills: int = 0
	for wave: int in 3:
		await _wait_for_state(&"active", 90.0)
		# Strike spawns over 6 s: wait for them all, then kill everything.
		var t0: float = SimClock.now()
		while main.ships.alive().size() < main.waves.plan.spawn_total() and SimClock.now() - t0 < 30.0:
			await _ticks(1)
		await _ticks(2)
		expected_kills += main.ships.alive().size()
		assert_true(_exec("kill all").ok)
		await _wait_for_state(&"cleared", 20.0)
		assert_eq(main.waves.plan.wave_number, wave + 1)
		assert_eq(main.waves.plan.state, WavePlan.State.CLEARED, "wave %d cleared" % (wave + 1))
	Engine.time_scale = 1.0
	assert_eq(main.waves.kills, expected_kills)
	assert_eq(expected_kills, 3 + 3 + 4)
	assert_eq(DebugConsole.registry.format_path("waves.kills"), "waves.kills = 10")
	await _wait_for_state(&"countdown", 20.0)
	assert_eq(main.waves.plan.wave_number, 4, "and it loops: wave 4 is the strike again with one more")
	assert_eq(main.waves.plan.spawn_total(), 5)


func test_the_status_line_follows_the_state() -> void:
	assert_eq(main.status_line, "")
	_exec("wave start 2")
	assert_true(main.status_line.begins_with("WAVE 2  PATROL   IN "), main.status_line)
	Engine.time_scale = 5.0
	await _wait_for_state(&"active")
	await _ticks(3)
	Engine.time_scale = 1.0
	assert_string_contains(main.status_line, "RAIDERS 3")
	assert_string_contains(main.status_line, "KILLS 0")
	_exec("wave stop")
	assert_eq(main.status_line, "")


func test_wave_next_skips_and_restart_repeats() -> void:
	_exec("wave start 1")
	assert_true(_exec("wave next").ok)
	assert_eq(main.waves.plan.wave_number, 2)
	assert_true(_exec("wave restart").ok)
	assert_eq(main.waves.plan.wave_number, 2)
	assert_eq(main.waves.plan.state, WavePlan.State.COUNTDOWN)
	assert_true(_exec("wave stop").ok)
	assert_eq(main.waves.plan.state, WavePlan.State.IDLE)
	assert_false(_exec("wave start 9").ok, "only three scripted waves")


func test_the_waves_provider() -> void:
	var registry: ConsoleRegistry = DebugConsole.registry
	for key: String in ["scenario", "index", "name", "state", "next_in_s", "alive", "kills", "losses"]:
		assert_true(registry.read("waves.%s" % key)["ok"], key)
	_exec("wave start 3")
	assert_eq(registry.format_path("waves.index"), "waves.index = 3")
	assert_eq(registry.format_path("waves.name"), "waves.name = STRIKE")
	assert_eq(registry.format_path("waves.state"), "waves.state = countdown")


func test_the_wave_goes_on_across_the_players_death() -> void:
	_exec("wave start 2")
	Engine.time_scale = 5.0
	await _wait_for_state(&"active")
	await _ticks(3)
	assert_eq(main.ships.alive().size(), 3)
	DebugConsole.flags.invulnerable = false
	assert_true(_exec("kill player").ok)
	assert_eq(main.waves.losses, 1)
	assert_eq(main.ships.alive().size(), 3, "the raiders stay")
	assert_eq(main.waves.plan.state, WavePlan.State.ACTIVE, "and the wave is still on")
	var t0: float = SimClock.now()
	while not main.player_alive and SimClock.now() - t0 < 10.0:
		await _ticks(1)
	Engine.time_scale = 1.0
	assert_true(main.player_alive)
	assert_eq(main.ships.alive().size(), 3)
	assert_eq(main.waves.plan.wave_number, 2, "the same wave")
	for combatant: Combatant in main.ships.alive():
		assert_eq(combatant.driver._retarget_in_s, 0.0, "pilots look for the respawned player at once")


func test_free_flight_has_no_waves_and_no_pool() -> void:
	var free: Main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	free.input_source = FakeInputSource.new()
	free.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	add_child_autofree(free)
	await _ticks(3)
	assert_eq(free.ships.pool_size(), 0)
	assert_eq(free.waves.plan.state, WavePlan.State.IDLE)
	await _ticks(60)
	assert_eq(free.waves.plan.state, WavePlan.State.IDLE, "free flight never starts a wave")
	assert_false(DebugConsole.registry.execute("wave start 1")[0].ok, "no waves in this scenario")
	assert_eq(free.status_line, "")


func test_the_scenario_command_sets_the_session_setting() -> void:
	var backup: Variant = Settings.get_value(&"scenario")
	assert_true(_exec("scenario free_flight").ok)
	assert_eq(Settings.get_value(&"scenario"), &"free_flight")
	assert_eq(main.resolved_scenario_path(), "res://data/scenarios/free_flight.json")
	assert_false(_exec("scenario moon_base").ok, "an unknown scenario is refused")
	Settings.set_value(&"scenario", backup)
	assert_eq(main.resolved_scenario_path(), "res://data/scenarios/%s.json" % backup)


func test_scenario_path_overrides_the_setting() -> void:
	assert_eq(main.resolved_scenario_path(), "res://data/scenarios/combat_sandbox.json")
	main.scenario_path = "res://data/scenarios/free_flight.json"
	assert_eq(main.resolved_scenario_path(), "res://data/scenarios/free_flight.json")
