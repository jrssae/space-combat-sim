extends MissionScript
## The tutorial (M8 D79): a pilot new to Babylon 5 flies the check that qualifies a squadron leader. Until the alarm there
## are two ships, the instructor and the player (M8-T33): their launch is the opening cinematic, and it cuts to the two at
## rest in clear space 8 km off the station, where the lessons start: handling first (attitude, thrust, strafe, assist,
## brake), the views and lights, the X button, a timed buoy course (its rating is the career remark), gunnery on unarmed
## drones and wing orders, which the instructor takes as the player's wingman; then the station tour and a jump through
## the gate. Nothing is flown behind the instructor before the controls are taught (the maintainer's play-test, 2026-11-21). As the
## player comes back out the raid begins, a surprise to everyone: six raiders through the gate, then a strike carrier with
## eight more. The whole wing launches at the alarm, in play: the player's two wingmen and nine more in flights of their
## own. The debrief is the first time the raid is discussed, and it gives the rank.
##
## `data/scenarios/tutorial.json` holds the buoys, the instructor, the flight and the objectives, `data/dialog/tutorial.json`
## every line, `data/missions/tutorial_rules.json` the grading. No check can be failed; the pause menu skips the training
## block; a pilot lost after the alarm may restart from it (`m.checkpoint`).

const INSTRUCTOR: String = "INSTRUCTOR"
const GATE: String = "JUMPGATE"
const STATION: String = "BABYLON 5"
const CARRIER: String = "RAIDER CARRIER"
const WING: String = "alpha"
## The pilot the instructor flies with while it is the player's wingman or fights; its own never fires.
const FIGHTING_PILOT: String = "ally_starfury"
## Starfuries launched at the alarm, all together: the player's two wingmen and nine more in three flights (the wing of
## twelve less the player; the maintainer, 2026-11-19).
const ALARM_LAUNCH: int = 11
## Where the lessons start, metres from the station: the player at rest in clear space, nose on the course's first buoy,
## the instructor ahead and to the side where the cockpit shows it.
const LESSON_AT: Vector3 = Vector3(-8000.0, 1500.0, 0.0)
const LESSON_FACING: Vector3 = Vector3(0.0, 0.0, -1.0)
const INSTRUCTOR_OFF: Vector3 = Vector3(90.0, 25.0, -260.0)
const LEAD_MPS: float = 150.0
## The handling lessons in order: turning in place first, then thrust, the strafes and the assist. Auto-track holds the nose
## on a target and so blocks a turn: before each of the first it is switched off, if it is on.
const ATTITUDE_CHECKS: Array[StringName] = [&"pitch", &"yaw", &"roll"]
const THRUST_CHECKS: Array[StringName] = [&"main_pods", &"retros", &"strafe_left", &"strafe_right", &"strafe_up", &"strafe_down",
		&"assist_off"]
const ASSIST_CHECKS: Array[StringName] = [&"assist_on", &"brake"]
## The view lesson asks for the view the pilot is not in, then for the way back.
const VIEW_FROM_COCKPIT: Array[StringName] = [&"camera_to_chase", &"camera_to_cockpit"]
const VIEW_FROM_CHASE: Array[StringName] = [&"camera_to_cockpit", &"camera_to_chase"]
const LOOK_CHECKS: Array[StringName] = [&"free_look", &"running_lights"]
## The buoy course: the buoys in order (the scenario places them), and how near a pass counts.
const COURSE: Array[String] = ["NAV 1", "NAV 2", "NAV 3", "NAV 4", "NAV 5"]
const COURSE_AT: Array[Vector3] = [Vector3(-8000.0, 1500.0, -1500.0), Vector3(-9500.0, 1900.0, -3000.0),
		Vector3(-8200.0, 1200.0, -4700.0), Vector3(-10200.0, 1700.0, -5500.0), Vector3(-9000.0, 1500.0, -7300.0)]
const BUOY_PASS_M: float = 200.0
## A course "flown" faster than this was skipped, not flown: it counts as a par time (the maintainer, 2026-11-19), so it
## cannot make a squadron leader at once, and its remark is owed until the skip lands (`_owed_remark`).
const COURSE_MIN_S: float = 5.0
## The drones: unarmed raider hulls on a slow track, released 1.7 km beyond the course's last buoy, where the pilot is.
const DRONE: Dictionary = {"type": "raider_fighter", "anchor": "origin", "behaviour": {"type": "ai", "profile": "training_drone"}}
const GUNNERY_DRONES: Array[String] = ["DRONE 1", "DRONE 2", "DRONE 3"]
const ORDER_DRONES: Array[String] = ["DRONE 4", "DRONE 5"]
const DRONE_AT: Vector3 = Vector3(-9200.0, 1600.0, -9000.0)
const DRONE_TRACK: Array[Vector3] = [Vector3(0.0, 0.0, -2000.0), Vector3(900.0, 300.0, -1000.0)]
## Where the instructor waits for the pilot at the course's end: this far above its last buoy.
const COURSE_WAIT: Vector3 = Vector3(0.0, 300.0, 0.0)
const DRONE_MPS: float = 45.0
## The tour's stops (`data/tour/station_tour.json`) and the line said over each.
const TOUR: Array[Dictionary] = [
	{"stop": "cobra_arm", "line": &"tour_cobra"},
	{"stop": "main_docking_bay", "line": &"tour_docking"},
	{"stop": "bow", "line": &"tour_command"},
	{"stop": "defense_grid", "line": &"tour_grid"},
	{"stop": "heavy_cannons", "line": &"tour_cannons"},
]
## The tour's own captions stay off: Control and the instructor talk over each stop, and the caption lay over their lines.
const TOUR_CAPTIONS: bool = false
## The instructor waits this far in front of the gate; the jump is taught from inside `GATE_NEAR_M`.
const GATE_HOLD_M: float = 7000.0
const GATE_NEAR_M: float = 9000.0
## Where the jump leaves the player's flight: this far out of the gate's mouth.
const GATE_OUT_M: float = 2500.0
const GATE_OUT_RADIUS_M: float = 6000.0
## The raid: the gate group's spread, the quiet before the carrier, and where it jumps in (between the gate and the station).
const RAIDER_GATE: Dictionary = {"type": "raider_fighter", "anchor": "origin", "arrival": "gate",
		"behaviour": {"type": "ai", "profile": "raider", "orders": "attack", "objective": STATION}}
const RAIDER_CARRIED: Dictionary = {"type": "raider_fighter", "anchor": "origin", "arrival": "jump", "via": "carrier",
		"behaviour": {"type": "ai", "profile": "raider"}}
const GATE_SPREAD_M: float = 120.0
const CARRIER_AFTER_S: float = 45.0
const CARRIER_AT: Vector3 = Vector3(12000.0, 2000.0, -2500.0)
const CARRIER_SPREAD_M: float = 150.0
const SCRAMBLE_RETRY_S: float = 5.0
const SCRAMBLE_TRIES: int = 12

var _rules: TutorialRules = null


func steps() -> Array[StringName]:
	return [&"launch", &"flight_checks", &"camera_lights", &"x_button", &"course", &"combat", &"wing_orders",
			&"tour", &"jumpgate", &"raid", &"defense", &"debrief"]


# Holding X through the launch hands the flight over at once.
func opening_until() -> StringName:
	return &"flight_checks"


# The pause menu's "Skip training": from any of the training steps straight to the tour.
func skip_block() -> Dictionary:
	return {"from": &"flight_checks", "to": &"tour", "label": "Skip training"}


# The opening cinematic: two ships launch from the Cobra bays, the instructor (as the player's flight for the launch) and
# then the player. It cuts to both at rest where the lessons start.
func step_launch(m: MissionApi) -> void:
	m.lock_controls(true)
	m.own_dock_offer()
	m.say(&"control_launch_clear")  # not awaited: the lines play over the launch
	m.say(&"instructor_welcome")
	m.demo_requested.connect(_on_demo.bind(m))  # a bound method: a lambda holding `m` outlived a step cut short
	m.join_flight(INSTRUCTOR)
	await m.launch_squadron(WING, 0, 1)
	m.leave_flight(INSTRUCTOR)
	m.put("player", LESSON_AT, LESSON_FACING)
	m.put(INSTRUCTOR, LESSON_AT + INSTRUCTOR_OFF, LESSON_FACING)
	m.traffic(true)
	m.lock_controls(false)
	m.objective_add(&"qualify")


# Handling, from rest: the turns, then thrust and the strafes, the assist off and on, the brake.
func step_flight_checks(m: MissionApi) -> void:
	await m.say(&"instructor_box")
	await m.say(&"instructor_flight_intro")
	for check: StringName in ATTITUDE_CHECKS:
		await _auto_track_off(m)
		await m.check(check)
	await m.run_checks(THRUST_CHECKS)
	await m.say(&"instructor_assist_drift")
	await m.run_checks(ASSIST_CHECKS)
	await m.say(&"instructor_flight_done")


# The two views, asked for from the one the pilot is in, then free look and the lights.
func step_camera_lights(m: MissionApi) -> void:
	await m.say(&"instructor_camera_intro")
	await m.run_checks(VIEW_FROM_COCKPIT if m.fact(&"cockpit_view") >= 1.0 else VIEW_FROM_CHASE)
	await m.run_checks(LOOK_CHECKS)


# What X does: a tap tracks, a hold runs the target's interaction (flown for real at the gate).
func step_x_button(m: MissionApi) -> void:
	await m.say(&"instructor_x_intro")
	await m.say(&"instructor_x_more")
	m.waypoint(COURSE[0])
	await m.run_checks([&"target_menu", &"autotrack"])


# The timed buoy course; its rating is the instructor's career remark and counts toward the qualification.
func step_course(m: MissionApi) -> void:
	await m.say(&"instructor_course_intro")
	await m.say(&"instructor_course_cue")
	m.fly(INSTRUCTOR, [COURSE_AT[-1] + COURSE_WAIT], LEAD_MPS)
	m.say(&"instructor_course_go")
	var buoys_before: float = m.fact(&"buoys_lost")
	await m.until(_buoy(m, 0))
	var started_s: float = m.time_s()
	m.say(&"instructor_course_clock")
	for i: int in range(1, COURSE.size()):
		m.waypoint(COURSE[i])
		await m.until(_buoy(m, i))
	m.waypoint(null)
	m.gather([INSTRUCTOR], _at(m, COURSE_AT[-1] + COURSE_WAIT))
	var time_s: float = m.time_s() - started_s
	if m.noted(&"course") != null:
		return  # a restart from the checkpoint keeps the flown result
	if time_s < COURSE_MIN_S:
		m.note(&"course", TutorialRules.PAR)
		m.note(&"course_remark", &"owed")  # a skipped step's lines are not heard
		return
	var rating: StringName = _grading().rating(time_s, m.fact(&"buoys_lost") > buoys_before)
	m.note(&"course", rating)
	m.note(&"course_time_s", snappedf(time_s, 0.1))
	await m.say(StringName("course_%s" % rating))


# Targeting, the lead reticle and the fire modes on unarmed drones.
func step_combat(m: MissionApi) -> void:
	await m.say(&"instructor_combat_intro")
	_release_drones(m, GUNNERY_DRONES, 0)
	await m.run_checks([&"target_next"])
	await m.say(&"instructor_lead")
	await m.run_checks([&"fire_linked", &"fire_alternating"])
	await m.say(&"instructor_drones_free")
	await m.until(TriggerSpec.destroyed(GUNNERY_DRONES))
	await m.say(&"instructor_drones_down")


# The instructor flies as the player's wingman and takes the orders: form, attack and cover. Then it instructs again. The
# attack is over when the drone the pilot ordered it at is down; the other is left to practise on until the tour recalls it.
func step_wing_orders(m: MissionApi) -> void:
	await m.say(&"instructor_wing_intro")
	m.pilot(INSTRUCTOR, FIGHTING_PILOT)
	m.join_flight(INSTRUCTOR)
	await m.run_checks([&"wing_form"])
	_release_drones(m, ORDER_DRONES, GUNNERY_DRONES.size())
	await m.run_checks([&"wing_attack"])
	var ordered: String = m.player_target()  # ATTACK MY TARGET sent the wingman at the pilot's selection
	if ORDER_DRONES.has(ordered):
		await m.until(TriggerSpec.destroyed([ordered]))
	else:
		await m.until(TriggerSpec.destroyed(ORDER_DRONES, false))
	await m.say(&"instructor_wing_kill")
	await m.run_checks([&"wing_cover"])
	m.leave_flight(INSTRUCTOR)
	m.pilot(INSTRUCTOR)
	await m.say(&"instructor_wing_done")


# The station from outside, a stop at a time, the ship at rest meanwhile.
func step_tour(m: MissionApi) -> void:
	await _owed_remark(m)
	await m.say(&"instructor_tour_intro")
	await m.check(&"brake")
	m.lock_controls(true)
	m.dismiss(GUNNERY_DRONES + ORDER_DRONES)  # Control recalls what is left of the drones while the camera is at the station
	for stop: Dictionary in TOUR:
		m.say(stop["line"])  # not awaited: it plays over the shot
		await m.tour(String(stop["stop"]), TOUR_CAPTIONS)
		await m.until(TriggerSpec.dialog_finished(stop["line"]))
	m.lock_controls(false)


# Out to the gate behind the instructor: the gate targeted, in on the approach cue, and through once the gate offers the
# jump. The hold of X is called only then, by the gate's own range check. The round trip ends back out of the blue vortex.
func step_jumpgate(m: MissionApi) -> void:
	m.waypoint(GATE)
	await m.say(&"instructor_gate_intro")
	var hold: UniversePos = m.gate_point(GATE_HOLD_M)
	if hold != null:
		m.fly(INSTRUCTOR, [_at(m, Vector3.ZERO).offset_to(hold)], LEAD_MPS * 4.0, true)
	await m.say(&"instructor_gate_target")
	await m.until(TriggerSpec.targeted(GATE))
	await m.say(&"instructor_gate_cue")
	var near: TriggerProximity = TriggerSpec.proximity("player", GATE, GATE_NEAR_M)
	near.place_at = m.gate_point(GATE_NEAR_M - 1000.0)
	await m.until(near)
	await m.until(TriggerSpec.fact(&"gate_offer", 1.0))
	m.say(&"instructor_gate_hold")  # not awaited: the pilot may hold X before the line is out
	await m.until(TriggerSpec.fact(&"gate_jumps", 1.0))
	var out: UniversePos = m.gate_point(GATE_OUT_M)
	m.gather(["player", INSTRUCTOR], out)
	if out != null:
		await m.until(TriggerSpec.near_point("player", out, GATE_OUT_RADIUS_M))
	m.waypoint(null)
	await m.say(&"instructor_gate_back")


# The alarm: raiders out of the gate behind the player, and the squadron launches. The checkpoint is taken here.
func step_raid(m: MissionApi) -> void:
	m.checkpoint(&"raid", "the raid's start")
	m.pilot(INSTRUCTOR, FIGHTING_PILOT)
	_scramble(m, ALARM_LAUNCH, &"alpha_2_launch")
	var names: PackedStringArray = _raider_names(0, _grading().gate_raiders)
	for i: int in names.size():
		var spawn: Dictionary = RAIDER_GATE.duplicate(true)
		spawn["name"] = names[i]
		spawn["offset"] = [GATE_SPREAD_M * (i - (names.size() - 1) * 0.5), 0.0, 0.0]
		m.spawn(spawn)
	m.objective_add(&"defend")
	m.objective_add(&"flight")
	m.when(TriggerSpec.fact(&"dock_offers", m.fact(&"dock_offers") + 1.0), func() -> void: m.say(&"control_dock_offer"))
	m.when(TriggerSpec.fact(&"repairs", m.fact(&"repairs") + 1.0), func() -> void: m.say(&"control_repaired"))
	await m.say(&"control_alarm", true)
	await m.say(&"instructor_raid")
	await m.say(&"control_raid_orders")
	await m.say(&"alpha_3_launch")
	await m.wait(CARRIER_AFTER_S)


# The strike carrier jumps in and launches the second group; it can be killed until its drive has recharged.
func step_defense(m: MissionApi) -> void:
	var gate_group: int = _grading().gate_raiders
	var names: PackedStringArray = _raider_names(gate_group, _grading().carrier_raiders)
	for i: int in names.size():
		var spawn: Dictionary = RAIDER_CARRIED.duplicate(true)
		var at: Vector3 = CARRIER_AT + Vector3(CARRIER_SPREAD_M * (i - (names.size() - 1) * 0.5), 0.0, 0.0)
		spawn["name"] = names[i]
		spawn["offset"] = [at.x, at.y, at.z]
		spawn["carrier"] = {"arrival": "docked", "name": CARRIER}
		m.spawn(spawn)
		m.send(names[i], STATION)
	m.objective_add(&"carrier")
	await m.say(&"control_carrier", true)
	await m.say(&"instructor_carrier_window")
	await m.say(&"control_carrier_run")
	var everyone: PackedStringArray = _raider_names(0, gate_group + names.size())
	await m.until(TriggerSpec.destroyed(everyone))
	await m.until(TriggerSpec.fact(&"capitals_in_play", 1.0, true))
	var gone: PackedStringArray = everyone.duplicate()
	gone.append(CARRIER)
	m.transient(gone)
	if m.objective_state(&"carrier") == ObjectiveBook.DONE:
		await m.say(&"control_carrier_down")
	await m.say(&"control_stand_down")


# The raid is talked through for the first time, and the rank is given.
func step_debrief(m: MissionApi) -> void:
	var starfuries: int = int(m.fact(&"starfuries_lost"))
	var civilians: int = int(m.fact(&"civilians_lost"))
	var carrier_down: bool = m.objective_state(&"carrier") == ObjectiveBook.DONE
	var course: StringName = StringName(str(m.noted(&"course", "")))
	var rank: StringName = _grading().rank(course, starfuries, civilians)
	await m.say(&"instructor_debrief_open")
	if TutorialRules.perfect(starfuries):
		await m.say(&"instructor_debrief_perfect")
	else:
		await m.say(&"instructor_debrief_one_lost" if starfuries == 1 else &"instructor_debrief_losses")
	if civilians > 0:
		await m.say(&"instructor_debrief_civilians")
	await m.say(&"instructor_debrief_carrier_down" if carrier_down else &"instructor_debrief_carrier_away")
	await m.say(&"instructor_verdict_leader" if rank == Career.SQUADRON_LEADER else &"instructor_verdict_squadron")
	m.debrief_line("Buoy course: %s" % String(course).replace("_", " "))
	m.debrief_line("Starfuries lost: %d%s" % [starfuries, "   PERFECT SCORE" if TutorialRules.perfect(starfuries) else ""])
	m.debrief_line("Civilian ships lost: %d" % civilians)
	m.debrief_line("Raider carrier: %s" % ("destroyed" if carrier_down else "escaped"))
	m.debrief_line("Assignment: %s" % String(Career.RANK_NAMES[rank]))
	m.award_rank(rank)
	if m.objective_state(&"flight") == ObjectiveBook.ACTIVE:
		m.objective_complete(&"flight")
	m.objective_complete(&"defend")
	m.objective_complete(&"qualify")  # the last primary: the mission ends, and Control's welcome is its closing line


# The par remark for a course that was skipped, said once where the skip lands: at the tour.
func _owed_remark(m: MissionApi) -> void:
	if m.noted(&"course_remark") != &"owed":
		return
	m.note(&"course_remark", &"said")
	await m.say(&"course_par")


# Auto-track holds the nose on its target, so no turn can be shown with it on: the pilot switches it off first. Off already,
# nothing is said.
func _auto_track_off(m: MissionApi) -> void:
	if m.fact(&"auto_track") >= 1.0:
		await m.check(&"autotrack_off")


# Launches up to `count` more of the wing from its Cobra arm, in play, and says `line` as they go; an arm still busy with a
# launch is asked again. The first ships out take the player's two free slots, the rest fly in flights of their own.
func _scramble(m: MissionApi, count: int, line: StringName, tries_left: int = SCRAMBLE_TRIES) -> void:
	if m.scramble(WING, count):
		m.say(line)
	elif tries_left > 0:
		m.when(TriggerSpec.timer(SCRAMBLE_RETRY_S), func() -> void: _scramble(m, count, line, tries_left - 1))


func _on_demo(_check: StringName, demo: StringName, m: MissionApi) -> void:
	_show(m, demo)


# The instructor flies the move a check asked for.
func _show(m: MissionApi, demo: StringName) -> void:
	m.say(&"instructor_demo")
	m.demo(INSTRUCTOR, demo)


func _release_drones(m: MissionApi, names: Array[String], first: int) -> void:
	for i: int in names.size():
		var at: Vector3 = DRONE_AT + Vector3(260.0 * (first + i), 90.0 * i, 0.0)
		var spawn: Dictionary = DRONE.duplicate(true)
		spawn["name"] = names[i]
		spawn["offset"] = [at.x, at.y, at.z]
		m.spawn(spawn)
		m.fly(names[i], [at + DRONE_TRACK[0], at + DRONE_TRACK[1]], DRONE_MPS)
	m.transient(PackedStringArray(names))


# Passing buoy `i` of the course: its place, not the buoy, so one shot away cannot stall the course.
func _buoy(m: MissionApi, i: int) -> TriggerProximity:
	return TriggerSpec.near_point("player", _at(m, COURSE_AT[i]), BUOY_PASS_M)


func _at(m: MissionApi, point: Vector3) -> UniversePos:
	return UniversePos.new(point.x, point.y, point.z, m.world.system_id)


func _grading() -> TutorialRules:
	if _rules == null:
		var made: Dictionary = TutorialRules.load_file()
		_rules = made["rules"] if bool(made["ok"]) else TutorialRules.new()
		if not bool(made["ok"]):
			push_error("Tutorial: %s" % made["error"])
	return _rules


static func _raider_names(first: int, count: int) -> PackedStringArray:
	var out := PackedStringArray()
	for i: int in count:
		out.append("RAIDER %d" % (first + i + 1))
	return out
