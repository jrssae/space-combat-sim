extends GutTest
## `BotMotion` (M7-T11, Q11): slow loops, a retreat along the loop to a hatch when fighting is near, hiding there, and coming
## out again after the quiet; all of it kinematic and smooth.

const DT: float = 1.0 / 60.0


func _motion(start_s: float = 0.0) -> BotMotion:
	var loop: BotLoop = BotLoop.from_points(PackedVector3Array([Vector3(0, 0, 0), Vector3(30, 0, 0), Vector3(30, 0, 50), Vector3(0, 0, 50)]))
	var hatches: Array[Dictionary] = [{"name": "h", "s": loop.control_s[2], "inside": Vector3(36.0, 0.0, 56.0)}]
	var m := BotMotion.new()
	m.setup(loop, hatches, 3.0, Vector3.UP, start_s, 0.0)
	return m


# Steps until `phase` or `limit` seconds; the seconds taken.
func _until(m: BotMotion, phase: BotMotion.Phase, alarm: bool, limit_s: float = 120.0) -> float:
	var t: float = 0.0
	while m.phase != phase and t < limit_s:
		m.step(DT, alarm)
		t += DT
	return t


func test_a_quiet_bot_flies_its_loop_slowly() -> void:
	var m: BotMotion = _motion()
	var start: Vector3 = m.position
	for i: int in 600:
		m.step(DT, false)
	assert_eq(m.phase, BotMotion.Phase.PATROL)
	assert_almost_eq(m.speed_mps, 3.0, 1e-6)
	var covered: float = fposmod(m.s, m.loop.length_m)
	assert_almost_eq(covered, fposmod(3.0 * 10.0, m.loop.length_m), 0.01, "3 m/s for 10 s")
	assert_true(m.is_visible())
	assert_ne(m.position, start)


func test_fighting_sends_it_along_the_loop_to_the_hatch_and_inside() -> void:
	var m: BotMotion = _motion()
	for i: int in 120:
		m.step(DT, false)
	m.step(DT, true)
	assert_eq(m.phase, BotMotion.Phase.RETREAT)
	var left: float = m.loop.ahead(m.s, m.hatches[0]["s"])
	_until(m, BotMotion.Phase.ENTER, true)
	assert_eq(m.phase, BotMotion.Phase.ENTER, "reached the hatch")
	assert_almost_eq(m.s, float(m.hatches[0]["s"]), 1e-6)
	_until(m, BotMotion.Phase.HIDDEN, true)
	assert_eq(m.phase, BotMotion.Phase.HIDDEN)
	assert_false(m.is_visible(), "vanished inside")
	assert_almost_eq(m.position, Vector3(36.0, 0.0, 56.0), Vector3.ONE * 1e-4, "at the hatch's inside point")
	assert_eq(m.times_hidden, 1)
	assert_lt(left, m.loop.length_m, "the hatch is under one lap away")


func test_it_stays_in_while_the_alarm_lasts_and_for_a_minimum() -> void:
	var m: BotMotion = _motion()
	m.step(DT, true)
	_until(m, BotMotion.Phase.HIDDEN, true)
	for i: int in 3000:
		m.step(DT, true)
	assert_eq(m.phase, BotMotion.Phase.HIDDEN, "fifty seconds of alarm: still in")
	var m2: BotMotion = _motion()
	m2.step(DT, true)
	_until(m2, BotMotion.Phase.HIDDEN, true)
	for i: int in int((BotMotion.MIN_HIDDEN_S - 1.0) / DT):
		m2.step(DT, false)
	assert_eq(m2.phase, BotMotion.Phase.HIDDEN, "not out before the minimum")
	_until(m2, BotMotion.Phase.EXIT, false, 5.0)
	assert_eq(m2.phase, BotMotion.Phase.EXIT)
	assert_true(m2.is_visible(), "drawn again as it comes out")


func test_it_comes_out_and_goes_on_round_its_loop() -> void:
	var m: BotMotion = _motion()
	m.step(DT, true)
	_until(m, BotMotion.Phase.HIDDEN, true)
	_until(m, BotMotion.Phase.EXIT, false)
	_until(m, BotMotion.Phase.PATROL, false)
	assert_eq(m.phase, BotMotion.Phase.PATROL)
	assert_eq(m.times_emerged, 1)
	assert_almost_eq(m.s, float(m.hatches[0]["s"]), 1e-6, "back on the loop at its hatch")
	var before: float = m.s
	for i: int in 60:
		m.step(DT, false)
	assert_ne(m.s, before, "and moving")


func test_fighting_again_while_it_comes_out_sends_it_back_in() -> void:
	var m: BotMotion = _motion()
	m.step(DT, true)
	_until(m, BotMotion.Phase.HIDDEN, true)
	_until(m, BotMotion.Phase.EXIT, false)
	for i: int in 20:
		m.step(DT, false)
	assert_eq(m.phase, BotMotion.Phase.EXIT)
	m.step(DT, true)
	assert_eq(m.phase, BotMotion.Phase.ENTER, "turns round in the leg")
	_until(m, BotMotion.Phase.HIDDEN, true)
	assert_eq(m.phase, BotMotion.Phase.HIDDEN)


func test_each_bots_own_delay_staggers_its_coming_out() -> void:
	var a: BotMotion = _motion()
	var b: BotMotion = _motion()
	b.emerge_delay_s = 12.0
	for m: BotMotion in [a, b]:
		m.step(DT, true)
		_until(m, BotMotion.Phase.HIDDEN, true)
	var ta: float = _until(a, BotMotion.Phase.EXIT, false)
	var tb: float = _until(b, BotMotion.Phase.EXIT, false)
	assert_almost_eq(tb - ta, 4.0, 0.1, "8 s in for the first, 12 s of quiet for the second")


func test_motion_is_smooth_through_every_phase() -> void:
	# No tick moves the bot further than its speed allows and the speed never changes faster than the acceleration says
	# (leaving the hatch starts it again at the minimum speed).
	var m: BotMotion = _motion()
	var last: Vector3 = m.position
	var last_speed: float = m.speed_mps
	var last_phase: BotMotion.Phase = m.phase
	var worst_step: float = 0.0
	var worst_accel: float = 0.0
	var alarm: bool = false
	for i: int in 60 * 160:
		if i == 300:
			alarm = true
		if i == 60 * 70:
			alarm = false
		m.step(DT, alarm)
		worst_step = maxf(worst_step, m.position.distance_to(last) / DT - m.speed_mps)
		if not (last_phase == BotMotion.Phase.HIDDEN and m.phase == BotMotion.Phase.EXIT):
			worst_accel = maxf(worst_accel, absf(m.speed_mps - last_speed) / DT)
		last = m.position
		last_speed = m.speed_mps
		last_phase = m.phase
	assert_eq(m.times_hidden, 1)
	assert_eq(m.times_emerged, 1)
	assert_lt(worst_step, 0.01, "a tick never moves the bot further than its speed (%.4f m/s over)" % worst_step)
	assert_lt(worst_accel, BotMotion.ACCEL_MPS2 + 0.01, "speed changes at the acceleration (%.3f m/s2)" % worst_accel)


func test_the_basis_always_has_the_nose_along_the_heading() -> void:
	var m: BotMotion = _motion()
	for i: int in 1200:
		m.step(DT, i == 200)
		var b: Basis = m.target_basis()
		assert_almost_eq(-b.z, m.heading, Vector3.ONE * 1e-4)
		assert_true(b.orthonormalized().is_equal_approx(b), "a proper rotation")
