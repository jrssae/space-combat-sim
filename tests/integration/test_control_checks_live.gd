extends TestSteps
## The control checks in the real main scene (M8 D80, AC3), on the test mission: the probe measures the real ship, the HUD
## hint names the live bindings and follows a rebind, and the console lists, starts and passes checks.

const MISSION_PATH: String = "res://tests/fixtures/missions/test_mission.json"

var main: Main
var source: FakeInputSource
var _layout: ControlProfile = null
var _game_state: GameFlow.State
var _game_result: Dictionary


func before_all() -> void:
	ControlProfiles.store.default_profile().apply_to_input_map()


func before_each() -> void:
	get_tree().paused = false
	_game_state = Game.flow.state
	_game_result = Game.flow.last_result
	_layout = ControlProfile.from_input_map("saved")
	source = FakeInputSource.new()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	main.scenario_path = MISSION_PATH
	add_child_autofree(main)
	await _ticks(2)


func after_each() -> void:
	get_tree().paused = false
	_layout.apply_to_input_map()
	Game.flow.state = _game_state
	Game.flow.last_result = _game_result


func _checks() -> ControlCheckRunner:
	return main.mission.api.checks


func _wait_for(what: String, reached: Callable, max_ticks: int = 600) -> void:
	var waited: int = 0
	while not bool(reached.call()) and waited < max_ticks:
		await _ticks(1)
		waited += 1
	assert_true(bool(reached.call()), "waited %d ticks for: %s" % [waited, what])


func test_the_main_pods_check_passes_on_the_real_ships_measured_speed() -> void:
	assert_true(_console("checks start main_pods").ok)
	assert_eq(_checks().current.id, &"main_pods")
	await _ticks(30)
	assert_eq(_checks().current.progress, 0.0, "hands off: nothing gained")
	assert_true(main.mission.hint.is_showing())
	assert_eq(main.mission.hint.label, "FIRE BOTH MAIN PODS")
	assert_eq(main.mission.hint.buttons, "LT + RT / W", "the live bindings")
	source.hold(InputAdapter.MAIN_LEFT)
	await _ticks(60)
	assert_eq(_checks().current.id, &"main_pods", "one pod does not pass it")
	source.hold(InputAdapter.MAIN_RIGHT)
	await _wait_for("the main pods check", func() -> bool: return not _checks().is_active())
	source.release_all()
	assert_eq(_checks().passed_ids, [&"main_pods"] as Array[StringName])
	assert_gt(main.ship.linear_velocity.length(), 35.0, "the ship really gained the speed")
	await _ticks(2)
	assert_false(main.mission.hint.is_showing(), "the hint goes with the check")
	assert_has(main.mission.api.journal, "check main_pods passed")


func test_state_checks_read_the_real_ship() -> void:
	assert_true(_console("checks start running_lights").ok)
	await _ticks(2)
	var lit: bool = main.ship.running_lights
	source.hold(InputAdapter.TOGGLE_RUNNING_LIGHTS)
	await _ticks(3)
	source.release_all()
	assert_ne(main.ship.running_lights, lit)
	assert_false(_checks().is_active(), "the lights changed: passed")
	var view_check: String = "camera_to_chase" if main.camera_rig.mode == CameraRig.Mode.COCKPIT else "camera_to_cockpit"
	assert_true(_console("checks start %s" % view_check).ok)
	await _ticks(2)
	source.hold(InputAdapter.TOGGLE_CAMERA)
	await _ticks(3)
	source.release_all()
	assert_false(_checks().is_active(), "the view changed: passed")
	main.ship.set_assist(true)
	assert_true(_console("checks start assist_off").ok)
	await _ticks(2)
	source.hold(InputAdapter.TOGGLE_ASSIST)
	await _ticks(3)
	source.release_all()
	assert_false(main.ship.assist_on)
	assert_eq(_checks().passed_ids, [&"running_lights", StringName(view_check), &"assist_off"] as Array[StringName])


func test_the_probe_fills_every_field_a_check_can_read() -> void:
	var sample: ControlCheckSample = ControlCheckProbe.sample(main)
	for field: StringName in ControlCheckSample.FIELDS:
		assert_true(sample.state.has(field), "%s" % field)
	assert_eq(sample.state[ControlCheckSample.FIRE_MODE], "alternating", "the Starfury starts in alternating fire, so the tutorial's linked check is not passed for free (Q79)")
	assert_eq(sample.state[ControlCheckSample.CAMERA], String(CameraRig.mode_name(main.camera_rig.mode)))
	main.player_alive = false
	assert_true(ControlCheckProbe.sample(main).state.is_empty(), "nothing passes on a wreck")
	main.player_alive = true


func test_the_hint_follows_a_rebind() -> void:
	assert_true(_console("checks start assist_off").ok)
	await _ticks(2)
	assert_eq(main.mission.hint.buttons, "D-PAD UP / T")
	var edited: ControlProfile = ControlProfile.from_input_map("edit")
	edited.bindings[InputAdapter.TOGGLE_ASSIST] = ["pad:button:11", "key:F9"]
	assert_eq(edited.apply_to_input_map(), PackedStringArray())
	await _ticks(2)
	assert_eq(main.mission.hint.buttons, "D-PAD UP / F9", "the next tick shows the new key")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(main.mission.hint.visible)


func test_the_console_lists_starts_and_passes_checks() -> void:
	var listed: ConsoleResult = _console("checks list")
	assert_true(listed.ok)
	assert_eq(listed.lines.size(), main.mission.api.check_book.ids().size())
	assert_string_contains(listed.lines[0], "autotrack_off  TAP X / SHIFT / MOUSE 4: SWITCH AUTO-TRACK OFF")
	assert_string_contains(listed.lines[4], "main_pods  LT + RT / W: FIRE BOTH MAIN PODS", "the turns are taught before thrust")
	assert_string_contains(_console("checks").lines[0], "no check open")
	assert_false(_console("checks pass").ok, "nothing open")
	assert_false(_console("checks start").ok)
	assert_string_contains(_console("checks start rol").error, "did you mean roll")
	assert_true(_console("checks start roll").ok)
	assert_false(_console("checks start brake").ok, "one at a time")
	assert_eq(_console("get checks.current").lines[0], "checks.current = roll")
	assert_string_contains(_console("checks status").lines[0], "roll: R STICK DIAGONAL / CAPSLOCK or G: ROLL")
	assert_false(_console("checks pass brake").ok, "another check is open")
	assert_true(_console("checks pass roll").ok)
	assert_eq(_console("get checks.active").lines[0], "checks.active = false")
	assert_true(_console("checks start brake").ok)
	assert_true(_console("checks stop").ok)
	assert_false(_checks().is_active())
	assert_false(_console("checks list brake").ok, "list takes no id")
