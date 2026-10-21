extends GutTest
## SpeedGovernor: the mass-limited thrust curve, the assist cap and the hard ceiling (architecture §5.6).

const LIMIT: float = 9999.0
const CAP: float = 5000.0


func test_gain_is_one_at_rest_and_zero_at_the_limit() -> void:
	assert_eq(SpeedGovernor.thrust_gain(0.0, LIMIT), 1.0)
	assert_eq(SpeedGovernor.thrust_gain(LIMIT, LIMIT), 0.0)
	assert_eq(SpeedGovernor.thrust_gain(LIMIT * 2.0, LIMIT), 0.0, "past the limit stays at zero, never negative")


func test_gain_falls_monotonically() -> void:
	var previous: float = 1.0
	for speed: float in [500.0, 2000.0, CAP, 8000.0, 9500.0]:
		var gain: float = SpeedGovernor.thrust_gain(speed, LIMIT)
		assert_lt(gain, previous, "gain at %s m/s" % speed)
		previous = gain


func test_gain_matches_the_lorentz_factor() -> void:
	var speed: float = CAP
	assert_almost_eq(SpeedGovernor.thrust_gain(speed, LIMIT) * SpeedGovernor.mass_factor(speed, LIMIT), 1.0, 1e-9)
	var ratio: float = speed / LIMIT
	assert_almost_eq(SpeedGovernor.mass_factor(speed, LIMIT), 1.0 / sqrt(1.0 - ratio * ratio), 1e-9)


func test_a_non_positive_limit_switches_the_effect_off() -> void:
	assert_eq(SpeedGovernor.thrust_gain(7000.0, 0.0), 1.0)
	assert_eq(SpeedGovernor.assist_cap_correction(Vector3.FORWARD, Vector3.FORWARD * 9000.0, 0.0), Vector3.ZERO)
	assert_eq(SpeedGovernor.clamp_velocity(Vector3.FORWARD * 9000.0, 0.0), Vector3.FORWARD * 9000.0)


func test_cap_cancels_thrust_along_the_velocity_once_at_the_cap() -> void:
	var velocity: Vector3 = Vector3(0.0, 0.0, -CAP)
	var force: Vector3 = Vector3(1000.0, 0.0, -5000.0)
	var fixed: Vector3 = force + SpeedGovernor.assist_cap_correction(force, velocity, CAP)
	assert_almost_eq(fixed.z, 0.0, 1e-9, "the forward part is gone")
	assert_almost_eq(fixed.x, 1000.0, 1e-9, "the sideways part stays, so the ship can still turn its velocity")


func test_cap_does_nothing_below_the_cap_or_when_slowing() -> void:
	var force: Vector3 = Vector3(0.0, 0.0, -5000.0)
	assert_eq(SpeedGovernor.assist_cap_correction(force, Vector3(0.0, 0.0, -(CAP - 1.0)), CAP), Vector3.ZERO)
	var braking: Vector3 = Vector3(0.0, 0.0, 5000.0)
	assert_eq(SpeedGovernor.assist_cap_correction(braking, Vector3(0.0, 0.0, -CAP * 1.2), CAP), Vector3.ZERO,
			"thrust against the velocity is always allowed")


func test_clamp_velocity_keeps_direction() -> void:
	var fast: Vector3 = Vector3(3.0, 0.0, -4.0).normalized() * (LIMIT + 500.0)
	var clamped: Vector3 = SpeedGovernor.clamp_velocity(fast, LIMIT)
	assert_almost_eq(clamped.length(), LIMIT, 1e-6)
	assert_almost_eq(clamped.normalized().dot(fast.normalized()), 1.0, 1e-9)
	var slow: Vector3 = Vector3(10.0, 0.0, 0.0)
	assert_eq(SpeedGovernor.clamp_velocity(slow, LIMIT), slow)
