class_name AttackBrain
extends PilotBrain
## A raider's gun run (architecture §15.8, M2-T07). States:
##
## - **APPROACH**: close at a speed matched to the target's, face the velocity error until it is small, then the
##   `InterceptMath` lead. The trigger is held when the nose is within `fire_cone_deg` of the lead, in `fire_range_m`, and
##   the `FireLane` is clear.
## - **BREAK**: under `break_range_m`, or after `max_time_on_target_s` in fire range: cross the line of sight (a seeded side)
##   for `break_duration_s`. No fire.
## - **EXTEND**: fly away for at least `extend_min_s` and until beyond `extend_range_m`, then APPROACH again.
##
## It never brakes. Without a hostile target it holds its velocity.
##
## `AiPilot`'s attack (M3-T06) drives the same machine through `engage` with a target of its own choosing, and sets
## `aim_offset_rad`, the pilot's aim error. M2's brains leave it at zero.

enum State { APPROACH, BREAK, EXTEND }

const STATE_NAMES: Array[StringName] = [&"approach", &"break", &"extend"]

var tactics: RaiderTactics = RaiderTactics.new()
var state: State = State.APPROACH
## Seconds spent in the current state, and seconds inside the fire range this approach.
var state_time_s: float = 0.0
var on_target_s: float = 0.0
## Whether the trigger is held, and the nose's error off the intercept lead (degrees), for tests and the console.
var firing: bool = false
var lead_error_deg: float = 0.0
## Radians: the aim error, the lead turned right (x) and up (y) about the line of sight to it.
var aim_offset_rad: Vector2 = Vector2.ZERO

var _seed: int = 0
var _side: float = 1.0
var _rng := RandomNumberGenerator.new()
var _last_range_m: float = INF


func _init(p_tactics: RaiderTactics = null, p_seed: int = 0) -> void:
	if p_tactics != null:
		tactics = p_tactics
	_seed = p_seed
	reset()


func reset() -> void:
	state = State.APPROACH
	state_time_s = 0.0
	on_target_s = 0.0
	firing = false
	_rng.seed = _seed
	_side = 1.0 if _rng.randf() < 0.5 else -1.0
	_last_range_m = INF


func think(p: Perception, dt: float) -> PilotCommand:
	if p.target == null or not p.target_hostile:
		firing = false
		return PilotCommand.new()  # nothing to attack: hold course
	return engage(p, p.target.id, p.target.position, p.target.velocity, dt)


## One tick of the gun run against a hostile. `target_id` is excluded from the fire lane.
func engage(p: Perception, target_id: int, target_position: Vector3, target_velocity: Vector3, dt: float) -> PilotCommand:
	var cmd := PilotCommand.new()
	firing = false
	var los: Vector3 = target_position - p.position
	var range_m: float = los.length()
	if range_m < 1e-3:
		return cmd
	_last_range_m = range_m
	var los_dir: Vector3 = los / range_m
	state_time_s += dt
	# Lead from the muzzles, where the bolts start, so their parallel paths cross at the intercept.
	var lead: Dictionary = InterceptMath.solve(p.position + p.muzzle_offset, p.velocity, target_position, target_velocity,
			p.muzzle_speed_mps, p.weapon_lifetime_s)
	var lead_dir: Vector3 = (lead["aim_dir"] as Vector3) if bool(lead["ok"]) else los_dir
	if aim_offset_rad != Vector2.ZERO:
		lead_dir = _offset(lead_dir)
	var v_des := Vector3.ZERO
	var face_dir: Vector3 = lead_dir
	var cap: float = tactics.max_speed_mps
	match state:
		State.APPROACH:
			if range_m < tactics.fire_range_m:
				on_target_s += dt
			if range_m < tactics.break_range_m or on_target_s >= tactics.max_time_on_target_s:
				_enter(State.BREAK)
			else:
				var closing: float = tactics.closing_far_mps if range_m > tactics.near_range_m else tactics.closing_near_mps
				v_des = target_velocity + los_dir * closing
				cap = maxf(cap, target_velocity.length()) + closing  # never slower than the target
				var dv: Vector3 = v_des - p.velocity
				face_dir = lead_dir if dv.length() < tactics.face_lead_delta_v_mps else dv.normalized()
				lead_error_deg = rad_to_deg(PilotSteering.angle_to(p.basis, lead_dir))
				var cone_deg: float = minf(tactics.fire_cone_deg, rad_to_deg(atan(tactics.fire_miss_m / range_m)))
				firing = range_m < tactics.fire_range_m and lead_error_deg < cone_deg \
						and FireLane.clear_seen(p, p.forward(), range_m, target_id)
		State.BREAK:
			if state_time_s >= tactics.break_duration_s:
				_enter(State.EXTEND)
			else:
				v_des = target_velocity + _across(los_dir) * tactics.break_speed_mps
				face_dir = (v_des - p.velocity).normalized() if (v_des - p.velocity).length() > 1.0 else p.forward()
		State.EXTEND:
			if state_time_s >= tactics.extend_min_s and range_m > tactics.extend_range_m:
				_enter(State.APPROACH)
			else:
				v_des = target_velocity - los_dir * tactics.closing_far_mps
				face_dir = (v_des - p.velocity).normalized() if (v_des - p.velocity).length() > 1.0 else p.forward()
	if tactics.max_speed_mps > 0.0 and v_des.length() > cap:
		v_des = v_des.normalized() * cap
	cmd.flight.rot = PilotSteering.face(p.basis, face_dir, p.capability.rate_max_rad)
	seek_velocity(cmd.flight, p, v_des)
	cmd.combat.fire = firing
	return cmd


## A fresh run for a new target. The seeded break sides carry on.
func restart() -> void:
	_enter(State.APPROACH)
	firing = false
	_last_range_m = INF


func describe() -> Dictionary:
	return {"behaviour": "attack", "state": String(STATE_NAMES[state]), "state_time_s": snappedf(state_time_s, 0.1),
			"range_m": snappedf(_last_range_m, 1.0) if _last_range_m < INF else -1.0, "firing": firing}


func _enter(next: State) -> void:
	state = next
	state_time_s = 0.0
	if next == State.APPROACH:
		on_target_s = 0.0
	if next == State.BREAK:
		_side = 1.0 if _rng.randf() < 0.5 else -1.0


# The lead turned by the aim error.
func _offset(lead_dir: Vector3) -> Vector3:
	var right: Vector3 = lead_dir.cross(Vector3.UP if absf(lead_dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
	var up: Vector3 = right.cross(lead_dir)
	return (lead_dir + right * tan(aim_offset_rad.x) + up * tan(aim_offset_rad.y)).normalized()


# Perpendicular to the line of sight, on the seeded side.
func _across(los_dir: Vector3) -> Vector3:
	var up := Vector3.UP if absf(los_dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	return los_dir.cross(up).normalized() * _side
