extends GutTest
## DebriefModel (M5-T09, D56, AC9): what the debrief says, built from a finished mission's result: success or failure and why,
## every objective and its state, the mission time, the player's kills and assists, wing losses, shots and hits.


func _objectives() -> Array[Dictionary]:
	return [
		{"id": &"reach", "text": "Fly to NAV ALPHA", "primary": true, "state": &"done"},
		{"id": &"raiders", "text": "Destroy the raiders", "primary": true, "state": &"done"},
		{"id": &"protect", "text": "Keep NAV ALPHA in one piece", "primary": false, "state": &"failed"},
		{"id": &"report", "text": "Report to Control", "primary": true, "state": &"active"},
		{"id": &"bonus", "text": "Take no damage", "primary": false, "state": &"hidden"},
	]


func _result(overrides: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {
		"success": true, "reason": "every primary objective done", "scenario_id": &"test_mission", "title": "Test Mission",
		"objectives": _objectives(), "time_s": 252.4,
		"kills": 2, "assists": 1, "wing_losses": 1, "shots_fired": 120, "shots_hit": 54,
	}
	result.merge(overrides, true)
	return result


func _texts(model: DebriefModel) -> PackedStringArray:
	var out := PackedStringArray()
	for line: Dictionary in model.panel()["lines"]:
		out.append(line["text"])
	return out


func _text_with(model: DebriefModel, needle: String) -> String:
	for text: String in _texts(model):
		if text.contains(needle):
			return text
	return ""


# --- Reading the result ----------------------------------------------------------------------------------------


func test_a_success_reads_its_result_and_counts() -> void:
	var model := DebriefModel.from_result(_result())
	assert_true(model.success)
	assert_eq(model.headline(), "MISSION COMPLETE")
	assert_eq(model.title, "Test Mission")
	assert_eq(model.scenario_id, &"test_mission")
	assert_almost_eq(model.time_s, 252.4, 1e-6)
	assert_eq([model.kills, model.assists, model.wing_losses], [2, 1, 1])
	assert_eq([model.shots_fired, model.shots_hit], [120, 54])


func test_a_failure_says_so() -> void:
	var model := DebriefModel.from_result(_result({"success": false, "reason": "player destroyed"}))
	assert_false(model.success)
	assert_eq(model.headline(), "MISSION FAILED")
	assert_eq(model.result_text(), "Failure - Player destroyed")


func test_a_success_gives_its_reason() -> void:
	assert_eq(DebriefModel.from_result(_result()).result_text(), "Success - Every primary objective done")


func test_a_result_with_no_reason_is_just_the_verdict() -> void:
	assert_eq(DebriefModel.from_result(_result({"reason": ""})).result_text(), "Success")
	assert_eq(DebriefModel.from_result(_result({"success": false, "reason": ""})).result_text(), "Failure")


func test_a_failed_objective_is_named_by_its_text_not_its_id() -> void:
	var model := DebriefModel.from_result(_result({"success": false, "reason": "objective failed: protect"}))
	assert_eq(model.result_text(), "Failure - Objective failed: Keep NAV ALPHA in one piece")


func test_a_failed_objective_with_an_unknown_id_keeps_the_reason_as_given() -> void:
	var model := DebriefModel.from_result(_result({"success": false, "reason": "objective failed: ghost"}))
	assert_eq(model.result_text(), "Failure - Objective failed: ghost")


func test_a_result_with_no_stats_reads_zeros() -> void:
	var model := DebriefModel.from_result({"success": true, "reason": "scripted", "time_s": 3.0})
	assert_eq([model.kills, model.assists, model.wing_losses, model.shots_fired, model.shots_hit], [0, 0, 0, 0, 0])
	assert_eq(model.objectives.size(), 0)
	assert_eq(model.title, "")


func test_an_empty_result_is_no_debrief() -> void:
	assert_null(DebriefModel.from_result({}), "nothing ended, nothing to show")


func test_the_model_does_not_alias_the_result() -> void:
	var result: Dictionary = _result()
	var model := DebriefModel.from_result(result)
	(result["objectives"] as Array[Dictionary])[0]["state"] = &"failed"
	assert_eq(model.objectives[0]["state"], &"done")


# --- Objectives ------------------------------------------------------------------------------------------------


func test_every_objective_is_listed_with_its_state_hidden_ones_too() -> void:
	var model := DebriefModel.from_result(_result())
	assert_eq(model.objectives.size(), 5, "the debrief shows what was never reached as well")
	var states: Array[StringName] = []
	for row: Dictionary in model.objectives:
		states.append(row["state"])
	assert_eq(states, [&"done", &"done", &"failed", &"active", &"hidden"] as Array[StringName])


func test_objective_rows_carry_a_word_for_the_state() -> void:
	var model := DebriefModel.from_result(_result())
	var words: Array[String] = []
	for row: Dictionary in model.objectives:
		words.append(row["state_text"])
	assert_eq(words, ["done", "done", "failed", "not finished", "not reached"] as Array[String])


func test_the_panel_marks_each_objective_and_names_the_unfinished_ones() -> void:
	var lines: Array = DebriefModel.from_result(_result()).panel()["lines"]
	var by_text: Dictionary = {}
	for line: Dictionary in lines:
		by_text[line["text"]] = line
	assert_eq(by_text["Fly to NAV ALPHA"]["mark"], "[x]")
	assert_eq(by_text["Fly to NAV ALPHA"]["state"], &"done")
	assert_eq(by_text["Keep NAV ALPHA in one piece (optional)"]["mark"], "[!]")
	assert_eq(by_text["Keep NAV ALPHA in one piece (optional)"]["state"], &"failed")
	assert_eq(by_text["Report to Control - not finished"]["mark"], "[ ]")
	assert_eq(by_text["Take no damage (optional) - not reached"]["mark"], "[-]")
	assert_true(by_text["Take no damage (optional) - not reached"]["optional"])
	assert_false(by_text["Fly to NAV ALPHA"]["optional"])


func test_an_objective_with_no_text_falls_back_to_its_id() -> void:
	var model := DebriefModel.from_result(_result({"objectives": [{"id": &"x", "text": "", "primary": true, "state": &"done"}] as Array[Dictionary]}))
	assert_has(_texts(model), "x")


# --- Time and accuracy -----------------------------------------------------------------------------------------


func test_time_reads_minutes_and_seconds() -> void:
	assert_eq(DebriefModel.format_time(0.0), "0:00")
	assert_eq(DebriefModel.format_time(59.9), "0:59", "whole seconds, rounded down")
	assert_eq(DebriefModel.format_time(252.4), "4:12")
	assert_eq(DebriefModel.format_time(3725.0), "1:02:05", "an hour or more shows hours")
	assert_eq(DebriefModel.format_time(-5.0), "0:00", "never negative")


func test_accuracy_is_a_whole_percent() -> void:
	assert_eq(DebriefModel.from_result(_result()).accuracy_text(), "45%")
	assert_eq(DebriefModel.from_result(_result({"shots_fired": 3, "shots_hit": 1})).accuracy_text(), "33%")
	assert_eq(DebriefModel.from_result(_result({"shots_fired": 0, "shots_hit": 0})).accuracy_text(), "no shots fired")


func test_hits_never_read_above_the_shots_fired() -> void:
	var model := DebriefModel.from_result(_result({"shots_fired": 2, "shots_hit": 5}))
	assert_lte(model.accuracy(), 1.0)


# --- The panel -------------------------------------------------------------------------------------------------


func test_the_panel_says_everything_the_debrief_promises() -> void:
	var model := DebriefModel.from_result(_result())
	var panel: Dictionary = model.panel()
	assert_eq(panel["title"], "DEBRIEF")
	assert_true(panel["compact"], "a debrief is long: its lines are set small")
	var texts: PackedStringArray = _texts(model)
	assert_has(texts, "Test Mission")
	assert_has(texts, "Success - Every primary objective done")
	assert_has(texts, "Time: 4:12")
	assert_has(texts, "Kills: 2   Assists: 1")
	assert_has(texts, "Wing losses: 1")
	assert_has(texts, "Shots: 120 fired, 54 hit (45%)")


func test_the_result_line_is_green_for_a_success_and_red_for_a_failure() -> void:
	var success: Dictionary = DebriefModel.from_result(_result()).panel()["lines"][1]
	assert_eq(success["text"], "Success - Every primary objective done")
	assert_eq(success["state"], &"done")
	var failure: Dictionary = DebriefModel.from_result(_result({"success": false, "reason": "player destroyed"})).panel()["lines"][1]
	assert_eq(failure["state"], &"failed")


func test_a_mission_with_no_title_leaves_the_title_line_out() -> void:
	var lines: Array = DebriefModel.from_result(_result({"title": ""})).panel()["lines"]
	assert_eq(lines[0]["text"], "Success - Every primary objective done", "the verdict is the first line")


func test_no_shots_reads_plainly() -> void:
	var model := DebriefModel.from_result(_result({"shots_fired": 0, "shots_hit": 0}))
	assert_eq(_text_with(model, "Shots:"), "Shots: none fired")


func test_the_summary_is_one_value_per_key_for_the_console() -> void:
	var summary: Dictionary = DebriefModel.from_result(_result()).summary()
	assert_eq(summary["result"], "success")
	assert_eq(summary["reason"], "every primary objective done")
	assert_eq(summary["time"], "4:12")
	assert_eq(summary["kills"], 2)
	assert_eq(summary["assists"], 1)
	assert_eq(summary["wing_losses"], 1)
	assert_eq(summary["shots_fired"], 120)
	assert_eq(summary["shots_hit"], 54)
	assert_eq(summary["accuracy"], "45%")
	assert_eq(summary["objectives"], "reach done, raiders done, protect failed, report active, bonus hidden")
