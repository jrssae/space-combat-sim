class_name MissileStandin
extends RefCounted
## A guided missile stand-in (M4-T12, Q19): bench-only, replaced by M12's missiles. A capital fires a `Projectile` of kind
## missile at a hostile fighter, and this object is its `steering`: proportional navigation at a constant speed with a turn
## rate limit, toward the body it was launched at. Without that body it flies straight on until its lifetime ends. The hit
## resolver sweeps it like any projectile, with the missile's hit radius, and interceptors shoot it down.

const SPEED_MPS: float = 350.0
## The most the missile can turn its velocity, rad/s (about 21 g at its speed).
const TURN_RATE_RAD_S: float = 0.6
## Proportional navigation's gain.
const NAV_GAIN: float = 4.0
const LIFETIME_S: float = 20.0
const DAMAGE: float = 40.0
## A capital fires at hostile fighters within this, m.
const RANGE_M: float = 6000.0
const COLOR: Color = Color(3.0, 1.2, 0.4, 1.0)
const PROJECTILE_SCENE: PackedScene = preload("res://src/weapons/projectile.tscn")

## Steering calls and their cost since the counters were cleared (profiling only, wall clock).
static var steers: int = 0
static var steer_us: int = 0
## The native weapon rows (`ScsWeaponRows`) that steer missiles from their targets' rows this tick (M4-T20), set by the
## director while the rows step the weapons; null for the GDScript.
static var native_rows: Object = null
## Steering calls the native rows answered since the counters were cleared.
static var native_steers: int = 0
static var _weapon: WeaponSpec = null

## The body it flies at (instance id); 0 once that is gone.
var target_id: int = 0
var turn_rate_rad_s: float = TURN_RATE_RAD_S


## The missile's look, lifetime and damage.
static func weapon() -> WeaponSpec:
	if _weapon == null:
		_weapon = WeaponSpec.new()
		_weapon.muzzle_speed_mps = SPEED_MPS
		_weapon.lifetime_s = LIFETIME_S
		_weapon.damage = DAMAGE
		_weapon.hit_radius_m = Projectile.hit_radius_for(Projectile.KIND_MISSILE)
		_weapon.bolt_length_m = 4.0
		_weapon.bolt_radius_m = 0.3
		_weapon.bolt_color = COLOR
	return _weapon


## Fires a missile from `at` (World frame) under `projectiles` at `target`, for `shooter_id` and `faction`, aimed at the lead.
static func launch(projectiles: Node3D, at: Vector3, target: Node3D, shooter_id: int, faction: StringName,
		now_s: float) -> Projectile:
	var missile := PROJECTILE_SCENE.instantiate() as Projectile
	projectiles.add_child(missile)
	missile.configure(weapon())
	missile.set_kind(Projectile.KIND_MISSILE)
	missile.shooter_id = shooter_id
	missile.faction = faction
	var guide := MissileStandin.new()
	guide.target_id = target.get_instance_id()
	missile.guidance = guide
	missile.steering = guide.step
	var direction: Vector3 = launch_direction(at, Vector3.ZERO, target.global_position, _velocity_of(target))
	missile.launch(at, direction * SPEED_MPS, now_s)
	return missile


## The guidance object of `missile`, or null for a projectile that is not one of these.
static func of(missile: Projectile) -> MissileStandin:
	return missile.guidance as MissileStandin if missile != null else null


## Where a missile leaves along: at the target's lead point for the missile's speed, else straight at it. Unit.
static func launch_direction(at: Vector3, shooter_velocity: Vector3, target_at: Vector3, target_velocity: Vector3) -> Vector3:
	var lead: Dictionary = InterceptMath.solve(at, shooter_velocity, target_at, target_velocity, SPEED_MPS, LIFETIME_S)
	var aim: Vector3 = lead["aim_dir"]
	if aim.length_squared() > 0.5:
		return aim
	var line: Vector3 = target_at - at
	return line.normalized() if line.length_squared() > 1e-6 else Vector3.FORWARD


## Proportional navigation for one tick: the velocity that turns `velocity` toward `nav_gain` times the line of sight's
## turn, by at most `max_turn_rate` (rad/s), at the same speed. Straight on once the target is behind or on top of it.
static func steer(position: Vector3, velocity: Vector3, target_position: Vector3, target_velocity: Vector3, nav_gain: float,
		max_turn_rate: float, delta: float) -> Vector3:
	var speed: float = velocity.length()
	var line: Vector3 = target_position - position
	var range_sq: float = line.length_squared()
	if speed < 1e-6 or range_sq < 1e-6:
		return velocity
	var closing: Vector3 = target_velocity - velocity
	if line.dot(closing) >= 0.0:
		return velocity
	var line_turn: Vector3 = line.cross(closing) / range_sq
	var wanted: Vector3 = velocity + nav_gain * line_turn.cross(velocity) * delta
	if wanted.length_squared() < 1e-12:
		return velocity
	return TurretStandin.turned_toward(velocity / speed, wanted.normalized(), max_turn_rate * delta) * speed


## The projectile's steering hook: this tick's velocity toward the target, or straight on without it. The native rows
## answer when they can (the target's row is current); otherwise the GDScript, the reference.
func step(missile: Projectile, delta: float) -> Vector3:
	var started_us: int = Time.get_ticks_usec()  # profiling readout only
	var velocity: Vector3 = missile.velocity
	var answered: bool = false
	if native_rows != null and target_id != 0:
		var out: Vector4 = native_rows.steer_missile(target_id, missile.global_position, velocity, NAV_GAIN, turn_rate_rad_s,
				delta)
		if out.w >= 0.0:
			answered = true
			native_steers += 1
			if out.w > 0.0:
				velocity = Vector3(out.x, out.y, out.z)
			else:
				target_id = 0
	if not answered:
		var target := instance_from_id(target_id) as Node3D if target_id != 0 and is_instance_id_valid(target_id) else null
		if target == null or not target.is_inside_tree() or not target.is_visible_in_tree():
			target_id = 0
		else:
			velocity = steer(missile.global_position, velocity, target.global_position, _velocity_of(target), NAV_GAIN,
					turn_rate_rad_s, delta)
	steers += 1
	steer_us += Time.get_ticks_usec() - started_us
	return velocity


static func _velocity_of(body: Node3D) -> Vector3:
	return (body as RigidBody3D).linear_velocity if body is RigidBody3D else Vector3.ZERO
