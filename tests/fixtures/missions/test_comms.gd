extends MissionScript
## The comms test mission (M5-T06): two lines a second long, said in two steps, and a quiet last step. `test_comms.json` declares an
## objective that is done once the second line has finished, so the `dialog_finished` trigger is exercised end to end.


func steps() -> Array[StringName]:
	return [&"hail", &"warning", &"close"]


func step_hail(m: MissionApi) -> void:
	await m.wait(0.2)
	await m.say(&"hail")


func step_warning(m: MissionApi) -> void:
	m.objective_add(&"heard")
	await m.say(&"warning")


func step_close(m: MissionApi) -> void:
	await m.wait(1000.0)
