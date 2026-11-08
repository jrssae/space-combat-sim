extends GutTest
## M4-T44 (F5): what a world made must leave with it. The native brain host holds its core (rows, RIDs, step threads), so it
## is dropped when that core's world leaves; the tier director's hull cache is cleared when the director leaves.


func _world() -> WorldFrame:
	var world := WorldFrame.new()
	world.name = "World"
	add_child(world)
	return world


func test_the_brain_host_leaves_with_its_world() -> void:
	var world: WorldFrame = _world()
	var sim: SimCore = SimCore.attach(world)
	assert_not_null(sim, "a core attaches to the world")
	var host: Object = NativeBrains.host(get_tree())
	assert_not_null(host, "the host is made over the core")
	assert_same(NativeBrains._core, sim.core, "and holds it")
	world.free()
	assert_null(NativeBrains._host, "the host left with its world")
	assert_null(NativeBrains._core, "and so did its core")


func test_another_world_leaving_keeps_the_live_host() -> void:
	var world: WorldFrame = _world()
	var sim: SimCore = SimCore.attach(world)
	var host: Object = NativeBrains.host(get_tree())
	var stray := SimCore.new()  # a core that never fed the host
	add_child(stray)
	stray.free()
	assert_same(NativeBrains._host, host, "a core the host is not over leaves it alone")
	assert_same(NativeBrains._core, sim.core)
	world.free()


func test_the_tier_hull_cache_leaves_with_its_director() -> void:
	var world: WorldFrame = _world()
	var body := RigidBody3D.new()
	world.add_child(body)
	var hull := Damageable.new()
	hull.name = "Damageable"
	body.add_child(hull)
	var tier: TierDirector = TierDirector.attach(world, null)
	assert_not_null(tier, "a director attaches to the world")
	assert_same(TierDirector._damageable_of(body.get_instance_id()), hull, "the director finds the hull")
	assert_eq(TierDirector._damageables.size(), 1, "and keeps it")
	world.free()
	assert_true(TierDirector._damageables.is_empty(), "the cache left with the director")
