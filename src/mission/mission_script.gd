class_name MissionScript
extends RefCounted
## The base of a mission's script (architecture §18 D51): `data/missions/<id>.gd` extends it, lists its steps in order and
## writes each as a method `step_<name>(m: MissionApi)`, a coroutine the runner awaits before starting the next.
##
## A step waits only through the API (`await m.wait(...)`, `m.until(...)`, `m.say(...)`, `m.player_did(...)`,
## `m.until_objective(...)`, `m.cinematic(...)`), never on timers or signals of its own: that is how `mission skip`
## fast-forwards it and `mission goto` reaches a later step. World changes (`spawn`, `send`, objectives) still run when skipped.
##
## Wait with `until`, never poll: in a skipped step every wait returns at once, so `while m.alive("X"): await m.wait(1.0)` would
## spin. After `MissionApi.SKIP_SPIN_LIMIT` such returns in one skip the API reports the step and gives it one wait per tick.
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
##                 "behaviour": {"type": "ai", "profile": "raider"}, "arrival": "jump",
##                 "via": "carrier"})
##         m.send("RAIDER 1", "NAV ALPHA")
##         await m.until(TriggerSpec.destroyed(["RAIDER 1"]))

## The method each step runs: `step_` + its name.
const STEP_PREFIX: String = "step_"


## The steps, in the order they run.
func steps() -> Array[StringName]:
	return []


## The first step after the opening sequence (the intro shots and the briefing, with the controls held), or &"" for none. While
## the opening runs with the controls held, holding X skips to it (M7-T54).
func opening_until() -> StringName:
	return &""


## Steps the pause menu may skip as one block (M8 D79: the tutorial's training), `{from, to, label}`: offered while a step
## from `from` up to the one before `to` runs, and taking it goes to `to`. Empty for none.
func skip_block() -> Dictionary:
	return {}


## "" when every step has its method (and the opening ends on a listed step), else what is wrong.
func check_steps() -> String:
	var seen: Dictionary = {}
	for step: StringName in steps():
		if seen.has(step):
			return "step %s is listed twice" % step
		seen[step] = true
		if not has_method(STEP_PREFIX + String(step)):
			return "no method %s%s for step %s" % [STEP_PREFIX, step, step]
	if opening_until() != &"" and not seen.has(opening_until()):
		return "the opening ends at %s, which is not a step" % opening_until()
	var block: Dictionary = skip_block()
	if not block.is_empty() and not (seen.has(block.get("from")) and seen.has(block.get("to"))):
		return "the skip block's from and to must be steps"
	return ""
