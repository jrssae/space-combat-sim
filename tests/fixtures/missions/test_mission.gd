extends MissionScript
## The test mission (M5-T05): every kind of wait the API offers, in three steps. `test_mission.json` declares its objectives.

## Where the two raiders come out of their carrier's jump point (universe metres from the scenario's origin).
const RAIDER_OFFSETS: Array[Vector3] = [Vector3(0.0, 0.0, -9000.0), Vector3(300.0, 0.0, -9000.0)]


func steps() -> Array[StringName]:
	return [&"brief", &"raid", &"report"]


func step_brief(m: MissionApi) -> void:
	await m.say(&"control_brief")
	m.objective_add(&"reach")
	m.waypoint("NAV ALPHA")
	await m.until_objective(&"reach")


func step_raid(m: MissionApi) -> void:
	for i: int in RAIDER_OFFSETS.size():
		var offset: Vector3 = RAIDER_OFFSETS[i]
		m.spawn({"type": "raider_fighter", "name": "RAIDER %d" % (i + 1), "anchor": "origin",
				"offset": [offset.x, offset.y, offset.z], "behaviour": {"type": "ai", "profile": "raider"}, "arrival": "jump",
				"via": "carrier"})
		m.send("RAIDER %d" % (i + 1), "NAV ALPHA")
	m.objective_add(&"raiders")
	m.objective_add(&"protect")
	await m.say(&"control_raiders")
	await m.until(TriggerSpec.destroyed(["RAIDER 1", "RAIDER 2"]))


func step_report(m: MissionApi) -> void:
	m.waypoint(null)
	m.objective_add(&"report")
	await m.wait(1.0)
	await m.player_did(&"toggle_flight_assist")
	m.objective_complete(&"report")
