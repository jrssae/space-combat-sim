class_name IdleBrain
extends PilotBrain
## Does nothing: the ship coasts at its current velocity, or with `hold` set it holds the brake (all stop) and comes to
## rest. The sandbox's target dummies and the P1/P3 screenshot raiders.

var hold: bool = false


func _init(p_hold: bool = false) -> void:
	hold = p_hold


func think(_p: Perception, _dt: float) -> PilotCommand:
	var cmd := PilotCommand.new()
	cmd.flight.brake = hold
	return cmd


func describe() -> Dictionary:
	return {"behaviour": "idle", "state": "hold" if hold else "coast"}
