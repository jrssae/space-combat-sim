extends GutTest
## Where a minefield's mines lie from the data a scenario or a mission gives (M10-T15, Q20): every pattern, the seed, the gap and
## what is refused.


func _entry(pattern: String, extra: Dictionary = {}) -> Dictionary:
	var entry: Dictionary = {"id": "t", "faction": "narn", "pattern": pattern, "count": 60, "seed": 5}
	entry.merge(extra, true)
	return entry


func test_a_box_field_holds_its_count_inside_its_box_and_is_seeded() -> void:
	var entry: Dictionary = _entry("box", {"size": [2000, 600, 1000], "centre": [100, 0, 0]})
	var plan: MineFieldPlan = MineFieldPlan.place(entry)
	assert_eq(plan.rows.size(), 60)
	for row: Dictionary in plan.rows:
		var at: Vector3 = row["offset"] - Vector3(100.0, 0.0, 0.0)
		assert_true(absf(at.x) <= 1000.0 and absf(at.y) <= 300.0 and absf(at.z) <= 500.0, "inside the box: %s" % at)
		assert_eq([row["faction"], row["kind"]], [&"narn", &"mine_prox"])
	assert_eq(MineFieldPlan.place(entry).rows, plan.rows, "the same entry gives the same field")
	entry["seed"] = 6
	assert_ne(MineFieldPlan.place(entry).rows, plan.rows, "another seed another field")


func test_the_round_patterns_lie_where_they_say() -> void:
	for row: Dictionary in MineFieldPlan.place(_entry("sphere", {"radius_m": 500})).rows:
		assert_lte((row["offset"] as Vector3).length(), 500.001)
	for row: Dictionary in MineFieldPlan.place(_entry("shell", {"radius_m": 800, "thickness_m": 100})).rows:
		assert_between((row["offset"] as Vector3).length(), 749.9, 850.1, "on the skin")
	var ring: MineFieldPlan = MineFieldPlan.place(_entry("ring", {"radius_m": 1000, "width_m": 200, "thickness_m": 40, "axis": [0, 0, 1]}))
	for row: Dictionary in ring.rows:
		var at: Vector3 = row["offset"]
		assert_lte(absf(at.z), 20.001, "flat about its axis")
		assert_between(Vector2(at.x, at.y).length(), 899.9, 1100.1, "in the ring")


func test_a_line_is_evenly_spaced_and_points_are_taken_as_given() -> void:
	var line: MineFieldPlan = MineFieldPlan.place(_entry("line", {"from": [0, 0, 0], "to": [900, 0, 0], "count": 4}))
	assert_eq(line.rows.map(func(r: Dictionary) -> Vector3: return r["offset"]), [Vector3.ZERO, Vector3(300, 0, 0), Vector3(600, 0, 0), Vector3(900, 0, 0)])
	var points: MineFieldPlan = MineFieldPlan.place(_entry("points", {"points": [[1, 2, 3], [4, 5, 6]], "centre": [10, 0, 0], "kind": "mine_energy"}))
	assert_eq(points.rows.size(), 2)
	assert_eq(points.rows[1]["offset"], Vector3(14.0, 5.0, 6.0))
	assert_eq(points.rows[1]["kind"], &"mine_energy")


func test_a_gap_keeps_random_mines_apart_and_counts_what_found_no_room() -> void:
	var plan: MineFieldPlan = MineFieldPlan.place(_entry("box", {"size": [400, 400, 400], "count": 80, "min_gap_m": 100}))
	for i: int in plan.rows.size():
		for j: int in range(i + 1, plan.rows.size()):
			assert_gte((plan.rows[i]["offset"] as Vector3).distance_to(plan.rows[j]["offset"]), 99.99)
	assert_eq(plan.rows.size() + plan.shortfall, 80, "every mine is laid or counted")
	assert_gt(plan.shortfall, 0, "80 mines 100 m apart do not fit a 400 m cube")


func test_a_field_with_a_problem_says_so_and_lays_nothing() -> void:
	assert_ne(MineFieldPlan.problem({"faction": "narn", "pattern": "cone"}), "")
	assert_ne(MineFieldPlan.problem({"pattern": "box", "size": [1, 1, 1], "count": 3}), "", "no faction")
	assert_ne(MineFieldPlan.problem(_entry("box", {"size": [1, 0, 1]})), "", "a flat box")
	assert_ne(MineFieldPlan.problem(_entry("sphere", {"count": 0, "radius_m": 3})), "")
	assert_ne(MineFieldPlan.problem(_entry("box", {"size": [1, 1, 1], "kind": "mine_spiky"})), "")
	assert_ne(MineFieldPlan.problem(_entry("line", {"from": [0, 0, 0]})), "")
	assert_eq(MineFieldPlan.problem(_entry("sphere", {"radius_m": 3})), "")
	assert_eq(MineFieldPlan.place({"faction": "narn", "pattern": "cone"}).rows.size(), 0)
