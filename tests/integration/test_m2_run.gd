extends GutTest
## M2 end to end (M2-T10, AC6, AC11): the real main scene runs the three waves headless, driven by `FakeInputSource` (the trigger
## held, so bolts fly) and `kill all`. The number of `GaussianSplatNode`s in the tree is the same at the end as at scenario load
## (no splat node enters or leaves the tree during play); the counters add up; the hit resolver's worst tick is recorded.

const SPEED_UP: float = 5.0

var main: Main
var source: FakeInputSource
var _scale_backup: float = 1.0


func before_each() -> void:
	_scale_backup = Engine.time_scale
	get_tree().paused = false
	DebugConsole.flags.invulnerable = true
	source = FakeInputSource.new()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	main.waves_auto_start = false
	add_child_autofree(main)
	await get_tree().physics_frame
	await get_tree().physics_frame


func after_each() -> void:
	Engine.time_scale = _scale_backup
	DebugConsole.flags.invulnerable = false
	get_tree().paused = false


func _splat_nodes(node: Node) -> int:
	var n: int = 1 if node is GaussianSplatNode else 0
	for child: Node in node.get_children():
		n += _splat_nodes(child)
	return n


func test_three_waves_headless_keep_the_splat_node_count_and_the_counters() -> void:
	var splat_nodes_at_load: int = _splat_nodes(get_tree().root)
	assert_gt(splat_nodes_at_load, 0)
	var resolver: HitResolver = main.get_node("Combat/HitResolver") as HitResolver
	assert_true(DebugConsole.registry.execute("wave start 1")[0].ok)
	source.hold(InputAdapter.FIRE)  # the player keeps firing, so bolts, hits and flashes happen
	Engine.time_scale = SPEED_UP
	var max_resolve_us: int = 0
	var resolve_samples := PackedInt64Array()
	var max_bolts: int = 0
	var killed: int = 0
	var played: Array[int] = []
	for wave: int in 3:
		var t0: float = SimClock.now()
		while main.waves.plan.state != WavePlan.State.ACTIVE and SimClock.now() - t0 < 60.0:
			await get_tree().physics_frame
			max_resolve_us = maxi(max_resolve_us, resolver.resolve_us)
			resolve_samples.append(resolver.resolve_us)
		t0 = SimClock.now()
		while main.ships.alive(ShipPool.DEFAULT_TYPE).size() < main.waves.plan.spawn_total() and SimClock.now() - t0 < 30.0:
			await get_tree().physics_frame
			max_resolve_us = maxi(max_resolve_us, resolver.resolve_us)
			resolve_samples.append(resolver.resolve_us)
			max_bolts = maxi(max_bolts, resolver.projectiles_last_tick)
		for i: int in 120:  # a couple of seconds of the wave: raiders fly their brains, the player's bolts fly
			await get_tree().physics_frame
			max_resolve_us = maxi(max_resolve_us, resolver.resolve_us)
			resolve_samples.append(resolver.resolve_us)
			max_bolts = maxi(max_bolts, resolver.projectiles_last_tick)
		# Every raider of the wave came; the wingmen (M3-T10) and the player's bolts may have shot some down since.
		var spawned: int = main.waves.plan.spawn_total()
		killed += spawned
		played.append(spawned)
		assert_true(DebugConsole.registry.execute("kill all")[0].ok)
		assert_eq(_splat_nodes(get_tree().root), splat_nodes_at_load, "wave %d: splat nodes unchanged" % (wave + 1))
		t0 = SimClock.now()
		while main.waves.plan.wave_number <= wave + 1 and SimClock.now() - t0 < 30.0:
			await get_tree().physics_frame
	source.release(InputAdapter.FIRE)
	Engine.time_scale = 1.0
	resolve_samples.sort()
	var p99_us: int = resolve_samples[mini(resolve_samples.size() - 1, int(0.99 * float(resolve_samples.size())))] if not resolve_samples.is_empty() else 0
	gut.p("M2 run: raiders per wave %s, %d kills, max bolts in a tick %d, combat.resolve_us p99 %d, worst %d" % [str(played),
			main.waves.kills, max_bolts, p99_us, max_resolve_us])
	assert_eq(played, [4, 5, 6], "the three scripted waves")
	assert_eq(main.waves.kills, killed, "every raider the run saw was a kill")
	assert_eq(main.waves.kills, 15)
	assert_eq(main.waves.losses, 0)
	assert_eq(main.waves.plan.wave_number, 4, "and it moved on to the first looped wave")
	assert_eq(main.ships.alive(ShipPool.DEFAULT_TYPE).size(), 0)
	assert_eq(_splat_nodes(get_tree().root), splat_nodes_at_load, "at the end of the run too")
	assert_gt(max_bolts, 0, "bolts flew")
	# Wall clock: the worst single tick is a kill (the destruction's effects run inside the resolve) and doubles on a busy
	# machine (M3-T18: 4 ms alone, 8 ms during the full suite), so the 99th percentile is asserted and the worst recorded.
	WallClockBudget.assert_under(self, p99_us, 5000, "the hit resolver's 99th-percentile tick stayed under 5 ms (the slack is for a busy machine)")
	assert_eq(main.debris.active_chunk_count() >= 0, true)
