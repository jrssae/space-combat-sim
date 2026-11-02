extends GutTest
## BenchLayout (M4-T01): where the benchmark's ships start, pure and seeded. `furball`: everyone in one fight within 5 km;
## `spread`: fights of about 12 (6 against 6, the setting's full squadron) 20 km apart; `transit`: wings of four on looped
## routes, no fight. Half allies, half raiders, in a frame where the player sits at the origin with its nose along -Z.

const SENSOR_M: float = ContactScan.SENSOR_RANGE_M


func _count(plan: Array[Dictionary], type: StringName) -> int:
	var n: int = 0
	for e: Dictionary in plan:
		n += 1 if StringName(e["type"]) == type else 0
	return n


func _groups(plan: Array[Dictionary]) -> Dictionary:
	var out: Dictionary = {}
	for e: Dictionary in plan:
		var g: int = int(e["group"])
		if not out.has(g):
			out[g] = [] as Array[Dictionary]
		(out[g] as Array[Dictionary]).append(e)
	return out


func test_every_layout_places_n_ships_half_allies_half_raiders() -> void:
	for layout: StringName in BenchLayout.NAMES:
		for n: int in [1, 25, 50, 101]:
			var plan: Array[Dictionary] = BenchLayout.plan(layout, n, 1)
			assert_eq(plan.size(), n, "%s %d" % [layout, n])
			var allies: int = _count(plan, ShipPool.ALLY_TYPE)
			var raiders: int = _count(plan, ShipPool.DEFAULT_TYPE)
			assert_eq(allies + raiders, n, "%s %d: only allies and raiders" % [layout, n])
			var slack: int = BenchLayout.WING_SIZE if layout == BenchLayout.TRANSIT else 1
			assert_lte(absi(allies - raiders), slack, "%s %d: half and half (%d allies, %d raiders)" % [layout, n, allies, raiders])


func test_ships_fly_the_ai_profile_of_their_side() -> void:
	for layout: StringName in BenchLayout.NAMES:
		for e: Dictionary in BenchLayout.plan(layout, 24, 3):
			var behaviour: Dictionary = e["behaviour"]
			assert_eq(String(behaviour["type"]), "ai")
			var wanted: String = "ally_starfury" if StringName(e["type"]) == ShipPool.ALLY_TYPE else "raider"
			assert_eq(String(behaviour["profile"]), wanted, "%s: profile by side" % layout)
			assert_true(bool(BrainFactory.from_behaviour(behaviour, UniversePos.new(), int(e["seed"]))["ok"]),
					"%s: the brain builds" % layout)


func test_a_plan_is_the_same_for_the_same_seed_and_differs_for_another() -> void:
	for layout: StringName in BenchLayout.NAMES:
		var a: Array[Dictionary] = BenchLayout.plan(layout, 40, 7)
		var b: Array[Dictionary] = BenchLayout.plan(layout, 40, 7)
		var c: Array[Dictionary] = BenchLayout.plan(layout, 40, 8)
		var same: bool = true
		var differs: bool = false
		for i: int in a.size():
			same = same and (a[i]["offset"] as Vector3) == (b[i]["offset"] as Vector3) and int(a[i]["seed"]) == int(b[i]["seed"])
			differs = differs or int(a[i]["seed"]) != int(c[i]["seed"])
		assert_true(same, "%s: same seed, same plan" % layout)
		assert_true(differs, "%s: another seed flies other pilots" % layout)


func test_unknown_layout_or_no_ships_places_nothing() -> void:
	assert_eq(BenchLayout.plan(&"parade", 10, 1).size(), 0)
	assert_eq(BenchLayout.plan(BenchLayout.FURBALL, 0, 1).size(), 0)
	assert_false(BenchLayout.is_layout(&"parade"))
	assert_true(BenchLayout.is_layout(&"spread"))


func test_furball_is_one_fight_inside_sensor_range_of_everyone() -> void:
	var plan: Array[Dictionary] = BenchLayout.plan(BenchLayout.FURBALL, 500, 1)
	var worst: float = 0.0
	var closest: float = INF
	for i: int in plan.size():
		var a: Vector3 = plan[i]["offset"]
		for j: int in range(i + 1, plan.size()):
			var d: float = a.distance_to(plan[j]["offset"] as Vector3)
			worst = maxf(worst, d)
			closest = minf(closest, d)
	assert_lt(worst, SENSOR_M, "every ship sees every other one (widest pair %.0f m)" % worst)
	assert_gte(closest, BenchLayout.MIN_SPACING_M, "no two ships start on top of each other (closest %.1f m)" % closest)
	assert_eq(_groups(plan).size(), 1, "one fight")
	assert_true(BenchLayout.fights(BenchLayout.FURBALL))


func test_furball_sides_face_each_other_ahead_of_the_player() -> void:
	for e: Dictionary in BenchLayout.plan(BenchLayout.FURBALL, 60, 2):
		var at: Vector3 = e["offset"]
		var nose: Vector3 = -(e["basis"] as Basis).z
		assert_lt(at.z, 0.0, "ahead of the player")
		if StringName(e["type"]) == ShipPool.ALLY_TYPE:
			assert_gt(at.z, -BenchLayout.FIGHT_AHEAD_M - 1e-3, "allies on the near side")
			assert_lt(nose.z, -0.99, "allies face the raiders")
		else:
			assert_lt(at.z, -BenchLayout.FIGHT_AHEAD_M + 1e-3, "raiders on the far side")
			assert_gt(nose.z, 0.99, "raiders face the allies")


func test_spread_is_squadron_sized_fights_far_apart() -> void:
	for n: int in [25, 100, 500]:
		var plan: Array[Dictionary] = BenchLayout.plan(BenchLayout.SPREAD, n, 1)
		var groups: Dictionary = _groups(plan)
		assert_eq(groups.size(), maxi(1, roundi(float(n) / float(BenchLayout.GROUP_SIZE))), "%d ships: groups" % n)
		for g: int in groups:
			var members: Array[Dictionary] = groups[g]
			assert_between(members.size(), BenchLayout.GROUP_SIZE - 1, BenchLayout.GROUP_SIZE + 1, "%d ships: group %d about 12" % [n, g])
			var allies: int = _count(members, ShipPool.ALLY_TYPE)
			assert_lte(absi(2 * allies - members.size()), 1, "%d ships: group %d half against half" % [n, g])
			for a: Dictionary in members:
				for b: Dictionary in members:
					assert_lt((a["offset"] as Vector3).distance_to(b["offset"] as Vector3), SENSOR_M, "a group is one fight")
		# Ships of different fights start out of each other's sensor range by a wide margin.
		var closest_apart: float = INF
		for i: int in plan.size():
			for j: int in range(i + 1, plan.size()):
				if int(plan[i]["group"]) != int(plan[j]["group"]):
					closest_apart = minf(closest_apart, (plan[i]["offset"] as Vector3).distance_to(plan[j]["offset"] as Vector3))
		if groups.size() > 1:
			assert_gt(closest_apart, 3.0 * SENSOR_M, "%d ships: fights are apart (closest %.0f m)" % [n, closest_apart])


func test_spread_group_centres_are_twenty_km_apart() -> void:
	var centres: Array[Vector3] = BenchLayout.group_centres(8)
	assert_eq(centres.size(), 8)
	assert_eq(centres[0], Vector3(0.0, 0.0, -BenchLayout.FIGHT_AHEAD_M), "the first fight is just ahead of the player")
	for i: int in centres.size():
		var nearest: float = INF
		for j: int in centres.size():
			if i != j:
				nearest = minf(nearest, centres[i].distance_to(centres[j]))
		assert_almost_eq(nearest, BenchLayout.GROUP_SPACING_M, 1e-3, "centre %d" % i)
	assert_eq(BenchLayout.GROUP_SPACING_M, 20000.0)


func test_transit_is_wings_of_four_on_routes_with_no_fight() -> void:
	var plan: Array[Dictionary] = BenchLayout.plan(BenchLayout.TRANSIT, 26, 1)
	assert_false(BenchLayout.fights(BenchLayout.TRANSIT), "transit is no fight")
	var wings: Dictionary = {}
	for e: Dictionary in plan:
		var wing: String = String(e["wing"])
		assert_false(wing.is_empty(), "every transit ship is in a wing")
		if not wings.has(wing):
			wings[wing] = [] as Array[Dictionary]
		(wings[wing] as Array[Dictionary]).append(e)
	assert_eq(wings.size(), 7, "26 ships: six wings of four and one of two")
	for wing: String in wings:
		var members: Array[Dictionary] = wings[wing]
		assert_lte(members.size(), BenchLayout.WING_SIZE)
		var leader: Dictionary = members[0]
		assert_true(bool(leader["leader"]), "%s: the first is its leader" % wing)
		var route: Array = ((leader["behaviour"] as Dictionary)["patrol"] as Dictionary)["waypoints"]
		assert_gte(route.size(), 2, "%s: the leader flies a route" % wing)
		var nose: Vector3 = -(leader["basis"] as Basis).z
		assert_almost_eq((leader["velocity"] as Vector3).length(), BenchLayout.CRUISE_MPS, 1e-3, "%s: cruising" % wing)
		assert_almost_eq((leader["velocity"] as Vector3).normalized().dot(nose), 1.0, 1e-6, "%s: along its nose" % wing)
		var slots := Formation.new()
		for k: int in range(1, members.size()):
			var m: Dictionary = members[k]
			assert_false(bool(m["leader"]))
			assert_eq(StringName(m["type"]), StringName(leader["type"]), "%s: one side per wing" % wing)
			assert_false((m["behaviour"] as Dictionary).has("patrol"), "members follow the leader, not a route")
			var expected: Vector3 = (leader["offset"] as Vector3) + (leader["basis"] as Basis) * slots.offset(k)
			assert_almost_eq((m["offset"] as Vector3).distance_to(expected), 0.0, 1e-3, "%s: member %d in its finger-four slot" % [wing, k])
			assert_eq(m["velocity"] as Vector3, leader["velocity"] as Vector3, "%s: member %d flies with the leader" % [wing, k])


func test_transit_wings_start_beyond_each_others_sensor_range() -> void:
	var plan: Array[Dictionary] = BenchLayout.plan(BenchLayout.TRANSIT, 100, 1)
	var leaders: Array[Vector3] = []
	for e: Dictionary in plan:
		if bool(e["leader"]):
			leaders.append(e["offset"])
	var closest: float = INF
	for i: int in leaders.size():
		for j: int in range(i + 1, leaders.size()):
			closest = minf(closest, leaders[i].distance_to(leaders[j]))
	assert_gt(closest, SENSOR_M, "wing leaders start out of each other's sensor range (closest %.0f m)" % closest)
