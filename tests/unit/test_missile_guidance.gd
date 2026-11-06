extends GutTest
## The missile stand-in's guidance (M4-T12, Q19): proportional navigation at a constant speed with a turn rate limit. Pure
## kinematics: a missile launched at a crossing fighter closes and hits within its lifetime at the stand-in's turn rate and
## misses at a tenth of it.

const DT: float = 1.0 / 60.0
## The hull sphere of a fighter the size of a Starfury, m: a pass inside it plus the missile's hit radius is a hit.
const FIGHTER_RADIUS_M: float = 5.0


# Flies a missile from the origin, pointed at the target's start, against a target crossing at constant velocity; returns
# the closest approach (m) and when it came (s).
func _fly(turn_rate: float, target_at: Vector3, target_velocity: Vector3) -> Dictionary:
	var p := Vector3.ZERO
	var v: Vector3 = (target_at - p).normalized() * MissileStandin.SPEED_MPS
	var tp: Vector3 = target_at
	var closest: float = INF
	var when: float = -1.0
	for i: int in roundi(MissileStandin.LIFETIME_S / DT):
		v = MissileStandin.steer(p, v, tp, target_velocity, MissileStandin.NAV_GAIN, turn_rate, DT)
		# The closest point of this tick's relative motion, both flying straight through it.
		var rel0: Vector3 = tp - p
		var rel_step: Vector3 = (target_velocity - v) * DT
		var t: float = clampf(-rel0.dot(rel_step) / maxf(rel_step.length_squared(), 1e-12), 0.0, 1.0)
		var d: float = (rel0 + rel_step * t).length()
		if d < closest:
			closest = d
			when = (float(i) + t) * DT
		p += v * DT
		tp += target_velocity * DT
	return {"miss": closest, "at": when}


func test_a_missile_hits_a_crossing_fighter_within_its_lifetime() -> void:
	var flight: Dictionary = _fly(MissileStandin.TURN_RATE_RAD_S, Vector3(0.0, 0.0, -1500.0), Vector3(150.0, 0.0, 0.0))
	assert_lt(float(flight["miss"]), FIGHTER_RADIUS_M + Projectile.hit_radius_for(Projectile.KIND_MISSILE),
			"it passes inside the fighter's hull sphere (%.2f m)" % float(flight["miss"]))
	assert_lt(float(flight["at"]), MissileStandin.LIFETIME_S, "before it expires")


func test_it_also_hits_a_fighter_crossing_above_and_climbing() -> void:
	var flight: Dictionary = _fly(MissileStandin.TURN_RATE_RAD_S, Vector3(800.0, 400.0, -2500.0), Vector3(-60.0, 90.0, 40.0))
	assert_lt(float(flight["miss"]), FIGHTER_RADIUS_M + Projectile.hit_radius_for(Projectile.KIND_MISSILE),
			"closes in three dimensions (%.2f m)" % float(flight["miss"]))


func test_at_a_tenth_of_the_turn_rate_it_misses() -> void:
	var flight: Dictionary = _fly(MissileStandin.TURN_RATE_RAD_S * 0.1, Vector3(0.0, 0.0, -1500.0), Vector3(150.0, 0.0, 0.0))
	assert_gt(float(flight["miss"]), 50.0, "it cannot turn hard enough (%.1f m)" % float(flight["miss"]))


func test_the_turn_per_tick_is_limited_and_the_speed_holds() -> void:
	var v := Vector3(0.0, 0.0, -MissileStandin.SPEED_MPS)
	# A target abeam asks for far more than the limit.
	var after: Vector3 = MissileStandin.steer(Vector3.ZERO, v, Vector3(1000.0, 0.0, -10.0), Vector3(0.0, 0.0, 300.0),
			MissileStandin.NAV_GAIN, MissileStandin.TURN_RATE_RAD_S, DT)
	assert_almost_eq(after.length(), MissileStandin.SPEED_MPS, 1e-3, "constant speed")
	assert_gt(v.angle_to(after), 0.0, "it turns")
	assert_lte(v.angle_to(after), MissileStandin.TURN_RATE_RAD_S * DT + 1e-6, "by at most the turn rate")
	assert_gt(after.x, 0.0, "toward the target's side")


func test_a_target_dead_ahead_and_still_needs_no_turn() -> void:
	var v := Vector3(0.0, 0.0, -MissileStandin.SPEED_MPS)
	var after: Vector3 = MissileStandin.steer(Vector3.ZERO, v, Vector3(0.0, 0.0, -2000.0), Vector3.ZERO,
			MissileStandin.NAV_GAIN, MissileStandin.TURN_RATE_RAD_S, DT)
	assert_almost_eq(v.angle_to(after), 0.0, 1e-6)


func test_it_flies_straight_once_past_or_on_top_of_its_target() -> void:
	var v := Vector3(0.0, 0.0, -MissileStandin.SPEED_MPS)
	var after: Vector3 = MissileStandin.steer(Vector3.ZERO, v, Vector3.ZERO, Vector3(10.0, 0.0, 0.0),
			MissileStandin.NAV_GAIN, MissileStandin.TURN_RATE_RAD_S, DT)
	assert_eq(after, v, "no line of sight to steer on")


func test_the_launch_points_at_the_lead() -> void:
	var at := Vector3(0.0, 0.0, -2000.0)
	var target_velocity := Vector3(100.0, 0.0, 0.0)
	var dir: Vector3 = MissileStandin.launch_direction(Vector3.ZERO, Vector3.ZERO, at, target_velocity)
	assert_almost_eq(dir.length(), 1.0, 1e-5)
	assert_gt(dir.x, 0.0, "ahead of the crossing target")
	var t: float = 2000.0 / MissileStandin.SPEED_MPS
	assert_almost_eq(dir.angle_to(at + target_velocity * t), 0.0, 0.05, "about where it will be")
