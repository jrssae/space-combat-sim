class_name BehaviourIdle
extends AiBehaviour
## Nothing to do (architecture §16 D34): hold position with the brake (`AiProfile.idle_hold`) or coast. The fallback,
## always scoring `SCORE`, so a pilot with nothing better idles.

const SCORE: float = 0.05

var hold: bool = false


func _init(p_hold: bool = false) -> void:
	id = &"idle"
	hold = p_hold


func score(_ctx: AiContext) -> float:
	return SCORE


func think(_ctx: AiContext, _dt: float) -> PilotCommand:
	var cmd := PilotCommand.new()
	cmd.flight.brake = hold
	return cmd


func describe() -> Dictionary:
	return {"state": "hold" if hold else "coast"}
