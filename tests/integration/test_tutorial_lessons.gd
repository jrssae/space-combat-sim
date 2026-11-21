extends TutorialSteps
## The tutorial's lessons after the maintainer's play-test of 2026-11-21 (M8-T33): the launch is the opening cinematic and
## cuts to the two ships at rest in clear space, where the turns are taught before thrust and before anything is flown behind
## the instructor; auto-track is switched off first when it is on, and nothing is said when it is off; the view lesson asks
## for the view the pilot is not in; at the gate the pilot is told to target it, and the hold of X is called only once the
## gate takes the request. A line names a control as it is bound now, on the device the pilot is using.


func after_each() -> void:
	super.after_each()
	ControlProfiles.store.default_profile().apply_to_input_map()  # a test here rebinds


# --- the start in space ----------------------------------------------------------------------------------------------------


func test_the_launch_cuts_to_both_ships_at_rest_in_clear_space_and_the_turns_come_before_thrust() -> void:
	assert_eq(Script_.new().steps().slice(0, 3), [&"launch", &"flight_checks", &"camera_lights"] as Array[StringName],
			"the lessons follow the launch at once: no leg behind the instructor first")
	assert_eq(Script_.new().opening_until(), &"flight_checks")
	await _fly()
	assert_eq(_api().step_name(), &"launch")
	assert_true(main.launches.locks_controls(), "the opening is the two-ship launch, a cinematic")
	await _goto(&"flight_checks")
	assert_lt(_distance_to(Script_.LESSON_AT), 5.0, "the player is where the lessons start")
	assert_gt(_distance_to(Vector3.ZERO), 7000.0, "clear of the station")
	var instructor: Combatant = _ship("INSTRUCTOR")
	assert_almost_eq(instructor.ship.global_position.distance_to(main.ship.global_position), Script_.INSTRUCTOR_OFF.length(), 5.0,
			"the instructor is ahead where the cockpit shows it")
	assert_gt((-main.ship.global_basis.z).dot((instructor.ship.global_position - main.ship.global_position).normalized()), 0.9,
			"in front of the nose")
	assert_false(main.controls_locked(), "the controls are the pilot's")
	assert_null(main.camera_rig.playing_shot(), "no shot follows the ship across the cut")
	assert_eq(_starfuries(), ["INSTRUCTOR"])
	await _ticks(120)
	assert_lt(_speed(), 1.0, "at rest, hands off")
	assert_lt(_distance_to(Script_.LESSON_AT), 60.0, "and staying there")
	assert_lt((instructor.ship.linear_velocity - main.world.rest_velocity()).length(), 2.0, "the instructor holds too")
	await _wait_for("the first lesson", func() -> bool: return _api().checks.is_active(), 1800)
	assert_eq(_api().checks.current.id, &"pitch", "a turn in place is the first lesson")
	assert_false(_journal_has("fly INSTRUCTOR"), "nothing is flown behind the instructor before the controls are taught")
	var order: Array[StringName] = []
	order.append_array(Script_.ATTITUDE_CHECKS)
	order.append_array(Script_.THRUST_CHECKS)
	order.append_array(Script_.ASSIST_CHECKS)
	assert_eq(order.slice(0, 5), [&"pitch", &"yaw", &"roll", &"main_pods", &"retros"] as Array[StringName])
	for id: StringName in order:
		assert_true(_check_open(id), "%s is the lesson now" % id)
		assert_true(_run("checks pass").ok)
		await _wait_for("the lesson after %s" % id, func() -> bool: return not _check_open(id), 1200)
		if id != order[-1]:
			await _wait_for("the next lesson", func() -> bool: return _api().checks.is_active(), 1200)
	await _wait_for("the views", func() -> bool: return _api().step_name() == &"camera_lights", 1200)


func test_a_launch_played_through_also_ends_at_rest_where_the_lessons_start() -> void:
	await _fly()
	await _wait_for("the launch's end", func() -> bool: return _api().step_name() == &"flight_checks", 9000)
	assert_true(_journal_has("put player"), "the cut is a world change of the script")
	assert_lt(_distance_to(Script_.LESSON_AT), 30.0)
	assert_false(main.controls_locked())
	assert_null(main.camera_rig.playing_shot())
	await _ticks(180)
	assert_lt(_speed(), 1.0, "no launch burn carries on after the cut")


# --- auto-track -------------------------------------------------------------------------------------------------------------


func test_with_auto_track_off_the_turns_start_with_nothing_said_about_it() -> void:
	await _fly()
	await _goto(&"flight_checks")
	var seen: Array[StringName] = []
	await _wait_for("the pitch lesson", func() -> bool:
		if _api().checks.is_active() and not seen.has(_api().checks.current.id):
			seen.append(_api().checks.current.id)
		return _check_open(&"pitch"), 1800)
	assert_eq(seen, [&"pitch"] as Array[StringName], "auto-track is off: no word about it")
	assert_almost_eq(_api().fact(&"auto_track"), 0.0, 1e-9)


func test_with_auto_track_on_the_instructor_has_it_switched_off_first_naming_its_control() -> void:
	await _fly()
	await _goto(&"flight_checks")
	assert_true(main.ship.targeting.select_by_name("INSTRUCTOR"))
	await _press(InputAdapter.AUTOTRACK)
	await _ticks(5)
	assert_true(main.ship.get_flight_output().tracking, "auto-track holds the nose on the instructor")
	await _wait_for("the instructor's call", func() -> bool: return _check_open(&"autotrack_off"), 1800)
	await _wait_for("the instructor's words", func() -> bool: return _line() == &"check_autotrack_off", 300)
	assert_true(main.mission.hint.is_showing())
	assert_eq(main.mission.hint.label, "SWITCH AUTO-TRACK OFF")
	var check: ControlCheck = _api().check_book.make(&"autotrack_off")
	assert_eq(main.mission.hint.buttons, ControlHintText.bindings(check), "the live pad button and key are named")
	assert_string_contains(main.mission.hint.buttons, "X")
	assert_string_contains(main.mission.hint.buttons, "/", "a key beside the pad's button")
	await _ticks(180)
	assert_true(_check_open(&"autotrack_off"), "it waits until auto-track is off: no pitch lesson meanwhile")
	await _press(InputAdapter.AUTOTRACK)
	await _wait_for("the pitch lesson", func() -> bool: return _check_open(&"pitch"), 600)
	assert_false(main.ship.get_flight_output().tracking)


# --- the views --------------------------------------------------------------------------------------------------------------


func test_the_view_lesson_asks_for_the_view_the_pilot_is_not_in_and_needs_the_change() -> void:
	for start_in_cockpit: bool in [true, false]:
		if main != null and is_instance_valid(main):
			main.queue_free()
			await _ticks(2)
			Game.flow = GameFlow.new()
		await _fly()
		await _goto(&"flight_checks")
		if (main.camera_rig.mode == CameraRig.Mode.COCKPIT) != start_in_cockpit:
			await _press(InputAdapter.TOGGLE_CAMERA)
		assert_eq(main.camera_rig.mode == CameraRig.Mode.COCKPIT, start_in_cockpit)
		await _goto(&"camera_lights")
		var first: StringName = &"camera_to_chase" if start_in_cockpit else &"camera_to_cockpit"
		var second: StringName = &"camera_to_cockpit" if start_in_cockpit else &"camera_to_chase"
		await _await_check(first, 1200)
		await _wait_for("the call for the other view than the one on", func() -> bool: return _line() == StringName("check_%s" % first), 300)
		assert_eq(main.mission.hint.label, "SWITCH TO THE %s VIEW" % ("CHASE" if start_in_cockpit else "COCKPIT"))
		await _ticks(120)
		assert_true(_check_open(first), "hands off, the view is the same: not passed")
		await _press(InputAdapter.TOGGLE_CAMERA)
		assert_ne(main.camera_rig.mode == CameraRig.Mode.COCKPIT, start_in_cockpit, "the view changed")
		await _await_check(second, 600)
		await _press(InputAdapter.TOGGLE_CAMERA)
		await _wait_for("the look lesson", func() -> bool: return _check_open(&"free_look"), 600)
		assert_eq(main.camera_rig.mode == CameraRig.Mode.COCKPIT, start_in_cockpit, "back in the view the pilot chose")


# --- the gate ---------------------------------------------------------------------------------------------------------------


func test_at_the_gate_the_pilot_is_told_to_target_it_and_to_hold_x_only_once_the_gate_takes_the_request() -> void:
	await _fly()
	await _goto(&"jumpgate")
	var gate: Jumpgate = main.gates.gate()
	await _wait_for("the instruction to target the gate", func() -> bool: return _line() == &"instructor_gate_target", 1500)
	main.ship.targeting.clear_selection()
	await _ticks(600)
	assert_false(_said(&"instructor_gate_cue"), "the run-in waits for the gate to be targeted")
	assert_eq(_api().waypoint_name, "JUMPGATE")
	assert_true(main.ship.targeting.select_by_name("JUMPGATE"))
	await _wait_for("the run-in's call", func() -> bool: return _said(&"instructor_gate_cue"), 120)
	var pilot := _ship("INSTRUCTOR").driver.brain as AiPilot
	assert_eq(pilot.context.route.pace, Route.PACE_PLAYER, "the instructor leads at the pilot's pace")
	# Inside the old 9 km mark but outside the gate's reach, at rest: no offer, so no call to hold X.
	_put_player(_from_origin(_api().gate_point(Script_.GATE_NEAR_M - 500.0)))
	await _ticks(600)
	assert_false(main.gates.can_request_jump(), "the gate does not take a request from here (%s)" % main.gates.jump_refusal())
	assert_almost_eq(_api().fact(&"gate_offer"), 0.0, 1e-9)
	assert_false(_said(&"instructor_gate_hold"), "no hold-X call before the gate offers the jump")
	assert_false(_api().checks.is_active(), "and no check's hint repeating it")
	_put_player(_from_origin(_api().gate_point(1500.0)))
	await _wait_for("the gate's offer", func() -> bool: return main.gates.can_request_jump(), 120)
	await _wait_for("the call to hold X", func() -> bool: return _said(&"instructor_gate_hold"), 30)
	assert_lt(main.ship.global_position.distance_to(gate.global_position), main.gates.request_range_m() + 1.0,
			"by the gate's own range check")


func _from_origin(at: UniversePos) -> Vector3:
	return UniversePos.new(0.0, 0.0, 0.0, main.world.origin.system_id).offset_to(at)


# --- controls named as bound ------------------------------------------------------------------------------------------------


func _rebind(action: StringName, event: InputEvent) -> void:
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, event)


# The pilot touches the stand-in pad, or the keyboard, without flying anything.
func _use(keyboard: bool) -> void:
	source.hold(InputAdapter.TOGGLE_OVERLAY, 0.01, keyboard)
	source.release(InputAdapter.TOGGLE_OVERLAY)


func test_a_line_names_its_control_as_bound_now_and_follows_a_rebind_and_a_change_of_device() -> void:
	ControlProfiles.store.default_profile().apply_to_input_map()
	await _fly()
	await _goto(&"x_button")
	await _await_check(&"target_menu", 3600)
	await _wait_for("the instructor's call for the target menu", func() -> bool: return _line() == &"check_target_menu", 600)
	var comms: CommsPanel = main.mission.comms
	assert_string_contains(_api().dialog.current.text, "{action:target_cycle,target_next}", "the line is written with a placeholder")
	_use(false)
	var pad_button: String = BindingNames.first(InputMap.action_get_events(&"target_cycle"), BindingNames.pad_name)
	assert_eq(comms.shown_text(), "Open the target menu: hold %s and pick NAV ONE." % pad_button, "on the pad: its button")
	assert_false(comms.shown_text().contains("{"), "no placeholder reaches the screen")
	_use(true)
	var key: String = BindingNames.first(InputMap.action_get_events(&"target_next"), BindingNames.key_name)
	assert_string_contains(comms.shown_text(), "hold %s" % key, "on the keyboard: its key, the line still up")
	assert_ne(key, pad_button + "?")
	var k := InputEventKey.new()
	k.physical_keycode = KEY_K
	_rebind(&"target_next", k)
	assert_eq(comms.shown_text(), "Open the target menu: hold K and pick NAV ONE.", "a rebind made now shows now")
	assert_eq(String(_run("get dialog.text").text()).contains("hold K"), true, "the console reads the same words")
	var y := InputEventJoypadButton.new()
	y.button_index = JOY_BUTTON_Y
	_rebind(&"target_cycle", y)
	_use(false)
	assert_eq(comms.shown_text(), "Open the target menu: hold Y and pick NAV ONE.", "back on the pad, with its new button")
	await _ticks(2)
	assert_string_contains(main.mission.hint.buttons, "Y", "the hint beside it follows too")
	assert_string_contains(main.mission.hint.buttons, "K")
