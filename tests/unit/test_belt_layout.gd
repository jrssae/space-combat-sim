extends GutTest
## `BeltLayout` (M5-T29, D63): a belt's rocks scattered through its box, seeded and deterministic, every rock inside, no two
## closer than the gap, small rocks far more common than large ones, and a count that cannot fit said rather than hidden.


func _belt(overrides: Dictionary = {}) -> Dictionary:
	var belt: Dictionary = {"size": Vector3(4000.0, 800.0, 3000.0), "count": 300, "radius_m": Vector2(5.0, 120.0), "seed": 7,
			"min_gap_m": 60.0}
	belt.merge(overrides, true)
	return belt


func test_the_same_seed_places_the_same_rocks_and_another_seed_does_not() -> void:
	var a: BeltLayout = BeltLayout.place(_belt(), 16)
	var b: BeltLayout = BeltLayout.place(_belt(), 16)
	var c: BeltLayout = BeltLayout.place(_belt({"seed": 8}), 16)
	assert_eq(a.rocks.size(), b.rocks.size())
	assert_eq(var_to_bytes(a.rocks), var_to_bytes(b.rocks), "byte for byte")
	assert_ne(var_to_bytes(a.rocks), var_to_bytes(c.rocks))


func test_every_rock_lies_inside_the_box() -> void:
	var layout: BeltLayout = BeltLayout.place(_belt(), 16)
	var half: Vector3 = 0.5 * Vector3(4000.0, 800.0, 3000.0)
	for rock: Dictionary in layout.rocks:
		var at: Vector3 = rock["offset"]
		var r: float = rock["radius"]
		assert_true(absf(at.x) + r <= half.x + 1e-3 and absf(at.y) + r <= half.y + 1e-3 and absf(at.z) + r <= half.z + 1e-3,
				"rock at %s, radius %.1f, is inside" % [at, r])


func test_no_two_rocks_are_closer_than_the_gap() -> void:
	var layout: BeltLayout = BeltLayout.place(_belt(), 16)
	var rocks: Array[Dictionary] = layout.rocks
	var worst: float = INF
	for i: int in rocks.size():
		for j: int in range(i + 1, rocks.size()):
			var clear: float = (rocks[i]["offset"] as Vector3).distance_to(rocks[j]["offset"]) - float(rocks[i]["radius"]) \
					- float(rocks[j]["radius"])
			worst = minf(worst, clear)
	assert_gte(worst, 60.0 - 1e-3, "the closest pair keeps the gap (%.1f m)" % worst)


func test_small_rocks_outnumber_large_ones_and_sizes_stay_in_range() -> void:
	var layout: BeltLayout = BeltLayout.place(_belt(), 16)
	var small: int = 0
	var large: int = 0
	for rock: Dictionary in layout.rocks:
		var r: float = rock["radius"]
		assert_between(r, 5.0, 120.0)
		if r < 20.0:
			small += 1
		elif r > 60.0:
			large += 1
	assert_gt(small, 3 * large, "%d small, %d large" % [small, large])


func test_shapes_and_turns_vary() -> void:
	var layout: BeltLayout = BeltLayout.place(_belt(), 16)
	var shapes: Dictionary = {}
	for rock: Dictionary in layout.rocks:
		shapes[rock["shape"]] = true
		assert_between(int(rock["shape"]), 0, 15)
		assert_true((rock["basis"] as Basis).is_conformal(), "a pure turn")
	assert_eq(shapes.size(), 16, "every shape is used")


func test_a_count_that_cannot_fit_places_what_fits_and_says_so() -> void:
	var layout: BeltLayout = BeltLayout.place(_belt({"size": Vector3(600.0, 300.0, 600.0), "count": 500}), 16)
	assert_lt(layout.rocks.size(), 500)
	assert_eq(layout.shortfall, 500 - layout.rocks.size())
	assert_gt(layout.rocks.size(), 0)


func test_the_mean_gap_is_a_few_hundred_metres_for_the_escort_belt() -> void:
	# D63: 8 km deep, 24 km across, 3 km high, a few hundred rocks of 5 to 150 m.
	var layout: BeltLayout = BeltLayout.place({"size": Vector3(24000.0, 3000.0, 8000.0), "count": 360,
			"radius_m": Vector2(5.0, 150.0), "seed": 1, "min_gap_m": 250.0}, 16)
	assert_eq(layout.shortfall, 0, "all fit")
	var per_rock: float = 24000.0 * 3000.0 * 8000.0 / float(layout.rocks.size())
	var spacing: float = pow(per_rock, 1.0 / 3.0)
	assert_between(spacing, 800.0, 1600.0, "mean spacing %.0f m" % spacing)
