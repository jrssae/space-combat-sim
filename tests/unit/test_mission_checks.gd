extends GutTest
## `MissionApi.check` and `run_checks` (M8 D80, AC3): a step waits until the player has passed each check; the hint is said
## as a comms line and repeated, the demo is asked for, a skipped step passes them at once, an unbound check is left out.

const DT: float = 1.0 / 60.0


## Runs two checks, one after the other, then one alone.
class Lesson extends MissionScript:
	var trace: Array[String] = []

	func steps() -> Array[StringName]:
		return [&"basics", &"lights"]

	func step_basics(m: MissionApi) -> void:
		await m.run_checks([&"assist_off", &"roll"])
		trace.append("basics done")

	func step_lights(m: MissionApi) -> void:
		await m.check(&"lights")
		trace.append("lights done")


## Asks for a check the book lacks and one the layout does not bind.
class Odd extends MissionScript:
	var trace: Array[String] = []

	func steps() -> Array[StringName]:
		return [&"odd"]

	func step_odd(m: MissionApi) -> void:
		await m.run_checks([&"unbound"])
		trace.append("unbound left out")
		await m.check(&"no_such_check")
		trace.append("went on")


var world: MissionWorld
var api: MissionApi
var state: Dictionary
var demos: Array[String] = []


func before_all() -> void:
	ControlProfiles.store.default_profile().apply_to_input_map()


func before_each() -> void:
	world = MissionWorld.new()
	api = MissionApi.new(world, ObjectiveBook.new())
	api.check_book = _checks()
	api.dialog_book = _dialog()
	state = {"assist": true, "lights": true}
	demos = []
	api.demo_requested.connect(func(check_id: StringName, demo: StringName) -> void: demos.append("%s %s" % [check_id, demo]))


func after_each() -> void:
	api.release()


func _checks() -> ControlCheckBook:
	var book := ControlCheckBook.new()
	assert_eq(book.add({"defaults": {"repeat_s": 2.0}, "checks": [
		{"id": "assist_off", "label": "ASSIST OFF", "actions": ["toggle_flight_assist"], "kind": "state",
			"when": [{"field": "assist", "op": "equals", "value": false}], "hint_line": "say_assist"},
		{"id": "roll", "label": "ROLL", "actions": ["roll_left", "roll_right"], "kind": "rotation", "turn": "roll", "min_deg": 90,
			"hint_line": "say_roll", "demo": "roll"},
		{"id": "lights", "label": "LIGHTS", "actions": ["toggle_running_lights"], "kind": "state",
			"when": [{"field": "lights", "op": "changed"}], "hint_line": "not_in_the_dialog"},
		{"id": "unbound", "label": "AHEAD", "actions": ["target_ahead"], "kind": "state", "when": [{"field": "target", "op": "set"}]},
	]}, "t"), "")
	return book


func _dialog() -> DialogBook:
	var book := DialogBook.new()
	assert_eq(book.add_speakers({"speakers": [{"id": "teacher", "name": "Teacher", "callsign": "TEACHER", "faction": "earth_alliance"}]},
			"t"), "")
	assert_eq(book.add_lines({"lines": [
		{"id": "say_assist", "speaker": "teacher", "text": "Assist off.", "voice": "v", "hold_s": 1.0},
		{"id": "say_roll", "speaker": "teacher", "text": "Roll.", "voice": "v", "hold_s": 1.0}]}, "t"), "")
	return book


# Ticks the mission with the measured state and the held events, and the ship rolling at `roll_dps`.
func _ticks(count: int, events: Array = [], roll_dps: float = 0.0) -> void:
	for _i: int in count:
		var sample := ControlCheckSample.new()
		sample.state = state.duplicate()
		sample.angular_velocity = Vector3.BACK * deg_to_rad(roll_dps)
		for event: Variant in events:
			sample.events[StringName(str(event))] = true
		api.check_sample = sample
		api.tick(DT, {})


func test_a_step_waits_until_each_check_has_passed() -> void:
	var script := Lesson.new()
	assert_eq(api.begin(script), "")
	assert_eq(api.checks.current.id, &"assist_off", "open at once")
	_ticks(1)
	assert_eq(api.dialog.current.id, &"say_assist", "the instructor says the hint as a comms line")
	assert_has(api.journal, "check assist_off hint")
	_ticks(30)
	assert_eq(script.trace, [] as Array[String], "the step waits")
	state["assist"] = false
	_ticks(1, ["toggle_flight_assist"])
	assert_has(api.journal, "check assist_off passed")
	assert_eq(api.checks.current.id, &"roll", "the next opens on the same tick")
	_ticks(61, ["roll_right"], 90.0)
	assert_eq(script.trace, ["basics done"] as Array[String], "the list done, the await resolves")
	assert_eq(api.step_name(), &"lights")
	assert_eq(api.checks.current.id, &"lights", "and the next step's check is open")
	state["lights"] = false
	_ticks(2, ["toggle_running_lights"])
	assert_eq(script.trace, ["basics done", "lights done"] as Array[String])
	assert_false(api.checks.is_active())
	assert_eq(api.checks.passed_ids, [&"assist_off", &"roll", &"lights"] as Array[StringName])


func test_a_missed_check_repeats_and_then_asks_for_the_demo_and_never_fails() -> void:
	var script := Lesson.new()
	assert_eq(api.begin(script), "")
	state["assist"] = false
	_ticks(2, ["toggle_flight_assist"])
	assert_eq(api.checks.current.id, &"roll")
	_ticks(125)
	assert_eq(api.journal.count("check roll hint"), 2, "after 2 s the hint again")
	assert_eq(demos, [] as Array[String])
	_ticks(120)
	assert_eq(demos, ["roll roll"], "after another 2 s the instructor is asked to show it")
	assert_has(api.journal, "check roll demo roll")
	_ticks(600)
	assert_true(api.is_running(), "ten seconds on: still waiting, the mission has not failed")
	assert_eq(api.journal.count("check roll hint"), 2)
	assert_eq(demos.size(), 1)
	_ticks(61, ["roll_left"], -90.0)
	assert_eq(script.trace, ["basics done"] as Array[String])


func test_a_hint_without_a_dialog_line_still_runs_the_check() -> void:
	var script := Lesson.new()
	assert_eq(api.begin(script), "")
	assert_eq(api.goto(&"lights"), "")
	_ticks(2)
	assert_eq(api.checks.current.id, &"lights")
	assert_null(api.dialog.current, "its line is not in this mission's dialog: nothing is said")
	assert_has(api.journal, "check lights hint")


func test_a_skipped_step_passes_its_checks_at_once() -> void:
	var script := Lesson.new()
	assert_eq(api.begin(script), "")
	_ticks(1)
	assert_eq(api.skip(), "")
	assert_eq(script.trace, ["basics done"] as Array[String])
	assert_has(api.journal, "check assist_off passed")
	assert_has(api.journal, "check roll passed")
	assert_eq(api.checks.current.id, &"lights", "the next step is played, not skipped")
	_ticks(2)
	assert_eq(script.trace, ["basics done"] as Array[String])


func test_goto_skips_checks_that_never_opened() -> void:
	var script := Lesson.new()
	assert_eq(api.begin(script), "")
	assert_eq(api.goto(&"lights"), "")
	assert_eq(api.checks.passed_ids, [&"assist_off", &"roll"] as Array[StringName])
	assert_eq(api.journal.count("check roll hint"), 0, "nothing was asked of the player")


func test_an_unbound_check_is_left_out_and_an_unknown_one_is_an_error() -> void:
	var script := Odd.new()
	assert_eq(api.begin(script), "")
	assert_has(api.journal, "check unbound left out: not bound")
	assert_push_error("no control check 'no_such_check'")
	assert_eq(script.trace, ["unbound left out", "went on"] as Array[String], "neither holds the mission up")


func test_ending_the_mission_drops_the_open_check() -> void:
	var script := Lesson.new()
	assert_eq(api.begin(script), "")
	_ticks(1)
	api.end(false, "player destroyed")
	assert_false(api.checks.is_active())
	_ticks(5)
	assert_eq(script.trace, [] as Array[String])
