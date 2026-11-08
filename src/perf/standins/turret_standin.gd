class_name TurretStandin
extends Node3D
## A capital's turret stand-in (M4-T07, Q19): bench-only, replaced by M12's turrets, AI gunners and defence grid. A `GUN`
## takes the nearest hostile fighter within `RANGE_M` from the contact scan, turns its gun axis toward the lead point at a
## limited rate and fires pulse-cannon bolts through a `PulseCannonGate` only while the aim is inside `GATE_RAD`. An
## `INTERCEPTOR` shoots down a hostile projectile within `INTERCEPT_RANGE_M` at its own rate (no bolt of its own): the nearest
## missile first, else the nearest bolt (M4-T12), from the candidates the director found for it through the hit broad phase's
## grid. `StandinDirector` steps every turret once per tick; a turret has no process of its own. With the native rows on
## (M4-T20) the director's `NativeWeapons` steps them instead and keeps their state; this code is then the reference.

enum Role { GUN, INTERCEPTOR }

const RANGE_M: float = 4000.0
const INTERCEPT_RANGE_M: float = 1500.0
const TURN_RATE_RAD_S: float = PI / 6.0
## The fire gate: the aim may be this far off the lead point.
const GATE_RAD: float = 1.5 * PI / 180.0
## A gun looks for a new target this often, in ticks (staggered across turrets); it aims and fires every tick.
const RETARGET_TICKS: int = 6
const INTERCEPT_INTERVAL_S: float = 0.5
## Contacts larger than this are capitals or rocks, not fighters, m (until the scan carries kinds, M4-T09).
const FIGHTER_RADIUS_MAX_M: float = 50.0
const MUZZLE_SPEED_MPS: float = 1000.0
const SHOT_INTERVAL_S: float = 1.0
const BOLT_LIFETIME_S: float = 4.2
const BOLT_DAMAGE: float = 10.0

static var _weapon: WeaponSpec = null

var role: Role = Role.GUN
var capital: CapitalStandin = null
## The gun's pointing, World frame, unit.
var axis: Vector3 = Vector3.FORWARD
## The body it is shooting at (instance id), 0 for none.
var target_id: int = 0
## Bolts fired (a gun) or projectiles shot down (an interceptor).
var shots: int = 0
## Missiles an interceptor shot down.
var missile_shots: int = 0
var gate: PulseCannonGate = PulseCannonGate.new(1, SHOT_INTERVAL_S)

var _aim_error: float = PI


## The bolt every gun fires.
static func weapon() -> WeaponSpec:
	if _weapon == null:
		_weapon = WeaponSpec.new()
		_weapon.muzzle_speed_mps = MUZZLE_SPEED_MPS
		_weapon.shot_interval_s = SHOT_INTERVAL_S
		_weapon.lifetime_s = BOLT_LIFETIME_S
		_weapon.damage = BOLT_DAMAGE
	return _weapon


## The aim's distance from the lead point after the last step, rad (PI with no target).
func aim_error_rad() -> float:
	return _aim_error


## The gun's axis turned toward `wanted` by at most `max_angle`, both unit vectors.
static func turned_toward(from: Vector3, wanted: Vector3, max_angle: float) -> Vector3:
	var angle: float = from.angle_to(wanted)
	if angle <= max_angle:
		return wanted
	var turn_axis: Vector3 = from.cross(wanted)
	if turn_axis.length_squared() < 1e-12:
		turn_axis = from.cross(Vector3.UP if absf(from.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT)
	return from.rotated(turn_axis.normalized(), max_angle).normalized()


## Fires one of `cap`'s gun bolts from `at` at `velocity` (World frame) as a row the core owns (M4-T35): the native rows'
## fire decision (M4-T20). Nothing without a core.
static func launch_bolt(cap: CapitalStandin, at: Vector3, velocity: Vector3, now_s: float) -> void:
	var sim: SimCore = SimCore.current()
	if sim != null and sim.bolt_rows_on():
		sim.add_bolt(at, velocity, cap.faction, cap.get_instance_id(), weapon(), now_s)


## What the native rows keep for this turret while they step it (M4-T20): `[axis, target_id, aim error, the gate's ready
## time, shots, missile_shots]`.
func native_state() -> Array:
	return [axis, target_id, _aim_error, gate._ready_at_s, shots, missile_shots]


## Takes back the state the native rows kept (`native_state`'s order), so the GDScript carries on where they left off.
func take_native_state(p_axis: Vector3, p_target_id: int, aim_error: float, ready_at_s: float, p_shots: int,
		p_missile_shots: int) -> void:
	axis = p_axis
	target_id = p_target_id
	_aim_error = aim_error
	gate._ready_at_s = ready_at_s
	shots = p_shots
	missile_shots = p_missile_shots
