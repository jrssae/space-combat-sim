extends MissionScript
## The cinematic test mission (M5-T08): a three-second intro shot framed on the player and then on the buoy, and a long quiet step
## after it. `test_cinematic.json` holds the shot.


func steps() -> Array[StringName]:
	return [&"intro", &"fly"]


func step_intro(m: MissionApi) -> void:
	await m.cinematic(&"intro")


func step_fly(m: MissionApi) -> void:
	await m.wait(1000.0)
