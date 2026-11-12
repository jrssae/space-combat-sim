class_name TriggerTimer
extends Trigger
## `timer` (D52): `seconds` of sim time have passed since the trigger went live (or since its first check, if nobody armed it).
## Forced, it simply resolves; time does not move.

var seconds: float = 0.0
## Sim time when it went live; -1 before.
var started_s: float = -1.0


func _init(p_seconds: float = 0.0) -> void:
	kind = &"timer"
	seconds = p_seconds


func arm(world: MissionWorld) -> void:
	if started_s < 0.0:
		started_s = world.time_s


func test(world: MissionWorld) -> bool:
	arm(world)
	return world.time_s - started_s >= seconds


## D51: nothing in the world to change; `make_true` latches it.
func force(_world: MissionWorld) -> void:
	pass


func describe() -> String:
	return "timer %.1f s" % seconds
