extends GutTest
## `BotFerryMotion` (M7-T11, the cargo scene): the trip out of the bay's wall to the pods and back, and what fighting near does
## to it. A cluster of them is staggered so some go out while others come back.

const DT: float = 1.0 / 60.0
const BAY: Dictionary = {
	"cargo_bay_hold": Vector3(0.0, 339.0, -4700.0), "cargo_bay_entry": Vector3(0.0, 339.0, -3534.0),
	"cargo_bay_clear_min": Vector3(-32.1, 327.5, -3580.0), "cargo_bay_clear_max": Vector3(32.1, 354.2, -3512.0),
}

var plan: CargoFerryPlan


func before_each() -> void:
	plan = CargoFerryPlan.build(BAY, Hardpoints.load_collision_only(BotCargoScene.HARDPOINTS))
	assert_true(plan.valid, plan.error)


func _bot(lane: int = 0, stagger_s: float = 0.0) -> BotFerryMotion:
	var routes: Array[BotRoute] = plan.routes_for(lane)
	var m := BotFerryMotion.new()
	m.setup(routes[0], routes[1], Vector3.UP, stagger_s)
	return m


func _until(m: BotFerryMotion, phase: BotFerryMotion.Phase, alarm: bool, limit_s: float = 400.0) -> float:
	var t: float = 0.0
	while m.phase != phase and t < limit_s:
		m.step(DT, alarm)
		t += DT
	return t


func test_a_bot_starts_hidden_in_the_bay_and_makes_the_whole_trip() -> void:
	var m: BotFerryMotion = _bot()
	assert_eq(m.phase, BotFerryMotion.Phase.HIDDEN)
	assert_false(m.is_visible())
	_until(m, BotFerryMotion.Phase.OUT, false)
	assert_true(m.is_visible(), "out of the wall")
	var out_s: float = _until(m, BotFerryMotion.Phase.WAIT, false)
	assert_almost_eq(m.position, plan.pod_stops[0], Vector3.ONE * 0.05, "at its pod")
	assert_almost_eq(m.speed_mps, 0.0, 1e-6, "stopped")
	assert_between(out_s, 50.0, 110.0, "a minute or so out (%.0f s)" % out_s)
	var wait_s: float = _until(m, BotFerryMotion.Phase.BACK, false)
	assert_almost_eq(wait_s, BotFerryMotion.WAIT_AT_PODS_S, 0.1, "a short pause there")
	_until(m, BotFerryMotion.Phase.HIDDEN, false)
	assert_eq(m.trips, 1)
	assert_false(m.is_visible(), "gone into the bay's wall")
	assert_gt(m.position.z, plan.wall_z)
	var hidden_s: float = _until(m, BotFerryMotion.Phase.OUT, false)
	assert_almost_eq(hidden_s, BotFerryMotion.HIDDEN_S, 0.1, "briefly inside, then out again")


func test_the_trip_is_smooth() -> void:
	var m: BotFerryMotion = _bot(1)
	var last: Vector3 = m.position
	var last_speed: float = m.speed_mps
	var worst_step: float = 0.0
	var worst_accel: float = 0.0
	var top: float = 0.0
	for i: int in 60 * 360:
		var before: BotFerryMotion.Phase = m.phase
		m.step(DT, false)
		# Where a phase ends the speed is set to nothing and, into the wall, the unseen bot's place moves to where its next trip starts.
		if before == m.phase:
			worst_step = maxf(worst_step, m.position.distance_to(last) / DT - m.speed_mps)
			if before != BotFerryMotion.Phase.HIDDEN and before != BotFerryMotion.Phase.WAIT:
				worst_accel = maxf(worst_accel, absf(m.speed_mps - last_speed) / DT)
		top = maxf(top, m.speed_mps)
		last = m.position
		last_speed = m.speed_mps
	assert_gt(m.trips, 1, "it keeps going")
	assert_lt(worst_step, 0.05, "a tick never moves it further than its speed (%.3f over)" % worst_step)
	assert_lt(worst_accel, BotFerryMotion.ACCEL_MPS2 + 0.01, "speed changes at the acceleration (%.2f m/s2)" % worst_accel)
	assert_lte(top, BotFerryMotion.CRUISE_MPS + 1e-6, "never above cruise when nothing is wrong")


func test_fighting_on_the_way_out_turns_it_round_into_the_bay() -> void:
	var m: BotFerryMotion = _bot()
	_until(m, BotFerryMotion.Phase.OUT, false)
	for i: int in 60 * 20:
		m.step(DT, false)
	var from: float = m.s
	m.step(DT, true)
	assert_eq(m.phase, BotFerryMotion.Phase.FLEE)
	var on_route: Vector3 = m.position
	m.step(DT, true)
	assert_lt(m.s, from + 1.0, "going back along the way it came")
	assert_almost_eq(m.heading, -plan.routes_for(0)[0].direction_at(m.s), Vector3.ONE * 1e-4, "nose first")
	_until(m, BotFerryMotion.Phase.HIDDEN, true)
	assert_eq(m.phase, BotFerryMotion.Phase.HIDDEN)
	assert_false(m.is_visible())
	assert_lt(on_route.distance_to(plan.routes_for(0)[0].point_at(from)), 2.0, "it never left the route")


func test_fighting_at_the_pods_or_on_the_way_back_sends_it_home_in_a_hurry() -> void:
	var m: BotFerryMotion = _bot()
	_until(m, BotFerryMotion.Phase.WAIT, false)
	m.step(DT, true)
	assert_eq(m.phase, BotFerryMotion.Phase.BACK, "no waiting at the pods")
	var top: float = 0.0
	while m.phase == BotFerryMotion.Phase.BACK:
		m.step(DT, true)
		top = maxf(top, m.speed_mps)
	assert_gt(top, BotFerryMotion.CRUISE_MPS, "faster than cruise")
	assert_eq(m.phase, BotFerryMotion.Phase.HIDDEN)


func test_it_stays_in_until_the_quiet_has_held_then_goes_again_staggered() -> void:
	var a: BotFerryMotion = _bot(0, 0.0)
	var b: BotFerryMotion = _bot(1, 9.0)
	for m: BotFerryMotion in [a, b]:
		_until(m, BotFerryMotion.Phase.OUT, false)
		m.step(DT, true)
		_until(m, BotFerryMotion.Phase.HIDDEN, true)
		for i: int in 60 * 90:
			m.step(DT, true)
		assert_eq(m.phase, BotFerryMotion.Phase.HIDDEN, "held in while the alarm lasts")
	var ta: float = _until(a, BotFerryMotion.Phase.OUT, false)
	var tb: float = _until(b, BotFerryMotion.Phase.OUT, false)
	assert_lt(ta, 0.1, "no stagger: out as soon as the quiet allows")
	assert_almost_eq(tb - ta, 9.0, 0.2, "the second waits its stagger from the start of the quiet")


func test_a_cluster_is_staggered_into_a_steady_stream() -> void:
	var count: int = 5
	var cycle_s: float = BotCargoScene.trip_seconds(plan)
	var bots: Array[BotFerryMotion] = []
	for lane: int in count:
		var m: BotFerryMotion = _bot(lane)
		BotCargoScene.warm(m, cycle_s * float(lane) / float(count))
		bots.append(m)
	var phases := {}
	for m: BotFerryMotion in bots:
		phases[m.phase] = true
	var going_out: int = 0
	var coming_back: int = 0
	var seconds_with_out: int = 0
	var seconds_with_back: int = 0
	var seconds: int = int(cycle_s * 1.5)
	for sec: int in seconds:
		for i: int in 60:
			for m: BotFerryMotion in bots:
				m.step(DT, false)
		var out_now: int = bots.filter(func(m: BotFerryMotion) -> bool: return m.phase == BotFerryMotion.Phase.OUT).size()
		var back_now: int = bots.filter(func(m: BotFerryMotion) -> bool: return m.phase == BotFerryMotion.Phase.BACK).size()
		going_out = maxi(going_out, out_now)
		coming_back = maxi(coming_back, back_now)
		seconds_with_out += 1 if out_now > 0 else 0
		seconds_with_back += 1 if back_now > 0 else 0
	assert_gte(phases.size(), 3, "at the start the bots are in different phases (%s)" % str(phases.keys()))
	assert_gte(going_out, 2, "some going out at once")
	assert_gte(coming_back, 1, "while others come back")
	assert_gt(float(seconds_with_out) / float(seconds), 0.85, "something is always on its way out")
	assert_gt(float(seconds_with_back) / float(seconds), 0.7, "and something on its way back")
