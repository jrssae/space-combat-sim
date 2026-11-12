extends TestSteps
## Kill credit in play (M3-T16, Q18, AC24): on the real main scene with the combat sandbox, the player's own bolts make a
## player kill; firing at the selected raider and leaving the kill to an ally makes an assist, never both; the player's ram
## is a kill; total kills counts every raider; the status line and the `waves` provider show all three; a pool ship handed
## out again starts clean.

const DT: float = 1.0 / 60.0

var main: Main
var source: FakeInputSource
var _scale_backup: float = 1.0
var _shots: int = 0


func before_each() -> void:
	_scale_backup = Engine.time_scale
	get_tree().paused = false
	DebugConsole.flags.invulnerable = true  # nothing here is about the player's hull
	source = FakeInputSource.new()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	main.waves_auto_start = false
	add_child_autofree(main)
	await _ticks(2)
	_exec("despawn all")  # the sandbox's wingmen (M3-T10) would shoot these tests' raiders
	_shots = 0
	main.cannon.shot_fired.connect(func(_i: int, _at: Vector3) -> void: _shots += 1)


func after_each() -> void:
	Engine.time_scale = _scale_backup
	DebugConsole.flags.invulnerable = false
	get_tree().paused = false


func _spawn(line: String, type: StringName = ShipPool.DEFAULT_TYPE) -> Combatant:
	assert_true(_exec(line).ok, line)
	var alive: Array[Combatant] = main.ships.alive(type)
	return alive[alive.size() - 1]


func _select(combatant: Combatant) -> void:
	assert_true(main.ship.targeting.select_id(combatant.targetable.get_instance_id()), "selected %s" % combatant.display_name)


# Holds the trigger until `shots` bolts have left the guns (or `limit_s` of sim time), then lets go.
func _fire(shots: int, limit_s: float = 5.0) -> void:
	var target: int = _shots + shots
	var t0: float = SimClock.now()
	source.hold(InputAdapter.FIRE)
	while _shots < target and SimClock.now() - t0 < limit_s:
		await _ticks(1)
	source.release(InputAdapter.FIRE)
	await _ticks(1)
	assert_gte(_shots, target, "the player fired")


func _fatal_hit(victim: Combatant, shooter_id: int, cause: StringName = HitInfo.CAUSE_BOLT) -> void:
	victim.damageable.apply_hit(HitInfo.new(victim.ship.get_instance_id(), shooter_id, Factions.EARTH_ALLIANCE,
			victim.damageable.hull.max_hp * 10.0, victim.ship.global_position, Vector3.UP, 50.0, cause))


func test_the_players_own_bolts_make_a_player_kill() -> void:
	var raider: Combatant = _spawn("spawn raider idle 200")
	# On the line of the first gun (the guns sit under the cabin, off the raider's centre at 200 m).
	var muzzle: Vector3 = (main.cannon._muzzles[0] as Node3D).global_position
	raider.ship.reset_to(Transform3D(raider.ship.global_basis, muzzle - main.ship.global_basis.z * 200.0))
	raider.damageable.hull.apply(raider.damageable.hull.max_hp - 1.0)  # one bolt from dead
	_select(raider)
	var t0: float = SimClock.now()
	source.hold(InputAdapter.FIRE)
	while main.waves.kills == 0 and SimClock.now() - t0 < 5.0:
		await _ticks(1)
	source.release(InputAdapter.FIRE)
	assert_eq(main.waves.kills, 1, "the raider dead ahead went down")
	assert_eq(main.waves.credit.player_kills, 1, "to the player's bolt")
	assert_eq(main.waves.credit.player_assists, 0, "a kill is never also an assist")


func test_an_allys_kill_of_the_raider_the_player_fired_at_is_an_assist() -> void:
	var ally: Combatant = _spawn("spawn ally idle 150", ShipPool.ALLY_TYPE)
	var raider: Combatant = _spawn("spawn raider idle 1500 70")  # far off the nose: the bolts miss it
	_select(raider)
	await _fire(1)
	_fatal_hit(raider, ally.ship.get_instance_id())
	assert_eq(main.waves.kills, 1)
	assert_eq([main.waves.credit.player_kills, main.waves.credit.player_assists], [0, 1])
	assert_eq(DebugConsole.registry.format_path("waves.player_assists"), "waves.player_assists = 1")


func test_shots_with_another_ship_selected_earn_no_assist() -> void:
	var raider: Combatant = _spawn("spawn raider idle 1500 70")
	var other: Combatant = _spawn("spawn raider idle 1500 -70")
	_select(other)
	await _fire(1)
	assert_true(raider.damageable.kill())
	assert_eq(main.waves.kills, 1)
	assert_eq([main.waves.credit.player_kills, main.waves.credit.player_assists], [0, 0])


func test_the_players_ram_is_a_player_kill() -> void:
	var raider: Combatant = _spawn("spawn raider idle 1500 70")
	_select(raider)
	await _fire(1)  # fired at it as well: still one kill, no assist
	_fatal_hit(raider, main.ship.get_instance_id(), HitInfo.CAUSE_RAM)
	assert_eq([main.waves.credit.player_kills, main.waves.credit.player_assists], [1, 0])
	assert_eq(DebugConsole.registry.format_path("waves.player_kills"), "waves.player_kills = 1")


func test_the_status_line_shows_total_kills_the_players_and_assists() -> void:
	assert_true(_exec("wave start 1").ok)
	Engine.time_scale = 4.0
	var t0: float = SimClock.now()
	while main.waves.plan.state_name() != &"active" and SimClock.now() - t0 < 60.0:
		await _ticks(1)
	await _ticks(3)
	Engine.time_scale = 1.0
	var raiders: Array[Combatant] = main.ships.alive(ShipPool.DEFAULT_TYPE)
	assert_eq(raiders.size(), 4, "TARGET PRACTICE")
	assert_string_contains(main.status_line, "RAIDERS 4   KILLS 0   YOURS 0   ASSISTS 0")
	_fatal_hit(raiders[0], main.ship.get_instance_id())
	await _ticks(1)
	assert_string_contains(main.status_line, "RAIDERS 3   KILLS 1   YOURS 1   ASSISTS 0")
	assert_true(_exec("kill all").ok)
	await _ticks(2)
	assert_string_contains(main.status_line, "CLEARED   KILLS 4   YOURS 1   ASSISTS 0")


func test_a_pool_ship_handed_out_again_starts_clean() -> void:
	var raiders: Array[Combatant] = []
	for i: int in main.ships.pool_size(ShipPool.DEFAULT_TYPE):
		raiders.append(_spawn("spawn raider idle %d %d" % [1500 + 100 * i, 70]))
	var marked: Combatant = raiders[2]
	_select(marked)
	await _fire(1)
	var id: int = marked.targetable.get_instance_id()
	assert_true(main.waves.credit.fired_at(id))
	main.ships.release(marked)
	assert_true(main.waves.credit.fired_at(id), "parked, it keeps its mark until it is somebody new")
	var again: Combatant = _spawn("spawn raider idle 1500 -70")
	assert_eq(again, marked, "the only free raider")
	assert_false(main.waves.credit.fired_at(id), "the reused ship starts clean")
	assert_true(again.damageable.kill())
	assert_eq(main.waves.credit.player_assists, 0)
