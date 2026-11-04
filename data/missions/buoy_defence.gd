extends MissionScript
## Buoy defence (M5-T10, AC10): Alpha wing flies out to the relay buoy NAV ALPHA, one of 16 on a ring, and holds it against two
## raider groups sent at it from beyond sensor range. `data/scenarios/buoy_defence.json` holds the ring, the wing, the
## objectives, the closing lines and the intro's two shots; `data/dialog/buoy_defence.json` holds every line.

const BUOY: String = "NAV ALPHA"
const RAIDER: Dictionary = {"type": "raider_fighter", "anchor": "origin", "behaviour": {"type": "ai", "profile": "raider"},
		"arrival": "jump"}
## Wave one jumps in off the wing's port side, about 9.5 km from the buoy (metres from the scenario origin, the buoy).
const WAVE_ONE: Array[Vector3] = [Vector3(-8500.0, 600.0, -4200.0), Vector3(-8650.0, 600.0, -4050.0),
		Vector3(-8350.0, 600.0, -4050.0)]
## Wave two comes from the other side, starboard and low, about 9.4 km out.
const WAVE_TWO: Array[Vector3] = [Vector3(7800.0, -500.0, 5200.0), Vector3(7950.0, -500.0, 5350.0),
		Vector3(7650.0, -500.0, 5350.0), Vector3(8100.0, -500.0, 5500.0)]
## Sim seconds between Control's warning and the second jump point.
const WAVE_TWO_DELAY_S: float = 4.0


func steps() -> Array[StringName]:
	return [&"intro", &"brief", &"wave_one", &"wave_two", &"wrap"]


# The relay with the sun behind it, then the wing flying past; Control hails over the fly-past.
func step_intro(m: MissionApi) -> void:
	m.lock_controls(true)
	await m.cinematic(&"relay")
	m.say(&"control_hail")  # not awaited: it plays over the shot
	await m.cinematic(&"wing")


# Control's tasking while the wing coasts in, then the controls hand over.
func step_brief(m: MissionApi) -> void:
	await m.until(TriggerSpec.dialog_finished(&"control_hail"))
	await m.say(&"control_brief")
	await m.say(&"control_tasking")
	await m.say(&"alpha_2_copy")
	m.objective_add(&"protect")
	m.objective_add(&"raiders")
	m.objective_add(&"home")
	m.waypoint(BUOY)
	m.lock_controls(false)
	await m.say(&"control_handover")


func step_wave_one(m: MissionApi) -> void:
	var names: Array[String] = _send_wave(m, WAVE_ONE, 1)
	await m.say(&"control_contacts")
	await m.until(TriggerSpec.destroyed(PackedStringArray(names)))


func step_wave_two(m: MissionApi) -> void:
	await m.say(&"control_second_group")
	await m.wait(WAVE_TWO_DELAY_S)
	_send_wave(m, WAVE_TWO, WAVE_ONE.size() + 1)
	await m.say(&"raider_lead_taunt")
	await m.say(&"alpha_3_tally")
	await m.until_objective(&"raiders")


# The wing comes home whole only if nobody was lost; protecting the buoy is the last primary, so the mission ends there.
func step_wrap(m: MissionApi) -> void:
	if m.objective_state(&"home") == ObjectiveBook.ACTIVE:
		m.objective_complete(&"home")
	await m.say(&"control_success")
	await m.say(&"alpha_2_home")
	m.objective_complete(&"protect")


# Jumps a raider group in at `offsets` and sends every one at the buoy. Returns their names.
func _send_wave(m: MissionApi, offsets: Array[Vector3], first_number: int) -> Array[String]:
	var names: Array[String] = []
	for i: int in offsets.size():
		var spawn: Dictionary = RAIDER.duplicate(true)
		spawn["name"] = "RAIDER %d" % (first_number + i)
		spawn["offset"] = [offsets[i].x, offsets[i].y, offsets[i].z]
		m.spawn(spawn)
		m.send(spawn["name"], BUOY)
		names.append(spawn["name"])
	return names
