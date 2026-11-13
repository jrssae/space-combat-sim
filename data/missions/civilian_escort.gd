extends MissionScript
## Civilian escort (M5-T30, D62): Alpha 1 and ALPHA 2 see a civilian ship, drawn from the nine hulls by the seed, from NAV
## ALPHA through the asteroid belt to NAV BETA, 30 km out. Three raider waves jump in as it passes 25, 50 and 75 % of the
## route. `data/scenarios/civilian_escort.json` holds the buoys, the belt, the route, the wing, the objectives and the shots;
## `data/dialog/civilian_escort.json` holds every line.

const NAV_BETA: String = "NAV BETA"
const RAIDER: Dictionary = {"type": "raider_fighter", "anchor": "origin", "behaviour": {"type": "ai", "profile": "raider"},
		"arrival": "jump", "via": "carrier"}
## The route's progress points (25, 50 and 75 %), metres from the scenario origin; the civilian's route flies through each.
const POINT_25: Vector3 = Vector3(0.0, 0.0, -7500.0)
const POINT_50: Vector3 = Vector3(0.0, 0.0, -15000.0)
const POINT_75: Vector3 = Vector3(0.0, 0.0, -22500.0)
const POINT_RADIUS_M: float = 1000.0
## Done when the civilian is this close to NAV BETA (D62).
const ARRIVAL_M: float = 1500.0
## Where each wave jumps in from the civilian: beyond the AI's 5 km sensors, each from its own bearing.
const WAVE_ONE_FROM: Vector3 = Vector3(-8200.0, 900.0, -2500.0)
const WAVE_TWO_FROM: Vector3 = Vector3(7000.0, -1200.0, 5200.0)
const WAVE_THREE_FROM: Vector3 = Vector3(1500.0, 2000.0, -9000.0)
const WAVE_SIZES: Array[int] = [3, 4, 6]
## Spacing between raiders of one wave, metres.
const SPREAD_M: float = 150.0


func steps() -> Array[StringName]:
	return [&"intro", &"brief", &"depart", &"wave_one", &"wave_two", &"wave_three", &"arrive"]


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
	m.lock_controls(false)
	await m.say(&"control_handover")


func step_depart(m: MissionApi) -> void:
	await m.until(_reached(m, POINT_25))


func step_wave_one(m: MissionApi) -> void:
	var names: PackedStringArray = _send_wave(m, 0, WAVE_ONE_FROM)
	await m.say(&"control_wave_one")
	await m.say(&"civilian_under_fire")
	await m.until(_reached(m, POINT_50))
	m.transient(names)


func step_wave_two(m: MissionApi) -> void:
	var names: PackedStringArray = _send_wave(m, 1, WAVE_TWO_FROM)
	await m.say(&"control_wave_two")
	await m.say(&"raider_lead_taunt")
	await m.say(&"alpha_2_tally")
	await m.until(_reached(m, POINT_75))
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
