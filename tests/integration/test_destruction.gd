extends GutTest
## Destruction (M2-T06, AC7, architecture §15.7): a raider at zero hull is destroyed once, leaves play in the same tick, and
## becomes an `Explosion` plus a set of debris chunks while it goes back to the pool; the player's death hides the ship,
## ignores input and respawns it after 3 s of sim time with a full hull. Runs the real main scene; bolts and the resolver are
## stepped by hand where a tick matters.

const DT: float = 1.0 / 60.0
const BOLT_SPEED: float = 400.0

var main: Main
var source: FakeInputSource
var resolver: HitResolver
var raiders: Array[Combatant] = []
var destroyed_log: Array[Combatant] = []


func before_each() -> void:
	get_tree().paused = false
	DebugConsole.flags.invulnerable = false
	source = FakeInputSource.new()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	add_child_autofree(main)
	await _ticks(2)
	resolver = main.get_node("Combat/HitResolver") as HitResolver
	resolver.set_physics_process(false)
	destroyed_log.clear()
	main.director.raider_destroyed.connect(func(c: Combatant, _info: HitInfo) -> void: destroyed_log.append(c))


func after_each() -> void:
	DebugConsole.flags.invulnerable = false
	get_tree().paused = false


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


## A raider `distance` metres ahead of the player, at rest relative to it.
func _spawn_raider(distance: float = 200.0) -> Combatant:
	assert_true(DebugConsole.registry.execute("spawn raider %s" % distance)[0].ok)
	var raider: Combatant = main.ships.alive()[main.ships.alive().size() - 1]
	return raider


## A player bolt at the raider's nose, one tick from hitting it.
func _bolt_at(raider: Combatant, ahead: float = 3.0) -> Projectile:
	var bolt := (load(Projectile.SCENE_PATH) as PackedScene).instantiate() as Projectile
	main.projectiles.add_child(bolt)
	bolt.configure(main.ship.spec.weapon)
	bolt.shooter_id = main.ship.get_instance_id()
	bolt.faction = Factions.EARTH_ALLIANCE
	bolt.launch(raider.ship.global_position + raider.ship.global_basis.z * -1.0 * 0.0 + (main.ship.global_position - raider.ship.global_position).normalized() * (4.0 + ahead), -(main.ship.global_position - raider.ship.global_position).normalized() * BOLT_SPEED, SimClock.now())
	bolt.set_physics_process(false)
	return bolt


func _step_bolts_and_resolve() -> void:
	for node: Node in main.projectiles.get_children():
		var bolt := node as Projectile
		if bolt != null and not bolt.is_spent():
			bolt._physics_process(DT)
	resolver.resolve(DT)


func _effects() -> Array[Explosion]:
	var out: Array[Explosion] = []
	for child: Node in main.effects.get_children():
		if child is Explosion and not child.is_queued_for_deletion():
			out.append(child as Explosion)
	return out


# --- a raider --------------------------------------------------------------------------------------------------


func test_a_raider_at_zero_hull_is_destroyed_once_and_leaves_play_in_the_same_tick() -> void:
	var raider: Combatant = _spawn_raider()
	raider.damageable.hull.apply(raider.damageable.hull.max_hp - 10.0)
	var destroyed_signals: Array[HitInfo] = []
	raider.damageable.destroyed.connect(func(info: HitInfo) -> void: destroyed_signals.append(info))
	var hits_taken: Array[HitInfo] = []
	raider.damageable.hit_taken.connect(func(info: HitInfo) -> void: hits_taken.append(info))
	_bolt_at(raider)
	_bolt_at(raider, 4.0)  # a second bolt arrives in the very same tick
	_step_bolts_and_resolve()
	assert_eq(destroyed_signals.size(), 1, "destroyed fires once")
	assert_eq(hits_taken.size(), 1, "and the second bolt of the tick finds a dead ship")
	assert_false(raider.ship.visible, "hidden in the same tick")
	assert_eq(raider.ship.process_mode, Node.PROCESS_MODE_DISABLED)
	assert_false(raider.targetable.is_active())
	assert_false(raider.damageable.is_active())
	assert_eq(destroyed_log, [raider])
	assert_eq(main.ships.free_count(), main.ships.pool_size(), "back in the pool")
	assert_eq(main.ships.alive().size(), 0)


func test_no_later_bolt_hits_a_destroyed_raider() -> void:
	var raider: Combatant = _spawn_raider()
	raider.damageable.hull.apply(raider.damageable.hull.max_hp - 10.0)
	var position: Vector3 = raider.ship.global_position
	_bolt_at(raider)
	_step_bolts_and_resolve()
	var hits: int = resolver.hits_total
	var late := (load(Projectile.SCENE_PATH) as PackedScene).instantiate() as Projectile
	main.projectiles.add_child(late)
	late.configure(main.ship.spec.weapon)
	late.shooter_id = main.ship.get_instance_id()
	late.faction = Factions.EARTH_ALLIANCE
	late.launch(position + Vector3(0.0, 0.0, 20.0), Vector3(0.0, 0.0, -BOLT_SPEED), SimClock.now())
	late.set_physics_process(false)
	for i: int in 20:
		_step_bolts_and_resolve()
	assert_eq(resolver.hits_total, hits, "nothing else was hit")


func test_the_players_selection_clears_within_one_tick() -> void:
	var raider: Combatant = _spawn_raider()
	main.ship.targeting.refresh()
	assert_true(main.ship.targeting.select_by_name(raider.display_name))
	var seen: Array[int] = []
	main.ship.targeting.target_changed.connect(func(id: int) -> void: seen.append(id))
	raider.damageable.hull.apply(raider.damageable.hull.max_hp - 10.0)
	_bolt_at(raider)
	_step_bolts_and_resolve()
	await _ticks(1)
	assert_false(main.ship.targeting.system.has_selection(), "cleared by the next tick")
	assert_eq(seen, [TargetingSystem.NO_TARGET])


func test_an_explosion_appears_at_the_raider_and_drifts_with_its_velocity() -> void:
	var raider: Combatant = _spawn_raider()
	raider.ship.linear_velocity = Vector3(12.0, 0.0, -35.0)
	var position: Vector3 = raider.ship.global_position
	raider.damageable.kill()
	var explosions: Array[Explosion] = _effects()
	assert_eq(explosions.size(), 1)
	assert_eq(explosions[0].velocity, Vector3(12.0, 0.0, -35.0))
	assert_almost_eq(explosions[0].global_position, position, Vector3.ONE * 1e-3)
	assert_almost_eq(explosions[0].radius_m, raider.damageable.bounding_radius, 1e-5)
	explosions[0].advance(3.2)
	assert_true(explosions[0].is_queued_for_deletion(), "frees itself")


func test_a_chunk_set_leaves_the_pool_and_flies_with_the_ship_then_returns() -> void:
	var raider: Combatant = _spawn_raider()
	var ship_velocity := Vector3(0.0, 0.0, -50.0)
	raider.ship.linear_velocity = ship_velocity
	assert_eq(main.debris.free_set_count(), 2)
	raider.damageable.kill()
	assert_eq(main.debris.free_set_count(), 1, "a set left the pool")
	assert_eq(main.debris.active_chunk_count(), 5)
	var active: Array[DebrisChunk] = []
	for child: Node in main.debris.get_children():
		if (child as DebrisChunk).is_active():
			active.append(child as DebrisChunk)
	for chunk: DebrisChunk in active:
		var separation: float = (chunk.velocity - ship_velocity).length()
		assert_lt(separation, 15.0 + 0.5 + 1e-3, "ship velocity plus a separation speed (and the ship's spin, none here)")
	for i: int in roundi((DebrisChunk.LIFETIME_S + DebrisChunk.SHRINK_S + 0.2) * 60.0):
		for chunk: DebrisChunk in active:
			chunk.advance(DT)
	assert_eq(main.debris.free_set_count(), 2, "and the set is back")


func test_with_both_sets_busy_a_third_break_up_uses_mesh_chunks() -> void:
	for i: int in 3:
		_spawn_raider(100.0 + 60.0 * float(i))
	for combatant: Combatant in main.ships.alive():
		combatant.damageable.kill()
	assert_eq(main.debris.free_set_count(), 0)
	assert_eq(main.debris.mesh_chunks_in_flight(), 5, "the third raider's chunks are mesh only")
	assert_eq(destroyed_log.size(), 3)


func test_kill_all_and_kill_target_work_through_the_console_and_kill_target_needs_a_selection() -> void:
	_spawn_raider(100.0)
	_spawn_raider(160.0)
	assert_false(DebugConsole.registry.execute("kill target")[0].ok, "nothing selected")
	main.ship.targeting.refresh()
	assert_true(DebugConsole.registry.execute("set targeting.selected \"RAIDER 1\"")[0].ok)
	assert_true(DebugConsole.registry.execute("kill target")[0].ok)
	assert_eq(main.ships.alive().size(), 1)
	assert_true(DebugConsole.registry.execute("kill all")[0].ok)
	assert_eq(main.ships.alive().size(), 0)
	assert_eq(destroyed_log.size(), 2)


func test_kill_bypasses_god_mode_but_damage_does_not() -> void:
	DebugConsole.registry.execute("god on")
	DebugConsole.registry.execute("damage 100000 player")
	assert_true(main.player_alive, "god mode holds against damage")
	assert_true(DebugConsole.registry.execute("kill player")[0].ok)
	assert_false(main.player_alive, "but not against kill")


# --- the player --------------------------------------------------------------------------------------------------


func test_the_players_death_hides_the_ship_ignores_input_and_respawns_after_three_seconds() -> void:
	var deaths: Array[int] = []
	var respawns: Array[int] = []
	main.player_died.connect(func() -> void: deaths.append(1))
	main.player_respawned.connect(func() -> void: respawns.append(1))
	main.ship.linear_velocity = Vector3(0.0, 0.0, -40.0)
	await _ticks(2)
	var death_position: Vector3 = main.ship.global_position
	var started_s: float = SimClock.now()
	DebugConsole.registry.execute("kill player")
	assert_false(main.player_alive)
	assert_eq(deaths.size(), 1)
	assert_false(main.ship.visible)
	assert_eq(main.ship.process_mode, Node.PROCESS_MODE_DISABLED)
	assert_eq(_effects().size(), 1, "an explosion at the ship")
	assert_almost_eq(_effects()[0].global_position, death_position, Vector3.ONE * 1.0)
	assert_eq(main.debris.active_chunk_count(), DebrisPool.SHARD_COUNT, "generic shards: the Starfury has no chunks")
	# Input is ignored while dead.
	source.hold(InputAdapter.FIRE)
	var bolts_before: int = main.projectiles.get_child_count()
	await _ticks(30)
	assert_eq(main.projectiles.get_child_count(), bolts_before, "no shots from a dead ship")
	source.release(InputAdapter.FIRE)
	assert_true(main.director.respawn_pending())
	# Respawn after 3 s of sim time, not before.
	while SimClock.now() < started_s + DestructionDirector.RESPAWN_DELAY_S - 0.1:
		await _ticks(1)
	assert_false(main.player_alive, "still dead just before the 3 s are up")
	while SimClock.now() < started_s + DestructionDirector.RESPAWN_DELAY_S + 0.2:
		await _ticks(1)
	assert_true(main.player_alive)
	assert_eq(respawns.size(), 1)
	assert_true(main.ship.visible)
	assert_eq(main.ship.process_mode, Node.PROCESS_MODE_INHERIT)
	assert_eq(main.combatant.damageable.hull.hp, main.combatant.damageable.hull.max_hp, "a full hull")
	assert_false(main.combatant.damageable.hull.destroyed)
	assert_almost_eq(main.ship.linear_velocity.length(), 0.0, 1e-3, "at rest at the scenario start")
	assert_false(main.director.respawn_pending())


func test_the_respawned_player_can_fly_and_be_hit_again() -> void:
	DebugConsole.registry.execute("kill player")
	main.respawn()
	assert_true(main.player_alive)
	assert_true(main.combatant.damageable.is_active())
	assert_true(main.combatant.targetable.is_active())
	assert_true(DebugConsole.registry.execute("damage 50 player")[0].ok)
	assert_eq(main.combatant.damageable.hull.hp, 250.0)


func test_killing_a_dead_player_again_is_refused() -> void:
	assert_true(DebugConsole.registry.execute("kill player")[0].ok)
	assert_false(DebugConsole.registry.execute("kill player")[0].ok)
