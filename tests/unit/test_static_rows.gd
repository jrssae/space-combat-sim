extends GutTest
## The store of rows with no node (M4-T29, architecture §17.16): rocks by RID and mines, registered once, moved only by their
## own world's rebase, and read by the contact scan, the hit resolver and the ram resolver without a walk a tick. The solid
## rows (rocks: bolts hit them, ships ram them) are kept apart from the mines and rebuilt only when a solid row changes.

var _a: WorldFrame
var _b: WorldFrame


func before_each() -> void:
	StaticRows.clear()
	_a = WorldFrame.new()
	add_child_autofree(_a)
	_b = autofree(WorldFrame.new())  # out of the tree: it only owns rows (one world per tree, M4-T42)


func after_each() -> void:
	StaticRows.clear()


func test_rows_are_registered_once_and_removed_by_id() -> void:
	var before: int = StaticRows.registrations
	StaticRows.register(101, Vector3(1, 2, 3), 50.0, BodyKind.STATIC, Factions.NEUTRAL, _a)
	StaticRows.register(102, Vector3(4, 5, 6), 50.0, BodyKind.MINE, Factions.RAIDERS, _a)
	StaticRows.register(103, Vector3(7, 8, 9), 70.0)
	assert_eq(StaticRows.registrations - before, 3, "each registration counted once")
	assert_eq(StaticRows.count(), 3)
	assert_true(StaticRows.has(102))
	assert_eq(StaticRows.position_of(102), Vector3(4, 5, 6))
	assert_true(StaticRows.unregister(102), "a known row is removed")
	assert_false(StaticRows.unregister(102), "and only once")
	assert_false(StaticRows.has(102))
	assert_eq(StaticRows.ids, PackedInt64Array([101, 103]), "the others keep their order")
	StaticRows.unregister_many(PackedInt64Array([103, 999, 101]))
	assert_eq(StaticRows.count(), 0, "many at once, unknown ids ignored")


func test_a_shift_moves_only_its_own_worlds_rows_once() -> void:
	StaticRows.register(201, Vector3(100, 0, 0), 10.0, BodyKind.STATIC, Factions.NEUTRAL, _a)
	StaticRows.register(202, Vector3(200, 0, 0), 10.0, BodyKind.MINE, Factions.RAIDERS, _b)
	StaticRows.register(203, Vector3(300, 0, 0), 10.0)
	StaticRows.shift(Vector3(-10, 5, 0), _a)
	assert_eq(StaticRows.position_of(201), Vector3(90, 5, 0), "world A's row moved")
	assert_eq(StaticRows.position_of(202), Vector3(200, 0, 0), "world B's did not")
	assert_eq(StaticRows.position_of(203), Vector3(300, 0, 0), "nor a row with no world")


func test_the_solid_rows_are_the_rocks_and_are_rebuilt_only_when_a_rock_changes() -> void:
	StaticRows.register(301, Vector3(1, 0, 0), 40.0, BodyKind.STATIC, Factions.NEUTRAL, _a)
	StaticRows.register(302, Vector3(2, 0, 0), 50.0, BodyKind.MINE, Factions.RAIDERS, _a)
	StaticRows.register(303, Vector3(3, 0, 0), 60.0, BodyKind.STATIC, Factions.NEUTRAL, _a)
	var solid: StaticRows.Solid = StaticRows.solid()
	assert_eq(solid.ids, PackedInt64Array([301, 303]), "only the rocks are solid")
	assert_eq(solid.positions, PackedVector3Array([Vector3(1, 0, 0), Vector3(3, 0, 0)]))
	assert_eq(solid.radii, PackedFloat64Array([40.0, 60.0]))
	var builds: int = StaticRows.solid_builds
	for tick: int in 10:
		StaticRows.solid()
	assert_eq(StaticRows.solid_builds, builds, "read every tick, built once")
	var version: int = StaticRows.version
	StaticRows.unregister(302)
	StaticRows.register(302, Vector3(2, 0, 0), 50.0, BodyKind.MINE, Factions.RAIDERS, _a)
	assert_gt(StaticRows.version, version, "a mine coming and going changes the rows")
	assert_true(StaticRows.solid() == solid and StaticRows.solid_builds == builds, "but not the solid ones")
	StaticRows.shift(Vector3(10, 0, 0), _a)
	assert_eq(StaticRows.solid().positions, PackedVector3Array([Vector3(11, 0, 0), Vector3(13, 0, 0)]), "a rebase moves them")
	assert_eq(StaticRows.solid_builds, builds + 1, "built again once")


func test_new_ids_are_unique() -> void:
	var seen: Dictionary = {}
	for i: int in 1000:
		var id: int = StaticRows.new_id()
		assert_false(seen.has(id), "id %d handed out twice" % id)
		seen[id] = true
		if seen.size() < i + 1:
			break
	assert_eq(seen.size(), 1000)
