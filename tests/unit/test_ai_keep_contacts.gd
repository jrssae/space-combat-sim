extends GutTest
## What an AI pilot keeps in its contacts beyond the nearest k (M4-T04): `AiContext.keep_ids` / `keep_names`, `AiPilot`'s and
## `PilotBrain`'s. Pure; no scene.


func test_a_pilot_without_a_wing_or_targets_keeps_nothing() -> void:
	var ctx := AiContext.new()
	assert_eq(ctx.keep_ids().size(), 0)
	assert_eq(ctx.keep_names().size(), 0)


func test_the_context_keeps_its_wing_leader_targets_and_pace_ship() -> void:
	var ctx := AiContext.new()
	ctx.wing_ids = PackedInt64Array([11, 12])
	ctx.leader_id = 11
	ctx.leader_target_id = 21
	ctx.current_target_id = 22
	ctx.attack_target_id = 23
	ctx.route = Route.new()
	ctx.route.pace_id = 31
	assert_eq(Array(ctx.keep_ids()), [11, 12, 11, 21, 22, 23, 31])


func test_ids_of_zero_are_not_kept() -> void:
	var ctx := AiContext.new()
	ctx.route = Route.new()
	assert_eq(ctx.keep_ids().size(), 0, "no leader, targets or pace ship")


func test_keeping_never_changes_the_wing_list() -> void:
	var ctx := AiContext.new()
	ctx.wing_ids = PackedInt64Array([11])
	ctx.leader_id = 11
	ctx.keep_ids().append(99)
	assert_eq(Array(ctx.wing_ids), [11], "a copy: the caller may append to it")


func test_the_objective_and_the_guarded_ship_are_kept_by_name() -> void:
	var ctx := AiContext.new()
	ctx.objective_name = "NAV ALPHA"
	assert_eq(Array(ctx.keep_names()), ["NAV ALPHA"])
	ctx.guard_name = "ALPHA 1"
	assert_eq(Array(ctx.keep_names()), ["NAV ALPHA", "ALPHA 1"])


func test_an_ai_pilot_adds_the_target_it_wants() -> void:
	var pilot := AiPilot.new()
	pilot.context.wing_ids = PackedInt64Array([11])
	pilot.wanted_target_id = 41
	assert_eq(Array(pilot.keep_ids()), [11, 41])
	pilot.wanted_target_id = PilotBrain.TARGET_NONE
	assert_eq(Array(pilot.keep_ids()), [11])
	pilot.context.guard_name = "ALPHA 1"
	assert_eq(Array(pilot.keep_names()), ["ALPHA 1"])


func test_any_brain_keeps_the_target_it_wants() -> void:
	var brain := PilotBrain.new()
	assert_eq(brain.keep_ids().size(), 0, "the nearest-hostile rule: nothing of its own")
	brain.wanted_target_id = 41
	assert_eq(Array(brain.keep_ids()), [41])
	assert_eq(brain.keep_names().size(), 0)
