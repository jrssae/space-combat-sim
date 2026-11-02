class_name MeasureHeldBrain
extends PilotBrain
## For scripts/measure_fight.gd: holds still and keeps firing, so a heavy scene stays in view with bolts flying for as long as it is measured.


func think(_p: Perception, _dt: float) -> PilotCommand:
	var cmd := PilotCommand.new()
	cmd.flight.brake = true
	cmd.combat.fire = true
	return cmd


func describe() -> Dictionary:
	return {"behaviour": "held", "state": "firing"}
