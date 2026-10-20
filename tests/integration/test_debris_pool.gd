extends GutTest
## DebrisPool and DebrisChunk (M2-T06, architecture §15.6, §15.7): two parked sets of the raider's chunks, taken by a
## break-up, flown at the ship's velocity plus spin plus a separation speed, hidden and returned after their life; a third
## simultaneous break-up uses mesh chunks; an asset without chunks gets generic shards; no splat node ever enters or leaves
## the tree.

const SPEC_PATH: String = "res://assets/ships/raider_delta_v.tres"
const GEN_ASSETS_HINT: String = "run scripts/gen_assets.sh, then scripts/run_tests.sh (it imports first)"
const ASSET: StringName = &"raider_fighter"

var pool: DebrisPool
var chunks: Array[Dictionary]
var xform := Transform3D(Basis(Vector3.UP, deg_to_rad(40.0)), Vector3(100.0, 20.0, -300.0))


func before_each() -> void:
	var world := Node3D.new()
	world.name = "World"
	add_child_autofree(world)
	pool = DebrisPool.new()
	pool.name = "Debris"
	world.add_child(pool)
	var spec := load(SPEC_PATH) as ShipSpec
	var hardpoints: Hardpoints = Hardpoints.load_file(spec.hardpoints_path())
	assert_true(hardpoints.valid, "%s (%s)" % [hardpoints.error, GEN_ASSETS_HINT])
	chunks = hardpoints.chunks
	assert_eq(pool.prepare(ASSET), DebrisPool.SETS_PER_TYPE)


func _splat_nodes() -> int:
	return _count(get_tree().root)


func _count(node: Node) -> int:
	var n: int = 1 if node is GaussianSplatNode else 0
	for child: Node in node.get_children():
		n += _count(child)
	return n


func _burst(seed_value: int = 1, velocity: Vector3 = Vector3(0.0, 0.0, -30.0), spin: Vector3 = Vector3.ZERO) -> Array[DebrisChunk]:
	return pool.burst(ASSET, chunks, xform, velocity, spin, seed_value)


func _run(seconds: float) -> void:
	for i: int in roundi(seconds * 60.0):
		for child: Node in pool.get_children():
			(child as DebrisChunk).advance(1.0 / 60.0)


# --- the pool ----------------------------------------------------------------------------------------------------


func test_two_sets_of_every_chunk_are_built_parked() -> void:
	assert_eq(chunks.size(), 5)
	assert_eq(pool.set_count(), 2)
	assert_eq(pool.free_set_count(), 2)
	assert_eq(pool.get_child_count(), 10)
	var splat_nodes: int = 0
	for child: Node in pool.get_children():
		splat_nodes += 1 if (child as DebrisChunk).splats != null else 0
	assert_eq(splat_nodes, 10, "one splat node per chunk")
	for child: Node in pool.get_children():
		var chunk := child as DebrisChunk
		assert_false(chunk.visible)
		assert_eq(chunk.process_mode, Node.PROCESS_MODE_DISABLED)
		assert_false(chunk.is_active())
		assert_not_null(chunk.splats, "a splat node each")
		assert_not_null(chunk.mesh_instance.mesh, "and the chunk's mesh (%s)" % GEN_ASSETS_HINT)
		assert_true(chunk.is_in_group(SplatStatus.MESH_GROUP))
		assert_true(chunk.is_in_group(WorldFrame.SHIFTABLE_GROUP))


func test_each_chunk_has_its_own_splats() -> void:
	var names: Array[String] = []
	for child: Node in pool.get_children():
		var chunk := child as DebrisChunk
		names.append(chunk.chunk_name)
		assert_not_null(chunk.splats.gaussian, "%s: PLY imported (%s)" % [chunk.chunk_name, GEN_ASSETS_HINT])
	assert_eq(names.count("wing_l"), 2)
	assert_eq(names.count("hump"), 2)


# --- a break-up --------------------------------------------------------------------------------------------------


func test_a_burst_takes_a_set_and_places_every_chunk_at_its_offset() -> void:
	var launched: Array[DebrisChunk] = _burst()
	assert_eq(launched.size(), 5)
	assert_eq(pool.free_set_count(), 1)
	for i: int in launched.size():
		var chunk: DebrisChunk = launched[i]
		assert_true(chunk.is_active())
		assert_true(chunk.visible)
		assert_eq(chunk.chunk_name, chunks[i]["name"])
		assert_almost_eq(chunk.global_position, xform.origin + xform.basis * (chunks[i]["offset"] as Vector3), Vector3.ONE * 1e-4)
		assert_true(chunk.global_basis.is_equal_approx(xform.basis), "starts in the ship's orientation")


func test_chunks_fly_at_ship_velocity_plus_spin_plus_a_separation_speed() -> void:
	var velocity := Vector3(5.0, -2.0, -60.0)
	var spin := Vector3(0.0, 0.5, 0.0)
	var launched: Array[DebrisChunk] = _burst(7, velocity, spin)
	for i: int in launched.size():
		var chunk: DebrisChunk = launched[i]
		var r: Vector3 = xform.basis * (chunks[i]["offset"] as Vector3)
		var separation: Vector3 = chunk.velocity - velocity - spin.cross(r)
		assert_true(separation.length() >= 4.0 - 1e-3 and separation.length() <= 15.0 + 1e-3, "%s separation %.2f m/s in 4-15" % [chunk.chunk_name, separation.length()])
		if r.length() > 0.1:
			assert_gt(separation.normalized().dot(r.normalized()), 0.99, "%s: outward" % chunk.chunk_name)
		assert_lte(chunk.angular_velocity.length(), deg_to_rad(90.0) + 1e-6)


func test_the_same_seed_gives_the_same_break_up() -> void:
	var first: Array[DebrisChunk] = _burst(42)
	var first_velocities: Array[Vector3] = []
	for chunk: DebrisChunk in first:
		first_velocities.append(chunk.velocity)
		chunk.park()
	var again: Array[DebrisChunk] = _burst(42)
	for i: int in again.size():
		assert_eq(again[i].velocity, first_velocities[i], "chunk %d" % i)
	for chunk: DebrisChunk in again:
		chunk.park()
	var other: Array[DebrisChunk] = _burst(43)
	assert_ne(other[0].velocity, first_velocities[0])


func test_chunks_drift_and_spin_without_collisions() -> void:
	var launched: Array[DebrisChunk] = _burst(3)
	var chunk: DebrisChunk = launched[2]
	var start: Vector3 = chunk.global_position
	var v: Vector3 = chunk.velocity
	_run(1.0)
	assert_almost_eq(chunk.global_position, start + v * (60.0 / 60.0), Vector3.ONE * 0.01)
	if chunk.angular_velocity.length() > 0.01:
		assert_false(chunk.global_basis.is_equal_approx(xform.basis), "it has turned")


func test_a_set_hides_and_returns_after_its_lifetime_with_a_half_second_shrink() -> void:
	var launched: Array[DebrisChunk] = _burst()
	_run(DebrisChunk.LIFETIME_S - 0.1)
	for chunk: DebrisChunk in launched:
		assert_true(chunk.is_active())
		assert_almost_eq(chunk.scale.x, 1.0, 1e-5, "full size until the end of its life")
	_run(0.25)
	assert_lt(launched[0].scale.x, 1.0, "shrinking")
	_run(DebrisChunk.SHRINK_S)
	for chunk: DebrisChunk in launched:
		assert_false(chunk.is_active())
		assert_false(chunk.visible)
		assert_eq(chunk.process_mode, Node.PROCESS_MODE_DISABLED)
	assert_eq(pool.free_set_count(), 2, "the set is back")
	_burst(9)
	assert_almost_eq(launched[0].scale, Vector3.ONE, Vector3.ONE * 1e-5)


func test_with_both_sets_busy_a_third_break_up_uses_mesh_chunks() -> void:
	var before: int = _splat_nodes()
	_burst(1)
	_burst(2)
	assert_eq(pool.free_set_count(), 0)
	assert_eq(pool.mesh_chunks_in_flight(), 0)
	var third: Array[DebrisChunk] = _burst(3)
	assert_eq(third.size(), 5)
	assert_eq(pool.mesh_chunks_in_flight(), 5)
	for chunk: DebrisChunk in third:
		assert_null(chunk.splats, "mesh only")
		assert_true(chunk.mesh_instance.visible)
		assert_true(chunk.one_shot)
	assert_eq(_splat_nodes(), before, "no splat node was created")
	_run(DebrisChunk.LIFETIME_S + DebrisChunk.SHRINK_S + 0.2)
	await get_tree().process_frame
	assert_eq(pool.mesh_chunks_in_flight(), 0, "the mesh chunks freed themselves")


func test_splat_nodes_never_enter_or_leave_the_tree_during_break_ups() -> void:
	var before: int = _splat_nodes()
	for round: int in 6:
		_burst(round)
		assert_eq(_splat_nodes(), before, "round %d" % round)
		_run(DebrisChunk.LIFETIME_S + DebrisChunk.SHRINK_S + 0.2)
		await get_tree().process_frame
		assert_eq(_splat_nodes(), before, "round %d, after" % round)


func test_an_asset_without_chunks_gets_generic_shards() -> void:
	var shards: Array[DebrisChunk] = pool.burst(&"starfury_aurora", [] as Array[Dictionary], xform, Vector3.ZERO, Vector3.ZERO, 5)
	assert_eq(shards.size(), DebrisPool.SHARD_COUNT)
	for shard: DebrisChunk in shards:
		assert_true(shard.is_active())
		assert_null(shard.splats)
		assert_not_null(shard.mesh_instance.mesh)
		assert_true(shard.one_shot)
	assert_eq(pool.free_set_count(), 2, "the raider's sets are untouched")


func test_the_fallback_mesh_is_shown_instead_of_the_splats() -> void:
	var chunk: DebrisChunk = _burst()[0]
	chunk.use_fallback_mesh(false)
	assert_true(chunk.splats.visible)
	assert_false(chunk.mesh_instance.visible)
	chunk.use_fallback_mesh(true)
	assert_false(chunk.splats.visible)
	assert_true(chunk.mesh_instance.visible)


func test_a_rebase_moves_chunks_in_flight() -> void:
	var world := WorldFrame.new()
	world.name = "WorldFrame"
	add_child_autofree(world)
	var local_pool := DebrisPool.new()
	world.add_child(local_pool)
	local_pool.prepare_chunks(ASSET, chunks, false)
	var launched: Array[DebrisChunk] = local_pool.burst(ASSET, chunks, xform, Vector3.ZERO, Vector3.ZERO, 1)
	var before: Vector3 = launched[0].global_position
	world.rebase(Vector3(1000.0, 0.0, 0.0))
	assert_almost_eq(launched[0].global_position, before - Vector3(1000.0, 0.0, 0.0), Vector3.ONE * 1e-3)


func test_the_debris_provider_reports_the_pool() -> void:
	var registry: ConsoleRegistry = DebugConsole.registry
	assert_eq(registry.format_path("debris.sets"), "debris.sets = 2")
	_burst()
	assert_eq(registry.format_path("debris.free_sets"), "debris.free_sets = 1")
	assert_eq(registry.format_path("debris.active_chunks"), "debris.active_chunks = 5")
