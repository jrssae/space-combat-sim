extends GutTest
## A mission's steps without a game (architecture §18 D51, M5-T05): `MissionApi` and `MissionSequencer` over a bare `MissionWorld`.
## Steps run in order as coroutines on sim time (ticks only); `skip` fast-forwards the current step and forces what it awaits;
## `goto` skips up to a named step; `end` and the objective rules finish the mission once.

const DT: float = 1.0 / 60.0


## Three steps: a raider to kill, a timed wait and a roll to perform, then an ending.
class ThreeSteps extends MissionScript:
	var trace: Array[String] = []

	func steps() -> Array[StringName]:
		return [&"intercept", &"hold", &"finish"]

	func step_intercept(m: MissionApi) -> void:
		trace.append("intercept")
		m.spawn({"type": "raider_fighter", "name": "RAIDER 1", "anchor": "origin", "offset": [0, 0, -6000]})
		m.objective_add(&"raider")
		await m.say(&"intro_1")
		await m.until(TriggerSpec.destroyed(["RAIDER 1"]))
		trace.append("intercept done")

	func step_hold(m: MissionApi) -> void:
		trace.append("hold")
		await m.wait(2.0)
		trace.append("hold waited")
		await m.player_did(&"roll_right")
		trace.append("hold rolled")

	func step_finish(m: MissionApi) -> void:
		trace.append("finish")
		await m.until({"kind": "proximity", "actor": "player", "to": "NAV ALPHA", "radius_m": 300})
		m.objective_complete(&"home")
		trace.append("finish done")


## Ends itself in its first step.
class EndsEarly extends MissionScript:
	var after_end: bool = false

	func steps() -> Array[StringName]:
		return [&"only", &"never"]

	func step_only(m: MissionApi) -> void:
		m.end(false, "scripted loss")
		await m.wait(1.0)
		after_end = true

	func step_never(_m: MissionApi) -> void:
		after_end = true


## Waits for its raider before spawning it (D52: a name not yet in play is not destroyed), then polls, which it should not.
class EarlyWait extends MissionScript:
	var trace: Array[String] = []

	func steps() -> Array[StringName]:
		return [&"early"]

	func step_early(m: MissionApi) -> void:
		var gone: Trigger = TriggerSpec.destroyed(["RAIDER 9"])
		trace.append("waiting")
		m.spawn({"type": "raider_fighter", "name": "RAIDER 9", "anchor": "origin", "offset": [0, 0, -6000]})
		await m.until(gone)
		trace.append("gone")


## Polls with wait instead of waiting with until: under a skip every wait returns at once.
class Polls extends MissionScript:
	var loops: int = 0

	func steps() -> Array[StringName]:
		return [&"poll"]

	func step_poll(m: MissionApi) -> void:
		while m.alive("PLAYER"):
			loops += 1
			await m.wait(1.0)


class MissingStep extends MissionScript:
	func steps() -> Array[StringName]:
		return [&"there", &"missing"]

	func step_there(_m: MissionApi) -> void:
		pass


var world: MissionWorld
var book: ObjectiveBook
var api: MissionApi


func before_each() -> void:
	world = MissionWorld.new()
	world.set_actor("PLAYER", UniversePos.new())
	world.set_actor("NAV ALPHA", UniversePos.new(0.0, 0.0, -2000.0))
	book = ObjectiveBook.new()
	assert_eq(book.declare([
		{"id": "raider", "text": "Destroy the raider", "primary": true, "success": {"kind": "destroyed", "name": "RAIDER 1"}},
		{"id": "home", "text": "Return to NAV ALPHA", "primary": true, "active": true},
	]), "")
	api = MissionApi.new(world, book)


func after_each() -> void:
	api.release()


func _ticks(count: int, actions: Dictionary = {}) -> void:
	for _i: int in count:
		api.tick(DT, actions)


func _start(script: MissionScript) -> void:
	assert_eq(api.begin(script), "")


# --- running ---------------------------------------------------------------------------------------------------------


func test_steps_run_in_order_each_waiting_for_what_it_awaits() -> void:
	var script := ThreeSteps.new()
	_start(script)
	assert_eq(script.trace, ["intercept"] as Array[String], "the first step runs until its first wait")
	assert_eq(api.step_name(), &"intercept")
	_ticks(30)
	assert_eq(script.trace.size(), 1, "the raider lives")
	world.set_alive("RAIDER 1", false)
	_ticks(1)
	assert_eq(script.trace, ["intercept", "intercept done", "hold"] as Array[String])
	assert_eq(book.state_of(&"raider"), ObjectiveBook.DONE, "its success trigger saw the kill")
	_ticks(119)
	assert_false(script.trace.has("hold waited"), "2 s are 120 ticks")
	_ticks(1)
	assert_true(script.trace.has("hold waited"))
	_ticks(5, {&"roll_left": true})
	assert_false(script.trace.has("hold rolled"))
	_ticks(1, {&"roll_right": true})
	assert_true(script.trace.has("hold rolled"))
	assert_eq(api.step_name(), &"finish")


func test_time_is_sim_time_from_ticks_never_the_wall_clock() -> void:
	var script := ThreeSteps.new()
	_start(script)
	world.set_alive("RAIDER 1", false)
	_ticks(1)
	for _i: int in 10:
		await get_tree().process_frame
	assert_false(script.trace.has("hold waited"), "frames without ticks move no mission time")
	assert_almost_eq(api.time_s(), DT, 1e-9)


func test_say_resolves_at_once_and_marks_its_line_finished() -> void:
	_start(ThreeSteps.new())
	assert_true(world.line_finished(&"intro_1"), "the T06 seam: lines are finished as soon as said")
	assert_has(api.journal, "say intro_1")


# --- skip and goto (D51) -------------------------------------------------------------------------------------------------


func test_skip_forces_the_awaited_trigger_and_keeps_the_world_changes() -> void:
	var script := ThreeSteps.new()
	_start(script)
	assert_eq(api.skip(), "")
	assert_eq(script.trace, ["intercept", "intercept done", "hold"] as Array[String], "the step ran to its end at once")
	assert_false(world.is_alive("RAIDER 1"), "destroyed was made true: the raider is released")
	assert_eq(book.state_of(&"raider"), ObjectiveBook.DONE, "and the objective it completes is done")
	assert_has(api.journal, "spawn RAIDER 1 raider_fighter")
	assert_false(api.is_skipping(), "only that step was skipped")
	assert_eq(api.step_name(), &"hold")


func test_skip_resolves_waits_and_input_without_moving_time() -> void:
	var script := ThreeSteps.new()
	_start(script)
	api.skip()
	assert_eq(api.skip(), "")
	assert_true(script.trace.has("hold rolled"))
	assert_eq(api.time_s(), 0.0, "no tick happened")
	assert_eq(api.step_name(), &"finish")


func test_goto_skips_every_step_before_the_named_one() -> void:
	var script := ThreeSteps.new()
	_start(script)
	assert_eq(api.goto(&"finish"), "")
	assert_eq(script.trace, ["intercept", "intercept done", "hold", "hold waited", "hold rolled", "finish"] as Array[String])
	assert_eq(api.step_name(), &"finish")
	assert_false(api.is_skipping(), "the named step runs normally")
	_ticks(10)
	assert_false(script.trace.has("finish done"), "it waits as usual")


func test_goto_refuses_unknown_and_past_steps() -> void:
	_start(ThreeSteps.new())
	assert_string_contains(api.goto(&"nowhere"), "no step")
	assert_string_contains(api.goto(&"intercept"), "already")
	api.skip()
	assert_string_contains(api.goto(&"intercept"), "already")


func test_skip_after_the_last_step_refuses() -> void:
	book.add(&"later", "Something after the script", true)  # keeps the mission running past its last step
	var script := ThreeSteps.new()
	_start(script)
	api.goto(&"finish")
	assert_eq(api.skip(), "")
	assert_true(script.trace.has("finish done"))
	assert_string_contains(api.skip(), "finished")


func test_a_skipped_run_leaves_the_same_spawns_and_objectives_as_a_played_one() -> void:
	var played := ThreeSteps.new()
	_start(played)
	world.set_alive("RAIDER 1", false)
	_ticks(121)
	_ticks(1, {&"roll_right": true})
	world.set_actor("PLAYER", UniversePos.new(0.0, 0.0, -1900.0))
	_ticks(1)
	var played_journal: PackedStringArray = api.journal.duplicate()
	var played_book: Array[Dictionary] = book.snapshot()
	var played_alive: bool = world.is_alive("RAIDER 1")
	api.release()

	before_each()
	var skipped := ThreeSteps.new()
	_start(skipped)
	api.goto(&"finish")
	api.skip()
	assert_eq(skipped.trace, played.trace)
	assert_eq(api.journal, played_journal, "same spawns, sends, lines and objective changes, in the same order")
	assert_eq_deep(book.snapshot(), played_book)
	assert_eq(world.is_alive("RAIDER 1"), played_alive)


# --- ending ------------------------------------------------------------------------------------------------------------


func test_all_primaries_done_ends_in_success_once() -> void:
	var ended: Array[Dictionary] = []
	api.ended.connect(func(result: Dictionary) -> void: ended.append(result))
	_start(ThreeSteps.new())
	api.goto(&"finish")
	api.skip()
	assert_eq(ended.size(), 1)
	assert_true(bool(ended[0]["success"]))
	assert_eq(api.result["reason"], "every primary objective done")
	_ticks(5)
	assert_eq(ended.size(), 1, "it ends once")


func test_a_failed_primary_ends_in_failure() -> void:
	_start(ThreeSteps.new())
	book.fail(&"home")
	_ticks(1)
	assert_true(api.has_ended())
	assert_false(bool(api.result["success"]))
	assert_string_contains(String(api.result["reason"]), "home")


func test_end_stops_the_script_where_it_is() -> void:
	var script := EndsEarly.new()
	_start(script)
	assert_true(api.has_ended())
	assert_eq(api.result["reason"], "scripted loss")
	_ticks(120)
	assert_false(script.after_end, "nothing after end runs, not even the next step")
	assert_string_contains(api.skip(), "ended")


func test_the_player_lost_ends_in_failure() -> void:
	_start(ThreeSteps.new())
	api.player_destroyed()
	assert_true(api.has_ended())
	assert_false(bool(api.result["success"]))
	assert_eq(api.result["reason"], "player destroyed")


func test_the_result_carries_the_objectives_and_the_time() -> void:
	_start(ThreeSteps.new())
	_ticks(30)
	api.end(true)
	assert_almost_eq(float(api.result["time_s"]), 30.0 * DT, 1e-9)
	assert_eq((api.result["objectives"] as Array).size(), 2)


func test_an_until_destroyed_on_a_ship_not_yet_in_play_waits_for_it() -> void:
	var early := ObjectiveBook.new()
	early.add(&"stay", "Keep the mission open", true)
	api.release()
	api = MissionApi.new(world, early)
	var gone: Trigger = TriggerSpec.destroyed(["RAIDER 8"])
	assert_false(gone.check(world), "a ship the script has not spawned is not destroyed")
	var script := EarlyWait.new()
	_start(script)
	_ticks(5)
	assert_eq(script.trace, ["waiting"] as Array[String], "the raider is in play")
	world.set_alive("RAIDER 9", false)
	_ticks(1)
	assert_eq(script.trace, ["waiting", "gone"] as Array[String])


func test_a_polling_step_under_skip_is_reported_and_does_not_spin() -> void:
	var script := Polls.new()
	_start(script)
	assert_eq(api.skip(), "", "returns: the loop did not spin forever")
	assert_push_error("it polls")
	# One loop waited before the skip; the skip's first wait comes back from it, then LIMIT waits return at once.
	assert_eq(script.loops, MissionApi.SKIP_SPIN_LIMIT + 2, "then the step waits")
	_ticks(3)
	assert_eq(script.loops, MissionApi.SKIP_SPIN_LIMIT + 5, "one wait per tick from there")


# --- refusals ----------------------------------------------------------------------------------------------------------


func test_a_step_without_its_method_is_refused_before_anything_runs() -> void:
	assert_string_contains(api.begin(MissingStep.new()), "step_missing")
	assert_false(api.is_running())


func test_a_bad_trigger_spec_is_an_error_and_does_not_hang_the_step() -> void:
	_start(ThreeSteps.new())
	await api.until({"kind": "nonsense"})
	assert_push_error("unknown kind")


func test_twenty_live_triggers_cost_a_counted_bound_per_tick() -> void:
	for i: int in 9:
		book.add(StringName("o%d" % i), "x", true, TriggerSpec.proximity("player", "NAV ALPHA", 100.0),
				TriggerSpec.destroyed(["NAV ALPHA"]))
	_start(ThreeSteps.new())
	for i: int in 9:
		book.activate(StringName("o%d" % i), world)
	_ticks(1)
	gut.p("20 live triggers (19 objective, 1 awaited): %d units of work in a tick" % api.tick_work)
	assert_eq(api.live_trigger_count(), 20)
	assert_lte(api.tick_work, 20 * 3, "a check and at most two lookups each, whatever the world holds")
