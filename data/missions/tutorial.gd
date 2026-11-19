extends MissionScript
## The tutorial (M8 D79): a pilot new to Babylon 5 flies the check that qualifies a squadron leader. The squadron launches,
## the instructor leads to a training box for the control checks, a timed buoy course (its rating is the career remark),
## gunnery on unarmed drones and wing orders; then the station tour and a jump through the gate. As the player comes back out
## the raid begins, a surprise to everyone: six raiders through the gate, then a strike carrier with eight more. The debrief
## is the first time the raid is discussed, and it gives the rank.
##
## `data/scenarios/tutorial.json` holds the buoys, the instructor, the flight and the objectives, `data/dialog/tutorial.json`
## every line, `data/missions/tutorial_rules.json` the grading. No check can be failed; the pause menu skips the training
## block; a pilot lost after the alarm may restart from it (`m.checkpoint`).

const INSTRUCTOR: String = "INSTRUCTOR"
const GATE: String = "JUMPGATE"
const STATION: String = "BABYLON 5"
const CARRIER: String = "RAIDER CARRIER"
const FLIGHT: Array[String] = ["ALPHA 2", "ALPHA 3"]
## Flights of three in the opening launch (the player's and one more); the rest of the wing scrambles in the raid.
const OPENING_FLIGHTS: int = 2
const WING: String = "alpha"
## The training box, metres from the station, and how near counts as there.
const BOX_AT: Vector3 = Vector3(-8000.0, 1500.0, 0.0)
const BOX_RADIUS_M: float = 1500.0
const BOX_ROUTE: Array[Vector3] = [Vector3(-5000.0, 1100.0, -600.0), Vector3(-8300.0, 1500.0, 200.0)]
const LEAD_MPS: float = 150.0
## The buoy course: the buoys in order (the scenario places them), and how near a pass counts.
const COURSE: Array[String] = ["NAV 1", "NAV 2", "NAV 3", "NAV 4", "NAV 5"]
const COURSE_AT: Array[Vector3] = [Vector3(-8000.0, 1500.0, -1500.0), Vector3(-9500.0, 1900.0, -3000.0),
		Vector3(-8200.0, 1200.0, -4700.0), Vector3(-10200.0, 1700.0, -5500.0), Vector3(-9000.0, 1500.0, -7300.0)]
const BUOY_PASS_M: float = 200.0
## A course "flown" faster than this was skipped, not flown: it counts as a par time (the maintainer, 2026-11-19), so it
## cannot make a squadron leader at once, and its remark is owed until the skip lands (`_owed_remark`).
const COURSE_MIN_S: float = 5.0
## The drones: unarmed raider hulls on a slow track through the box.
const DRONE: Dictionary = {"type": "raider_fighter", "anchor": "origin", "behaviour": {"type": "ai", "profile": "training_drone"}}
const GUNNERY_DRONES: Array[String] = ["DRONE 1", "DRONE 2", "DRONE 3"]
const ORDER_DRONES: Array[String] = ["DRONE 4", "DRONE 5"]
const DRONE_AT: Vector3 = Vector3(-9200.0, 1600.0, 1800.0)
const DRONE_MPS: float = 45.0
## The tour's stops (`data/tour/station_tour.json`) and the line said over each.
const TOUR: Array[Dictionary] = [
	{"stop": "cobra_arm", "line": &"tour_cobra"},
	{"stop": "main_docking_bay", "line": &"tour_docking"},
	{"stop": "bow", "line": &"tour_command"},
	{"stop": "defense_grid", "line": &"tour_grid"},
	{"stop": "heavy_cannons", "line": &"tour_cannons"},
]
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
	return [&"launch", &"form_up", &"flight_checks", &"camera_lights", &"x_button", &"course", &"combat", &"wing_orders",
			&"tour", &"jumpgate", &"raid", &"defense", &"debrief"]


# Holding X through the launch hands the flight over at once.
func opening_until() -> StringName:
	return &"form_up"


# The pause menu's "Skip training": from any of the training steps straight to the tour.
func skip_block() -> Dictionary:
	return {"from": &"flight_checks", "to": &"tour", "label": "Skip training"}


# The squadron launches from the Cobra bays, then the player; Control and the instructor talk over it.
func step_launch(m: MissionApi) -> void:
	m.lock_controls(true)
	m.own_dock_offer()
	m.say(&"control_launch_clear")  # not awaited: it plays over the launch
	m.demo_requested.connect(func(_check: StringName, demo: StringName) -> void: _show(m, demo))
	await m.launch_squadron(WING, 0, OPENING_FLIGHTS)
	m.traffic(true)
	m.lock_controls(false)
	m.objective_add(&"qualify")


# Form up on the instructor and follow to the training box, away from the traffic.
func step_form_up(m: MissionApi) -> void:
	await m.say(&"instructor_form_up")
	m.waypoint(INSTRUCTOR)
	m.fly(INSTRUCTOR, BOX_ROUTE, LEAD_MPS, true)
	await m.say(&"instructor_to_box")
	await m.until(TriggerSpec.near_point("player", _at(m, BOX_AT), BOX_RADIUS_M))
	m.waypoint(null)
	await m.say(&"instructor_box")


func step_flight_checks(m: MissionApi) -> void:
	await m.say(&"instructor_flight_intro")
	await m.run_checks([&"main_pods", &"retros", &"pitch", &"yaw", &"roll", &"strafe_left", &"strafe_right", &"strafe_up",
			&"strafe_down", &"assist_off"])
	await m.say(&"instructor_assist_drift")
	await m.run_checks([&"assist_on", &"brake"])
	await m.say(&"instructor_flight_done")


func step_camera_lights(m: MissionApi) -> void:
	await m.say(&"instructor_camera_intro")
	await m.run_checks([&"camera_switch", &"camera_back", &"free_look", &"running_lights"])


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
	m.fly(INSTRUCTOR, [COURSE_AT[-1] + Vector3(0.0, 300.0, 0.0)], LEAD_MPS)
	m.say(&"instructor_course_go")
	var buoys_before: float = m.fact(&"buoys_lost")
	await m.until(_buoy(m, 0))
	var started_s: float = m.time_s()
	m.say(&"instructor_course_clock")
	for i: int in range(1, COURSE.size()):
		m.waypoint(COURSE[i])
		await m.until(_buoy(m, i))
	m.waypoint(null)
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


# The player's flight of three takes its orders: form, attack and cover.
func step_wing_orders(m: MissionApi) -> void:
	await m.say(&"instructor_wing_intro")
	await m.run_checks([&"wing_form"])
	_release_drones(m, ORDER_DRONES, GUNNERY_DRONES.size())
	await m.run_checks([&"wing_attack"])
	await m.until(TriggerSpec.destroyed(ORDER_DRONES))
	await m.run_checks([&"wing_cover"])
	await m.say(&"instructor_wing_done")


# The station from outside, a stop at a time, the ship at rest meanwhile.
func step_tour(m: MissionApi) -> void:
	await _owed_remark(m)
	await m.say(&"instructor_tour_intro")
	await m.check(&"brake")
	m.lock_controls(true)
	for stop: Dictionary in TOUR:
		m.say(stop["line"])  # not awaited: it plays over the shot
		await m.tour(String(stop["stop"]))
		await m.until(TriggerSpec.dialog_finished(stop["line"]))
	m.lock_controls(false)


# Out to the gate behind the instructor, in on the approach cue, and through: the round trip ends back out of the blue vortex.
func step_jumpgate(m: MissionApi) -> void:
	m.waypoint(GATE)
	await m.say(&"instructor_gate_intro")
	var hold: UniversePos = m.gate_point(GATE_HOLD_M)
	if hold != null:
		m.fly(INSTRUCTOR, [_at(m, Vector3.ZERO).offset_to(hold)], LEAD_MPS * 4.0, true)
	await m.say(&"instructor_gate_cue")
	var near: TriggerProximity = TriggerSpec.proximity("player", GATE, GATE_NEAR_M)
	near.place_at = m.gate_point(GATE_NEAR_M - 1000.0)
	await m.until(near)
	await m.check(&"interact")
	await m.until(TriggerSpec.fact(&"gate_jumps", 1.0))
	var out: UniversePos = m.gate_point(GATE_OUT_M)
	m.gather(["player"] + FLIGHT + [INSTRUCTOR], out)
	if out != null:
		await m.until(TriggerSpec.near_point("player", out, GATE_OUT_RADIUS_M))
	m.waypoint(null)
	await m.say(&"instructor_gate_back")


# The alarm: raiders out of the gate behind the player. The checkpoint is taken here.
func step_raid(m: MissionApi) -> void:
	m.checkpoint(&"raid", "the raid's start")
	var names: PackedStringArray = _raider_names(0, _grading().gate_raiders)
	for i: int in names.size():
		var spawn: Dictionary = RAIDER_GATE.duplicate(true)
		spawn["name"] = names[i]
		spawn["offset"] = [GATE_SPREAD_M * (i - (names.size() - 1) * 0.5), 0.0, 0.0]
		m.spawn(spawn)
	m.objective_add(&"defend")
	m.objective_add(&"flight")
	m.when(TriggerSpec.fact(&"hostile_hits", 1.0), func() -> void: _scramble(m))
	m.when(TriggerSpec.fact(&"dock_offers", m.fact(&"dock_offers") + 1.0), func() -> void: m.say(&"control_dock_offer"))
	m.when(TriggerSpec.fact(&"repairs", m.fact(&"repairs") + 1.0), func() -> void: m.say(&"control_repaired"))
	await m.say(&"control_alarm", true)
	await m.say(&"instructor_raid")
	await m.say(&"control_raid_orders")
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


# The rest of the wing launches as the raiders first hit something; an arm still busy with a launch is asked again.
func _scramble(m: MissionApi, tries_left: int = SCRAMBLE_TRIES) -> void:
	if m.scramble(WING):
		m.say(&"control_wing_launch")
	elif tries_left > 0:
		m.when(TriggerSpec.timer(SCRAMBLE_RETRY_S), func() -> void: _scramble(m, tries_left - 1))


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
		m.fly(names[i], [at + Vector3(0.0, 0.0, -2600.0), at + Vector3(900.0, 300.0, -1300.0)], DRONE_MPS)
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
