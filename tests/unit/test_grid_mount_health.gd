extends GutTest
## The grid mounts' own health (M7-T07 fix): a hit within a mount's radius on its own body wears it down, at zero it is out, a
## repair makes it whole.

func _health() -> GridMountHealth:
	var entries: Array[Dictionary] = [
		{"name": "L1", "kind": "light_pulse", "body": "drum", "position": Vector3(0.0, 300.0, 0.0)},
		{"name": "H1", "kind": "heavy_cannon", "body": "frame", "position": Vector3(0.0, 300.0, 0.0)},
		{"name": "I1", "kind": "interceptor", "body": "frame", "position": Vector3(100.0, 300.0, 0.0)},
	]
	return GridMountHealth.from_mounts(entries, func(k: String) -> int: return StationGrid.KIND_OF.get(k, 1))


func test_a_hit_wears_down_only_a_mount_near_it_on_its_body() -> void:
	var h: GridMountHealth = _health()
	assert_eq(h.max_health, PackedFloat64Array([300.0, 4000.0, 200.0]), "health per kind")
	h.hit("frame", Vector3(0.0, 290.0, 10.0), 50.0)
	assert_eq(h.health[0], 300.0, "the drum's mount is on another body")
	assert_eq(h.health[1], 3950.0, "the heavy cannon within its 45 m")
	assert_eq(h.health[2], 200.0, "the interceptor 100 m off is out of its 25 m")


func test_at_zero_a_mount_is_out_once_and_a_repair_makes_it_whole() -> void:
	var h: GridMountHealth = _health()
	var lost: PackedInt32Array = h.hit("frame", Vector3(100.0, 300.0, 0.0), 150.0)
	assert_eq(lost.size(), 0)
	lost = h.hit("frame", Vector3(100.0, 300.0, 0.0), 150.0)
	assert_eq(lost, PackedInt32Array([2]), "knocked out by this hit")
	assert_true(h.is_out(2))
	assert_eq(h.hit("frame", Vector3(100.0, 300.0, 0.0), 150.0).size(), 0, "said once")
	assert_eq(h.out_count(), 1)
	assert_true(h.repair(2), "it was out")
	assert_false(h.is_out(2))
	assert_eq(h.health[2], 200.0)
	assert_false(h.repair(2), "a whole mount needs no repair")


func test_only_the_nearest_mount_in_reach_takes_a_hit() -> void:
	var h: GridMountHealth = GridMountHealth.from_mounts([
		{"name": "A", "kind": "heavy_cannon", "body": "frame", "position": Vector3(0.0, 0.0, 0.0)},
		{"name": "B", "kind": "heavy_cannon", "body": "frame", "position": Vector3(30.0, 0.0, 0.0)},
	] as Array[Dictionary], func(k: String) -> int: return StationGrid.KIND_OF.get(k, 1))
	assert_eq(h.nearest("frame", Vector3(20.0, 0.0, 0.0)), 1, "both in reach: the nearer")
	h.hit("frame", Vector3(20.0, 0.0, 0.0), 100.0)
	assert_eq(h.health[0], 4000.0, "only the part hit takes it (M10-T65, Q72)")
	assert_eq(h.health[1], 3900.0)
	assert_eq(h.nearest("frame", Vector3(200.0, 0.0, 0.0)), -1, "none in reach")
