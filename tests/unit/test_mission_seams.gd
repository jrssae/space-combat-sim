extends GutTest
## The mission seams the tutorial added (M8 D79), without a stage: facts and their trigger, `when`, notes and the checkpoint in
## the result, the pause menu's skip block, the debrief's lines and rank.

const DT: float = 1.0 / 60.0


class Lesson extends MissionScript:
	var trace: Array[String] = []

	func steps() -> Array[StringName]:
		return [&"intro", &"drill", &"exam", &"fight"]

	func skip_block() -> Dictionary:
		return {"from": &"drill", "to": &"fight", "label": "Skip training"}

	func step_intro(m: MissionApi) -> void:
		m.when(TriggerSpec.fact(&"hostile_hits", 1.0), func() -> void: trace.append("scramble"))
		await m.wait(0.1)

	func step_drill(m: MissionApi) -> void:
		await m.until(TriggerSpec.fact(&"gate_jumps", 1.0))
		if m.noted(&"course") == null:
			m.note(&"course", &"par")
		trace.append("drill done")

	func step_exam(m: MissionApi) -> void:
		await m.wait(100.0)

	func step_fight(m: MissionApi) -> void:
		m.checkpoint(&"fight", "the fight")
		m.debrief_line("Assignment: Squadron pilot")
		m.award_rank(Career.SQUADRON_PILOT)
		await m.wait(1.0)
		m.end(str(m.noted(&"course")) == "exemplary", "graded")


var world: MissionWorld
var api: MissionApi
var script_: Lesson


func before_each() -> void:
	world = MissionWorld.new()
	api = MissionApi.new(world, ObjectiveBook.new(), null)
	script_ = Lesson.new()


func _ticks(n: int) -> void:
	for i: int in n:
		api.tick(DT, {})


func test_a_fact_trigger_waits_for_its_number_and_reads_below_too() -> void:
	var at_least: TriggerFact = TriggerSpec.fact(&"gate_jumps", 1.0)
	var below: TriggerFact = TriggerSpec.fact(&"capitals_in_play", 1.0, true)
	assert_false(at_least.check(world))
	assert_true(below.check(world), "nobody set it: 0")
	world.set_fact(&"gate_jumps", 1.0)
	world.set_fact(&"capitals_in_play", 1.0)
	assert_true(at_least.check(world))
	assert_false(below.check(world))
	assert_almost_eq(world.fact(&"gate_jumps"), 1.0, 1e-6)


func test_a_fact_trigger_builds_from_json_and_refuses_an_unknown_fact() -> void:
	var made: Dictionary = TriggerSpec.from_dict({"kind": "fact", "fact": "capitals_destroyed", "at_least": 1})
	assert_true(bool(made["ok"]), str(made["error"]))
	assert_true(made["trigger"] is TriggerFact)
	assert_false(bool(TriggerSpec.from_dict({"kind": "fact", "fact": "nonsense"})["ok"]))


func test_when_runs_its_action_once_at_the_first_tick_the_trigger_holds_while_the_steps_go_on() -> void:
	assert_eq(api.begin(script_), "")
	_ticks(10)
	assert_eq(api.step_name(), &"drill")
	assert_eq(script_.trace, [] as Array[String])
	world.set_fact(&"hostile_hits", 2.0)
	_ticks(3)
	assert_eq(script_.trace, ["scramble"] as Array[String], "once")
	assert_eq(api.step_name(), &"drill", "it held no step up")


func test_the_skip_block_is_offered_only_inside_it_and_goes_to_its_end() -> void:
	assert_eq(api.begin(script_), "")
	assert_false(api.skip_offered(), "not during the intro")
	assert_eq(api.take_skip(), "nothing to skip now")
	_ticks(10)
	assert_true(api.skip_offered())
	assert_eq(api.take_skip(), "")
	_ticks(2)
	assert_eq(api.step_name(), &"fight")
	assert_false(api.skip_offered())
	assert_eq(script_.trace, ["drill done"] as Array[String], "the skipped steps still ran their world changes")


func test_a_script_whose_skip_block_names_no_step_is_refused() -> void:
	var odd := OddBlock.new()
	assert_string_contains(odd.check_steps(), "skip block")


class OddBlock extends MissionScript:
	func steps() -> Array[StringName]:
		return [&"a"]

	func skip_block() -> Dictionary:
		return {"from": &"a", "to": &"nowhere", "label": "Skip"}

	func step_a(_m: MissionApi) -> void:
		pass


func test_the_result_carries_the_checkpoint_the_notes_the_debrief_lines_and_no_rank_for_a_loss() -> void:
	assert_eq(api.begin(script_), "")
	assert_eq(api.goto(&"fight"), "")
	_ticks(120)
	assert_true(api.has_ended())
	assert_false(bool(api.result["success"]))
	assert_eq(api.result["checkpoint"]["step"], &"fight")
	assert_eq(api.result["checkpoint"]["label"], "the fight")
	assert_eq(api.result["checkpoint"]["notes"][&"course"], &"par", "the notes as they were at the checkpoint")
	assert_eq(Array(api.result["debrief_lines"]), ["Assignment: Squadron pilot"])
	assert_eq(api.result["rank"], &"", "a lost mission earns no rank")
	assert_true(GameFlow.has_checkpoint(api.result))


func test_notes_set_before_the_start_are_kept_as_a_checkpoint_restart_needs() -> void:
	api.notes = {&"course": &"exemplary"}
	assert_eq(api.begin(script_), "")
	assert_eq(api.goto(&"fight"), "")
	_ticks(120)
	assert_true(bool(api.result["success"]), "the drill did not overwrite the flown result")
	assert_eq(api.result["rank"], Career.SQUADRON_PILOT)
	assert_false(GameFlow.has_checkpoint(api.result), "a mission won offers no checkpoint")
