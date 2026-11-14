extends GutTest
## `BotLoop` (M7-T11): a closed, smooth path through control points, flown by arc length.

const SQUARE: Array[Vector3] = [Vector3(0, 0, 0), Vector3(40, 0, 0), Vector3(40, 0, 60), Vector3(0, 0, 60)]


func _loop() -> BotLoop:
	return BotLoop.from_points(PackedVector3Array(SQUARE))


func test_fewer_than_three_points_make_no_loop() -> void:
	assert_false(BotLoop.from_points(PackedVector3Array([Vector3.ZERO, Vector3.ONE])).valid())
	assert_true(_loop().valid())


func test_the_loop_closes_and_wraps() -> void:
	var loop: BotLoop = _loop()
	assert_almost_eq(loop.point_at(0.0), loop.point_at(loop.length_m), Vector3.ONE * 1e-6, "the end is the start")
	assert_almost_eq(loop.point_at(7.0), loop.point_at(7.0 + 3.0 * loop.length_m), Vector3.ONE * 1e-4, "and it wraps")
	assert_almost_eq(loop.point_at(-5.0), loop.point_at(loop.length_m - 5.0), Vector3.ONE * 1e-4, "backwards too")


func test_it_passes_through_every_control_point() -> void:
	var loop: BotLoop = _loop()
	assert_eq(loop.control_s.size(), SQUARE.size())
	for i: int in SQUARE.size():
		assert_almost_eq(loop.point_at(loop.control_s[i]), SQUARE[i], Vector3.ONE * 1e-4, "control point %d" % i)


func test_a_bot_at_constant_speed_moves_that_far_each_step() -> void:
	var loop: BotLoop = _loop()
	var speed: float = 4.0
	var worst: float = 0.0
	var s: float = 0.0
	for i: int in 600:
		var next: float = s + speed / 60.0
		worst = maxf(worst, absf(loop.point_at(next).distance_to(loop.point_at(s)) - speed / 60.0))
		s = next
	assert_lt(worst, 0.003, "no jumps: a tick's step is the speed's, to the polyline's chord (%.4f m)" % worst)


func test_the_heading_turns_smoothly() -> void:
	var loop: BotLoop = _loop()
	var worst: float = 0.0
	var s: float = 0.0
	while s < loop.length_m:
		worst = maxf(worst, loop.direction_at(s).angle_to(loop.direction_at(s + 1.0)))
		s += 1.0
	assert_lt(rad_to_deg(worst), 12.0, "the nose turns under 12 degrees a metre round the corners (%.1f)" % rad_to_deg(worst))


func test_ahead_counts_the_way_the_loop_runs() -> void:
	var loop: BotLoop = _loop()
	assert_almost_eq(loop.ahead(10.0, 25.0), 15.0, 1e-9)
	assert_almost_eq(loop.ahead(25.0, 10.0), loop.length_m - 15.0, 1e-9, "the long way round, never back")
	assert_almost_eq(loop.ahead(5.0, 5.0), 0.0, 1e-9)
