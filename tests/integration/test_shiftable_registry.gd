extends GutTest
## `ShiftableRegistry` (M6-T21): a rebase walks the World's shiftable nodes in play, kept as they enter and leave the tree,
## with what pools and the tier parked out of it, instead of walking the whole group.

const TOL_M: float = 1e-3

var world: WorldFrame


func before_each() -> void:
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)


func _spawned(x: float) -> Node3D:
	var node := Node3D.new()
	world.spawn(node, UniversePos.new(x, 0.0, 0.0))
	return node


func _registry() -> ShiftableRegistry:
	return ShiftableRegistry.of_tree(get_tree())


func test_a_spawned_node_is_in_play_until_it_leaves_the_tree() -> void:
	var node: Node3D = _spawned(10.0)
	assert_true(_registry().in_play(world).has(node), "listed when it entered the tree")
	world.remove_child(node)
	assert_false(_registry().in_play(world).has(node), "dropped when it left")
	world.add_child(node)
	assert_true(_registry().in_play(world).has(node), "listed again when it came back")
	node.free()
	assert_false(_registry().in_play(world).has(node), "and dropped when freed")


func test_a_parked_node_leaves_the_list_and_the_rebase_until_it_is_back() -> void:
	var pooled: Node3D = _spawned(20.0)
	var tiered: Node3D = _spawned(30.0)
	ShiftableRegistry.set_out(pooled, WorldFrame.PARKED_META, true)
	ShiftableRegistry.set_out(tiered, TierDirector.TIER_META, true)
	var listed: Dictionary = _registry().in_play(world)
	assert_false(listed.has(pooled) or listed.has(tiered), "parked by its pool or the tier: out of play")
	world.rebase(Vector3(1000.0, 0.0, 0.0))
	assert_almost_eq(pooled.global_position.x, 20.0, TOL_M, "a rebase leaves the pool's parked node")
	assert_almost_eq(tiered.global_position.x, 30.0, TOL_M, "and the tier's")
	ShiftableRegistry.set_out(pooled, WorldFrame.PARKED_META, false)
	assert_false(pooled.has_meta(WorldFrame.PARKED_META))
	assert_true(_registry().in_play(world).has(pooled), "back in play")
	world.rebase(Vector3(-1000.0, 0.0, 0.0))
	assert_almost_eq(pooled.global_position.x, 1020.0, TOL_M, "and moved with the rest")
	assert_almost_eq(tiered.global_position.x, 30.0, TOL_M, "the tier's still waits for its promotion")


func test_a_node_that_joins_the_group_late_or_leaves_it_in_the_tree_is_found_by_the_count() -> void:
	var late := Node3D.new()
	world.add_child(late)
	late.position = Vector3(40.0, 0.0, 0.0)
	late.add_to_group(WorldFrame.SHIFTABLE_GROUP)  # after it entered the tree: no add signal names it
	var resyncs: int = _registry().resyncs
	world.rebase(Vector3(1000.0, 0.0, 0.0))
	assert_almost_eq(late.global_position.x, 40.0 - 1000.0, TOL_M, "the count check read the group again and moved it")
	assert_eq(_registry().resyncs, resyncs + 1, "once")
	late.remove_from_group(WorldFrame.SHIFTABLE_GROUP)
	world.rebase(Vector3(-1000.0, 0.0, 0.0))
	assert_almost_eq(late.global_position.x, 40.0 - 1000.0, TOL_M, "out of the group, out of the walk")
	var node: Node3D = _spawned(50.0)
	world.rebase(Vector3(500.0, 0.0, 0.0))
	assert_eq(_registry().resyncs, resyncs + 2, "a node that joins before it enters needs no read of the group")
	assert_almost_eq(node.global_position.x, -450.0, TOL_M)


func test_a_shiftable_node_outside_the_world_is_not_its_own() -> void:
	var stray := Node3D.new()
	stray.add_to_group(WorldFrame.SHIFTABLE_GROUP)
	add_child_autofree(stray)
	stray.position = Vector3(60.0, 0.0, 0.0)
	var ours: Node3D = _spawned(70.0)
	assert_true(_registry().in_play(world).has(ours))
	assert_false(_registry().in_play(world).has(stray), "outside every World: in no World's list")
	world.rebase(Vector3(1000.0, 0.0, 0.0))
	assert_almost_eq(stray.global_position.x, 60.0, TOL_M, "and a rebase leaves it")
	assert_almost_eq(ours.global_position.x, -930.0, TOL_M)
