extends GutTest
## `data/checks/controls.json` (M8 D79, D80): the file loads, holds every check the tutorial's script lists, in the order it
## teaches them, and each entry names real actions, a hint line of its own and a real demo. `ControlCheckBook` refuses a bad
## file whole.

## Every control D79 has the instructor check (beats 4 to 9), by the check that covers it.
const D79_CHECKS: Array[StringName] = [
	&"autotrack_off", &"pitch", &"yaw", &"roll", &"main_pods", &"retros", &"strafe_left", &"strafe_right", &"strafe_up",
	&"strafe_down", &"assist_off", &"assist_on", &"brake",
	&"camera_to_chase", &"camera_to_cockpit", &"free_look", &"running_lights",
	&"autotrack", &"interact",
	&"target_menu",
	&"target_next", &"fire_linked", &"fire_alternating",
	&"wing_form", &"wing_attack", &"wing_cover",
]

var book: ControlCheckBook


func before_each() -> void:
	var made: Dictionary = ControlCheckBook.load_file()
	assert_true(bool(made["ok"]), str(made["error"]))
	book = made["book"]


func test_the_file_holds_every_check_of_the_tutorial_script_in_its_order() -> void:
	assert_eq(book.ids(), D79_CHECKS)


func test_each_check_has_a_label_real_actions_and_its_own_hint_line() -> void:
	var lines: Dictionary = {}
	for id: StringName in book.ids():
		var check: ControlCheck = book.make(id)
		assert_eq(check.label, check.label.to_upper(), "%s: the HUD's capitals" % id)
		for action: StringName in check.actions:
			assert_true(InputMap.has_action(action), "%s: %s is an input action" % [id, action])
		assert_eq(check.hint_line, StringName("check_%s" % id), "%s: its line in the dialog file" % id)
		assert_false(lines.has(check.hint_line))
		lines[check.hint_line] = true
		assert_gt(check.repeat_s, 5.0, "%s: time to try before the hint comes again" % id)


func test_the_moves_the_instructor_can_show_have_their_demo() -> void:
	var demos: Dictionary = {}
	for id: StringName in book.ids():
		var check: ControlCheck = book.make(id)
		if check.demo != &"":
			demos[id] = check.demo
			assert_not_null(Manoeuvres.create(check.demo), "%s: %s is one of D37's moves" % [id, check.demo])
	assert_eq(demos, {&"roll": &"roll", &"strafe_left": &"strafe_box", &"strafe_right": &"strafe_box", &"strafe_up": &"strafe_box",
			&"strafe_down": &"strafe_box", &"brake": &"all_stop"})


func test_make_hands_out_a_fresh_check_each_time() -> void:
	var first: ControlCheck = book.make(&"brake")
	first.force()
	var again: ControlCheck = book.make(&"brake")
	assert_ne(first, again)
	assert_false(again.passed, "a check can be run again")
	assert_eq(again.repeat_s, 20.0, "the file's default")
	assert_null(book.make(&"warp_drive"))
	assert_false(book.has(&"warp_drive"))
	assert_true(book.has(&"brake"))


func test_a_bad_file_is_refused_whole_with_the_entry_named() -> void:
	var fresh := ControlCheckBook.new()
	var good: Dictionary = {"id": "a", "label": "A", "actions": ["brake"], "kind": "state", "when": [{"field": "assist", "op": "set"}]}
	var bad: Dictionary = good.duplicate()
	bad["id"] = "b"
	bad["kind"] = "magic"
	assert_string_contains(fresh.add({"checks": [good, bad]}, "t.json"), "t.json: checks[1]: b: kind must be")
	assert_eq(fresh.ids(), [] as Array[StringName], "nothing of a refused file is kept")
	assert_string_contains(fresh.add({"checks": [good, good]}, "t.json"), "'a' is defined twice")
	assert_string_contains(fresh.add([], "t.json"), "expected {\"checks\"")
	assert_string_contains(fresh.add({"checks": [], "defaults": 3}, "t.json"), "defaults must be")
	assert_eq(fresh.add({"defaults": {"repeat_s": 7}, "checks": [good]}, "t.json"), "")
	assert_eq(fresh.make(&"a").repeat_s, 7.0)
	assert_string_contains(fresh.add({"checks": [good]}, "u.json"), "'a' is defined twice")
	assert_false(bool(ControlCheckBook.load_file("res://data/checks/nope.json")["ok"]))
