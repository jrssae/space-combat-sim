class_name PatrolBrain
extends PilotBrain
## Flies a loop of waypoints at a cruise speed (architecture §15.8): the nose toward the next waypoint, the desired
## velocity `min(cruise, 0.8 * sqrt(2 * a_stop * distance))` toward it so the ship slows for the arrival, the next waypoint
## taken within `arrival_m`. Waypoints are `UniversePos` (rebase-proof), turned into World-local points every tick.

var waypoints: Array[UniversePos] = []
var cruise_mps: float = 80.0
var arrival_m: float = 150.0
## Index of the waypoint being flown to.
var index: int = 0
## Waypoints reached so far (a loop counts every pass).
var reached: int = 0


func _init(p_waypoints: Array[UniversePos] = [], p_cruise_mps: float = 80.0) -> void:
	waypoints = p_waypoints
	cruise_mps = p_cruise_mps


func think(p: Perception, _dt: float) -> PilotCommand:
	var cmd := PilotCommand.new()
	if waypoints.is_empty():
		return cmd
	var to: Vector3 = p.to_local(waypoints[index]) - p.position
	if to.length() < arrival_m:
		index = (index + 1) % waypoints.size()
		reached += 1
		to = p.to_local(waypoints[index]) - p.position
	var distance: float = to.length()
	if distance < 1e-3:
		return cmd
	var dir: Vector3 = to / distance
	var speed: float = minf(cruise_mps, 0.8 * sqrt(2.0 * p.capability.a_retro * distance))
	var v_des: Vector3 = dir * speed
	cmd.flight.rot = PilotSteering.face(p.basis, dir, p.capability.rate_max_rad)
	PilotSteering.apply_seek(cmd.flight, PilotSteering.seek(p.velocity, v_des, p.basis, p.capability))
	return cmd


func describe() -> Dictionary:
	return {"behaviour": "patrol", "state": "waypoint %d of %d" % [index + 1, waypoints.size()], "reached": reached}


func reset() -> void:
	index = 0
	reached = 0
