extends TestSteps
## The explosion level of detail in play (M4-T23, architecture §17.14): a near death is the full explosion as before, a death
## farther out a reduced one (no light, fewer particles, no debris), and a far death a point flash in one shared multimesh
## that costs no node and no particle; the distances come from the fireball's size on this picture (fix round 1); a death in the low-attention tier flashes where its row flew; a capital's death
## flashes too, leaves play and keeps its blast's energy and radius on the event (M12). The real main scene.

var main: Main


func before_each() -> void:
	get_tree().paused = false
	DebugConsole.flags.invulnerable = false
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.waves_auto_start = false
	add_child_autofree(main)
	await _ticks(2)


func after_each() -> void:
	DebugConsole.flags.invulnerable = false


func _raider(distance_m: float) -> Combatant:
	assert_true(DebugConsole.registry.execute("spawn raider %s" % distance_m)[0].ok)
	var alive: Array[Combatant] = main.ships.alive(ShipPool.DEFAULT_TYPE)
	return alive[alive.size() - 1]


func _explosions() -> Array[Explosion]:
	var out: Array[Explosion] = []
	for child: Node in main.effects.get_children():
		if child is Explosion and not child.is_queued_for_deletion():
			out.append(child as Explosion)
	return out


func _flash_count() -> int:
	var flashes: FarFlashes = FarFlashes.of(main.world)
	return flashes.flash_count() if flashes != null else 0


func _camera_distance(at: Vector3) -> float:
	return get_viewport().get_camera_3d().global_position.distance_to(at)


# Where a hull of `radius`'s fireball is `px` pixels in radius on this picture, m.
func _switch_m(radius: float, px: float) -> float:
	return ExplosionLod.switch_distance_m(radius, ExplosionLod.picture_lines(get_viewport()), get_viewport().get_camera_3d().fov, px)


func _level(radius: float, at: Vector3) -> ExplosionLod.Level:
	return ExplosionLod.level(radius, _camera_distance(at), ExplosionLod.picture_lines(get_viewport()), get_viewport().get_camera_3d().fov)


# A raider placed `distance_m` ahead, with its radius known before it is spawned (the pool's raiders are all alike).
func _raider_radius() -> float:
	var probe: Combatant = _raider(100.0)
	var r: float = probe.damageable.bounding_radius
	main.ships.release(probe)
	return r


func test_a_near_death_is_the_full_explosion_as_before() -> void:
	var raider: Combatant = _raider(200.0)
	await _ticks(1)
	var debris_before: int = main.debris.active_chunk_count()
	raider.damageable.kill()
	var made: Array[Explosion] = _explosions()
	assert_eq(made.size(), 1, "one explosion")
	assert_false(made[0].reduced, "the full effect")
	assert_eq(_flash_count(), 0, "no far flash")
	assert_gt(main.debris.active_chunk_count(), debris_before, "and its debris")
	assert_gt(main.fx.busy_count(FxSpecs.EXPLOSION_SPARKS), 0, "and its sparks")


func test_a_death_between_is_a_reduced_explosion_with_no_light_and_no_debris() -> void:
	var r: float = _raider_radius()
	var raider: Combatant = _raider(0.5 * (_switch_m(r, ExplosionLod.FULL_PX) + _switch_m(r, ExplosionLod.REDUCED_PX)))
	await _ticks(1)
	assert_eq(_level(r, raider.ship.global_position), ExplosionLod.Level.REDUCED, "(the raider sits in the reduced band)")
	var debris_before: int = main.debris.active_chunk_count()
	raider.damageable.kill()
	var made: Array[Explosion] = _explosions()
	assert_eq(made.size(), 1)
	assert_true(made[0].reduced, "the reduced effect")
	assert_false(made[0].lit(), "no light")
	assert_eq(main.fx.busy_count(FxSpecs.EXPLOSION_SPARKS), 0, "no sparks")
	assert_eq(main.fx.busy_count(FxSpecs.EXPLOSION_FRAGMENTS), 0, "no fragments")
	assert_eq(main.debris.active_chunk_count(), debris_before, "no debris")


func test_a_far_death_is_a_point_flash_that_costs_no_node_and_no_particle() -> void:
	var r: float = _raider_radius()
	var raider: Combatant = _raider(1.3 * _switch_m(r, ExplosionLod.REDUCED_PX))
	await _ticks(2)
	assert_false(raider.ship.is_tier_parked(), "(within 10 km: still on its body)")
	assert_eq(_level(r, raider.ship.global_position), ExplosionLod.Level.FAR, "(past the flash's switch)")
	var nodes_before: int = main.effects.get_child_count()
	var busy_before: int = main.fx.busy_count()
	var debris_before: int = main.debris.active_chunk_count()
	var info := HitInfo.new(raider.ship.get_instance_id(), 0, &"", 1.0e9, raider.ship.global_position, Vector3.ZERO, 0.0,
			HitInfo.CAUSE_CONSOLE)
	raider.damageable.apply_hit(info)
	assert_eq(main.effects.get_child_count(), nodes_before, "no explosion node")
	assert_eq(main.fx.busy_count(), busy_before, "no particles")
	assert_eq(main.debris.active_chunk_count(), debris_before, "no debris")
	assert_eq(_flash_count(), 1, "one far flash")
	assert_almost_eq(info.blast_energy_j, raider.ship.mass * DestructionDirector.BLAST_J_PER_KG, 1.0, "the blast's energy stays on the event")
	assert_gt(info.blast_radius_m, 0.0, "and its radius")
	await _ticks(60)
	assert_eq(_flash_count(), 0, "the flash is over within a second")


func test_a_death_in_the_tier_flashes_where_its_row_flew() -> void:
	var raider: Combatant = _raider(15000.0)
	raider.ship.linear_velocity = Vector3(0.0, 80.0, 0.0)
	await _ticks(70)
	assert_true(raider.ship.is_tier_parked(), "(15 km: a tier row)")
	var sim: SimCore = SimCore.for_tree(get_tree())
	var row: Vector4 = sim.core.tier_position(raider.ship.get_instance_id())
	raider.damageable.kill()
	assert_eq(_explosions().size(), 0, "no explosion node")
	assert_eq(_flash_count(), 1, "a far flash")
	var flashes: FarFlashes = FarFlashes.of(main.world)
	assert_lt(flashes.flash_position(0).distance_to(main.world.to_global(Vector3(row.x, row.y, row.z))), 5.0, "where the row was")
	assert_gt(flashes.flash_position(0).distance_to(raider.ship.global_position), 20.0, "(not where the node was parked)")


func test_a_far_capitals_death_flashes_leaves_play_and_keeps_its_blast_on_the_event() -> void:
	var standins: StandinDirector = main.world.get_node("Standins") as StandinDirector
	var cap: CapitalStandin = standins.add_capital(&"carrier", Factions.RAIDERS, "CARRIER", main.world.to_universe(Vector3(0.0, 0.0, -14000.0)),
			Basis.IDENTITY, Vector3.ZERO)
	standins.active = true
	await _ticks(4)
	assert_true(cap.is_tier_parked(), "(14 km: a tier row)")
	var events: Array[HitInfo] = []
	main.director.capital_destroyed.connect(func(_c: CapitalStandin, info: HitInfo) -> void: events.append(info))
	assert_true(cap.damageable.kill())
	assert_eq(events.size(), 1, "the death is an event")
	assert_almost_eq(events[0].blast_energy_j, cap.mass * DestructionDirector.BLAST_J_PER_KG, 1.0, "its blast energy on it")
	assert_almost_eq(events[0].blast_radius_m, cap.damageable.bounding_radius * DestructionDirector.BLAST_RADIUS_FACTOR, 0.01)
	assert_false(cap.visible or cap.can_process(), "the capital left play")
	var sim: SimCore = SimCore.for_tree(get_tree())
	assert_false(sim.core.tier_has(cap.get_instance_id()), "and the tier")
	assert_eq(_explosions().size(), 1, "at 14 km a carrier's fireball is tens of pixels: the full explosion")
	assert_false(_explosions()[0].reduced)
	assert_eq(_flash_count(), 0)
	await _ticks(4)
	assert_false(cap.visible, "and is not promoted back")


func test_a_capital_past_its_switch_dies_as_a_far_flash() -> void:
	var standins: StandinDirector = main.world.get_node("Standins") as StandinDirector
	var far_m: float = 1.3 * _switch_m(CapitalStandin.hull_radius(&"cruiser"), ExplosionLod.REDUCED_PX)
	var cap: CapitalStandin = standins.add_capital(&"cruiser", Factions.RAIDERS, "CRUISER", main.world.to_universe(Vector3(0.0, 0.0, -far_m)),
			Basis.IDENTITY, Vector3.ZERO)
	standins.active = true
	await _ticks(4)
	assert_true(cap.is_tier_parked(), "(%.0f km: a tier row)" % (far_m / 1000.0))
	assert_true(cap.damageable.kill())
	assert_eq(_explosions().size(), 0, "no explosion node")
	assert_eq(_flash_count(), 1, "a far flash")


func test_kill_target_destroys_a_selected_capital() -> void:
	var standins: StandinDirector = main.world.get_node("Standins") as StandinDirector
	var cap: CapitalStandin = standins.add_capital(&"cruiser", Factions.RAIDERS, "CRUISER", main.world.to_universe(Vector3(0.0, 0.0, -3000.0)),
			Basis.IDENTITY, Vector3.ZERO)
	standins.active = true
	await _ticks(2)
	assert_true(main.ship.targeting.select_by_name("CRUISER"))
	var result: ConsoleResult = DebugConsole.registry.execute("kill")[0]
	assert_true(result.ok, str(result.lines))
	assert_true(cap.damageable.hull.destroyed)
