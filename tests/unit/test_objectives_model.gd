extends GutTest
## ObjectivesModel (architecture §18, D57, Q15): what the menu frame's right panel says, from the objectives a running mission
## reports (hidden ones left out) or, with none, from what is being played. Pure.


func _objective(id: StringName, text: String, state: StringName, primary: bool = true) -> Dictionary:
	return {"id": id, "text": text, "primary": primary, "state": state}


func _objectives(list: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(list)
	return out


# --- Objective lines ---------------------------------------------------------------------------------------------


func test_hidden_objectives_are_not_shown_and_the_order_is_kept() -> void:
	var lines: Array[Dictionary] = ObjectivesModel.lines(_objectives([
		_objective(&"defend", "Defend the buoy", &"active"),
		_objective(&"secret", "A surprise", &"hidden"),
		_objective(&"survive", "Survive", &"active"),
	]))
	assert_eq(lines.size(), 2)
	assert_eq(lines[0]["text"], "Defend the buoy")
	assert_eq(lines[1]["text"], "Survive")


func test_each_state_has_its_own_mark() -> void:
	var marks: Dictionary = {}
	for state: StringName in [&"active", &"done", &"failed"]:
		var lines: Array[Dictionary] = ObjectivesModel.lines(_objectives([_objective(&"o", "x", state)]))
		marks[state] = lines[0]["mark"]
		assert_eq(lines[0]["state"], state)
	assert_eq(marks.values().size(), 3, "three states")
	assert_ne(marks[&"active"], marks[&"done"])
	assert_ne(marks[&"done"], marks[&"failed"])
	assert_ne(marks[&"active"], marks[&"failed"])


func test_an_optional_objective_says_so() -> void:
	var lines: Array[Dictionary] = ObjectivesModel.lines(_objectives([
		_objective(&"a", "Defend the buoy", &"active", true),
		_objective(&"b", "Lose no wingman", &"active", false),
	]))
	assert_false(bool(lines[0]["optional"]))
	assert_true(bool(lines[1]["optional"]))
	assert_string_contains(String(lines[1]["text"]), "optional")
	assert_false("optional" in String(lines[0]["text"]))


func test_an_objective_with_no_text_shows_its_id() -> void:
	var lines: Array[Dictionary] = ObjectivesModel.lines(_objectives([{"id": &"defend", "state": &"active"}]))
	assert_eq(lines[0]["text"], "defend")


func test_an_unknown_state_is_not_shown() -> void:
	assert_eq(ObjectivesModel.lines(_objectives([_objective(&"o", "x", &"sideways")])).size(), 0)
	assert_eq(ObjectivesModel.lines(_objectives([{"id": &"o", "text": "x"}])).size(), 0, "no state at all")


# --- What the panel says -----------------------------------------------------------------------------------------


func test_with_objectives_the_panel_lists_them() -> void:
	var content: Dictionary = ObjectivesModel.content(
			_objectives([_objective(&"defend", "Defend the buoy", &"active")]),
			GameFlow.make_request(&"mission", &"buoy_defence"))
	assert_eq(content["title"], "OBJECTIVES")
	assert_eq(content["lines"].size(), 1)
	assert_eq(content["lines"][0]["text"], "Defend the buoy")


func test_free_flight_says_so_and_whether_encounters_are_on() -> void:
	var on: Dictionary = ObjectivesModel.content(_objectives([]), GameFlow.make_request(&"free_flight", &"free_flight", true))
	var off: Dictionary = ObjectivesModel.content(_objectives([]), GameFlow.make_request(&"free_flight", &"free_flight", false))
	assert_eq(on["title"], "OBJECTIVES")
	assert_eq(on["lines"][0]["text"], "Free flight")
	assert_eq(on["lines"][1]["text"], "Encounters: on")
	assert_eq(off["lines"][1]["text"], "Encounters: off")


func test_a_sandbox_names_the_scenario() -> void:
	var content: Dictionary = ObjectivesModel.content(_objectives([]), GameFlow.make_request(&"sandbox", &"combat_sandbox"))
	assert_eq(content["lines"][0]["text"], "Sandbox: Combat Sandbox")
	assert_eq(content["lines"].size(), 1, "no encounters line: the sandbox has its own waves")


func test_a_mission_with_nothing_to_show_yet_says_so() -> void:
	var content: Dictionary = ObjectivesModel.content(
			_objectives([_objective(&"later", "Later", &"hidden")]), GameFlow.make_request(&"mission", &"buoy_defence"))
	assert_eq(content["lines"][0]["text"], "Mission: Buoy Defence")
	assert_eq(content["lines"].size(), 1)


func test_with_no_request_and_no_objectives_the_panel_is_empty() -> void:
	var content: Dictionary = ObjectivesModel.content(_objectives([]), {})
	assert_eq(content["lines"].size(), 0)


func test_a_briefing_is_a_titled_paragraph() -> void:
	var content: Dictionary = ObjectivesModel.briefing("Buoy defence", "Raiders are coming.\nHold the line.")
	assert_eq(content["title"], "BRIEFING")
	assert_eq(content["lines"][0]["text"], "Buoy defence")
	assert_eq(content["lines"][1]["text"], "Raiders are coming.")
	assert_eq(content["lines"][2]["text"], "Hold the line.")
	for line: Dictionary in content["lines"]:
		assert_eq(line["mark"], "", "a briefing has no state marks")


func test_a_briefing_with_no_text_is_empty() -> void:
	assert_eq(ObjectivesModel.briefing("", "")["lines"].size(), 0)
