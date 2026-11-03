extends GutTest
## ObjectiveBook (architecture §18 D52, M5-T05): objectives move hidden -> active -> done | failed, their success and fail triggers
## are evaluated while active (fail first), a forced success completes, the result rules read primaries only, and `snapshot`
## is what the pause menu and the debrief list.

var book: ObjectiveBook
var world: MissionWorld


func before_each() -> void:
	book = ObjectiveBook.new()
	world = MissionWorld.new()
	world.set_actor("PLAYER", UniversePos.new())
	world.set_actor("NAV ALPHA", UniversePos.new(0.0, 0.0, -2000.0))
	world.set_actor("RAIDER 1", UniversePos.new(0.0, 0.0, -6000.0))


func _declare_buoy_defence() -> void:
	var error: String = book.declare([
		{"id": "protect", "text": "Protect NAV ALPHA", "primary": true,
				"fail": {"kind": "destroyed", "name": "NAV ALPHA"}},
		{"id": "raiders", "text": "Destroy the raiders", "primary": true,
				"success": {"kind": "destroyed", "names": ["RAIDER 1"]}},
		{"id": "home", "text": "Bring Alpha wing home", "primary": false, "active": true},
	])
	assert_eq(error, "")


func test_declared_objectives_start_hidden_unless_marked_active() -> void:
	_declare_buoy_defence()
	assert_eq(book.state_of(&"protect"), ObjectiveBook.HIDDEN)
	assert_eq(book.state_of(&"raiders"), ObjectiveBook.HIDDEN)
	assert_eq(book.state_of(&"home"), ObjectiveBook.ACTIVE)
	assert_eq(book.state_of(&"nothing"), &"", "unknown id")


func test_snapshot_lists_every_objective_in_order() -> void:
	_declare_buoy_defence()
	book.activate(&"protect", world)
	var snap: Array[Dictionary] = book.snapshot()
	assert_eq(snap.size(), 3)
	assert_eq_deep(snap[0], {"id": &"protect", "text": "Protect NAV ALPHA", "primary": true, "state": &"active"})
	assert_eq_deep(snap[2], {"id": &"home", "text": "Bring Alpha wing home", "primary": false, "state": &"active"})
	assert_true(snap[1]["id"] is StringName and snap[1]["state"] is StringName)


func test_success_trigger_completes_an_active_objective() -> void:
	_declare_buoy_defence()
	book.activate(&"raiders", world)
	assert_eq(book.evaluate(world), [] as Array[StringName])
	world.set_alive("RAIDER 1", false)
	assert_eq(book.evaluate(world), [&"raiders"] as Array[StringName])
	assert_eq(book.state_of(&"raiders"), ObjectiveBook.DONE)
	assert_eq(book.evaluate(world), [] as Array[StringName], "done stays done; it is reported once")


func test_fail_trigger_fails_an_active_objective() -> void:
	_declare_buoy_defence()
	book.activate(&"protect", world)
	world.set_alive("NAV ALPHA", false)
	assert_eq(book.evaluate(world), [&"protect"] as Array[StringName])
	assert_eq(book.state_of(&"protect"), ObjectiveBook.FAILED)


func test_fail_wins_over_success_in_the_same_tick() -> void:
	book.add(&"race", "Reach the buoy first", true, TriggerSpec.timer(0.0), TriggerSpec.timer(0.0))
	book.activate(&"race", world)
	book.evaluate(world)
	assert_eq(book.state_of(&"race"), ObjectiveBook.FAILED)


func test_a_json_objective_declared_before_its_ships_spawn_waits_for_them() -> void:
	assert_eq(book.declare([
		{"id": "wave", "text": "Destroy the second wave", "active": true,
				"success": {"kind": "destroyed", "names": ["RAIDER 5", "RAIDER 6"]}},
		{"id": "escort", "text": "Keep ALPHA 2 alive", "active": true, "fail": {"kind": "destroyed", "name": "ALPHA 2"}},
	]), "")
	assert_eq(book.evaluate(world), [] as Array[StringName], "tick 1: none of them has arrived")
	assert_eq(book.state_of(&"wave"), ObjectiveBook.ACTIVE)
	assert_eq(book.state_of(&"escort"), ObjectiveBook.ACTIVE, "the escort that jumps in later has not failed")
	world.set_actor("RAIDER 5", UniversePos.new(0.0, 0.0, -7000.0))
	world.set_actor("RAIDER 6", UniversePos.new(0.0, 0.0, -7100.0))
	world.set_actor("ALPHA 2", UniversePos.new(50.0, 0.0, 0.0))
	assert_eq(book.evaluate(world), [] as Array[StringName], "all in play")
	world.set_alive("RAIDER 5", false)
	world.set_alive("RAIDER 6", false)
	assert_eq(book.evaluate(world), [&"wave"] as Array[StringName])
	world.set_alive("ALPHA 2", false)
	assert_eq(book.evaluate(world), [&"escort"] as Array[StringName])
	assert_eq(book.state_of(&"escort"), ObjectiveBook.FAILED)


func test_hidden_objectives_are_not_evaluated() -> void:
	_declare_buoy_defence()
	world.set_alive("RAIDER 1", false)
	assert_eq(book.evaluate(world), [] as Array[StringName])
	assert_eq(book.state_of(&"raiders"), ObjectiveBook.HIDDEN)


func test_script_can_complete_and_fail_and_finished_ones_stay_finished() -> void:
	_declare_buoy_defence()
	assert_true(book.complete(&"home"))
	assert_false(book.fail(&"home"), "done is final")
	assert_string_contains(book.error, "already done")
	assert_true(book.fail(&"protect"), "a hidden objective may fail outright")
	assert_false(book.activate(&"protect", world))
	assert_false(book.complete(&"nothing"))
	assert_string_contains(book.error, "no objective")


func test_forced_success_makes_the_trigger_true_and_completes() -> void:
	_declare_buoy_defence()
	book.activate(&"raiders", world)
	assert_true(book.force_success(&"raiders", world))
	assert_eq(book.state_of(&"raiders"), ObjectiveBook.DONE)
	assert_false(world.is_alive("RAIDER 1"), "the raider was released, as the step would have left it")


func test_forced_success_without_a_trigger_just_completes() -> void:
	_declare_buoy_defence()
	assert_true(book.force_success(&"home", world))
	assert_eq(book.state_of(&"home"), ObjectiveBook.DONE)


func test_an_objective_can_be_added_by_the_script() -> void:
	assert_true(book.add(&"roll", "Roll right", false))
	assert_false(book.add(&"roll", "Again", false), "ids are unique")
	assert_eq(book.state_of(&"roll"), ObjectiveBook.HIDDEN)


func test_result_rules_read_the_primaries() -> void:
	_declare_buoy_defence()
	assert_false(book.all_primaries_done(), "nothing done yet")
	book.complete(&"raiders")
	assert_false(book.all_primaries_done())
	book.complete(&"protect")
	assert_true(book.all_primaries_done(), "the optional one does not count")
	assert_eq(book.failed_primary(), &"")


func test_a_failed_optional_is_not_a_failed_mission() -> void:
	_declare_buoy_defence()
	book.fail(&"home")
	assert_eq(book.failed_primary(), &"")
	book.fail(&"protect")
	assert_eq(book.failed_primary(), &"protect")


func test_a_book_without_primaries_is_never_all_done() -> void:
	book.add(&"roll", "Roll right", false)
	book.complete(&"roll")
	assert_false(book.all_primaries_done(), "success needs at least one primary (or the script ends it)")


func test_live_triggers_are_those_of_active_objectives() -> void:
	_declare_buoy_defence()
	assert_eq(book.live_triggers().size(), 0)
	book.activate(&"protect", world)
	book.activate(&"raiders", world)
	assert_eq(book.live_triggers().size(), 2)
	book.complete(&"raiders")
	assert_eq(book.live_triggers().size(), 1)


func test_activation_arms_a_timer_from_that_moment() -> void:
	book.add(&"hold", "Hold for 30 s", true, TriggerSpec.timer(30.0))
	world.time_s = 100.0
	book.activate(&"hold", world)
	world.time_s = 129.0
	assert_eq(book.evaluate(world), [] as Array[StringName])
	world.time_s = 130.0
	assert_eq(book.evaluate(world), [&"hold"] as Array[StringName])


func test_declare_refuses_bad_entries() -> void:
	assert_string_contains(book.declare([{"text": "x"}]), "id")
	assert_string_contains(ObjectiveBook.new().declare([{"id": "a"}, {"id": "a"}]), "twice")
	assert_string_contains(ObjectiveBook.new().declare([{"id": "a", "primary": "yes"}]), "primary")
	assert_string_contains(ObjectiveBook.new().declare([{"id": "a", "success": {"kind": "nope"}}]), "success")
	assert_string_contains(ObjectiveBook.new().declare("x"), "array")


func test_describe_lines_mark_state_and_optional() -> void:
	_declare_buoy_defence()
	book.complete(&"raiders")
	var lines: PackedStringArray = book.describe_lines()
	assert_eq(lines.size(), 3)
	assert_string_contains(lines[1], "done")
	assert_string_contains(lines[2], "optional")
