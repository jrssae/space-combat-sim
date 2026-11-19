extends TestSteps
## The tutorial mission (M8 D79, AC4): the front end offers it first and starts it; console commands drive it from the menu
## to the debrief on a fresh seed; the tour visits its stops; the raid comes out of the jumpgate's vortex and then off the
## strike carrier, and the rest of the wing scrambles when the raiders first hit something; a pilot lost before the alarm
## gets the full restart only, one lost after it also the restart from the raid's start, which keeps the course result; the
## buoy course gives its four remarks; the qualification makes a squadron leader or a squadron pilot, saved in the career.

const SCENARIO_ID: StringName = &"tutorial"
const MISSION_PATH: String = "res://data/scenarios/tutorial.json"
const CAREER_PATH: String = "user://test_tutorial_career.json"
const FrontEndScene: PackedScene = preload("res://src/frontend/front_end.tscn")
const Script_: GDScript = preload("res://data/missions/tutorial.gd")
const BEAT_S: float = 0.25

var main: Main
var holder: Node
var source: FakeInputSource
var _saved: Dictionary = {}


func before_each() -> void:
	get_tree().paused = false
	source = FakeInputSource.new()
	_saved = {"flow": Game.flow, "parent": Game.scene_parent, "main_path": Game.main_scene_path, "career": Game.career,
			"career_path": Game.career_path}
	Game.flow = GameFlow.new()
	Game.career = Career.new()
	Game.career_path = CAREER_PATH
	DirAccess.remove_absolute(CAREER_PATH)
	holder = Node.new()
	add_child_autofree(holder)
	Game.scene_parent = holder


func after_each() -> void:
	get_tree().paused = false
	DebugConsole.flags.invulnerable = false
	Game.flow = _saved["flow"]
	Game.scene_parent = _saved["parent"]
	Game.main_scene_path = _saved["main_path"]
	Game.career = _saved["career"]
	Game.career_path = _saved["career_path"]
	DirAccess.remove_absolute(CAREER_PATH)


# --- helpers -----------------------------------------------------------------------------------------------------------


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


func _wait_for(what: String, reached: Callable, max_ticks: int = 1500) -> void:
	var waited: int = 0
	while not bool(reached.call()) and waited < max_ticks:
		await _ticks(1)
		waited += 1
	assert_true(bool(reached.call()), "waited %d ticks for: %s" % [waited, what])


# The tutorial in the real Main, started as the flow starts a mission; `checkpoint` as a debrief's restart hands it over.
func _fly(seed_value: int = 5, checkpoint: Dictionary = {}) -> void:
	Game.flow.enter_directly(GameFlow.make_request(&"mission", SCENARIO_ID, false, seed_value))
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	main.scenario_path = MISSION_PATH
	main.scenario_seed = seed_value
	main.mission_checkpoint = checkpoint
	holder.add_child(main)
	await _ticks(2)
	main.mission.debrief_delay_s = BEAT_S


func _api() -> MissionApi:
	return main.mission.api


func _goto(step: StringName) -> void:
	assert_true(_run("mission goto %s" % step).ok, "mission goto %s" % step)
	await _wait_for("step %s" % step, func() -> bool: return _api().step_name() == step and not _api().is_skipping(), 600)


func _ship(ship_name: String) -> Combatant:
	return main.mission.stage._actors.get(MissionWorld.key(ship_name)) as Combatant


func _debrief() -> DebriefScreen:
	return holder.get_child(0) as DebriefScreen if holder.get_child_count() == 1 else null


func _local(at: Vector3) -> Vector3:
	return main.world.universe_to_local(UniversePos.new(at.x, at.y, at.z, main.world.origin.system_id))


func _put_player(at: Vector3) -> void:
	main.mission.stage.place("player", UniversePos.new(at.x, at.y, at.z, main.world.origin.system_id))


func _journal_has(prefix: String) -> bool:
	for entry: String in _api().journal:
		if entry.begins_with(prefix):
			return true
	return false


# Flies the course step with the clock moved by hand: the player is put at each buoy, `leg_s` of sim time apart.
func _fly_course(leg_s: float, lose_buoy: bool) -> void:
	await _goto(&"course")
	await _wait_for("the course's start", func() -> bool: return _api().waypoint_name == "NAV 1" and _journal_has("fly INSTRUCTOR"), 2400)
	await _wait_for("the start call", func() -> bool: return _api().dialog.current != null and _api().dialog.current.id == &"instructor_course_go", 2400)
	for i: int in Script_.COURSE_AT.size():
		_put_player(Script_.COURSE_AT[i] + Vector3(0.0, 120.0, 0.0))  # a pass beside the buoy, not through it
		await _ticks(3)
		if i == 2 and lose_buoy:
			main.mission.stage.facts.counts[&"buoys_lost"] += 1
		if i < Script_.COURSE_AT.size() - 1:
			_api().world.time_s += leg_s
	await _ticks(3)


# --- the menu ------------------------------------------------------------------------------------------------------------


func test_the_front_end_offers_the_tutorial_first_as_a_qualification_flight_and_starts_it_on_a_fresh_seed() -> void:
	var game := RecordingGame.new()
	autofree(game)
	var front: FrontEnd = FrontEndScene.instantiate() as FrontEnd
	front.game = game
	add_child_autofree(front)
	await wait_process_frames(2)
	(front.frame().current_page() as ChoiceListScreen).button_of(&"new_game").pressed.emit()
	await wait_process_frames(2)
	var page: NewGameSelect = front.frame().current_page() as NewGameSelect
	assert_eq(page.option_ids()[0], SCENARIO_ID, "the tutorial leads the New game list")
	page.button_of(SCENARIO_ID).grab_focus()
	await wait_process_frames(2)
	var shown: String = front.frame().detail_text()
	assert_string_contains(shown, "qualif")
	assert_false(shown.to_lower().contains("raid"), "nothing before the alarm hints at a raid")
	page.button_of(SCENARIO_ID).pressed.emit()
	assert_eq(game.played.size(), 1)
	assert_eq(game.played[0]["scenario_id"], SCENARIO_ID)
	assert_gt(int(game.played[0]["seed"]), 0)


func test_no_line_before_the_alarm_names_a_raid_and_every_check_has_its_hint() -> void:
	var made: Dictionary = DialogBook.load_file("res://data/dialog/tutorial.json")
	assert_true(bool(made["ok"]), str(made.get("error", "")))
	var book: DialogBook = made["book"]
	var ids: Array[StringName] = book.line_ids()
	var alarm: int = ids.find(&"control_alarm")
	assert_gt(alarm, 0)
	for i: int in alarm:
		var text: String = book.line(ids[i]).text.to_lower()
		assert_false(text.contains("raid") or text.contains("pirate") or text.contains("attack on"), "%s: %s" % [ids[i], text])
	var checks: Dictionary = ControlCheckBook.load_file()
	assert_true(bool(checks["ok"]))
	var check_book: ControlCheckBook = checks["book"]
	assert_null(check_book.make(&"target_prev"), "not taught (D79 beat 8)")
	assert_null(check_book.make(&"target_ahead"))
	for id: StringName in check_book.ids():
		assert_true(book.has_line(check_book.make(id).hint_line), "a hint line for %s" % id)
	assert_ne(book.speaker(&"instructor").callsign, "")


# --- menu to debrief -------------------------------------------------------------------------------------------------------


func test_console_commands_take_it_from_the_menu_to_the_debrief_on_a_fresh_seed() -> void:
	Game.main_scene_path = Game.MAIN_SCENE
	assert_true(_run("play tutorial 4711").ok)
	await _wait_for("Main after the loading screen", func() -> bool: return holder.get_child_count() == 1 and holder.get_child(0) is Main, 1800)
	main = holder.get_child(0) as Main
	await _ticks(2)
	main.mission.debrief_delay_s = BEAT_S
	assert_eq(main.mission.state_name(), "running")
	assert_eq(_api().step_name(), &"launch")
	assert_true(main.controls_locked(), "the launch has the ship")
	assert_true(main.launches.locks_controls(), "the squadron launch runs")
	assert_true(_run("mission goto form_up").ok)
	await _wait_for("the hand-over", func() -> bool: return _api().step_name() == &"form_up" and not main.controls_locked(), 600)
	assert_eq(main.wings.flights_of("ALPHA").size(), 2, "the player's flight and one more; the rest scramble in the raid")
	assert_eq(main.wings.player_wing().members().size(), 2, "the player commands a flight of three")
	assert_true(main.traffic.auto, "the station's run of traffic is on")
	assert_eq(_api().objective_state(&"qualify"), ObjectiveBook.ACTIVE)
	assert_eq(_api().objective_state(&"defend"), ObjectiveBook.HIDDEN, "nothing shows the raid coming")
	assert_true(_run("mission goto debrief").ok)
	await _wait_for("the debrief step", func() -> bool: return _api().step_name() == &"debrief" and not _api().is_skipping(), 900)
	assert_true(_journal_has("tour cobra_arm") and _journal_has("tour heavy_cannons"), "the skipped tour is journaled")
	assert_true(_run("mission skip").ok)
	await _wait_for("the debrief screen", func() -> bool: return _debrief() != null, 1200)
	assert_eq(Game.flow.state, GameFlow.State.DEBRIEF)
	assert_true(bool(Game.flow.last_result["success"]))
	var model: DebriefModel = _debrief().model
	assert_eq(model.headline(), DebriefModel.HEADLINE_SUCCESS)
	assert_true(" | ".join(model.extra_lines).contains("Assignment: Squadron pilot"), "a course never flown is not exemplary: %s" % model.extra_lines)
	assert_eq(model.options().size(), 2, "a mission won offers no checkpoint")
	assert_eq(Game.career.rank, Career.SQUADRON_PILOT)
	assert_eq(CareerStore.load_file(CAREER_PATH).rank, Career.SQUADRON_PILOT, "the rank is on disk: it survives a restart")
	assert_string_contains(_run("career").text(), "Squadron pilot")


# --- the training ----------------------------------------------------------------------------------------------------------


func test_the_instructor_leads_to_the_box_flies_a_demo_on_request_and_the_drones_are_unarmed() -> void:
	await _fly()
	await _goto(&"form_up")
	await _wait_for("the instructor's route", func() -> bool: return _journal_has("fly INSTRUCTOR"), 1200)
	var instructor: Combatant = _ship("INSTRUCTOR")
	assert_not_null(instructor)
	assert_true(instructor.damageable.invulnerable)
	var pilot := instructor.driver.brain as AiPilot
	assert_eq(pilot.context.route.pace, Route.PACE_PLAYER, "it holds its speed to the player's")
	_api().demo_requested.emit(&"roll", &"roll")
	assert_true(_journal_has("demo INSTRUCTOR roll"))
	assert_eq(pilot.context.route.waypoint(0).demo, &"roll", "the instructor flies the move where it is")
	assert_false(AiProfile.load_named(&"training_drone").fires, "the drones never pull the trigger")
	await _goto(&"combat")
	await _wait_for("the drones", func() -> bool: return _api().alive("DRONE 3"), 1200)
	assert_eq(_ship("DRONE 1").faction, Factions.RAIDERS, "a hostile to practise on")
	await _ticks(900)
	for drone: String in Script_.GUNNERY_DRONES:
		assert_true(_api().alive(drone), "%s is left for the pilot: the grid and the flight hold their fire out here" % drone)
		assert_almost_eq(_ship(drone).damageable.hull.fraction(), 1.0, 0.001)


func test_the_pause_menu_skips_the_training_block_to_the_tour() -> void:
	await _fly()
	assert_eq(main.mission.skip_label(), "", "not offered during the launch")
	await _goto(&"flight_checks")
	assert_eq(main.mission.skip_label(), "Skip training")
	var ids: Array = main.pause_menu.entries().map(func(e: Dictionary) -> StringName: return e["id"])
	assert_eq(ids[1], &"skip", "after Resume")
	assert_eq(main.mission.take_skip(), "")
	await _wait_for("the tour", func() -> bool: return _api().step_name() == &"tour" and not _api().is_skipping(), 600)
	assert_eq(main.mission.skip_label(), "", "gone once the block is behind")
	assert_eq(str(_api().noted(&"course")), "", "a skipped course has no rating")


func test_the_course_gives_its_four_remarks() -> void:
	var rules: TutorialRules = TutorialRules.load_file()["rules"]
	var legs: int = Script_.COURSE_AT.size() - 1
	var cases: Array[Dictionary] = [
		{"leg_s": rules.exemplary_time_s() * 0.9 / legs, "lose": false, "rating": &"exemplary", "line": &"course_exemplary"},
		{"leg_s": rules.par_time_s() * 0.95 / legs, "lose": false, "rating": &"par", "line": &"course_par"},
		{"leg_s": rules.par_time_s() * 1.5 / legs, "lose": false, "rating": &"below_par", "line": &"course_below_par"},
		{"leg_s": rules.exemplary_time_s() * 0.9 / legs, "lose": true, "rating": &"buoy_destroyed", "line": &"course_buoy_destroyed"},
	]
	for case: Dictionary in cases:
		if main != null and is_instance_valid(main):
			main.queue_free()
			await _ticks(2)
			Game.flow = GameFlow.new()
		await _fly()
		await _fly_course(float(case["leg_s"]), bool(case["lose"]))
		assert_eq(_api().noted(&"course"), case["rating"], "rated %s" % case["rating"])
		await _wait_for("the instructor's remark in flight: %s" % case["line"],
				func() -> bool: return _api().dialog.current != null and _api().dialog.current.id == case["line"], 1500)
		assert_eq(_api().step_name(), &"course", "said in flight, before the next lesson")
		assert_string_contains(_api().dialog_book.line(&"course_exemplary").text, "White Star")
		assert_string_contains(_api().dialog_book.line(&"course_buoy_destroyed").text, "rusty cargo ship")


# --- the tour and the gate ---------------------------------------------------------------------------------------------------


func test_the_tour_visits_its_stops_in_order() -> void:
	await _fly()
	await _goto(&"tour")
	await _wait_for("the brake check", func() -> bool: return _api().checks.is_active(), 1200)
	assert_true(_run("checks pass").ok)
	var want: Array = Script_.TOUR.map(func(stop: Dictionary) -> String: return stop["stop"])
	await _wait_for("the first stop", func() -> bool: return main.tours.playing, 600)
	assert_true(main.controls_locked())
	assert_eq(main.camera_rig.mode, CameraRig.Mode.CINEMATIC)
	await _wait_for("the whole tour", func() -> bool: return _api().step_name() == &"jumpgate", 20000)
	var seen: Array = main.tours.played.map(func(p: Dictionary) -> String: return p["point"])
	assert_eq(seen, want, "the Cobra bays, the docking bay, the command section, the grid and its heavy cannons")
	assert_eq(int(_api().fact(&"tour_stops")), want.size())
	assert_false(main.controls_locked(), "the controls are back for the flight to the gate")
	assert_eq(_api().waypoint_name, "JUMPGATE", "the gate is the tour's last stop, flown")


# --- the raid ----------------------------------------------------------------------------------------------------------------


func test_the_raid_comes_out_of_the_gate_then_off_the_carrier_and_the_wing_scrambles_at_the_first_hit() -> void:
	await _fly()
	await _goto(&"raid")
	var gate: Jumpgate = main.gates.gate()
	assert_lt(main.ship.global_position.distance_to(gate.global_position), 9000.0, "the player came out of the gate")
	for wingman: String in ["ALPHA 2", "ALPHA 3", "INSTRUCTOR"]:
		assert_lt(_ship(wingman).ship.global_position.distance_to(main.ship.global_position), 2000.0, wingman)
	assert_eq(_api().checkpoint_data["step"], &"raid", "the checkpoint is taken as the alarm sounds")
	assert_eq(_api().dialog.current.id, &"control_alarm")
	assert_eq(_api().objective_state(&"defend"), ObjectiveBook.ACTIVE)
	await _wait_for("six raiders through the vortex", func() -> bool: return _api().alive("RAIDER 6"), 3000)
	for i: int in 6:
		var raider: Combatant = _ship("RAIDER %d" % (i + 1))
		assert_lt(raider.ship.global_position.distance_to(gate.global_position), 6000.0, "RAIDER %d came out of the gate" % (i + 1))
	assert_false(_api().alive("RAIDER 7"), "the carrier's group is not here yet")
	assert_false(_journal_has("scramble"), "nobody has fired yet")
	main.mission.stage.facts._on_hit(_raider_bolt())
	await _ticks(3)
	assert_true(_journal_has("scramble alpha"), "the rest of the wing launches when the raiders first hit something")
	await _wait_for("the rest of the wing", func() -> bool: return main.wings.flights_of("ALPHA").size() == 4, 1800)
	assert_eq(_api().dialog_book.line(&"control_wing_launch").speaker, &"control")
	assert_true(_run("mission skip").ok)
	await _wait_for("the carrier's step", func() -> bool: return _api().step_name() == &"defense" and not _api().is_skipping(), 600)
	await _wait_for("the strike carrier", func() -> bool: return _api().fact(&"capitals_in_play") >= 1.0, 3000)
	assert_eq(_api().objective_state(&"carrier"), ObjectiveBook.ACTIVE)
	var carrier: CapitalStandin = main.mission.stage._actors["raider carrier"]
	assert_eq(carrier.ship_class, CapitalStandin.STRIKE_CARRIER)
	assert_true(_api().alive("RAIDER 14"), "eight more ride in on it")
	assert_gt(carrier.global_position.distance_to(gate.global_position), 20000.0, "on its own point, off the station")


func _raider_bolt() -> HitInfo:
	var info := HitInfo.new()
	info.cause = HitInfo.CAUSE_BOLT
	info.faction = Factions.RAIDERS
	return info


# --- losing the player -------------------------------------------------------------------------------------------------------


func test_a_pilot_lost_before_the_alarm_gets_only_the_full_restart() -> void:
	await _fly()
	await _goto(&"tour")
	main.combatant.damageable.kill()
	await _wait_for("the debrief screen", func() -> bool: return _debrief() != null, 2400)
	assert_false(bool(Game.flow.last_result["success"]))
	assert_eq(Game.flow.last_result["reason"], "player destroyed")
	var ids: Array = _debrief().model.options().map(func(o: Dictionary) -> StringName: return o["id"])
	assert_eq(ids, [&"retry", &"front_end"])
	assert_string_contains(_run("retry checkpoint").text(), "no checkpoint")
	assert_eq(Game.career.rank, Career.UNASSIGNED, "a lost mission earns nothing")


func test_a_pilot_lost_after_the_alarm_may_restart_from_the_raid_with_the_course_result_kept() -> void:
	await _fly(9)
	_api().note(&"course", TutorialRules.EXEMPLARY)
	await _goto(&"raid")
	await _ticks(5)
	main.combatant.damageable.kill()
	await _wait_for("the debrief screen", func() -> bool: return _debrief() != null, 2400)
	var options: Array[Dictionary] = _debrief().model.options()
	var ids: Array = options.map(func(o: Dictionary) -> StringName: return o["id"])
	assert_eq(ids, [&"checkpoint", &"retry", &"front_end"])
	assert_eq(options[0]["text"], "Restart from the raid's start")
	assert_eq(options[1]["text"], "Restart whole mission")
	Game.main_scene_path = Game.MAIN_SCENE
	assert_true(_run("retry checkpoint").ok)
	assert_eq(int(Game.flow.request["seed"]), 9, "the same seed")
	await _wait_for("Main after the loading screen", func() -> bool: return holder.get_child_count() == 1 and holder.get_child(0) is Main, 1800)
	main = holder.get_child(0) as Main
	await _wait_for("the raid's start", func() -> bool: return main.mission != null and main.mission.api != null \
			and _api().step_name() == &"raid" and not _api().is_skipping(), 900)
	assert_eq(_api().noted(&"course"), TutorialRules.EXEMPLARY, "the course result and its remark are kept")
	await _wait_for("the alarm", func() -> bool: return _api().dialog.current != null and _api().dialog.current.id == &"control_alarm", 120)
	await _wait_for("the controls", func() -> bool: return not main.controls_locked(), 900)
	assert_lt(main.ship.global_position.distance_to(main.gates.gate().global_position), 9000.0)
	assert_true(main.traffic.auto)
	assert_eq(main.wings.player_wing().members().size(), 2, "the flight is whole again")
	main.combatant.damageable.kill()
	await _wait_for("the debrief again", func() -> bool: return _debrief() != null, 2400)
	assert_true(_run("retry").ok, "and the whole mission from the debrief")
	assert_false(Game.flow.request.has("checkpoint"), "a full restart carries no checkpoint")


# --- the qualification ---------------------------------------------------------------------------------------------------------


func test_an_exemplary_course_and_a_clean_raid_make_a_squadron_leader_at_once() -> void:
	await _fly()
	_api().note(&"course", TutorialRules.EXEMPLARY)
	await _goto(&"debrief")
	main.mission.stage.facts.counts[&"starfuries_lost"] = 1
	assert_true(_run("mission skip").ok)
	await _wait_for("the debrief screen", func() -> bool: return _debrief() != null, 1200)
	var notes: String = " | ".join(_debrief().model.extra_lines)
	assert_string_contains(notes, "Assignment: Squadron leader")
	assert_string_contains(notes, "Raider carrier: escaped")
	assert_eq(Game.career.rank, Career.SQUADRON_LEADER)
	assert_eq(Game.career.course, TutorialRules.EXEMPLARY)
	assert_eq(CareerStore.load_file(CAREER_PATH).rank, Career.SQUADRON_LEADER)


# --- a fought raid -----------------------------------------------------------------------------------------------------------


## The raid fought by the wing, the grid and an invulnerable player's flight until the raiders are down or gone and the
## carrier has left or died: it ends in the debrief by itself. A long fight, so a balance test (`run_tests.sh --balance`).
func test_a_fought_raid_ends_in_the_debrief() -> void:
	if BalanceTests.skip(self):
		return
	await _fly(21)
	DebugConsole.flags.invulnerable = true
	await _goto(&"raid")
	await _wait_for("the carrier's step", func() -> bool: return _api().step_name() == &"defense", 6000)
	await _wait_for("the debrief step", func() -> bool: return _api().step_name() == &"debrief", 60000)
	assert_true(_journal_has("scramble alpha"), "the raiders fired and the wing launched")
	await _wait_for("the debrief screen", func() -> bool: return _debrief() != null, 6000)
	assert_true(bool(Game.flow.last_result["success"]))
	print("fought raid: %.0f s, %s" % [float(Game.flow.last_result["time_s"]), " | ".join(_debrief().model.extra_lines)])
