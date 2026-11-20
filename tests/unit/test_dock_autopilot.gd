extends GutTest
## DockAutopilot (M8-T06, D82): the speeds and commands that bring the player's ship to the lane and along it.


func _capability() -> ShipCapability:
	var cap := ShipCapability.new()
	cap.a_main = 30.0
	cap.a_retro = 12.0
	cap.a_rcs = Vector2(8.0, 8.0)
	cap.rate_max_rad = Vector3(1.5, 1.5, 2.0)
	return cap


func test_the_approach_speed_falls_with_the_distance_left() -> void:
	var cap: ShipCapability = _capability()
	assert_eq(DockAutopilot.approach_speed(5000.0, 140.0, 0.0, cap), 140.0, "far out: the cruise")
	var near: float = DockAutopilot.approach_speed(200.0, 140.0, 0.0, cap)
	assert_almost_eq(near, StoppingDistance.speed_for_mps(200.0, cap.a_main), 1e-6)
	assert_lt(near, 140.0)
	assert_eq(DockAutopilot.approach_speed(0.0, 140.0, 0.0, cap), 0.0, "at rest on the point")
	assert_eq(DockAutopilot.approach_speed(1.0, 140.0, 45.0, cap), 45.0, "a turning point is passed at speed")


func test_a_ship_that_stops_on_a_point_eases_onto_it() -> void:
	# The play-test (2026-11-19): a fighter holding short of the lane circled its point at 9 m/s, as if jockeying for position.
	var cap: ShipCapability = _capability()
	assert_almost_eq(DockAutopilot.approach_speed(5.0, 140.0, 0.0, cap), 2.5, 1e-6, "5 m out it closes at walking pace")
	assert_almost_eq(DockAutopilot.approach_speed(1.0, 140.0, 0.0, cap), 0.5, 1e-6)
	assert_eq(DockAutopilot.approach_speed(5.0, 140.0, 45.0, cap), 45.0, "a turning point is still passed at speed")
	# A point mass flown by the wish comes to rest on the point and stays there.
	var at := Vector3(0.0, 0.0, 300.0)
	var velocity := Vector3.ZERO
	var fastest_late: float = 0.0
	for k: int in 60 * 60:
		var to: Vector3 = -at
		var wish: Vector3 = to.normalized() * DockAutopilot.approach_speed(to.length(), 140.0, 0.0, cap) if to.length() > 1e-3 else Vector3.ZERO
		velocity = velocity.move_toward(wish, cap.a_rcs.x / 60.0)
		at += velocity / 60.0
		if k > 40 * 60:
			fastest_late = maxf(fastest_late, velocity.length())
	assert_lt(at.length(), 1.0, "on the point")
	assert_lt(fastest_late, 0.5, "and still, not circling it (%.2f m/s)" % fastest_late)


func test_a_ship_coming_in_fast_is_braked_before_anything_else() -> void:
	var cap: ShipCapability = _capability()
	# 600 m/s toward the target 1 km ahead, nose on it: far more than it can shed, so the nose turns round to burn.
	var cmd: FlightCommand = DockAutopilot.approach(Vector3.ZERO, Vector3(0.0, 0.0, -600.0), Basis.IDENTITY, Vector3(0.0, 0.0, -1000.0),
			140.0, 0.0, cap)
	assert_gt(cmd.retro_left + cmd.rot.length(), 0.0, "it brakes or turns to brake")
	assert_eq(cmd.main_left, 0.0, "never more thrust toward the bay")
	assert_gt(cmd.rot.length(), 0.5, "the nose comes round onto the burn")


func test_a_slow_ship_far_out_burns_toward_the_target() -> void:
	var cmd: FlightCommand = DockAutopilot.approach(Vector3.ZERO, Vector3.ZERO, Basis.IDENTITY, Vector3(0.0, 0.0, -3000.0), 140.0, 0.0,
			_capability())
	assert_gt(cmd.main_left, 0.5)
	assert_eq(cmd.main_left, cmd.main_right)
	assert_almost_eq(cmd.rot.length(), 0.0, 1e-3, "already pointing there")


func test_the_lane_speed_stops_the_ship_on_its_mark() -> void:
	var cap: ShipCapability = _capability()
	assert_eq(DockAutopilot.lane_speed(2000.0, 40.0, cap), 40.0)
	assert_lt(DockAutopilot.lane_speed(10.0, 40.0, cap), 40.0)
	assert_eq(DockAutopilot.lane_speed(-5.0, 40.0, cap), 0.0, "past the mark: stand still")
	# Braking from the lane's speed at the planned rate always fits the room the plan gives it.
	for room: float in [5.0, 20.0, 60.0, 200.0]:
		var speed: float = DockAutopilot.lane_speed(room, 40.0, cap)
		assert_true(StoppingDistance.can_stop(speed, room, cap.a_retro), "%.0f m/s stops within %.0f m" % [speed, room])


func test_the_lane_pulls_an_offset_ship_back_onto_the_axis() -> void:
	var axis := Vector3(0.0, 0.0, -1.0)
	# 12 m to the right of the axis, flying down it at the asked speed: only a strafe to the left is wanted.
	var cmd: FlightCommand = DockAutopilot.lane(Vector3(12.0, 0.0, 0.0), axis * 30.0, Basis.IDENTITY, Vector3.ZERO, axis, 30.0,
			_capability())
	assert_lt(cmd.strafe.x, -0.1, "strafe toward the axis")
	assert_almost_eq(cmd.main_left, 0.0, 0.05)
	assert_almost_eq(cmd.retro_left, 0.0, 0.05)
	assert_almost_eq(DockAutopilot.off_axis_m(Vector3(12.0, -5.0, -300.0), Vector3.ZERO, axis), 13.0, 1e-4)


func test_the_lane_brakes_a_ship_that_is_too_fast_without_turning_it_round() -> void:
	var axis := Vector3(0.0, 0.0, -1.0)
	var cmd: FlightCommand = DockAutopilot.lane(Vector3.ZERO, axis * 60.0, Basis.IDENTITY, Vector3.ZERO, axis, 20.0, _capability())
	assert_gt(cmd.retro_left, 0.5, "the retros slow it")
	assert_almost_eq(cmd.rot.length(), 0.0, 1e-3, "the nose stays on the axis: it flies in nose first")
