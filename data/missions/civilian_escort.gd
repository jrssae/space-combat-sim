extends MissionScript
## Civilian escort (M5-T30, D62): Alpha 1 with ALPHA 2 and ALPHA 3 (two wingmen since M8-T08) sees a civilian ship, drawn
## from the nine hulls by the seed, from NAV ALPHA through the asteroid belt to NAV BETA, 30 km out. Three raider waves jump
## in as it passes 25, 50 and 75 % of the route; a later wave also waits until the one before it is down and a breather has
## passed (M7-T54). The waves are six, eight and ten raiders (M8-T08), so a fought run now takes longer than Q40's
## 6 to 8 minutes (Q40). Each wave rides in docked on a raider strike carrier and is launched once it is clear of its point
## (M8-T08, Q6); the carrier hangs back, takes its survivors home and flees, and destroying one is an optional objective.
## `data/scenarios/civilian_escort.json` holds the buoys, the belt, the route, the wing, the objectives and the shots;
## `data/dialog/civilian_escort.json` holds every line.

const RAIDER: Dictionary = {"type": "raider_fighter", "anchor": "origin", "behaviour": {"type": "ai", "profile": "raider"},
		"arrival": "jump", "via": "carrier"}
## The optional objective: any wave's carrier destroyed (the scenario's objective lists the carriers' names).
const CARRIER_OBJECTIVE: StringName = &"carrier"
## The route's progress points (25, 50 and 75 %), metres from the scenario origin. The route flies through the first; the later
## two are marks on the way to NAV BETA (`_passed`), so a civilian back from fleeing never turns back for them (M7-T54).
const POINT_25: Vector3 = Vector3(0.0, 0.0, -7500.0)
const POINT_50: Vector3 = Vector3(0.0, 0.0, -15000.0)
const POINT_75: Vector3 = Vector3(0.0, 0.0, -22500.0)
const POINT_RADIUS_M: float = 1000.0
## The civilian's route ends within this of NAV BETA (D62): there it has arrived.
const ARRIVAL_M: float = 1500.0
## NAV BETA, metres from the scenario origin.
const BETA_AT: Vector3 = Vector3(0.0, 0.0, -30000.0)
## The quiet after a wave is down before the next may jump in, s (M7-T54: the last wave came too soon).
const BREATHER_S: float = 30.0
## The waves: how many raiders, where they jump in from the civilian (beyond the AI's 5 km sensors, each from its own
## bearing), and the capital that brings them (the spawn's `carrier` options: its fighters docked, its name as an actor).
## Six, eight and ten (the maintainer, 2026-11-18), so each wave fights on until three are left and those go home (D83); a
## strike carrier has eighteen cradles. The last wave comes with the Battle Wagon, launched from its tubes (M8-T09, Q8).
const WAVES: Array[Dictionary] = [
	{"size": 6, "from": Vector3(-8200.0, 900.0, -2500.0), "carrier": {"arrival": "docked", "name": "RAIDER CARRIER 1"}},
	{"size": 8, "from": Vector3(7000.0, -1200.0, 5200.0), "carrier": {"arrival": "docked", "name": "RAIDER CARRIER 2"}},
	{"size": 10, "from": Vector3(1500.0, 2000.0, -9000.0), "carrier": {"arrival": "docked", "name": "RAIDER BATTLE WAGON", "class": "battle_wagon"}},
]
## Spacing between raiders of one wave, metres.
const SPREAD_M: float = 150.0


func steps() -> Array[StringName]:
	return [&"intro", &"brief", &"depart", &"wave_one", &"wave_two", &"wave_three", &"arrive"]


# Holding X through the intro and the briefing hands the flight over at once (M7-T54).
func opening_until() -> StringName:
	return &"depart"


# The civilian beside NAV ALPHA with the belt beyond, then the wing flying past; the civilian hails over the fly-past.
func step_intro(m: MissionApi) -> void:
	m.lock_controls(true)
	await m.cinematic(&"departure")
	m.say(&"civilian_hail")  # not awaited: it plays over the shot
	await m.cinematic(&"wing")


# Control's tasking while the civilian gets under way, then the controls hand over.
func step_brief(m: MissionApi) -> void:
	await m.until(TriggerSpec.dialog_finished(&"civilian_hail"))
	await m.say(&"control_brief")
	await m.say(&"control_tasking")
	await m.say(&"alpha_2_copy")
	m.objective_add(&"escort")
	m.objective_add(&"home")
	m.waypoint(_civilian(m))
	m.show_hull(_civilian(m))
	m.hold_route_end(_civilian(m))  # chased off after it has arrived, it comes back to NAV BETA
	m.lock_controls(false)
	await m.say(&"control_handover")


func step_depart(m: MissionApi) -> void:
	await m.until(_reached(m, POINT_25))


func step_wave_one(m: MissionApi) -> void:
	var names: PackedStringArray = _send_wave(m, 0)
	m.objective_add(CARRIER_OBJECTIVE)
	await m.say(&"control_wave_one")
	await m.say(&"civilian_under_fire")
	m.say(&"control_carrier")  # not awaited: the wave's timing does not wait for it
	await _next_wave_due(m, names, POINT_50)
	_wave_over(m, 0, names)


func step_wave_two(m: MissionApi) -> void:
	var names: PackedStringArray = _send_wave(m, 1)
	await m.say(&"control_wave_two")
	await m.say(&"raider_lead_taunt")
	await m.say(&"alpha_2_tally")
	await _next_wave_due(m, names, POINT_75)
	_wave_over(m, 1, names)


func step_wave_three(m: MissionApi) -> void:
	_send_wave(m, 2)
	await m.say(&"control_wave_three")
	await m.say(&"civilian_nearly_there")
	# Arrived once it has flown its route to the end, wherever a later raid has chased it since (M8-T08: with the longer
	# waves it is often there before this one comes, and "near the buoy now" never held again).
	await m.until(TriggerSpec.arrived(_civilian(m)))


# At NAV BETA with no raider left fighting: the wingmen are home if both still fly, and the escort, the last primary, ends it.
func step_arrive(m: MissionApi) -> void:
	await m.until(TriggerSpec.destroyed(_raider_names(0, _total())))
	if m.objective_state(&"home") == ObjectiveBook.ACTIVE:
		m.objective_complete(&"home")
	if m.objective_state(CARRIER_OBJECTIVE) == ObjectiveBook.DONE:
		await m.say(&"control_carrier_down")
	await m.say(&"control_success")
	await m.say(&"civilian_thanks")
	m.objective_complete(&"escort")


func _civilian(m: MissionApi) -> String:
	return m.filled(ScenarioLoader.CIVILIAN_PLACEHOLDER)


func _reached(m: MissionApi, point: Vector3) -> TriggerProximity:
	return TriggerSpec.near_point(_civilian(m), _at(m, point), POINT_RADIUS_M)


# The civilian is as near NAV BETA as `point` is: on the way there, a detour cannot miss it. Forced, it is put at the point.
func _passed(m: MissionApi, point: Vector3) -> TriggerProximity:
	var trigger: TriggerProximity = _near_beta(m, BETA_AT.distance_to(point))
	trigger.place_at = _at(m, point)
	return trigger


# The civilian within `radius_m` of NAV BETA's place. The place, not the buoy: a buoy shot away in the fight must not stop
# the next wave or the arrival (M8-T08: it stalled the mission).
func _near_beta(m: MissionApi, radius_m: float) -> TriggerProximity:
	return TriggerSpec.near_point(_civilian(m), _at(m, BETA_AT), radius_m)


func _at(m: MissionApi, point: Vector3) -> UniversePos:
	return UniversePos.new(point.x, point.y, point.z, m.world.system_id)


# Until the next wave is due: the wave `names` down, the breather after it, and the civilian past `point`, whichever is last.
func _next_wave_due(m: MissionApi, names: PackedStringArray, point: Vector3) -> void:
	await m.until(TriggerSpec.destroyed(names))
	var down_s: float = m.time_s()
	await m.until(_passed(m, point))
	var left_s: float = BREATHER_S - (m.time_s() - down_s)
	if left_s > 0.0:
		await m.wait(left_s)


# A skipped wave leaves nothing behind: its raiders and the carrier that brought them (played, the carrier flees by itself).
func _wave_over(m: MissionApi, wave: int, names: PackedStringArray) -> void:
	var gone: PackedStringArray = names.duplicate()
	gone.append(String((WAVES[wave]["carrier"] as Dictionary)["name"]))
	m.transient(gone)


# Jumps wave `wave` in at its place off the civilian, behind its carrier, and sends every raider at the civilian. Returns
# their names.
func _send_wave(m: MissionApi, wave: int) -> PackedStringArray:
	var from: Vector3 = WAVES[wave]["from"]
	var civilian: String = _civilian(m)
	var at: UniversePos = m.world.position_of(civilian)
	var origin := UniversePos.new(0.0, 0.0, 0.0, m.world.system_id)
	var centre: Vector3 = (origin.offset_to(at) if at != null else POINT_50) + from
	var first: int = 0
	for w: int in wave:
		first += int(WAVES[w]["size"])
	var names: PackedStringArray = _raider_names(first, int(WAVES[wave]["size"]))
	var side: Vector3 = from.cross(Vector3.UP).normalized()
	for i: int in names.size():
		var spawn: Dictionary = RAIDER.duplicate(true)
		var offset: Vector3 = centre + side * SPREAD_M * (i - (names.size() - 1) * 0.5)
		spawn["name"] = names[i]
		spawn["offset"] = [offset.x, offset.y, offset.z]
		spawn["carrier"] = (WAVES[wave]["carrier"] as Dictionary).duplicate()
		m.spawn(spawn)
		m.send(names[i], civilian)
	return names


func _total() -> int:
	var n: int = 0
	for wave: Dictionary in WAVES:
		n += int(wave["size"])
	return n


static func _raider_names(first: int, count: int) -> PackedStringArray:
	var out := PackedStringArray()
	for i: int in count:
		out.append("RAIDER %d" % (first + i + 1))
	return out
