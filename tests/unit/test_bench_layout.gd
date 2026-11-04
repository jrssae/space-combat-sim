extends GutTest
## BenchLayout (M4-T01): where the benchmark's ships start, pure and seeded. `furball`: everyone in one fight within 5 km;
## `spread`: fights of about 12 (6 against 6, the setting's full squadron) 20 km apart; `transit`: wings of four on looped
## routes, no fight. Half allies, half raiders, in a frame where the player sits at the origin with its nose along -Z.
## `battle` and `typical` (M4-T07): fights of 24 on an 8 km lattice with capital stand-ins behind each side, the mix
## `BattleMix` states, an asteroid slab and a gravity source; four sides every pair hostile, or two.

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
	for layout: StringName in BenchLayout.FIGHTER_LAYOUTS:
		for n: int in [1, 25, 50, 101]:
			var plan: Array[Dictionary] = BenchLayout.plan(layout, n, 1)
			assert_eq(plan.size(), n, "%s %d" % [layout, n])
			var allies: int = _count(plan, ShipPool.ALLY_TYPE)
			var raiders: int = _count(plan, ShipPool.DEFAULT_TYPE)
			assert_eq(allies + raiders, n, "%s %d: only allies and raiders" % [layout, n])
			var slack: int = BenchLayout.WING_SIZE if layout == BenchLayout.TRANSIT else 1
			assert_lte(absi(allies - raiders), slack, "%s %d: half and half (%d allies, %d raiders)" % [layout, n, allies, raiders])


func test_ships_fly_the_ai_profile_of_their_side() -> void:
	for layout: StringName in BenchLayout.FIGHTER_LAYOUTS:
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


# --- battle and typical (M4-T07) -------------------------------------------------------------------------------


func _of_kind(plan: Array[Dictionary], kind: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in plan:
		if StringName(e["kind"]) == kind:
			out.append(e)
	return out


# The fight centres a plan's fighters gather around, by group.
func _fight_centres(plan: Array[Dictionary]) -> Dictionary:
	var out: Dictionary = {}
	for e: Dictionary in plan:
		if StringName(e["kind"]) == BenchLayout.KIND_FIGHTER:
			out[int(e["group"])] = e["fight_centre"]
	return out


func test_battle_and_typical_are_layouts_that_fight() -> void:
	for layout: StringName in [BenchLayout.BATTLE, BenchLayout.TYPICAL]:
		assert_true(BenchLayout.is_layout(layout))
		assert_true(BenchLayout.fights(layout))
		assert_true(BenchLayout.NAMES.has(layout), "%s is a bench layout" % layout)
		assert_false(BenchLayout.FIGHTER_LAYOUTS.has(layout))


func test_battle_holds_the_mix_with_a_quarter_of_the_capitals_a_side() -> void:
	for n: int in [50, 100, 300, 500]:
		var plan: Array[Dictionary] = BenchLayout.plan(BenchLayout.BATTLE, n, 1)
		var mix: Dictionary = BenchLayout.mix(BenchLayout.BATTLE, n)
		assert_eq(plan.size(), n, "%d: N counts fighters and capitals" % n)
		var capitals: Array[Dictionary] = _of_kind(plan, BenchLayout.KIND_CAPITAL)
		assert_eq(capitals.size(), roundi(0.15 * n), "%d: round(0.15 n) capitals" % n)
		assert_eq(capitals.size(), int(mix["capitals"]))
		var per_side: Dictionary = {}
		var per_class: Dictionary = {}
		for c: Dictionary in capitals:
			per_side[int(c["side"])] = int(per_side.get(int(c["side"]), 0)) + 1
			per_class[String(c["class"])] = int(per_class.get(String(c["class"]), 0)) + 1
			assert_true(CapitalStandin.CLASSES.has(StringName(c["class"])), "%d: a known class" % n)
		assert_eq(per_side.size(), 4, "%d: every side has capitals" % n)
		for side: int in per_side:
			assert_lte(absi(int(per_side[side]) * 4 - capitals.size()), 4, "%d: a quarter a side (%s)" % [n, per_side])
		assert_eq(int(per_class.get("carrier", 0)), int(mix["carriers"]))
		assert_eq(int(per_class.get("destroyer", 0)), int(mix["destroyers"]))
		assert_eq(int(per_class.get("cruiser", 0)), int(mix["cruisers"]))


func test_battle_has_four_sides_every_pair_hostile() -> void:
	var sides: Array[StringName] = BenchLayout.sides(BenchLayout.BATTLE)
	assert_eq(sides.size(), 4)
	assert_eq(sides[0], Factions.EARTH_ALLIANCE, "the player's side is the first")
	assert_eq(sides[1], Factions.RAIDERS)
	var table: FactionTable = BenchLayout.faction_table(BenchLayout.BATTLE)
	assert_not_null(table)
	for a: StringName in sides:
		for b: StringName in sides:
			var want: Factions.Relation = Factions.Relation.FRIENDLY if a == b else Factions.Relation.HOSTILE
			assert_eq(table.relation(a, b), want, "%s against %s" % [a, b])
	var seen: Dictionary = {}
	for e: Dictionary in BenchLayout.plan(BenchLayout.BATTLE, 200, 1):
		seen[StringName(e["faction"])] = true
		assert_eq(StringName(e["faction"]), sides[int(e["side"])], "a ship flies for its side")
	assert_eq(seen.size(), 4, "all four sides fly")
	assert_null(BenchLayout.faction_table(BenchLayout.FURBALL), "the other layouts keep the game's table")


func test_battle_fights_are_eight_km_apart_with_the_players_at_the_centre() -> void:
	for n: int in [100, 500, 1000]:
		var plan: Array[Dictionary] = BenchLayout.plan(BenchLayout.BATTLE, n, 1)
		var centres: Dictionary = _fight_centres(plan)
		var fighters: int = int(BenchLayout.mix(BenchLayout.BATTLE, n)["fighters"])
		assert_eq(centres.size(), maxi(1, roundi(float(fighters) / float(BenchLayout.FIGHT_SIZE))), "%d: fights of about 24" % n)
		assert_eq(centres[0] as Vector3, Vector3(0.0, 0.0, -BenchLayout.FIGHT_AHEAD_M), "%d: the player's fight is first, just ahead" % n)
		var area: Vector3 = BenchLayout.mix(BenchLayout.BATTLE, n)["area_m"]
		for g: int in centres:
			var nearest: float = INF
			for h: int in centres:
				if g != h:
					nearest = minf(nearest, (centres[g] as Vector3).distance_to(centres[h] as Vector3))
			if centres.size() > 1:
				assert_almost_eq(nearest, BenchLayout.FIGHT_SPACING_M, 1e-3, "%d: fight %d is 8 km from the next" % [n, g])
			var c: Vector3 = centres[g]
			assert_lte(absf(c.y), area.y * 0.5, "%d: fight %d inside the area's depth" % [n, g])
		for e: Dictionary in plan:
			var at: Vector3 = (e["offset"] as Vector3) - (centres[0] as Vector3)
			assert_true(absf(at.x) <= area.x * 0.5 and absf(at.y) <= area.y * 0.5 and absf(at.z) <= area.z * 0.5,
					"%d: every ship inside the area (%s)" % [n, at])


func test_no_two_ships_start_within_fifty_metres() -> void:
	for layout: StringName in [BenchLayout.BATTLE, BenchLayout.TYPICAL]:
		var plan: Array[Dictionary] = BenchLayout.plan(layout, 300 if layout == BenchLayout.BATTLE else 58, 2)
		var closest: float = INF
		for i: int in plan.size():
			for j: int in range(i + 1, plan.size()):
				var gap: float = (plan[i]["offset"] as Vector3).distance_to(plan[j]["offset"] as Vector3) \
						- float(plan[i]["radius"]) - float(plan[j]["radius"])
				closest = minf(closest, gap)
		assert_gte(closest, BenchLayout.MIN_SPACING_M, "%s: closest pair %.1f m apart (hull to hull for capitals)" % [layout, closest])


func test_a_sides_capitals_sit_five_km_behind_its_fight_heading_into_it() -> void:
	var plan: Array[Dictionary] = BenchLayout.plan(BenchLayout.BATTLE, 300, 1)
	for c: Dictionary in _of_kind(plan, BenchLayout.KIND_CAPITAL):
		var back: Vector3 = BenchLayout.side_direction(int(c["side"]))
		var from_fight: Vector3 = (c["offset"] as Vector3) - (c["fight_centre"] as Vector3)
		assert_almost_eq(from_fight.dot(back), BenchLayout.CAPITAL_STANDOFF_M, 1e-2, "behind its side's fighters")
		var nose: Vector3 = -(c["basis"] as Basis).z
		assert_almost_eq(nose.dot(-back), 1.0, 1e-5, "nose toward the fight")
		assert_almost_eq((c["velocity"] as Vector3).length(), CapitalStandin.CRUISE_MPS, 1e-3, "cruising")
		assert_almost_eq((c["velocity"] as Vector3).normalized().dot(nose), 1.0, 1e-5, "along its nose")
	for f: Dictionary in _of_kind(plan, BenchLayout.KIND_FIGHTER):
		var toward: Vector3 = (f["fight_centre"] as Vector3) - (f["offset"] as Vector3)
		assert_gt((-(f["basis"] as Basis).z).dot(toward.normalized()), 0.0, "a fighter faces into its fight")


func test_typical_is_two_fights_of_two_sides() -> void:
	var plan: Array[Dictionary] = BenchLayout.plan(BenchLayout.TYPICAL, 58, 1)
	assert_eq(plan.size(), 58)
	assert_eq(_of_kind(plan, BenchLayout.KIND_FIGHTER).size(), 50)
	assert_eq(_of_kind(plan, BenchLayout.KIND_CAPITAL).size(), 8)
	assert_eq(_fight_centres(plan).size(), 2, "two fights")
	assert_eq(BenchLayout.sides(BenchLayout.TYPICAL), [Factions.EARTH_ALLIANCE, Factions.RAIDERS] as Array[StringName])
	assert_null(BenchLayout.faction_table(BenchLayout.TYPICAL), "two sides: the game's own table")
	var allies: int = 0
	for e: Dictionary in _of_kind(plan, BenchLayout.KIND_FIGHTER):
		allies += 1 if StringName(e["type"]) == ShipPool.ALLY_TYPE else 0
		assert_true(bool(BrainFactory.from_behaviour(e["behaviour"], UniversePos.new(), int(e["seed"]))["ok"]), "the brain builds")
	assert_eq(allies, 25, "half and half")


func test_battle_plans_are_seeded() -> void:
	var a: Array[Dictionary] = BenchLayout.plan(BenchLayout.BATTLE, 100, 4)
	var b: Array[Dictionary] = BenchLayout.plan(BenchLayout.BATTLE, 100, 4)
	var c: Array[Dictionary] = BenchLayout.plan(BenchLayout.BATTLE, 100, 5)
	var same: bool = true
	var differs: bool = false
	for i: int in a.size():
		same = same and (a[i]["offset"] as Vector3) == (b[i]["offset"] as Vector3) and int(a[i]["seed"]) == int(b[i]["seed"])
		differs = differs or (a[i]["offset"] as Vector3) != (c[i]["offset"] as Vector3)
	assert_true(same)
	assert_true(differs)
	var ra: Array[Dictionary] = BenchLayout.rocks(BenchLayout.BATTLE, 100, 4)
	var rb: Array[Dictionary] = BenchLayout.rocks(BenchLayout.BATTLE, 100, 4)
	assert_eq(ra.size(), rb.size())
	assert_eq(ra[17]["offset"] as Vector3, rb[17]["offset"] as Vector3, "the rocks too")


func test_the_rock_slab_clears_every_ship() -> void:
	for layout: StringName in [BenchLayout.BATTLE, BenchLayout.TYPICAL]:
		var n: int = 100 if layout == BenchLayout.BATTLE else 58
		var plan: Array[Dictionary] = BenchLayout.plan(layout, n, 1)
		var rocks: Array[Dictionary] = BenchLayout.rocks(layout, n, 1)
		assert_eq(rocks.size(), int(BenchLayout.mix(layout, n)["asteroids"]), "%s: the mix's rocks" % layout)
		var slab: AABB = BenchLayout.rock_slab(layout, n)
		assert_eq(slab.size, BenchLayout.ROCK_SLAB_M)
		var smallest: float = INF
		var largest: float = 0.0
		var clear: float = INF
		for r: Dictionary in rocks:
			var at: Vector3 = r["offset"]
			var radius: float = r["radius"]
			smallest = minf(smallest, radius)
			largest = maxf(largest, radius)
			assert_true(slab.has_point(at), "%s: a rock in the slab" % layout)
			clear = minf(clear, at.length() - radius)  # the player at the origin
			for e: Dictionary in plan:
				clear = minf(clear, at.distance_to(e["offset"] as Vector3) - radius - float(e["radius"]))
		assert_gte(smallest, BenchLayout.ROCK_RADIUS_MIN_M)
		assert_lte(largest, BenchLayout.ROCK_RADIUS_MAX_M)
		assert_gt(largest, 4.0 * smallest, "%s: rocks of many sizes" % layout)
		assert_gte(clear, BenchLayout.ROCK_CLEARANCE_M, "%s: no ship starts inside a rock (closest %.0f m)" % [layout, clear])
		assert_gt(BenchLayout.fights_in_slab(layout, n), 0, "%s: the player's fight is among the rocks" % layout)
	assert_eq(BenchLayout.rocks(BenchLayout.FURBALL, 50, 1).size(), 0, "the other layouts have no rocks")


func test_the_gravity_source_is_a_moon_far_below() -> void:
	var g: Dictionary = BenchLayout.gravity_source(BenchLayout.BATTLE)
	assert_almost_eq((g["offset"] as Vector3).length(), 400000.0, 1.0, "a moon 400 km off")
	var at_centre: float = float(g["gm"]) / (g["offset"] as Vector3).length_squared()
	assert_almost_eq(at_centre, 0.03, 1e-6, "0.03 m/s^2 at the battle")
	assert_true(BenchLayout.gravity_source(BenchLayout.SPREAD).is_empty())


# --- mine belts (M4-T12) -----------------------------------------------------------------------------------------


func test_the_mine_belts_hold_the_mix_split_between_the_sides() -> void:
	for layout: StringName in [BenchLayout.TYPICAL, BenchLayout.BATTLE]:
		for n: int in [58, 100, 300]:
			var mix: Dictionary = BenchLayout.mix(layout, n)
			var mines: Array[Dictionary] = BenchLayout.mines(layout, n, 1)
			assert_eq(mines.size(), int(mix["mines"]), "%s %d lays the mix's mines" % [layout, n])
			var per_side: Dictionary = {}
			for m: Dictionary in mines:
				per_side[m["faction"]] = int(per_side.get(m["faction"], 0)) + 1
			var sides: Array[StringName] = BenchLayout.sides(layout)
			assert_eq(per_side.size(), sides.size(), "every side lays a belt")
			for f: StringName in per_side:
				assert_true(sides.has(f))
				assert_almost_eq(float(per_side[f]), float(mines.size()) / float(sides.size()), float(mines.size()) * 0.05 + 2.0)
	assert_eq(BenchLayout.mines(BenchLayout.FURBALL, 50, 1).size(), 0, "a fighter layout lays none")


func test_a_belt_lies_between_its_sides_fighters_and_capitals_clear_of_every_ship() -> void:
	var layout: StringName = BenchLayout.BATTLE
	var plan: Array[Dictionary] = BenchLayout.plan(layout, 100, 1)
	var sides: Array[StringName] = BenchLayout.sides(layout)
	for m: Dictionary in BenchLayout.mines(layout, 100, 1):
		var side: int = sides.find(m["faction"])
		var from_centre: Vector3 = (m["offset"] as Vector3) - (m["fight_centre"] as Vector3)
		var flat := Vector3(from_centre.x, 0.0, from_centre.z)
		assert_between(flat.length(), BenchLayout.MINE_BELT_RADIUS_M - BenchLayout.MINE_BELT_DEPTH_M,
				BenchLayout.MINE_BELT_RADIUS_M + BenchLayout.MINE_BELT_DEPTH_M, "on the belt's ring")
		assert_gt(flat.normalized().dot(BenchLayout.side_direction(side)), cos(deg_to_rad(46.0)), "on its own side's arc")
		for e: Dictionary in plan:
			var clear: float = float(e["radius"]) + MineStandin.TRIGGER_RADIUS_M
			assert_gt((m["offset"] as Vector3).distance_to(e["offset"]), clear, "no ship starts inside a trigger")


func test_mine_belts_are_seeded() -> void:
	assert_eq(BenchLayout.mines(BenchLayout.TYPICAL, 58, 3), BenchLayout.mines(BenchLayout.TYPICAL, 58, 3))
	assert_ne(BenchLayout.mines(BenchLayout.TYPICAL, 58, 3), BenchLayout.mines(BenchLayout.TYPICAL, 58, 4))
