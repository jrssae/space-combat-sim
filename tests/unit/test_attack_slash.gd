extends GutTest
## AttackSlash (M3-T18, Q19), pure on scripted perceptions: a pass at speed on a lead course with the fire gate deciding, a turn
## and burn once the range opens after closest approach, then a chase that settles at its range; time on target counts the time
## with the target inside the fire gate.

const DT: float = 1.0 / 60.0

var tactics: RaiderTactics
var slash: AttackSlash


func before_each() -> void:
	tactics = load(AiProfile.STARFURY_TACTICS_PATH) as RaiderTactics
	slash = AttackSlash.new(tactics)


func _p(target_at: Vector3, own_velocity: Vector3 = Vector3.ZERO, basis: Basis = Basis.IDENTITY) -> Perception:
	var p := Perception.new()
	p.basis = basis
	p.velocity = own_velocity
	var cap := ShipCapability.new()
	cap.a_main = 30.0
	cap.a_retro = 30.0
	cap.a_rcs = Vector2(10.0, 10.0)
	p.capability = cap
	p.muzzle_speed_mps = 1000.0
	p.weapon_lifetime_s = 4.0
	return p


func _engage(p: Perception, target_at: Vector3, target_velocity: Vector3 = Vector3.ZERO) -> PilotCommand:
	return slash.engage(p, 5, target_at, target_velocity, DT)


func test_the_pass_closes_at_speed_on_the_lead_and_fires_through_the_gate() -> void:
	var p := _p(Vector3(0.0, 0.0, -3000.0))
	var cmd: PilotCommand = _engage(p, Vector3(0.0, 0.0, -3000.0))
	assert_eq(slash.state, AttackSlash.State.PASS)
	var aim := (Vector3(0.0, 0.0, -3000.0) + Vector3.UP * AttackSlash.PASS_OFFSET_M).normalized()  # no sideways motion yet: up
	assert_almost_eq(slash.desired_velocity, aim * tactics.closing_far_mps, Vector3.ONE * 1e-3,
			"closing at speed, on a course that goes by 200 m to the side")
	assert_false(cmd.combat.fire, "beyond the fire range")
	var close := _p(Vector3(0.0, 0.0, -800.0), Vector3(0.0, 0.0, -150.0))
	cmd = _engage(close, Vector3(0.0, 0.0, -800.0))
	assert_true(slash.in_gate, "nose on the target inside the fire range")
	assert_true(cmd.combat.fire, "the gate decides: fire")
	var off := _p(Vector3(0.0, 0.0, -800.0), Vector3(0.0, 0.0, -150.0), Basis(Vector3.UP, deg_to_rad(5.0)))
	cmd = _engage(off, Vector3(0.0, 0.0, -800.0))
	assert_false(cmd.combat.fire, "5 degrees off at 800 m misses: hold fire")


func test_the_pass_goes_by_on_the_side_it_is_already_moving_to() -> void:
	# Drifting right relative to the target: the pass goes by on the right.
	_engage(_p(Vector3(0.0, 0.0, -2000.0), Vector3(30.0, 0.0, -150.0)), Vector3(0.0, 0.0, -2000.0))
	var aim := (Vector3(0.0, 0.0, -2000.0) + Vector3.RIGHT * AttackSlash.PASS_OFFSET_M).normalized()
	assert_almost_eq(slash.desired_velocity.normalized(), aim, Vector3.ONE * 1e-4)


func test_once_the_range_opens_it_turns_and_burns_back_then_chases() -> void:
	# Closing at 150 m/s past a target at rest: 300 m out, then 290 m, then opening behind.
	_engage(_p(Vector3(0.0, 0.0, -300.0), Vector3(0.0, 0.0, -150.0)), Vector3(0.0, 0.0, -300.0))
	_engage(_p(Vector3(0.0, 0.0, -50.0), Vector3(0.0, 0.0, -150.0)), Vector3(0.0, 0.0, -50.0))
	assert_eq(slash.state, AttackSlash.State.PASS)
	var behind := Vector3(0.0, 0.0, 100.0)  # passed: the target is now behind
	_engage(_p(behind, Vector3(0.0, 0.0, -150.0)), behind)
	assert_eq(slash.state, AttackSlash.State.TURN, "the range opened after closest approach")
	assert_eq(slash.passes, 1)
	assert_true(slash.desired_all_axes, "mains, retros and RCS together")
	assert_gt(slash.desired_velocity.z, 0.0, "burning back toward the target")
	# Nose round onto the target (behind: +Z) and closing again: chase.
	var turned := Basis(Vector3.UP, PI)
	_engage(_p(behind, Vector3(0.0, 0.0, 10.0), turned), behind)
	assert_eq(slash.state, AttackSlash.State.CHASE)


func test_the_chase_settles_at_its_range_and_a_lost_target_starts_a_new_pass() -> void:
	slash.state = AttackSlash.State.CHASE
	var target_velocity := Vector3(0.0, 0.0, -80.0)
	_engage(_p(Vector3(0.0, 0.0, -AttackSlash.CHASE_RANGE_M), target_velocity), Vector3(0.0, 0.0, -AttackSlash.CHASE_RANGE_M), target_velocity)
	assert_almost_eq(slash.desired_velocity, target_velocity, Vector3.ONE * 1e-3, "at the chase range: the target's velocity")
	_engage(_p(Vector3(0.0, 0.0, -1500.0), target_velocity), Vector3(0.0, 0.0, -1500.0), target_velocity)
	assert_almost_eq(slash.desired_velocity.z - target_velocity.z, -AttackSlash.CHASE_CLOSING_MPS, 1e-3, "closing, at most 60 m/s")
	_engage(_p(Vector3(0.0, 0.0, -200.0), target_velocity), Vector3(0.0, 0.0, -200.0), target_velocity)
	assert_almost_eq(slash.desired_velocity.z - target_velocity.z, AttackSlash.CHASE_OPENING_MPS, 1e-3, "too close: opening")
	var far: float = tactics.fire_range_m * AttackSlash.LOST_RANGE_FACTOR + 100.0
	_engage(_p(Vector3(0.0, 0.0, -far), target_velocity), Vector3(0.0, 0.0, -far), target_velocity)
	assert_eq(slash.state, AttackSlash.State.PASS, "lost: a new pass")


func test_time_on_target_counts_the_time_in_the_gate() -> void:
	for i: int in 60:
		_engage(_p(Vector3(0.0, 0.0, -600.0), Vector3(0.0, 0.0, -100.0)), Vector3(0.0, 0.0, -600.0))
	assert_almost_eq(slash.time_on_target_s, 1.0, 1e-6, "a second with the nose on it inside the fire range")
	for i: int in 60:
		_engage(_p(Vector3(0.0, 0.0, -600.0), Vector3(0.0, 0.0, -100.0), Basis(Vector3.UP, deg_to_rad(30.0))), Vector3(0.0, 0.0, -600.0))
	assert_almost_eq(slash.time_on_target_s, 1.0, 1e-6, "not while the nose is off it")
	slash.reset()
	assert_eq(slash.time_on_target_s, 0.0)


func test_a_close_pass_goes_by_at_100_m() -> void:
	slash.pass_offset_m = AttackSlash.CLOSE_PASS_OFFSET_M
	_engage(_p(Vector3(0.0, 0.0, -2000.0), Vector3(30.0, 0.0, -150.0)), Vector3(0.0, 0.0, -2000.0))
	var aim := (Vector3(0.0, 0.0, -2000.0) + Vector3.RIGHT * AttackSlash.CLOSE_PASS_OFFSET_M).normalized()
	assert_almost_eq(slash.desired_velocity.normalized(), aim, Vector3.ONE * 1e-4)
