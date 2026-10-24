extends GutTest
## The Starfury's break-up (M3-T08, AC7, architecture §15.7, §16 D35): a destroyed ally and the dead player both explode into the
## five Starfury chunks (the cabin and four arms, cut from LOD1) as pooled chunk splats. The pool prepares two Starfury sets in
## every scenario, shared by allies and the player; a third simultaneous break-up gets mesh chunks; an ally goes straight back
## to the ship pool; and no `GaussianSplatNode` enters or leaves the tree through any of it (D22). Runs the real main scene.

const DT: float = 1.0 / 60.0
const STARFURY: StringName = &"starfury_aurora"
const GEN_ASSETS_HINT: String = "run scripts/gen_assets.sh, then scripts/run_tests.sh (it imports first)"

var main: Main
var source: FakeInputSource
var manifest: ManifestReader
var chunk_entries: Array[Dictionary]
var shipped: Array[Combatant] = []


func before_each() -> void:
	get_tree().paused = false
	DebugConsole.flags.invulnerable = false
	source = FakeInputSource.new()
	main = _new_main()
	add_child_autofree(main)
	await _ticks(2)
	manifest = ManifestReader.load_dir("res://assets/generated/starfury_aurora")
	assert_true(manifest.is_valid(), "%s (%s)" % [manifest.errors_text(), GEN_ASSETS_HINT])
	chunk_entries = Hardpoints.load_file(main.ship.spec.hardpoints_path()).chunks
	assert_eq(chunk_entries.size(), 5, "the cabin and four arms")
	shipped.clear()
	main.director.ship_destroyed.connect(func(c: Combatant, _info: HitInfo) -> void: shipped.append(c))


func after_each() -> void:
	DebugConsole.flags.invulnerable = false
	get_tree().paused = false


# Free flight with explicit pools (three raiders, four allies): no waves and no wing, whatever the sandbox grows into.
func _new_main() -> Main:
	var instance := (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	instance.input_source = source
	instance.waves_auto_start = false
	instance.scenario_path = "res://data/scenarios/free_flight.json"
	instance.raider_pool_size = 3
	instance.ally_pool_size = 4
	return instance


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _exec(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


func _splat_nodes() -> int:
	return _count(get_tree().root)


func _count(node: Node) -> int:
	var n: int = 1 if node is GaussianSplatNode else 0
	for child: Node in node.get_children():
		n += _count(child)
	return n


func _spawn_ally(distance: float = 120.0) -> Combatant:
	assert_true(_exec("spawn ally idle %s" % distance).ok)
	var allies: Array[Combatant] = main.ships.alive(ShipPool.ALLY_TYPE)
	return allies[allies.size() - 1]


func _active_chunks() -> Array[DebrisChunk]:
	var out: Array[DebrisChunk] = []
	for child: Node in main.debris.get_children():
		var chunk := child as DebrisChunk
		if chunk != null and chunk.is_active():
			out.append(chunk)
	return out


func _effects() -> Array[Explosion]:
	var out: Array[Explosion] = []
	for child: Node in main.effects.get_children():
		if child is Explosion and not child.is_queued_for_deletion():
			out.append(child as Explosion)
	return out


## Runs every chunk in flight to the end of its life.
func _run_chunks_out() -> void:
	var active: Array[DebrisChunk] = _active_chunks()
	for i: int in roundi((DebrisChunk.LIFETIME_S + DebrisChunk.SHRINK_S + 0.2) * 60.0):
		for chunk: DebrisChunk in active:
			chunk.advance(DT)


func _assert_starfury_splat_chunks(chunks: Array[DebrisChunk], label: String) -> void:
	assert_eq(chunks.size(), 5, "%s: five chunks" % label)
	var names: PackedStringArray = PackedStringArray()
	var total: int = 0
	var dir: String = "res://assets/generated/starfury_aurora"
	for chunk: DebrisChunk in chunks:
		names.append(chunk.chunk_name)
		assert_not_null(chunk.splats, "%s: %s is a splat chunk, not a mesh-only one" % [label, chunk.chunk_name])
		assert_false(chunk.one_shot, "%s: %s is pooled" % [label, chunk.chunk_name])
		if chunk.splats == null or chunk.splats.gaussian == null:
			continue
		total += chunk.splats.gaussian.point_count
		var entry: Dictionary = _entry(chunk.chunk_name)
		assert_eq(chunk.splats.gaussian.resource_path, dir.path_join(String(entry["ply"])), "%s: %s" % [label, chunk.chunk_name])
	names.sort()
	assert_eq(names, PackedStringArray(["arm_ll", "arm_lr", "arm_ul", "arm_ur", "cabin"]))
	assert_eq(total, int(manifest.lods[1]["splats"]), "%s: the chunks hold exactly the LOD1 hull" % label)


func _entry(chunk_name: String) -> Dictionary:
	for entry: Dictionary in chunk_entries:
		if entry["name"] == chunk_name:
			return entry
	return {}


# --- the sets ----------------------------------------------------------------------------------------------------


func test_two_starfury_sets_are_prepared_beside_the_raiders() -> void:
	assert_eq(main.debris.set_count(STARFURY), DebrisPool.SETS_PER_TYPE)
	assert_eq(main.debris.free_set_count(STARFURY), DebrisPool.SETS_PER_TYPE)
	assert_eq(main.debris.set_count(&"raider_fighter"), DebrisPool.SETS_PER_TYPE)
	assert_eq(main.debris.set_count(), 2 * DebrisPool.SETS_PER_TYPE)
	assert_eq(DebugConsole.registry.format_path("debris.sets"), "debris.sets = 4")


func test_preparing_the_starfury_again_for_the_ally_type_builds_nothing_more() -> void:
	var before: int = _splat_nodes()
	assert_eq(main.debris.prepare(ShipPool.ALLY_TYPE), DebrisPool.SETS_PER_TYPE, "the ally shares the Starfury's sets")
	assert_eq(main.debris.prepare(&"starfury_aurora"), DebrisPool.SETS_PER_TYPE)
	assert_eq(main.debris.set_count(STARFURY), DebrisPool.SETS_PER_TYPE)
	assert_eq(_splat_nodes(), before)


func test_every_scenario_prepares_the_starfury_sets_not_only_the_sandbox() -> void:
	var free_flight := (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	free_flight.input_source = source
	free_flight.scenario_path = "res://data/scenarios/free_flight.json"
	add_child_autofree(free_flight)
	await _ticks(2)
	assert_eq(free_flight.debris.set_count(STARFURY), DebrisPool.SETS_PER_TYPE, "the player can die in free flight")
	assert_eq(free_flight.debris.set_count(&"raider_fighter"), 0, "but there are no raiders to break up")
	assert_eq(free_flight.ships.pool_size(), 0)


# --- the player --------------------------------------------------------------------------------------------------


func test_the_players_death_is_five_starfury_chunk_splats() -> void:
	assert_true(_exec("kill player").ok)
	var chunks: Array[DebrisChunk] = _active_chunks()
	_assert_starfury_splat_chunks(chunks, "player")
	assert_eq(main.debris.mesh_chunks_in_flight(), 0)
	assert_eq(main.debris.free_set_count(STARFURY), DebrisPool.SETS_PER_TYPE - 1)
	assert_eq(shipped.size(), 0, "the player has its own signal")


# --- an ally -----------------------------------------------------------------------------------------------------


func test_a_destroyed_ally_explodes_into_starfury_chunks_and_returns_to_the_pool() -> void:
	var ally: Combatant = _spawn_ally()
	ally.ship.linear_velocity = Vector3(5.0, 0.0, -40.0)
	var position: Vector3 = ally.ship.global_position
	var free_before: int = main.ships.free_count(ShipPool.ALLY_TYPE)
	assert_lt(free_before, main.ships.pool_size(ShipPool.ALLY_TYPE))
	assert_true(ally.damageable.kill())
	assert_eq(shipped, [ally], "ship_destroyed names the ally, once")
	assert_false(ally.ship.visible, "gone in the same tick")
	assert_eq(ally.ship.process_mode, Node.PROCESS_MODE_DISABLED)
	assert_false(ally.targetable.is_active())
	assert_false(ally.damageable.is_active())
	assert_eq(main.ships.free_count(ShipPool.ALLY_TYPE), main.ships.pool_size(ShipPool.ALLY_TYPE), "back in the pool")
	assert_eq(main.ships.alive(ShipPool.ALLY_TYPE).size(), 0)
	var explosions: Array[Explosion] = _effects()
	assert_eq(explosions.size(), 1)
	assert_almost_eq(explosions[0].global_position, position, Vector3.ONE * 1e-3)
	assert_eq(explosions[0].velocity, Vector3(5.0, 0.0, -40.0))
	assert_almost_eq(explosions[0].radius_m, ally.damageable.bounding_radius, 1e-5)
	var chunks: Array[DebrisChunk] = _active_chunks()
	_assert_starfury_splat_chunks(chunks, "ally")
	for chunk: DebrisChunk in chunks:
		assert_lt((chunk.velocity - Vector3(5.0, 0.0, -40.0)).length(), 15.0 + 0.5 + 1e-3, "the ship's velocity plus a separation speed")
	_run_chunks_out()
	assert_eq(main.debris.free_set_count(STARFURY), DebrisPool.SETS_PER_TYPE, "and the set is back")


func test_a_destroyed_ally_is_a_fresh_ship_when_it_launches_again() -> void:
	var ally: Combatant = _spawn_ally()
	ally.damageable.hull.apply(ally.damageable.hull.max_hp - 10.0)
	assert_true(ally.damageable.kill())
	var seen_it_again: bool = false
	for i: int in main.ships.pool_size(ShipPool.ALLY_TYPE):
		var again: Combatant = main.ships.acquire("ALPHA %d" % (i + 2), main.world.to_universe(Vector3(60.0 * float(i), 0.0, -300.0)),
				Basis.IDENTITY, Vector3.ZERO, null, ShipPool.ALLY_TYPE)
		assert_not_null(again)
		assert_eq(again.damageable.hull.hp, again.damageable.hull.max_hp, "full hull")
		assert_false(again.damageable.hull.destroyed)
		assert_true(again.damageable.is_active())
		assert_true(again.ship.visible)
		seen_it_again = seen_it_again or again == ally
	assert_true(seen_it_again, "the destroyed ally came back out of the pool")


func test_kill_target_works_on_an_ally_and_kill_allies_destroys_every_ally_but_no_raider() -> void:
	_spawn_ally(100.0)
	_spawn_ally(160.0)
	assert_true(_exec("spawn raider idle 220").ok)
	main.ship.targeting.refresh()
	assert_true(_exec("set targeting.selected \"ALPHA 2\"").ok)
	assert_true(_exec("kill target").ok)
	assert_eq(main.ships.alive(ShipPool.ALLY_TYPE).size(), 1)
	var result: ConsoleResult = _exec("kill allies")
	assert_true(result.ok)
	assert_string_contains(result.lines[0], "1 allied")
	assert_eq(main.ships.alive(ShipPool.ALLY_TYPE).size(), 0)
	assert_eq(main.ships.alive(ShipPool.DEFAULT_TYPE).size(), 1, "the raider is still there")
	assert_eq(shipped.size(), 2)
	assert_false(_exec("kill allies").ok, "none left")
	var all: ConsoleResult = _exec("kill all")
	assert_true(all.ok)
	assert_string_contains(all.lines[0], "1 raider")
	assert_eq(main.ships.alive().size(), 0)


func test_a_raiders_death_also_reports_ship_destroyed() -> void:
	assert_true(_exec("spawn raider idle 150").ok)
	var raider: Combatant = main.ships.alive()[0]
	assert_true(raider.damageable.kill())
	assert_eq(shipped, [raider])


# --- the sets are shared -----------------------------------------------------------------------------------------


func test_allies_and_the_player_share_two_sets_and_a_third_break_up_is_mesh_only() -> void:
	var first: Combatant = _spawn_ally(100.0)
	var second: Combatant = _spawn_ally(160.0)
	var third: Combatant = _spawn_ally(220.0)
	var before: int = _splat_nodes()
	first.damageable.kill()
	second.damageable.kill()
	assert_eq(main.debris.free_set_count(STARFURY), 0, "two allies used both sets")
	assert_eq(main.debris.mesh_chunks_in_flight(), 0)
	third.damageable.kill()
	assert_eq(main.debris.mesh_chunks_in_flight(), 5, "the third ally's chunks are mesh only")
	assert_eq(main.debris.free_set_count(&"raider_fighter"), DebrisPool.SETS_PER_TYPE, "the raiders' sets are untouched")
	main.combatant.damageable.kill()
	assert_eq(main.debris.mesh_chunks_in_flight(), 10, "and so are the player's, with both sets busy")
	assert_eq(_splat_nodes(), before, "no splat node was created for them")


# --- D22 ---------------------------------------------------------------------------------------------------------


func test_splat_nodes_never_enter_or_leave_the_tree_through_launch_destroy_and_respawn() -> void:
	var before: int = _splat_nodes()
	assert_gt(before, 0)
	for round: int in 3:
		var launched: Array[Combatant] = []
		for i: int in 3:
			launched.append(_spawn_ally(100.0 + 60.0 * float(i)))
		assert_true(_exec("spawn raider idle 400").ok)
		assert_eq(_splat_nodes(), before, "round %d: launched" % round)
		for combatant: Combatant in launched:
			combatant.damageable.kill()
		assert_eq(_splat_nodes(), before, "round %d: allies destroyed (two sets, a mesh third)" % round)
		assert_true(_exec("kill player").ok)
		assert_eq(_splat_nodes(), before, "round %d: the player destroyed" % round)
		_run_chunks_out()
		await get_tree().process_frame
		assert_eq(_splat_nodes(), before, "round %d: debris gone" % round)
		main.respawn()
		_exec("despawn all")
		assert_eq(_splat_nodes(), before, "round %d: respawned and parked" % round)
		assert_eq(main.debris.free_set_count(STARFURY), DebrisPool.SETS_PER_TYPE, "round %d: both sets are back" % round)
