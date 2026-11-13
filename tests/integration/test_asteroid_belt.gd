extends GutTest
## `AsteroidBelt` (M5-T29, D63): the generated rocks placed by a layout, drawn by a few multimeshes, each rock's spheres static
## rows and bodies by RID; a rebase moves the rows and the bodies with the belt; leaving the tree releases them all.

var world: WorldFrame


func before_each() -> void:
	StaticRows.clear()
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)


func after_each() -> void:
	StaticRows.clear()


func _layout() -> BeltLayout:
	return BeltLayout.place({"size": Vector3(3000.0, 600.0, 3000.0), "count": 40, "radius_m": Vector2(8.0, 90.0), "seed": 3,
			"min_gap_m": 80.0}, maxi(AsteroidBelt.shapes().size(), 1))


func _belt(at: Vector3 = Vector3(0.0, 0.0, -5000.0)) -> AsteroidBelt:
	var belt := AsteroidBelt.new()
	belt.name = "Belt"
	world.spawn(belt, world.to_universe(at))
	belt.build(_layout(), world.get_world_3d().space, world)
	world.rebased.connect(belt.on_rebased)
	return belt


func _skipped() -> bool:
	if AsteroidBelt.shapes().is_empty():
		pending("the asteroids are not generated (scripts/gen_assets.sh)")
		return true
	return false


func test_every_rock_is_drawn_and_its_spheres_are_rows() -> void:
	if _skipped():
		return
	var belt: AsteroidBelt = _belt()
	assert_eq(belt.rock_count, _layout().rocks.size())
	assert_gte(belt.sphere_count, belt.rock_count, "one sphere a rock at least")
	assert_eq(StaticRows.count(), belt.sphere_count, "each sphere a static row")
	var drawn: int = 0
	for child: Node in belt.get_children():
		if child is MultiMeshInstance3D:
			drawn += (child as MultiMeshInstance3D).multimesh.instance_count
	assert_eq(drawn, belt.rock_count, "every rock drawn once")
	assert_lte(belt.draw_groups, AsteroidBelt.shapes().size(), "a multimesh per shape, not per rock")


func test_a_rebase_moves_the_rows_and_the_bodies_with_the_belt() -> void:
	if _skipped():
		return
	var belt: AsteroidBelt = _belt()
	var id: int = StaticRows.ids[0]
	var before: Vector3 = StaticRows.position_of(id)
	# No ship near, so the spheres are rows only: a body comes to life where `placed` says (M6-T21, `test_rock_bodies`).
	var body_before: Vector3 = belt.rock_bodies().placed(0, belt.global_transform).origin
	world.rebase(Vector3(0.0, 0.0, -4000.0))
	assert_almost_eq(StaticRows.position_of(id), before + Vector3(0.0, 0.0, 4000.0), Vector3.ONE * 1e-2, "the row moved")
	var body_after: Vector3 = belt.rock_bodies().placed(0, belt.global_transform).origin
	assert_almost_eq(body_after, body_before + Vector3(0.0, 0.0, 4000.0), Vector3.ONE * 1e-2, "the body moved")
	assert_almost_eq(body_after, StaticRows.position_of(id), Vector3.ONE * 1e-2, "and they agree")


func test_leaving_the_tree_releases_every_row() -> void:
	if _skipped():
		return
	var belt: AsteroidBelt = _belt()
	assert_gt(StaticRows.count(), 0)
	belt.get_parent().remove_child(belt)
	belt.free()
	assert_eq(StaticRows.count(), 0)


func test_without_generated_shapes_it_builds_nothing_and_says_so() -> void:
	var belt := AsteroidBelt.new()
	world.spawn(belt, world.to_universe(Vector3.ZERO))
	belt.build(_layout(), world.get_world_3d().space, world, [])
	assert_eq(belt.rock_count, 0)
	assert_eq(StaticRows.count(), 0)
