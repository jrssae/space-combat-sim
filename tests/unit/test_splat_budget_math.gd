extends GutTest
## SplatBudgetMath (M3-T20, Q22): which ships step down a level, and how far, to bring the visible splats under the budget.

const SPLATS: PackedInt32Array = [1000, 250, 60, 15]
const CHAIN: PackedInt32Array = [0, 1, 2, 3]


func _ship(wanted: int, distance: float, forced: bool = false) -> Dictionary:
	return {"wanted": wanted, "levels": CHAIN, "splats": SPLATS, "distance": distance, "forced": forced}


func test_a_sum_inside_the_budget_changes_nothing() -> void:
	var plan: Dictionary = SplatBudgetMath.plan([_ship(0, 100.0), _ship(0, 200.0)], 500, 2500)
	assert_eq(plan["extra"], PackedInt32Array([0, 0]))
	assert_true(plan["fits"])
	assert_eq(plan["total"], 2500)


func test_the_farthest_ship_steps_down_first() -> void:
	var plan: Dictionary = SplatBudgetMath.plan([_ship(0, 100.0), _ship(0, 900.0), _ship(0, 400.0)], 0, 2500)
	assert_eq(plan["extra"], PackedInt32Array([0, 1, 0]), "750 saved brings 3000 to 2250")
	assert_true(plan["fits"])
	assert_eq(plan["total"], 2250)


func test_it_goes_one_level_at_a_time_across_the_ships() -> void:
	# Each ship gives one level before any gives a second, farthest first.
	var plan: Dictionary = SplatBudgetMath.plan([_ship(0, 100.0), _ship(0, 900.0), _ship(0, 400.0)], 0, 1500)
	assert_eq(plan["extra"], PackedInt32Array([0, 1, 1]), "1500 once the two farthest have given a level")
	plan = SplatBudgetMath.plan([_ship(0, 100.0), _ship(0, 900.0), _ship(0, 400.0)], 0, 700)
	assert_eq(plan["extra"], PackedInt32Array([1, 2, 1]), "750 after one round each, then the farthest gives its second")
	assert_true(plan["fits"])
	assert_eq(plan["total"], 560)


func test_it_stops_as_soon_as_the_sum_fits() -> void:
	var plan: Dictionary = SplatBudgetMath.plan([_ship(0, 100.0), _ship(0, 900.0)], 0, 1250)
	assert_eq(plan["extra"], PackedInt32Array([0, 1]))
	assert_eq(plan["total"], 1250)


func test_it_works_from_the_wanted_level_and_stops_at_the_chain_end() -> void:
	var plan: Dictionary = SplatBudgetMath.plan([_ship(3, 900.0), _ship(1, 100.0)], 0, 70)
	assert_eq(plan["extra"], PackedInt32Array([0, 2]), "the far ship is already coarsest, so the near one gives two levels")
	assert_true(plan["fits"])
	assert_eq(plan["total"], 30)


func test_a_short_chain_is_respected() -> void:
	var ally: Dictionary = {"wanted": 1, "levels": PackedInt32Array([1, 2, 3]), "splats": PackedInt32Array([250, 60, 15]), "distance": 900.0, "forced": false}
	var plan: Dictionary = SplatBudgetMath.plan([ally], 0, 60)
	assert_eq(plan["extra"], PackedInt32Array([1]), "LOD2 fits: one level")
	assert_eq(plan["total"], 60)


func test_when_even_the_coarsest_everywhere_does_not_fit() -> void:
	var plan: Dictionary = SplatBudgetMath.plan([_ship(0, 100.0), _ship(0, 900.0)], 0, 20)
	assert_eq(plan["extra"], PackedInt32Array([3, 3]), "every ship as coarse as it goes")
	assert_false(plan["fits"])
	assert_eq(plan["total"], 30)


func test_what_nothing_can_step_down_counts_against_the_budget() -> void:
	var plan: Dictionary = SplatBudgetMath.plan([_ship(0, 100.0)], 900, 1200)
	assert_eq(plan["extra"], PackedInt32Array([1]), "the sky and buoys leave 300")
	assert_eq(plan["total"], 1150)
	assert_false(SplatBudgetMath.plan([_ship(3, 100.0)], 1300, 1200)["fits"])


func test_a_forced_level_stays_forced_and_counts_as_it_is() -> void:
	var plan: Dictionary = SplatBudgetMath.plan([_ship(0, 900.0, true), _ship(0, 100.0)], 0, 1250)
	assert_eq(plan["extra"], PackedInt32Array([0, 1]), "the far ship is forced: the near one gives way")
	assert_eq(plan["total"], 1250)


func test_the_same_input_always_gives_the_same_plan() -> void:
	# No current level goes in, so stepping down cannot feed back into the next frame's plan.
	var ships: Array[Dictionary] = [_ship(0, 100.0), _ship(1, 900.0), _ship(0, 400.0), _ship(2, 900.0)]
	var first: Dictionary = SplatBudgetMath.plan(ships, 100, 700)
	for i: int in 5:
		assert_eq(SplatBudgetMath.plan(ships, 100, 700), first)


func test_ties_in_distance_break_by_order() -> void:
	assert_eq(SplatBudgetMath.plan([_ship(0, 500.0), _ship(0, 500.0)], 0, 1250)["extra"], PackedInt32Array([1, 0]))


# --- a hero chain (M3-T24): level -1 in front of LOD0 ----------------------------------------------------------------


const HERO_CHAIN: PackedInt32Array = [-1, 0, 1, 2, 3]
const HERO_SPLATS: PackedInt32Array = [4000, 1000, 250, 60, 15]


func _hero(wanted: int, distance: float) -> Dictionary:
	return {"wanted": wanted, "levels": HERO_CHAIN, "splats": HERO_SPLATS, "distance": distance, "forced": false}


func test_the_chain_index_finds_the_hero() -> void:
	assert_eq(SplatBudgetMath.chain_index(HERO_CHAIN, -1), 0)
	assert_eq(SplatBudgetMath.chain_index(HERO_CHAIN, 0), 1)
	assert_eq(SplatBudgetMath.chain_index(CHAIN, -1), 0, "a chain without it starts at its LOD0")


func test_a_hero_steps_down_to_lod0_like_any_level() -> void:
	var plan: Dictionary = SplatBudgetMath.plan([_hero(-1, 30.0)], 0, 1500)
	assert_eq(plan["extra"], PackedInt32Array([1]))
	assert_eq(plan["total"], 1000)


func test_the_nearest_ship_is_the_last_to_give_way_so_the_farther_ones_go_before_the_hero() -> void:
	var plan: Dictionary = SplatBudgetMath.plan([_hero(-1, 30.0), _ship(0, 400.0), _ship(0, 900.0)], 0, 4800)
	assert_eq(plan["extra"], PackedInt32Array([0, 1, 1]), "the two others give a level; the hero is untouched")
	assert_true(plan["fits"])
