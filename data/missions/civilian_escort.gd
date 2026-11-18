extends MissionScript
## Civilian escort (M5-T30, D62): Alpha 1 and ALPHA 2 see a civilian ship, drawn from the nine hulls by the seed, from NAV
## ALPHA through the asteroid belt to NAV BETA, 30 km out. Three raider waves jump in as it passes 25, 50 and 75 % of the
## route; a later wave also waits until the one before it is down and a breather has passed (M7-T54), so a fought run takes
## 6 to 8 minutes (Q40). `data/scenarios/civilian_escort.json` holds the buoys, the belt, the route, the wing, the objectives and the shots;
## `data/dialog/civilian_escort.json` holds every line.

const NAV_BETA: String = "NAV BETA"
const RAIDER: Dictionary = {"type": "raider_fighter", "anchor": "origin", "behaviour": {"type": "ai", "profile": "raider"},
		"arrival": "jump", "via": "carrier"}
## The route's progress points (25, 50 and 75 %), metres from the scenario origin. The route flies through the first; the later
## two are marks on the way to NAV BETA (`_passed`), so a civilian back from fleeing never turns back for them (M7-T54).
const POINT_25: Vector3 = Vector3(0.0, 0.0, -7500.0)
const POINT_50: Vector3 = Vector3(0.0, 0.0, -15000.0)
const POINT_75: Vector3 = Vector3(0.0, 0.0, -22500.0)
const POINT_RADIUS_M: float = 1000.0
## Done when the civilian is this close to NAV BETA (D62).
const ARRIVAL_M: float = 1500.0
## NAV BETA, metres from the scenario origin.
const BETA_AT: Vector3 = Vector3(0.0, 0.0, -30000.0)
## The quiet after a wave is down before the next may jump in, s (M7-T54: the last wave came too soon).
const BREATHER_S: float = 30.0
## Where each wave jumps in from the civilian: beyond the AI's 5 km sensors, each from its own bearing.
const WAVE_ONE_FROM: Vector3 = Vector3(-8200.0, 900.0, -2500.0)
const WAVE_TWO_FROM: Vector3 = Vector3(7000.0, -1200.0, 5200.0)
const WAVE_THREE_FROM: Vector3 = Vector3(1500.0, 2000.0, -9000.0)
const WAVE_SIZES: Array[int] = [3, 4, 6]
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
	m.lock_controls(false)
	await m.say(&"control_handover")


func step_depart(m: MissionApi) -> void:
	await m.until(_reached(m, POINT_25))


func step_wave_one(m: MissionApi) -> void:
	var names: PackedStringArray = _send_wave(m, 0, WAVE_ONE_FROM)
	await m.say(&"control_wave_one")
	await m.say(&"civilian_under_fire")
	await _next_wave_due(m, names, POINT_50)
	m.transient(names)


func step_wave_two(m: MissionApi) -> void:
	var names: PackedStringArray = _send_wave(m, 1, WAVE_TWO_FROM)
	await m.say(&"control_wave_two")
	await m.say(&"raider_lead_taunt")
	await m.say(&"alpha_2_tally")
	await _next_wave_due(m, names, POINT_75)
	m.transient(names)


func step_wave_three(m: MissionApi) -> void:
	_send_wave(m, 2, WAVE_THREE_FROM)
	await m.say(&"control_wave_three")
	await m.say(&"civilian_nearly_there")
	await m.until(TriggerSpec.proximity(_civilian(m), NAV_BETA, ARRIVAL_M))


# At NAV BETA with no raider left fighting: ALPHA 2 is home if still flying, and the escort, the last primary, ends it.
func step_arrive(m: MissionApi) -> void:
	await m.until(TriggerSpec.destroyed(_raider_names(0, _total())))
	if m.objective_state(&"home") == ObjectiveBook.ACTIVE:
		m.objective_complete(&"home")
	await m.say(&"control_success")
	await m.say(&"civilian_thanks")
	m.objective_complete(&"escort")


func _civilian(m: MissionApi) -> String:
	return m.filled(ScenarioLoader.CIVILIAN_PLACEHOLDER)


func _reached(m: MissionApi, point: Vector3) -> TriggerProximity:
	return TriggerSpec.near_point(_civilian(m), UniversePos.new(point.x, point.y, point.z, m.world.system_id), POINT_RADIUS_M)


# The civilian is as near NAV BETA as `point` is: on the way there, a detour cannot miss it. Forced, it is put at the point.
func _passed(m: MissionApi, point: Vector3) -> TriggerProximity:
	var trigger: TriggerProximity = TriggerSpec.proximity(_civilian(m), NAV_BETA, BETA_AT.distance_to(point))
	trigger.place_at = UniversePos.new(point.x, point.y, point.z, m.world.system_id)
	return trigger


# Until the next wave is due: the wave `names` down, the breather after it, and the civilian past `point`, whichever is last.
func _next_wave_due(m: MissionApi, names: PackedStringArray, point: Vector3) -> void:
	await m.until(TriggerSpec.destroyed(names))
	var down_s: float = m.time_s()
	await m.until(_passed(m, point))
	var left_s: float = BREATHER_S - (m.time_s() - down_s)
	if left_s > 0.0:
		await m.wait(left_s)


# Jumps wave `wave` in at `from` metres off the civilian and sends every raider at it. Returns their names.
func _send_wave(m: MissionApi, wave: int, from: Vector3) -> PackedStringArray:
	var civilian: String = _civilian(m)
	var at: UniversePos = m.world.position_of(civilian)
	var origin := UniversePos.new(0.0, 0.0, 0.0, m.world.system_id)
	var centre: Vector3 = (origin.offset_to(at) if at != null else POINT_50) + from
	var first: int = 0
	for w: int in wave:
		first += WAVE_SIZES[w]
	var names: PackedStringArray = _raider_names(first, WAVE_SIZES[wave])
	var side: Vector3 = from.cross(Vector3.UP).normalized()
	for i: int in names.size():
		var spawn: Dictionary = RAIDER.duplicate(true)
		var offset: Vector3 = centre + side * SPREAD_M * (i - (names.size() - 1) * 0.5)
		spawn["name"] = names[i]
		spawn["offset"] = [offset.x, offset.y, offset.z]
		m.spawn(spawn)
		m.send(names[i], civilian)
	return names


func _total() -> int:
	var n: int = 0
	for size: int in WAVE_SIZES:
		n += size
	return n


static func _raider_names(first: int, count: int) -> PackedStringArray:
	var out := PackedStringArray()
	for i: int in count:
		out.append("RAIDER %d" % (first + i + 1))
	return out
