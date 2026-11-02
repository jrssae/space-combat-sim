extends GutTest
## The Starfury's last-hit break-up (M3-T28, AC38, Q28): the killing hit picks the cabin or the arm that leaves first, the
## explosion starts at its joint and the others come away one at a time inside 1.2 s, each at the wreck's motion plus its kick.
## Runs the real main scene (free flight, so no waves); the wreck is stepped by hand.

const DT: float = 1.0 / 60.0
const STARFURY: StringName = &"starfury_aurora"
## A point on each part, in the ship's frame: DamageZones' cabin band and the four arms' quadrants.
const PART_POINTS: Dictionary[StringName, Vector3] = {
	&"cabin": Vector3(0.0, -0.3, -2.0), &"arm_ur": Vector3(4.0, 2.0, 0.4), &"arm_lr": Vector3(4.0, -2.0, 0.4),
	&"arm_ul": Vector3(-4.0, 2.0, 0.4), &"arm_ll": Vector3(-4.0, -2.0, 0.4),
}

var main: Main
var source: FakeInputSource
var chunk_entries: Array[Dictionary]


func before_each() -> void:
	get_tree().paused = false
	DebugConsole.flags.invulnerable = false
	source = FakeInputSource.new()
	main = _new_main("res://data/scenarios/free_flight.json")
	add_child_autofree(main)
	await _ticks(2)
	chunk_entries = Hardpoints.load_file(main.ship.spec.hardpoints_path()).chunks
	assert_eq(chunk_entries.size(), 5)


func after_each() -> void:
	Factions.reset()
	DebugConsole.flags.invulnerable = false
	get_tree().paused = false


func _new_main(scenario: String) -> Main:
	var instance := (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	instance.input_source = source
	instance.waves_auto_start = false
	instance.scenario_path = scenario
	instance.raider_pool_size = 3
	instance.ally_pool_size = 4
	return instance


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _exec(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


func _spawn_ally(distance: float = 120.0) -> Combatant:
	assert_true(_exec("spawn ally idle %s" % distance).ok)
	var allies: Array[Combatant] = main.ships.alive(ShipPool.ALLY_TYPE)
	return allies[allies.size() - 1]


func _chunk_index(chunk_name: StringName) -> int:
	for i: int in chunk_entries.size():
		if StringName(chunk_entries[i]["name"]) == chunk_name:
			return i
	return -1


func _joint_of(chunk_name: StringName) -> Vector3:
	return chunk_entries[_chunk_index(chunk_name)]["joint"]


func _explosions() -> Array[Explosion]:
	var out: Array[Explosion] = []
	for child: Node in main.effects.get_children():
		if child is Explosion and not child.is_queued_for_deletion():
			out.append(child as Explosion)
	return out


## The killing hit: a bolt (or a ram) that removes the whole hull at `local_point` of the ship.
func _kill_at(combatant: Combatant, local_point: Vector3, cause: StringName = HitInfo.CAUSE_BOLT) -> HitInfo:
	var info := HitInfo.new(combatant.ship.get_instance_id(), 0, Factions.RAIDERS, combatant.damageable.hull.max_hp * 2.0,
			combatant.ship.global_transform * local_point, Vector3.UP, 400.0, cause)
	combatant.damageable.apply_hit(info)
	return info


func _held_chunks() -> Array[DebrisChunk]:
	var out: Array[DebrisChunk] = []
	for child: Node in main.debris.get_children():
		var chunk := child as DebrisChunk
		if chunk != null and chunk.is_held():
			out.append(chunk)
	return out


func _chunk_nodes() -> Array[DebrisChunk]:
	var out: Array[DebrisChunk] = []
	for child: Node in main.debris.get_children():
		var chunk := child as DebrisChunk
		if chunk != null and chunk.is_active():
			out.append(chunk)
	return out


func _node_of(chunk_name: StringName) -> DebrisChunk:
	for chunk: DebrisChunk in _chunk_nodes():
		if chunk.chunk_name == String(chunk_name):
			return chunk
	return null


## One physics tick of the wreck and of every released chunk, done by hand.
func _step() -> void:
	main.debris.advance_wrecks(DT)
	for chunk: DebrisChunk in _chunk_nodes():
		chunk.advance(DT)


func _splat_nodes(node: Node) -> int:
	var n: int = 1 if node is GaussianSplatNode else 0
	for child: Node in node.get_children():
		n += _splat_nodes(child)
	return n


func _lights(node: Node) -> int:
	var n: int = 1 if node is Light3D else 0
	for child: Node in node.get_children():
		n += _lights(child)
	return n


# --- which part, and where the blast starts ----------------------------------------------------------------------


func test_the_part_hit_last_leaves_first_and_the_blast_starts_at_its_joint_for_the_player() -> void:
	for part_name: StringName in PART_POINTS:
		var body: Combatant = main.combatant
		main.ship.linear_velocity = Vector3(3.0, 1.0, -25.0)
		var xform: Transform3D = main.ship.global_transform
		var info := _kill_at(body, PART_POINTS[part_name])
		assert_false(main.player_alive, "%s: the player is dead" % part_name)
		var wreck: StagedWreck = main.debris.last_wreck
		assert_eq(wreck.plan.order[0], _chunk_index(part_name), "%s leaves first" % part_name)
		var blast: Explosion = _explosions()[_explosions().size() - 1]
		assert_lt(blast.global_position.distance_to(xform * _joint_of(part_name)), 0.5, "%s: the blast starts at its joint" % part_name)
		assert_eq(main.director.last_blast_position, blast.position, "the sound follows the blast")
		assert_almost_eq(info.point.distance_to(xform * PART_POINTS[part_name]), 0.0, 1e-4)
		var held: Array[DebrisChunk] = _held_chunks()
		assert_eq(held.size(), 4, "%s: the other four stay with the wreck" % part_name)
		assert_false(_node_of(part_name).is_held())
		for i: int in 200:
			_step()
		main.respawn()
		await _ticks(1)
		for chunk: DebrisChunk in _chunk_nodes():
			chunk.park()
		for explosion: Explosion in _explosions():
			explosion.free()


func test_the_same_holds_for_an_ally_and_for_a_ram() -> void:
	for part_name: StringName in PART_POINTS:
		var ally: Combatant = _spawn_ally()
		var xform: Transform3D = ally.ship.global_transform
		_kill_at(ally, PART_POINTS[part_name], HitInfo.CAUSE_RAM if part_name == &"arm_ul" else HitInfo.CAUSE_BOLT)
		assert_eq(main.debris.last_wreck.plan.order[0], _chunk_index(part_name), "%s leaves first (ally)" % part_name)
		var blast: Explosion = _explosions()[_explosions().size() - 1]
		assert_lt(blast.global_position.distance_to(xform * _joint_of(part_name)), 0.5, "%s: ally blast at its joint" % part_name)
		for i: int in 200:
			_step()
		for chunk: DebrisChunk in _chunk_nodes():
			chunk.park()
		for explosion: Explosion in _explosions():
			explosion.free()


func test_the_instructors_hull_type_breaks_up_the_same_way() -> void:
	var scenario: Main = _new_main("res://data/scenarios/instructor_route.json")
	add_child_autofree(scenario)
	await _ticks(2)
	var instructor: Combatant = scenario.instructor
	assert_not_null(instructor)
	instructor.damageable.invulnerable = false
	var xform: Transform3D = instructor.ship.global_transform
	var info := HitInfo.new(instructor.ship.get_instance_id(), 0, Factions.RAIDERS, 1.0e6, xform * PART_POINTS[&"arm_lr"], Vector3.UP, 300.0)
	instructor.damageable.apply_hit(info)
	var wreck: StagedWreck = scenario.debris.last_wreck
	assert_not_null(wreck)
	assert_eq(wreck.plan.order[0], _chunk_index(&"arm_lr"))
	assert_lt(scenario.director.last_blast_position.distance_to(xform * _joint_of(&"arm_lr")), 0.5, "the blast is at its joint")


func test_a_console_kill_blasts_from_the_centre_with_a_seeded_order() -> void:
	var ally: Combatant = _spawn_ally()
	var centre: Vector3 = ally.ship.global_position
	assert_true(ally.damageable.kill())
	var blast: Explosion = _explosions()[_explosions().size() - 1]
	assert_almost_eq(blast.global_position, centre, Vector3.ONE * 1e-3)
	var wreck: StagedWreck = main.debris.last_wreck
	assert_eq(wreck.plan.order.size(), 5)
	assert_eq(wreck.plan.release_s[wreck.plan.order[0]], 0.0)
	assert_eq(_held_chunks().size(), 4)


# --- the staged part ---------------------------------------------------------------------------------------------


func test_a_chunk_let_go_in_a_real_tick_does_not_pop_ahead_of_the_wreck() -> void:
	var ally: Combatant = _spawn_ally()
	ally.ship.linear_velocity = Vector3(0.0, 0.0, -80.0)
	_kill_at(ally, PART_POINTS[&"arm_ur"])
	var wreck: StagedWreck = main.debris.last_wreck
	var next: int = wreck.plan.order[1]
	var chunk: DebrisChunk = _node_of(StringName(chunk_entries[next]["name"]))
	var ticks: int = 0
	while chunk.is_held() and ticks < 120:
		await get_tree().physics_frame
		ticks += 1
	assert_false(chunk.is_held(), "it was let go")
	assert_lt(chunk.global_position.distance_to(wreck.chunk_transform(next).origin), 1e-3, "still exactly where the wreck has it")


func test_the_others_come_away_one_at_a_time_inside_1_2_s_with_the_wrecks_motion_plus_a_kick() -> void:
	var ally: Combatant = _spawn_ally()
	ally.ship.linear_velocity = Vector3(5.0, -2.0, -40.0)
	ally.ship.angular_velocity = Vector3(0.2, 0.5, -0.3)
	_kill_at(ally, PART_POINTS[&"arm_ur"])
	var wreck: StagedWreck = main.debris.last_wreck
	var order: PackedInt32Array = wreck.plan.order
	var released_at: Dictionary = {}  # chunk index -> tick
	var velocities: Dictionary = {}  # chunk index -> velocity at release
	var tick: int = 0
	while tick < 80:
		var held_before: Array[int] = []
		for i: int in 5:
			if _node_of(StringName(chunk_entries[i]["name"])).is_held():
				held_before.append(i)
		main.debris.advance_wrecks(DT)
		for i: int in held_before:
			var chunk: DebrisChunk = _node_of(StringName(chunk_entries[i]["name"]))
			if chunk.is_held():
				assert_false(chunk.has_vent(), "no venting while it is still part of the wreck")
			else:
				assert_true(chunk.has_vent(), "venting starts at release")
				assert_almost_eq(chunk.age_s(), 0.0, 1e-6, "its life starts at release")
				assert_false(released_at.has(i))
				released_at[i] = tick
				velocities[i] = chunk.velocity
				var r: Vector3 = wreck.basis * chunk_entries[i]["offset"]
				var rigid: Vector3 = wreck.velocity + wreck.spin.cross(r)
				var kick: float = (chunk.velocity - rigid).length()
				assert_almost_eq(kick, wreck.plan.kick_mps[i], 1e-2, "rigid motion at the point plus the kick")
				assert_between(kick, BreakupPlan.KICK_MPS.x - 1e-2, BreakupPlan.KICK_MPS.y + 1e-2)
		for chunk: DebrisChunk in _chunk_nodes():
			chunk.advance(DT)
		tick += 1
	assert_eq(released_at.size(), 4, "the four others came away after the first")
	var last_tick: int = -1
	for k: int in range(1, order.size()):
		var t: int = released_at[order[k]]
		assert_gt(t, last_tick, "one at a time, in the plan's order")
		last_tick = t
	assert_lt(float(last_tick) * DT, 1.2, "all gone within 1.2 s")
	assert_gt(float(released_at[order[1]]) * DT, 0.1, "the others stay joined for a moment")
	assert_eq(main.debris.held_wreck_count(), 0)
	for i: int in velocities:
		var chunk: DebrisChunk = _node_of(StringName(chunk_entries[i]["name"]))
		assert_eq(chunk.velocity, velocities[i], "constant after release: no damping")


func test_held_chunks_do_not_drift_apart() -> void:
	var ally: Combatant = _spawn_ally()
	ally.ship.linear_velocity = Vector3(0.0, 0.0, -60.0)
	ally.ship.angular_velocity = Vector3(0.1, 0.9, 0.4)
	_kill_at(ally, PART_POINTS[&"cabin"])
	var wreck: StagedWreck = main.debris.last_wreck
	var held: Array[DebrisChunk] = _held_chunks()
	var a: DebrisChunk = held[0]
	var b: DebrisChunk = held[1]
	var apart: float = a.global_position.distance_to(b.global_position)
	for i: int in 10:
		main.debris.advance_wrecks(DT)
	assert_almost_eq(a.global_position.distance_to(b.global_position), apart, 1e-3, "a rigid body keeps its shape")
	assert_almost_eq((a.global_basis.get_scale()).x, 1.0, 1e-4)
	assert_gt(wreck.age_s, 0.1)


func test_a_rebase_during_the_staged_part_moves_nothing_relative_to_the_wreck() -> void:
	var ally: Combatant = _spawn_ally()
	ally.ship.linear_velocity = Vector3(0.0, 0.0, -50.0)
	ally.ship.angular_velocity = Vector3(0.0, 0.2, 0.0)
	_kill_at(ally, PART_POINTS[&"arm_ll"])
	for i: int in 6:
		main.debris.advance_wrecks(DT)
	var held: Array[DebrisChunk] = _held_chunks()
	assert_gt(held.size(), 1)
	var before: Array[Vector3] = []
	for chunk: DebrisChunk in held:
		before.append(chunk.global_position)
	main.debris.advance_wrecks(DT)
	var step: Array[Vector3] = []
	for k: int in held.size():
		step.append(held[k].global_position - before[k])
	var offset := Vector3(4000.0, -50.0, -9000.0)
	var after_step: Array[Vector3] = []
	for chunk: DebrisChunk in held:
		after_step.append(chunk.global_position)
	main.world.rebase(offset)
	main.debris.advance_wrecks(DT)
	for k: int in held.size():
		assert_true(held[k].is_held())
		var expected: Vector3 = after_step[k] - offset + step[k]
		assert_almost_eq(held[k].global_position, expected, Vector3.ONE * 1e-3, "%s did not move against the wreck" % held[k].chunk_name)


func test_a_death_on_a_rebased_world_still_blasts_at_the_joint() -> void:
	var ally: Combatant = _spawn_ally()
	main.world.rebase(Vector3(6000.0, 0.0, -3000.0))
	var xform: Transform3D = ally.ship.global_transform
	_kill_at(ally, PART_POINTS[&"arm_ul"])
	var blast: Explosion = _explosions()[_explosions().size() - 1]
	assert_lt(blast.global_position.distance_to(xform * _joint_of(&"arm_ul")), 0.5)
	assert_eq(main.debris.last_wreck.plan.order[0], _chunk_index(&"arm_ul"))


# --- the pools ---------------------------------------------------------------------------------------------------


func test_the_player_respawning_during_the_staged_second_is_harmless() -> void:
	_kill_at(main.combatant, PART_POINTS[&"arm_ur"])
	for i: int in 5:
		main.debris.advance_wrecks(DT)
	main.respawn()
	for i: int in 90:
		_step()
	assert_true(main.player_alive)
	assert_eq(main.debris.held_wreck_count(), 0)
	assert_eq(_held_chunks().size(), 0)


func test_a_pooled_ally_taken_again_during_the_staged_second_does_not_disturb_the_wreck() -> void:
	var ally: Combatant = _spawn_ally()
	_kill_at(ally, PART_POINTS[&"arm_lr"])
	var wreck: StagedWreck = main.debris.last_wreck
	var again: Combatant = _spawn_ally(300.0)
	assert_not_null(again)
	for i: int in 80:
		_step()
	assert_eq(main.debris.held_wreck_count(), 0)
	assert_eq(wreck.plan.order.size(), 5)
	assert_true(wreck.finished())


func test_the_blasts_add_no_nodes_no_lights_and_do_not_reuse_particle_emitters() -> void:
	var ally: Combatant = _spawn_ally()
	var splats: int = _splat_nodes(get_tree().root)
	var lights: int = _lights(get_tree().root)
	var emitters: int = main.fx.get_child_count()
	var reused: int = main.fx.reused
	_kill_at(ally, PART_POINTS[&"arm_ur"])
	var most_hit_bursts: int = 0
	for i: int in 80:
		_step()
		most_hit_bursts = maxi(most_hit_bursts, main.fx.busy_count(FxSpecs.HIT))
	assert_gt(most_hit_bursts, 0, "the smaller blasts did happen")
	assert_eq(_splat_nodes(get_tree().root), splats, "AC32: no splat node enters or leaves")
	assert_eq(_lights(get_tree().root), lights, "the smaller blasts add no Light3D")
	assert_eq(main.fx.get_child_count(), emitters, "and no particle emitter")
	assert_eq(main.fx.reused, reused, "one death takes free emitters only")


func test_every_set_busy_gives_mesh_chunks_that_stage_the_same_way() -> void:
	var allies: Array[Combatant] = []
	for i: int in 3:
		allies.append(_spawn_ally(100.0 + 50.0 * float(i)))
	for ally: Combatant in allies:
		_kill_at(ally, PART_POINTS[&"arm_ul"])
	assert_eq(main.debris.free_set_count(STARFURY), 0)
	assert_eq(main.debris.mesh_chunks_in_flight(), 5, "the third wreck is mesh only")
	var wreck: StagedWreck = main.debris.last_wreck
	assert_eq(wreck.plan.order[0], _chunk_index(&"arm_ul"))
	for i: int in 80:
		_step()
	assert_eq(main.debris.held_wreck_count(), 0)


func test_raiders_and_buoys_break_up_as_before() -> void:
	assert_true(_exec("spawn raider idle 150").ok)
	var raider: Combatant = main.ships.alive(ShipPool.DEFAULT_TYPE)[0]
	assert_true(raider.damageable.kill())
	assert_eq(main.debris.held_wreck_count(), 0, "a raider's chunks all fly in the death tick")
	assert_eq(_held_chunks().size(), 0)
	assert_eq(main.debris.active_chunk_count(), 5)
