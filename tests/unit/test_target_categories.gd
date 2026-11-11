extends GutTest
## TargetCategories, pure (M5-T25): identification, the six categories, nearest-five ordering and the target button's tap, on
## hand-built cases and on seeded sets of 500 checked against an independent sort.

const C := TargetCategories.Category
const OWN: StringName = Factions.EARTH_ALLIANCE
const SEEDS: Array[int] = [1, 7, 20261111]


func after_all() -> void:
	Factions.reset()


func _info(id: int, position: Vector3, faction: StringName = Factions.RAIDERS, role: int = Targetable.Role.SHIP,
		broadcast_m: float = 0.0) -> TargetInfo:
	var info := TargetInfo.new(id, "T%d" % id, faction, position)
	info.role = role
	info.broadcast_range_m = broadcast_m
	return info


# 500 candidates around `centre`, to 24 km: raiders and neutral ships silent, allies, civilians and buoys broadcasting.
func _seeded(rng_seed: int, centre: Vector3) -> Array[TargetInfo]:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var out: Array[TargetInfo] = []
	for i: int in 500:
		var at: Vector3 = centre + Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized() \
				* rng.randf_range(50.0, 24000.0)
		var kind: int = rng.randi_range(0, 9)
		if kind < 5:
			out.append(_info(i + 1, at, Factions.RAIDERS))
		elif kind < 7:
			out.append(_info(i + 1, at, Factions.EARTH_ALLIANCE, Targetable.Role.SHIP, 1.0e5))
		elif kind == 7:
			out.append(_info(i + 1, at, [&"narn", &"centauri", Factions.EARTH_ALLIANCE][rng.randi_range(0, 2)], Targetable.Role.CIVILIAN, 15000.0))
		elif kind == 8:
			out.append(_info(i + 1, at, Factions.NEUTRAL, Targetable.Role.BEACON, 1.0e6))
		else:
			out.append(_info(i + 1, at, &"narn"))
	return out


# The category by the rules as written, independent of the class.
func _expected(info: TargetInfo, own: Vector3) -> C:
	if info.position.distance_to(own) > 5000.0 and info.broadcast_range_m <= 0.0:
		return C.UNKNOWN
	if info.role == Targetable.Role.BEACON:
		return C.NAVIGATION
	if info.faction == Factions.RAIDERS:
		return C.ENEMIES
	if info.role == Targetable.Role.CIVILIAN or info.faction != OWN:
		return C.CIVILIAN
	return C.ALLIES


func _ids(list: Array[TargetInfo]) -> Array[int]:
	var out: Array[int] = []
	for info: TargetInfo in list:
		out.append(info.id)
	return out


func test_identified_within_five_km_or_when_broadcasting() -> void:
	assert_eq(TargetCategories.IDENT_RANGE_M, ContactScan.SENSOR_RANGE_M, "the identification range is the AI's sensor range")
	assert_true(TargetCategories.is_identified(5000.0, 0.0))
	assert_false(TargetCategories.is_identified(5000.5, 0.0))
	assert_true(TargetCategories.is_identified(20000.0, 15000.0), "a transponder identifies at any range")
	assert_true(TargetCategories.is_identified(9.0e5, INF))


func test_each_kind_of_contact_falls_in_its_category() -> void:
	var own := Vector3(100.0, 0.0, 0.0)
	var near := own + Vector3(0.0, 0.0, -2000.0)
	var far := own + Vector3(0.0, 0.0, -9000.0)
	assert_eq(TargetCategories.category_of(_info(1, near), own, OWN), C.ENEMIES)
	assert_eq(TargetCategories.category_of(_info(1, far), own, OWN), C.UNKNOWN, "a raider beyond 5 km is unknown")
	assert_eq(TargetCategories.category_of(_info(1, far, OWN, Targetable.Role.SHIP, 1.0e5), own, OWN), C.ALLIES)
	assert_eq(TargetCategories.category_of(_info(1, near, OWN), own, OWN), C.ALLIES, "a silent friend is known up close")
	assert_eq(TargetCategories.category_of(_info(1, far, OWN), own, OWN), C.UNKNOWN, "and unknown far off")
	assert_eq(TargetCategories.category_of(_info(1, far, OWN, Targetable.Role.CIVILIAN, 15000.0), own, OWN), C.CIVILIAN,
			"a civilian of the pilot's own people is a civilian, not an ally")
	assert_eq(TargetCategories.category_of(_info(1, far, &"narn", Targetable.Role.CIVILIAN, 15000.0), own, OWN), C.CIVILIAN)
	assert_eq(TargetCategories.category_of(_info(1, near, &"narn"), own, OWN), C.CIVILIAN, "a neutral people's ship is not an ally")
	assert_eq(TargetCategories.category_of(_info(1, far, Factions.NEUTRAL, Targetable.Role.BEACON, 1.0e6), own, OWN), C.NAVIGATION)
	assert_eq(TargetCategories.category_of(_info(1, near, Factions.RAIDERS, Targetable.Role.CIVILIAN, 15000.0), own, OWN), C.ENEMIES,
			"a hostile civilian is an enemy first")
	assert_eq(TargetCategories.category_of(_info(1, near, OWN), own, Factions.RAIDERS), C.ENEMIES, "seen from the other side")


func test_five_hundred_candidates_sort_into_categories_nearest_first() -> void:
	for rng_seed: int in SEEDS:
		var own := Vector3(300.0, -200.0, 50.0)
		var candidates: Array[TargetInfo] = _seeded(rng_seed, own)
		var sorted: Dictionary = TargetCategories.sort_all(candidates, own, OWN)
		var total: int = 0
		for category: C in TargetCategories.ORDER:
			var expected: Array[TargetInfo] = candidates.filter(func(info: TargetInfo) -> bool: return _expected(info, own) == category)
			expected.sort_custom(func(a: TargetInfo, b: TargetInfo) -> bool:
				var ra: float = TargetingSystem.range_between(own, a.position)
				var rb: float = TargetingSystem.range_between(own, b.position)
				return ra < rb or (ra == rb and a.id < b.id))
			var got: Array[TargetInfo] = sorted[category]
			assert_eq(_ids(got), _ids(expected), "seed %d, %s" % [rng_seed, TargetCategories.NAMES[category]])
			assert_eq(_ids(TargetCategories.nearest(candidates, category, own, OWN)), _ids(expected).slice(0, 5),
					"seed %d, %s: the nearest five" % [rng_seed, TargetCategories.NAMES[category]])
			total += got.size()
		var summary: Dictionary = TargetCategories.summarise(candidates, own, OWN)
		for category: C in TargetCategories.ORDER:
			assert_eq(int(summary["counts"][category]), (sorted[category] as Array).size(), "seed %d: the one-pass count" % rng_seed)
		assert_eq(total, 500, "seed %d: every candidate is in exactly one category" % rng_seed)
		assert_eq((sorted[C.OBJECTIVES] as Array).size(), 0, "objectives come from the mission, not the candidates")
		assert_gt((sorted[C.ENEMIES] as Array).size(), 5, "seed %d: enough enemies to cut to five" % rng_seed)
		assert_gt((sorted[C.UNKNOWN] as Array).size(), 5)


func test_nearest_takes_a_limit_and_breaks_ties_by_id() -> void:
	var at := Vector3(0.0, 0.0, -1000.0)
	var candidates: Array[TargetInfo] = [_info(9, at), _info(3, at), _info(5, Vector3(0.0, 0.0, -500.0)), _info(4, at)]
	assert_eq(_ids(TargetCategories.nearest(candidates, C.ENEMIES, Vector3.ZERO, OWN)), [5, 3, 4, 9] as Array[int])
	assert_eq(_ids(TargetCategories.nearest(candidates, C.ENEMIES, Vector3.ZERO, OWN, 2)), [5, 3] as Array[int])
	assert_eq(TargetCategories.nearest(candidates, C.ALLIES, Vector3.ZERO, OWN).size(), 0)
	assert_eq(TargetCategories.nearest([] as Array[TargetInfo], C.ENEMIES, Vector3.ZERO, OWN).size(), 0)


func test_a_tap_toggles_between_the_nearest_and_the_second_nearest_enemy() -> void:
	for rng_seed: int in SEEDS:
		var own := Vector3(-40.0, 10.0, 900.0)
		var candidates: Array[TargetInfo] = _seeded(rng_seed, own)
		var enemies: Array[int] = _ids(TargetCategories.nearest(candidates, C.ENEMIES, own, OWN, 3))
		assert_eq(TargetCategories.tap_pick(candidates, own, OWN, TargetingSystem.NO_TARGET), enemies[0], "the first tap: the nearest")
		assert_eq(TargetCategories.tap_pick(candidates, own, OWN, enemies[0]), enemies[1], "a tap on the nearest: the 2nd nearest")
		assert_eq(TargetCategories.tap_pick(candidates, own, OWN, enemies[1]), enemies[0], "the next tap: back to the nearest")
		assert_eq(TargetCategories.tap_pick(candidates, own, OWN, enemies[2]), enemies[0], "from any other target: the nearest")


func test_a_tap_with_one_enemy_none_or_only_unknowns() -> void:
	var one: Array[TargetInfo] = [_info(1, Vector3(0.0, 0.0, -800.0)), _info(2, Vector3(0.0, 0.0, -300.0), OWN)]
	assert_eq(TargetCategories.tap_pick(one, Vector3.ZERO, OWN, 0), 1)
	assert_eq(TargetCategories.tap_pick(one, Vector3.ZERO, OWN, 1), 1, "one enemy: the tap keeps it")
	var none: Array[TargetInfo] = [_info(2, Vector3(0.0, 0.0, -300.0), OWN)]
	assert_eq(TargetCategories.tap_pick(none, Vector3.ZERO, OWN, 0), TargetingSystem.NO_TARGET, "allies are never the tap's pick")
	# Nothing identified as hostile: the unknown contacts stand in, nearest and 2nd nearest.
	var far: Array[TargetInfo] = [_info(7, Vector3(0.0, 0.0, -9000.0)), _info(8, Vector3(0.0, 0.0, -7000.0)),
			_info(2, Vector3(0.0, 0.0, -300.0), OWN)]
	assert_eq(TargetCategories.tap_pick(far, Vector3.ZERO, OWN, 0), 8)
	assert_eq(TargetCategories.tap_pick(far, Vector3.ZERO, OWN, 8), 7)
	far.append(_info(9, Vector3(0.0, 0.0, -4000.0)))
	assert_eq(TargetCategories.tap_pick(far, Vector3.ZERO, OWN, 8), 9, "an identified enemy comes before any unknown")
