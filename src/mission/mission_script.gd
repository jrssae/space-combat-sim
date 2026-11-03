class_name MissionScript
extends RefCounted
## The base of a mission's script (architecture §18 D51): `data/missions/<id>.gd` extends it, lists its steps in order and
## writes each as a method `step_<name>(m: MissionApi)`, a coroutine the runner awaits before starting the next.
##
## A step waits only through the API (`await m.wait(...)`, `m.until(...)`, `m.say(...)`, `m.player_did(...)`,
## `m.until_objective(...)`, `m.cinematic(...)`), never on timers or signals of its own: that is how `mission skip`
## fast-forwards it and `mission goto` reaches a later step. World changes (`spawn`, `send`, objectives) still run when skipped.
##
##     extends MissionScript
##
##     func steps() -> Array[StringName]:
##         return [&"intro", &"wave_one"]
##
##     func step_intro(m: MissionApi) -> void:
##         await m.say(&"control_briefing")
##         m.objective_add(&"protect")
##
##     func step_wave_one(m: MissionApi) -> void:
##         m.spawn({"type": "raider_fighter", "name": "RAIDER 1", "anchor": "origin", "offset": [0, 0, -9000],
##                 "behaviour": {"type": "ai", "profile": "raider"}, "arrival": "jump"})
##         m.send("RAIDER 1", "NAV ALPHA")
##         await m.until(TriggerSpec.destroyed(["RAIDER 1"]))

## The method each step runs: `step_` + its name.
const STEP_PREFIX: String = "step_"


## The steps, in the order they run.
func steps() -> Array[StringName]:
	return []


## "" when every step has its method, else which one is missing.
func check_steps() -> String:
	var seen: Dictionary = {}
	for step: StringName in steps():
		if seen.has(step):
			return "step %s is listed twice" % step
		seen[step] = true
		if not has_method(STEP_PREFIX + String(step)):
			return "no method %s%s for step %s" % [STEP_PREFIX, step, step]
	return ""
