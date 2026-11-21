extends GutTest
## `ControlCheck` (M8 D80, AC3): each kind of pass condition on measured state, with injected samples. A check passes only
## when its command events and the ship's measured motion or state agree; it never fails, it only stays open.

const DT: float = 1.0 / 60.0

var velocity: Vector3
var basis: Basis
var spin: Vector3
var state: Dictionary


func before_each() -> void:
	velocity = Vector3.ZERO
	basis = Basis.IDENTITY
	spin = Vector3.ZERO
	state = {}


func _check(entry: Dictionary) -> ControlCheck:
	var made: Dictionary = ControlCheck.from_dict(entry)
	assert_true(bool(made["ok"]), str(made["error"]))
	return made["check"] as ControlCheck


func _sample(events: Array = []) -> ControlCheckSample:
	var sample := ControlCheckSample.new()
	sample.velocity = velocity
	sample.basis = basis
	sample.angular_velocity = spin
	sample.state = state.duplicate()
	for event: Variant in events:
		sample.events[StringName(str(event))] = true
	return sample


func _main_pods() -> ControlCheck:
	return _check({"id": "main_pods", "label": "MAIN PODS", "actions": ["main_left", "main_right"], "need": "all",
			"kind": "velocity", "direction": "forward", "min_mps": 10.0})


# --- velocity ---------------------------------------------------------------------------------------------------------


func test_main_pods_pass_when_the_ship_gains_speed_along_its_nose_with_both_held() -> void:
	var check: ControlCheck = _main_pods()
	var ticks: int = 0
	while not check.observe(_sample(["main_left", "main_right"]), DT) and ticks < 200:
		velocity += basis * Vector3.FORWARD * 20.0 * DT
		ticks += 1
	assert_true(check.passed)
	assert_between(ticks, 30, 32, "10 m/s at 20 m/s2 is half a second")
	assert_eq(check.progress, 1.0)


func test_one_pod_alone_does_not_pass_a_check_that_needs_both() -> void:
	var check: ControlCheck = _main_pods()
	for _i: int in 120:
		check.observe(_sample(["main_left"]), DT)
		velocity += Vector3.FORWARD * 20.0 * DT
	assert_false(check.passed, "the ship gained speed, but on one pod")
	assert_eq(check.progress, 0.0)


func test_speed_gained_without_the_control_does_not_count() -> void:
	var check: ControlCheck = _main_pods()
	for _i: int in 120:
		check.observe(_sample(), DT)
		velocity += Vector3.FORWARD * 20.0 * DT
	assert_false(check.passed, "something else pushed the ship")


func test_the_gain_is_measured_in_the_ships_own_frame() -> void:
	basis = Basis(Vector3.UP, deg_to_rad(90.0))  # the nose points along the World's -X
	var check: ControlCheck = _main_pods()
	for _i: int in 60:
		check.observe(_sample(["main_left", "main_right"]), DT)
		velocity += Vector3.FORWARD * 20.0 * DT  # along the World's -Z: sideways for this ship
	assert_false(check.passed, "a push across the nose is not the main pods")
	check = _main_pods()
	for _i: int in 60:
		check.observe(_sample(["main_left", "main_right"]), DT)
		velocity += basis * Vector3.FORWARD * 20.0 * DT
	assert_true(check.passed, "along its own nose it is")


func test_the_wrong_way_does_not_pass() -> void:
	var check: ControlCheck = _check({"id": "strafe_left", "label": "STRAFE LEFT", "actions": ["strafe_left"],
			"kind": "velocity", "direction": "left", "min_mps": 3.0})
	for _i: int in 60:
		check.observe(_sample(["strafe_left"]), DT)
		velocity += Vector3.RIGHT * 10.0 * DT
	assert_false(check.passed)
	for _i: int in 120:
		check.observe(_sample(["strafe_left"]), DT)
		velocity += Vector3.LEFT * 10.0 * DT
	assert_true(check.passed, "it has to make up what it lost, then gain 3 m/s to the left")


func test_the_tick_after_a_release_still_counts() -> void:
	var check: ControlCheck = _check({"id": "retros", "label": "RETROS", "actions": ["retro_left"],
			"kind": "velocity", "direction": "back", "min_mps": 1.0})
	check.observe(_sample(["retro_left"]), DT)
	velocity += Vector3.BACK * 2.0  # the force of that tick shows in the next sample
	assert_true(check.observe(_sample(), DT), "the motion a command causes arrives a tick later")


# --- rotation ---------------------------------------------------------------------------------------------------------


func test_a_roll_passes_either_way_and_only_while_the_control_is_used() -> void:
	for way: float in [1.0, -1.0]:
		var check: ControlCheck = _check({"id": "roll", "label": "ROLL", "actions": ["roll_left", "roll_right"],
				"kind": "rotation", "turn": "roll", "min_deg": 90.0})
		spin = Vector3.BACK * deg_to_rad(90.0) * way
		for _i: int in 30:
			check.observe(_sample(), DT)
		assert_eq(check.progress, 0.0, "spinning with no hand on the control")
		var ticks: int = 0
		while not check.observe(_sample(["roll_right"]), DT) and ticks < 200:
			ticks += 1
		assert_true(check.passed)
		assert_between(ticks, 58, 61, "90 degrees at 90 degrees a second")


func test_a_turn_about_another_axis_does_not_count() -> void:
	var check: ControlCheck = _check({"id": "pitch", "label": "PITCH", "actions": ["pitch_up", "pitch_down"],
			"kind": "rotation", "turn": "pitch", "min_deg": 30.0})
	spin = Vector3.UP * deg_to_rad(60.0)  # yawing
	for _i: int in 120:
		check.observe(_sample(["pitch_up"]), DT)
	assert_false(check.passed)
	spin = Vector3.RIGHT * deg_to_rad(-60.0)
	for _i: int in 40:
		check.observe(_sample(["pitch_down"]), DT)
	assert_true(check.passed)


# --- brake ------------------------------------------------------------------------------------------------------------


func _brake() -> ControlCheck:
	return _check({"id": "brake", "label": "BRAKE", "actions": ["brake"], "press": "hold",
			"kind": "brake", "hold_s": 1.0, "min_drop_mps": 10.0, "stop_mps": 1.0})


func test_the_brake_passes_when_held_and_the_ship_slows() -> void:
	var check: ControlCheck = _brake()
	velocity = Vector3(0.0, 0.0, -50.0)
	var ticks: int = 0
	while not check.observe(_sample(["brake"]), DT) and ticks < 300:
		velocity = velocity.move_toward(Vector3.ZERO, 8.0 * DT)
		ticks += 1
	assert_true(check.passed)
	assert_between(ticks, 74, 77, "a 10 m/s drop at 8 m/s2")


func test_a_brake_let_go_early_starts_over() -> void:
	var check: ControlCheck = _brake()
	velocity = Vector3(0.0, 0.0, -50.0)
	for _i: int in 50:
		check.observe(_sample(["brake"]), DT)
		velocity = velocity.move_toward(Vector3.ZERO, 30.0 * DT)
	assert_false(check.passed, "slowed enough, not held a second")
	check.observe(_sample(), DT)
	assert_eq(check.progress, 0.0, "let go")
	for _i: int in 59:
		check.observe(_sample(["brake"]), DT)
	assert_false(check.passed, "the new hold slowed nothing yet and is short of a second")
	velocity = Vector3.ZERO
	assert_true(check.observe(_sample(["brake"]), DT), "held a second, and stopped")


func test_a_brake_that_slows_nothing_stays_open() -> void:
	var check: ControlCheck = _brake()
	velocity = Vector3(0.0, 0.0, -50.0)
	for _i: int in 300:
		check.observe(_sample(["brake"]), DT)
	assert_false(check.passed, "held, but the ship flies on")


# --- state ------------------------------------------------------------------------------------------------------------


func test_a_flag_passes_once_its_action_was_seen_and_the_state_holds() -> void:
	var check: ControlCheck = _check({"id": "assist_off", "label": "ASSIST OFF", "actions": ["toggle_flight_assist"],
			"kind": "state", "when": [{"field": "assist", "op": "equals", "value": false}]})
	state["assist"] = false
	assert_false(check.observe(_sample(), DT), "off already, but the player did nothing")
	state["assist"] = true
	assert_false(check.observe(_sample(["toggle_flight_assist"]), DT), "pressed: now it is on")
	state["assist"] = false
	assert_true(check.observe(_sample(), DT), "pressed again a tick ago: off")


func test_changed_reads_against_the_state_the_check_began_with() -> void:
	var check: ControlCheck = _check({"id": "camera_switch", "label": "VIEW", "actions": ["toggle_camera"],
			"kind": "state", "when": [{"field": "camera", "op": "changed"}]})
	state["camera"] = "chase"
	assert_false(check.observe(_sample(["toggle_camera"]), DT))
	state["camera"] = &"cockpit"
	assert_true(check.observe(_sample(), DT))


func test_held_wants_the_action_on_the_same_tick() -> void:
	var check: ControlCheck = _check({"id": "free_look", "label": "LOOK", "actions": ["camera_look"], "held": true,
			"kind": "state", "when": [{"field": "look_deg", "op": "at_least", "value": 25}]})
	state["look_deg"] = 10.0
	assert_false(check.observe(_sample(["camera_look"]), DT), "not far enough")
	state["look_deg"] = 40.0
	assert_false(check.observe(_sample(), DT), "far enough, but the button is up")
	assert_true(check.observe(_sample(["camera_look"]), DT))


func test_a_hold_event_and_a_counter_tell_the_tap_from_the_hold() -> void:
	var tap: ControlCheck = _check({"id": "autotrack", "label": "TRACK", "actions": ["autotrack"], "press": "tap",
			"kind": "state", "when": [{"field": "tracking", "op": "equals", "value": true}]})
	var hold: ControlCheck = _check({"id": "interact", "label": "INTERACT", "actions": ["autotrack"], "press": "hold",
			"events": ["interact"], "kind": "state", "when": [{"field": "interactions", "op": "increased"}]})
	state = {"tracking": false, "interactions": 2}
	tap.observe(_sample(), DT)
	hold.observe(_sample(), DT)
	state["tracking"] = true  # a tap: auto-track comes on, nothing ran
	assert_true(tap.observe(_sample(["autotrack"]), DT))
	assert_false(hold.observe(_sample(["autotrack"]), DT), "a tap is not the hold")
	state["interactions"] = 3
	assert_true(hold.observe(_sample(["interact"]), DT), "the completed hold ran the interaction")


func test_a_check_with_no_events_reads_the_state_alone() -> void:
	var check: ControlCheck = _check({"id": "wing_form", "label": "FORM", "actions": ["comms_menu", "wing_form"], "events": [],
			"kind": "state", "when": [{"field": "wing_orders", "op": "increased"}, {"field": "wing_order", "op": "equals", "value": "form"}]})
	state = {"wing_orders": 4, "wing_order": "form"}
	assert_false(check.observe(_sample(), DT), "formed up before the check: no new order")
	state = {"wing_orders": 5, "wing_order": "cover"}
	assert_false(check.observe(_sample(), DT), "another order")
	state = {"wing_orders": 6, "wing_order": &"form"}
	assert_true(check.observe(_sample(), DT), "the order came from the menu while the game was paused: no event needed")


func test_set_wants_a_target_and_a_missing_field_never_passes() -> void:
	var check: ControlCheck = _check({"id": "target_ahead", "label": "AHEAD", "actions": ["target_ahead"],
			"kind": "state", "when": [{"field": "target", "op": "set"}]})
	assert_false(check.observe(_sample(["target_ahead"]), DT), "no state at all (the player is down)")
	state["target"] = 0
	assert_false(check.observe(_sample(), DT), "nothing ahead to select")
	state["target"] = 4711
	assert_true(check.observe(_sample(), DT))


# --- the rest ----------------------------------------------------------------------------------------------------------


func test_a_passed_check_stays_passed_and_force_passes_one() -> void:
	var check: ControlCheck = _main_pods()
	assert_false(check.forced)
	check.force()
	assert_true(check.passed and check.forced)
	assert_true(check.observe(_sample(), DT))
	assert_eq(check.progress, 1.0)


func test_describe_says_what_was_measured() -> void:
	var check: ControlCheck = _main_pods()
	check.observe(_sample(["main_left", "main_right"]), DT)
	velocity += Vector3.FORWARD * 2.5
	check.observe(_sample(["main_left", "main_right"]), DT)
	assert_eq(check.describe(), "velocity forward 2.5/10.0 m/s")
	assert_eq(_brake().describe(), "brake held 0.0/1.0 s")


func test_events_of_reads_the_command_never_input() -> void:
	var pc := PilotCommand.new()
	pc.flight.main_left = 0.2
	pc.flight.rot = Vector3(-0.15, 0.0, 0.3)
	pc.flight.strafe = Vector2(0.05, -1.0)
	pc.ui.interact = true
	pc.ui.target_menu_open = true
	pc.combat.target_nearest = true
	var events: Dictionary = ControlCheckSample.events_of(pc)
	for name: StringName in [&"main_left", &"pitch_down", &"roll_right", &"strafe_down", &"interact", &"target_menu", &"target_next"]:
		assert_true(events.has(name), "%s" % name)
	for name: StringName in [&"main_right", &"strafe_right", &"strafe_left", &"yaw_left", &"fire"]:
		assert_false(events.has(name), "%s" % name)
	assert_true(ControlCheckSample.events_of(null).is_empty())


func test_a_bad_entry_is_refused_with_its_reason() -> void:
	var base: Dictionary = {"id": "x", "label": "X", "actions": ["brake"], "kind": "state",
			"when": [{"field": "assist", "op": "equals", "value": true}]}
	assert_true(bool(ControlCheck.from_dict(base)["ok"]))
	var cases: Array[Array] = [
		[{"id": "Bad Id"}, "id must be"], [{"label": ""}, "label is missing"], [{"actions": ["warp"]}, "unknown name 'warp'"],
		[{"actions": []}, "actions is empty"], [{"actions": ["target_cycle"]}, "no command event"],
		[{"events": ["warp"]}, "events: unknown name"], [{"need": "both"}, "need must be"], [{"press": "mash"}, "press must be"],
		[{"kind": "magic"}, "kind must be"], [{"kind": "velocity", "direction": "north", "min_mps": 1}, "direction must be"],
		[{"kind": "velocity", "direction": "up"}, "min_mps must be"], [{"kind": "rotation", "turn": "spin", "min_deg": 1}, "turn must be"],
		[{"kind": "brake", "hold_s": 1, "min_drop_mps": 1}, "stop_mps must be"], [{"when": []}, "needs its conditions"],
		[{"when": [{"field": "shields", "op": "set"}]}, "no state field"], [{"when": [{"field": "assist", "op": "wobbles"}]}, "no condition"],
		[{"when": [{"field": "assist", "op": "equals"}]}, "needs a value"], [{"demo": "loop"}, "no demo"],
		[{"repeat_s": 0}, "repeat_s must be"], [{"colour": "red"}, "unknown key 'colour'"],
	]
	for case: Array in cases:
		var entry: Dictionary = base.duplicate()
		entry.merge(case[0] as Dictionary, true)
		var made: Dictionary = ControlCheck.from_dict(entry)
		assert_false(bool(made["ok"]), str(case[0]))
		assert_string_contains(str(made["error"]), str(case[1]))
	assert_false(bool(ControlCheck.from_dict("nope")["ok"]))
