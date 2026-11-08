extends GutTest
## GameFlow (architecture §18, D50): the game's four states and the moves between them, the request carried across
## scenes, and the boot rule that sends every scripted run straight to Main. Pure: no tree, no files.

var flow: GameFlow


func before_each() -> void:
	flow = GameFlow.new()


func _free_flight(seed_value: int = 0) -> Dictionary:
	return GameFlow.make_request(&"free_flight", &"free_flight", false, seed_value)


func _in_space() -> void:
	assert_true(flow.start_loading(_free_flight()))
	assert_true(flow.finish_loading())


# --- States and transitions ----------------------------------------------------------------------------------------


func test_a_run_starts_at_the_front_end_with_nothing_asked_for() -> void:
	assert_eq(flow.state, GameFlow.State.FRONT_END)
	assert_eq(flow.request, {})
	assert_eq(flow.last_result, {})
	assert_eq(GameFlow.state_name(flow.state), "front_end")


func test_play_goes_through_loading_into_space() -> void:
	var request: Dictionary = _free_flight(7)
	assert_true(flow.start_loading(request))
	assert_eq(flow.state, GameFlow.State.LOADING)
	assert_eq(flow.request, request, "the request travels with the flow")
	assert_true(flow.finish_loading())
	assert_eq(flow.state, GameFlow.State.IN_SPACE)
	assert_eq(int(flow.request["seed"]), 7)


func test_the_stored_request_is_a_copy() -> void:
	var request: Dictionary = _free_flight()
	flow.start_loading(request)
	request["seed"] = 99
	assert_eq(int(flow.request["seed"]), 0, "changing the caller's dictionary does not change the flow")


func test_a_scripted_run_enters_space_directly_from_the_start() -> void:
	var request: Dictionary = GameFlow.make_request(&"sandbox", &"combat_sandbox")
	assert_true(flow.enter_directly(request))
	assert_eq(flow.state, GameFlow.State.IN_SPACE)
	assert_eq(flow.request, request)


func test_a_finished_run_goes_to_the_debrief_and_retry_reloads_the_same_request() -> void:
	_in_space()
	var result: Dictionary = {"success": false, "reason": "the buoy was destroyed"}
	assert_true(flow.end_run(result))
	assert_eq(flow.state, GameFlow.State.DEBRIEF)
	assert_eq(flow.last_result, result)
	assert_true(flow.retry())
	assert_eq(flow.state, GameFlow.State.LOADING)
	assert_eq(flow.request, _free_flight(), "retry plays the same scenario and seed")
	assert_eq(flow.last_result, result, "the last result stays readable after a retry")


func test_play_is_allowed_from_space_and_from_the_debrief() -> void:
	_in_space()
	assert_true(flow.start_loading(GameFlow.make_request(&"sandbox", &"dogfight", false, 3)), "restart or console play")
	assert_eq(flow.request["scenario_id"], &"dogfight")
	flow.finish_loading()
	flow.end_run({"success": true})
	assert_true(flow.start_loading(_free_flight()), "from the debrief")
	assert_eq(flow.state, GameFlow.State.LOADING)


func test_the_menu_is_reachable_from_every_state() -> void:
	for steps: int in 4:  # 0 front end, 1 loading, 2 in space, 3 debrief
		flow = GameFlow.new()
		if steps >= 1:
			flow.start_loading(_free_flight())
		if steps >= 2:
			flow.finish_loading()
		if steps >= 3:
			flow.end_run({"success": true})
		var from: String = GameFlow.state_name(flow.state)
		assert_eq(int(flow.state), [GameFlow.State.FRONT_END, GameFlow.State.LOADING, GameFlow.State.IN_SPACE,
				GameFlow.State.DEBRIEF][steps], "set up " + from)
		assert_true(flow.open_menu(), "menu from " + from)
		assert_eq(flow.state, GameFlow.State.FRONT_END, "menu from " + from)


func test_moves_that_make_no_sense_are_refused_and_change_nothing() -> void:
	assert_false(flow.finish_loading(), "nothing is loading")
	assert_false(flow.end_run({"success": true}), "no run to end at the front end")
	assert_false(flow.retry(), "no debrief to retry from")
	assert_eq(flow.state, GameFlow.State.FRONT_END)
	assert_ne(flow.error, "", "a refusal says why")

	flow.start_loading(_free_flight())
	assert_false(flow.start_loading(_free_flight(5)), "already loading")
	assert_eq(int(flow.request["seed"]), 0, "the refused request is not taken")
	assert_false(flow.enter_directly(_free_flight()), "not while loading")
	assert_false(flow.end_run({"success": true}), "not while loading")
	assert_eq(flow.state, GameFlow.State.LOADING)

	flow.finish_loading()
	assert_false(flow.enter_directly(_free_flight()), "only a fresh start enters directly")
	assert_false(flow.finish_loading(), "already in space")
	assert_false(flow.retry(), "retry is the debrief's")
	assert_eq(flow.state, GameFlow.State.IN_SPACE)

	flow.end_run({"success": true})
	assert_false(flow.end_run({"success": true}), "already in the debrief")
	assert_false(flow.finish_loading())
	assert_eq(flow.state, GameFlow.State.DEBRIEF)


func test_a_successful_move_clears_the_last_refusal() -> void:
	flow.finish_loading()
	assert_ne(flow.error, "")
	flow.start_loading(_free_flight())
	assert_eq(flow.error, "")


# --- Requests ------------------------------------------------------------------------------------------------------


func test_make_request_has_the_four_fields() -> void:
	var request: Dictionary = GameFlow.make_request(&"mission", &"civilian_escort", true, 42)
	assert_eq(request, {"kind": &"mission", "scenario_id": &"civilian_escort", "encounters": true, "seed": 42})
	assert_eq(GameFlow.make_request(&"sandbox", &"dogfight"),
			{"kind": &"sandbox", "scenario_id": &"dogfight", "encounters": false, "seed": 0}, "encounters off, seed 0")


func test_bad_requests_are_refused() -> void:
	assert_eq(GameFlow.validate_request(_free_flight()), "")
	assert_string_contains(GameFlow.validate_request(GameFlow.make_request(&"arcade", &"free_flight")), "kind")
	assert_string_contains(GameFlow.validate_request(GameFlow.make_request(&"sandbox", &"")), "scenario")
	assert_string_contains(GameFlow.validate_request({}), "kind")
	var no_seed: Dictionary = _free_flight()
	no_seed.erase("seed")
	assert_string_contains(GameFlow.validate_request(no_seed), "seed")
	assert_false(flow.start_loading(GameFlow.make_request(&"arcade", &"free_flight")))
	assert_false(flow.enter_directly({}))
	assert_eq(flow.state, GameFlow.State.FRONT_END)


func test_kind_for_a_scenario() -> void:
	assert_eq(GameFlow.kind_for(&"free_flight"), &"free_flight")
	for id: StringName in [&"combat_sandbox", &"dogfight", &"instructor_route"]:
		assert_eq(GameFlow.kind_for(id), &"sandbox", String(id))


func test_a_scenario_with_a_mission_block_is_a_mission() -> void:
	var text: String = JSON.stringify({"scenario_id": "civilian_escort", "mission": {"title": "Civilian escort"}})
	assert_eq(GameFlow.kind_for(&"civilian_escort", text), &"mission")
	assert_eq(GameFlow.kind_for(&"free_flight", JSON.stringify({"mission": {}})), &"free_flight", "an empty block is none")
	assert_eq(GameFlow.kind_for(&"dogfight", "{not json"), &"sandbox", "an unreadable file falls back")
	assert_eq(GameFlow.kind_for(&"no_such_scenario"), &"sandbox", "no file: the old rule")


func test_keep_result_leaves_the_state_alone() -> void:
	var result: Dictionary = {"success": true, "reason": "every primary objective done"}
	flow.keep_result(result)
	assert_eq(flow.last_result, result)
	assert_eq(flow.state, GameFlow.State.FRONT_END, "a run the flow did not start: no move")


func test_scenario_path() -> void:
	assert_eq(GameFlow.scenario_path(&"dogfight"), "res://data/scenarios/dogfight.json")


func test_describe_request_and_result_for_the_console() -> void:
	assert_eq(GameFlow.describe_request({}), "none")
	assert_eq(GameFlow.describe_request(GameFlow.make_request(&"sandbox", &"dogfight", false, 3)),
			"dogfight (sandbox), encounters off, seed 3")
	assert_eq(GameFlow.describe_request(GameFlow.make_request(&"free_flight", &"free_flight", true)),
			"free_flight (free_flight), encounters on, seed 0")
	assert_eq(GameFlow.describe_result({}), "none")
	assert_eq(GameFlow.describe_result({"success": true}), "success")
	assert_eq(GameFlow.describe_result({"success": false, "reason": "player destroyed"}), "failure: player destroyed")


func test_every_state_has_a_name() -> void:
	assert_eq(GameFlow.state_name(GameFlow.State.FRONT_END), "front_end")
	assert_eq(GameFlow.state_name(GameFlow.State.LOADING), "loading")
	assert_eq(GameFlow.state_name(GameFlow.State.IN_SPACE), "in_space")
	assert_eq(GameFlow.state_name(GameFlow.State.DEBRIEF), "debrief")


# --- The debrief (M5-T09, D56) -------------------------------------------------------------------------------------


func _mission(seed_value: int = 0) -> Dictionary:
	return GameFlow.make_request(&"mission", &"civilian_escort", false, seed_value)


func test_only_a_mission_has_a_debrief() -> void:
	assert_true(GameFlow.is_mission(_mission()))
	assert_false(GameFlow.is_mission(_free_flight()))
	assert_false(GameFlow.is_mission(GameFlow.make_request(&"sandbox", &"dogfight")))
	assert_false(GameFlow.is_mission({}), "nothing was asked for")


func test_the_debrief_is_offered_after_a_mission_ends() -> void:
	flow.enter_directly(_mission(4))
	assert_eq(flow.debrief_problem(), "no debrief yet: the run is not over", "still in space")
	flow.end_run({"success": true, "reason": "every primary objective done"})
	assert_eq(flow.debrief_problem(), "")


func test_no_debrief_without_a_mission_or_a_result() -> void:
	flow.enter_directly(_free_flight())
	flow.end_run({"success": true})
	assert_string_contains(flow.debrief_problem(), "not a mission")
	flow.open_menu()
	assert_string_contains(flow.debrief_problem(), "run is not over", "back at the front end")
	var empty := GameFlow.new()
	empty.enter_directly(_mission())
	empty.end_run({})
	assert_string_contains(empty.debrief_problem(), "no result", "a debrief with nothing to say never opens")


func test_retry_of_a_mission_keeps_its_seed_and_encounters() -> void:
	flow.enter_directly(GameFlow.make_request(&"mission", &"civilian_escort", true, 123))
	flow.end_run({"success": false, "reason": "player destroyed"})
	assert_true(flow.retry())
	assert_eq(flow.request, GameFlow.make_request(&"mission", &"civilian_escort", true, 123))
	assert_eq(flow.state, GameFlow.State.LOADING)


# --- Boot routing --------------------------------------------------------------------------------------------------


func _route(engine_args: Array, user_args: Array, headless: bool = false, skip: bool = false) -> Dictionary:
	return GameFlow.boot_route(PackedStringArray(engine_args), PackedStringArray(user_args), headless, skip)


func test_a_plain_windowed_launch_goes_to_the_front_end() -> void:
	var route: Dictionary = _route(["--path", "."], [])
	assert_false(route["straight"])
	assert_eq(route["reason"], "")
	assert_eq(route["scenario"], "")


func test_headless_goes_straight_to_main() -> void:
	assert_eq(_route([], [], true), {"straight": true, "reason": "headless", "scenario": ""}, "the display server says so")
	assert_eq(_route(["--headless", "--path", "."], [])["reason"], "headless", "or the engine arguments do")


func test_console_scripts_go_straight_to_main() -> void:
	assert_eq(_route([], ["--console-exec=wait 30; quit"])["reason"], "console-exec")
	assert_eq(_route([], ["--console-exec", "quit"])["reason"], "console-exec", "the two-token form too")
	assert_eq(_route([], ["--console-file=user://smoke.cfg"])["reason"], "console-file")
	assert_eq(_route([], ["--console-file", "smoke.cfg"])["reason"], "console-file")
	assert_true(_route([], ["--console-strict", "--console-exec=bench quick"])["straight"], "the M4 benchmark")


func test_the_scenario_argument_goes_straight_to_main_and_names_the_scenario() -> void:
	assert_eq(_route([], ["--scenario=free_flight"]), {"straight": true, "reason": "scenario", "scenario": "free_flight"})
	assert_eq(_route(["--scenario=dogfight"], [])["scenario"], "dogfight", "also before the --")
	var both: Dictionary = _route([], ["--scenario=free_flight"], true)
	assert_eq(both["reason"], "headless", "the first reason wins")
	assert_eq(both["scenario"], "free_flight", "the scenario is still taken")


func test_skip_front_end_goes_straight_to_main() -> void:
	assert_eq(_route([], [], false, true), {"straight": true, "reason": "skip_front_end", "scenario": ""})


func test_other_arguments_do_not_skip_the_front_end() -> void:
	assert_false(_route(["--resolution", "960x540", "--rendering-driver", "vulkan"], [])["straight"])
	assert_false(_route([], ["--console-strict"])["straight"], "strict alone runs no script")
	assert_false(_route([], ["scene=quiet", "--console-exec-not"])["straight"])
	assert_false(_route([], ["--console-exec"])["straight"], "a flag with no script after it runs nothing")
