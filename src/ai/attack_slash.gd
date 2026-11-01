class_name AttackSlash
extends PilotBrain
## The slashing pass and chase (architecture §16 D34, M3-T18, maintainer Q19): how better pilots fight a Starfury-style fight.
## `BehaviourAttack` delegates to it instead of `AttackBrain` for the pilots `AiTemperament.slashes` picks. States:
##
## - **PASS**: close at speed (the target's velocity plus `tactics.closing_far_mps`) on a course that goes by `PASS_OFFSET_M`
##   to the side of the target, on whichever side the ship already is, so the line of sight turns slowly enough for the nose to
##   stay on the lead: facing the lead and firing through closest approach under the same fire gate as `AttackBrain` (cone, miss distance,
##   fire range, `FireLane`). The driver's avoidance stays on, so the pass goes by clear of the target. Once the range opens
##   again after closest approach, the run turns.
## - **TURN**: face the target and burn to kill the overshoot: the wish is the target's velocity plus `CHASE_CLOSING_MPS`
##   toward it, with the mains (and on the Starfury the retros, equal since M3-T15) and the RCS all working (`all_axes`). It
##   fires whenever the gate allows. When the nose is on the lead and the ship closes on the target again, it chases.
## - **CHASE**: hold the target in the fire gate from behind at a small closing speed: the wish is the target's velocity plus
##   a closure that settles the range at `CHASE_RANGE_M` (at most `CHASE_CLOSING_MPS` in, `CHASE_OPENING_MPS` out). Beyond
##   `LOST_RANGE_FACTOR` x the fire range it starts a new pass.
##
## `time_on_target_s` counts the sim time with the target inside the fire gate (cone, miss distance and range), the measure
## AC26 compares with the standard attack's. The speed caps are `AttackBrain`'s (`RaiderTactics.max_speed_mps`).

enum State { PASS, TURN, CHASE }

const STATE_NAMES: Array[StringName] = [&"pass", &"turn", &"chase"]
## m: the pass goes by this far to the side (the line of sight then turns at about the closing speed / this, 0.75 rad/s at
## 150 m/s: trackable, where a pass straight through swings faster than any nose turns).
const PASS_OFFSET_M: float = 200.0
## m: the close pass of the most aggressive pilots (`AiTemperament.close_pass_chance`); harder to track, the guns on target
## for less of it, but nearer the target.
const CLOSE_PASS_OFFSET_M: float = 100.0
const CHASE_RANGE_M: float = 500.0
const CHASE_CLOSING_MPS: float = 60.0
const CHASE_OPENING_MPS: float = 30.0
## s^-1: closure per metre of range error in the chase.
const CHASE_GAIN: float = 0.1
const LOST_RANGE_FACTOR: float = 1.5
## TURN ends once the nose is within this of the lead (degrees) and the ship closes on the target.
const ON_TARGET_DEG: float = 10.0

var tactics: RaiderTactics = RaiderTactics.new()
var state: State = State.PASS
var state_time_s: float = 0.0
var firing: bool = false
var in_gate: bool = false
var lead_error_deg: float = 0.0
var time_on_target_s: float = 0.0
## Passes flown (each PASS that turned).
var passes: int = 0
## m: this pass's offset (`BehaviourAttack` sets it per pass: `PASS_OFFSET_M` or `CLOSE_PASS_OFFSET_M`).
var pass_offset_m: float = PASS_OFFSET_M
## Radians: the aim error (`BehaviourAttack` sets it), as `AttackBrain.aim_offset_rad`.
var aim_offset_rad: Vector2 = Vector2.ZERO

var _last_range_m: float = INF
var _last_lead_dir: Vector3 = Vector3.ZERO


func _init(p_tactics: RaiderTactics = null) -> void:
	if p_tactics != null:
		tactics = p_tactics
	reset()


func reset() -> void:
	state = State.PASS
	state_time_s = 0.0
	firing = false
	in_gate = false
	time_on_target_s = 0.0
	passes = 0
	_last_range_m = INF
	_last_lead_dir = Vector3.ZERO


## A fresh run on a new target.
func restart() -> void:
	_enter(State.PASS)
	_last_range_m = INF
	_last_lead_dir = Vector3.ZERO
	firing = false


func engage(p: Perception, target_id: int, target_position: Vector3, target_velocity: Vector3, dt: float) -> PilotCommand:
	var cmd := PilotCommand.new()
	firing = false
	in_gate = false
	var los: Vector3 = target_position - p.position
	var range_m: float = los.length()
	if range_m < 1e-3:
		return cmd
	var los_dir: Vector3 = los / range_m
	state_time_s += dt
	var lead: Dictionary = InterceptMath.solve(p.position + p.muzzle_offset, p.velocity, target_position, target_velocity,
			p.muzzle_speed_mps, p.weapon_lifetime_s)
	var lead_dir: Vector3 = (lead["aim_dir"] as Vector3) if bool(lead["ok"]) else los_dir
	if aim_offset_rad != Vector2.ZERO:
		lead_dir = _offset(lead_dir)
	lead_error_deg = rad_to_deg(PilotSteering.angle_to(p.basis, lead_dir))
	# How fast the lead turns, fed forward into the nose's turn (`PilotSteering.face_tracking`): a pass's line of sight turns
	# faster and faster toward closest approach, and a P loop alone trails it by more than the gate allows.
	var lead_omega := Vector3.ZERO
	if _last_lead_dir != Vector3.ZERO and dt > 0.0:
		lead_omega = _last_lead_dir.cross(lead_dir) / dt
	_last_lead_dir = lead_dir
	var cone_deg: float = minf(tactics.fire_cone_deg, rad_to_deg(atan(tactics.fire_miss_m / range_m)))
	in_gate = range_m < tactics.fire_range_m and lead_error_deg < cone_deg
	if in_gate:
		time_on_target_s += dt
	var opening: bool = range_m > _last_range_m
	var closing_rate: float = -(target_velocity - p.velocity).dot(los_dir)  # positive: closing
	_last_range_m = range_m
	var v_des := Vector3.ZERO
	var face_dir: Vector3 = lead_dir
	var tracking: bool = true  # facing the lead, its turn fed forward
	var all_axes: bool = false
	var cap: float = tactics.max_speed_mps
	# The state changes first, so a tick flies the state it ends in.
	match state:
		State.PASS:
			if opening and range_m < tactics.fire_range_m:
				passes += 1
				_enter(State.TURN)
		State.TURN:
			if lead_error_deg < ON_TARGET_DEG and closing_rate > 0.0:
				_enter(State.CHASE)
		State.CHASE:
			if range_m > tactics.fire_range_m * LOST_RANGE_FACTOR:
				_enter(State.PASS)
	match state:
		State.PASS:
			v_des = target_velocity + _pass_dir(p, target_position, target_velocity, los, los_dir) * tactics.closing_far_mps
			cap = maxf(cap, target_velocity.length()) + tactics.closing_far_mps
			var dv: Vector3 = v_des - p.velocity
			if dv.length() >= tactics.face_lead_delta_v_mps and range_m >= tactics.fire_range_m:
				face_dir = dv.normalized()
				tracking = false
		State.TURN:
			v_des = target_velocity + los_dir * CHASE_CLOSING_MPS
			cap = maxf(cap, target_velocity.length()) + CHASE_CLOSING_MPS
			all_axes = true
		State.CHASE:
			var closure: float = clampf((range_m - CHASE_RANGE_M) * CHASE_GAIN, -CHASE_OPENING_MPS, CHASE_CLOSING_MPS)
			v_des = target_velocity + los_dir * closure
			cap = maxf(cap, target_velocity.length()) + CHASE_CLOSING_MPS
			all_axes = true
	if tactics.max_speed_mps > 0.0 and v_des.length() > cap:
		v_des = v_des.normalized() * cap
	firing = in_gate and FireLane.clear(p.position, p.forward(), range_m, p.contacts, target_id, p.friendly_fire)
	if tracking:
		cmd.flight.rot = PilotSteering.face_tracking(p.basis, face_dir, lead_omega, p.capability.rate_max_rad)
	else:
		cmd.flight.rot = PilotSteering.face(p.basis, face_dir, p.capability.rate_max_rad)
	seek_velocity(cmd.flight, p, v_des, all_axes)
	cmd.combat.fire = firing
	return cmd


# Toward a point `PASS_OFFSET_M` to the side of the target, square to the line of sight, on the side the ship is already
# moving to (relative to the target; straight up when it has no sideways motion), so the pass goes by rather than through.
func _pass_dir(p: Perception, target_position: Vector3, target_velocity: Vector3, los: Vector3, los_dir: Vector3) -> Vector3:
	var rel_v: Vector3 = p.velocity - target_velocity
	var side: Vector3 = rel_v - los_dir * rel_v.dot(los_dir)
	if side.length_squared() < 1.0:
		var up: Vector3 = p.basis.y
		side = up - los_dir * up.dot(los_dir)
	if side.length_squared() < 1e-6:
		return los_dir
	var aim: Vector3 = los + side.normalized() * pass_offset_m
	return aim.normalized()


func describe() -> Dictionary:
	return {"behaviour": "attack", "state": String(STATE_NAMES[state]), "state_time_s": snappedf(state_time_s, 0.1),
			"range_m": snappedf(_last_range_m, 1.0) if _last_range_m < INF else -1.0, "firing": firing}


func _enter(next: State) -> void:
	state = next
	state_time_s = 0.0


# The lead turned by the aim error (as `AttackBrain._offset`).
func _offset(lead_dir: Vector3) -> Vector3:
	var right: Vector3 = lead_dir.cross(Vector3.UP if absf(lead_dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
	var up: Vector3 = right.cross(lead_dir)
	return (lead_dir + right * tan(aim_offset_rad.x) + up * tan(aim_offset_rad.y)).normalized()
