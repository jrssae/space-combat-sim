extends GutTest
## InterceptMath (architecture §15.8, AC1): the lead solution for a bolt that inherits the shooter's velocity.
## Solutions are checked by flying the bolt and the target forward in 64-bit and measuring the miss distance.

const SPEED: float = 400.0
const MEET_TOL_M: float = 1e-3
const EPS: float = 1e-9
const RANDOM_CASES: int = 600
const SEED: int = 20261022

var rng: RandomNumberGenerator


func before_each() -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = SEED


# Distance between the bolt (shooter velocity plus `aim_dir * speed`) and the target at time `t`, in 64-bit.
func _miss_distance(result: Dictionary, p_s: Vector3, v_s: Vector3, p_t: Vector3, v_t: Vector3, speed: float) -> float:
	var t: float = result["t"]
	var aim: Vector3 = result["aim_dir"]
	var sum: float = 0.0
	for axis: int in 3:
		var bolt: float = float(p_s[axis]) + (float(v_s[axis]) + float(aim[axis]) * speed) * t
		var target: float = float(p_t[axis]) + float(v_t[axis]) * t
		sum += (bolt - target) * (bolt - target)
	return sqrt(sum)


# |r + u t| - s t in 64-bit: positive while the bolt has not caught the target, zero at the meeting.
func _gap(p_s: Vector3, v_s: Vector3, p_t: Vector3, v_t: Vector3, speed: float, t: float) -> float:
	var sum: float = 0.0
	for axis: int in 3:
		var d: float = (float(p_t[axis]) - float(p_s[axis])) + (float(v_t[axis]) - float(v_s[axis])) * t
		sum += d * d
	return sqrt(sum) - speed * t


# --- analytic cases ------------------------------------------------------------------------------------------


func test_static_target_at_one_kilometre() -> void:
	var r: Dictionary = InterceptMath.solve(Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, -1000), Vector3.ZERO, SPEED, 4.0)
	assert_true(r["ok"])
	assert_almost_eq(float(r["t"]), 2.5, EPS)
	assert_eq(r["aim_dir"], Vector3(0, 0, -1))
	assert_eq(r["lead_point"], Vector3(0, 0, -1000), "nothing moves, so the lead is the target")


func test_crossing_target_solves_the_right_triangle() -> void:
	var r: Dictionary = InterceptMath.solve(Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, -1000), Vector3(100, 0, 0), SPEED, 6.0)
	var expected_t: float = 1000.0 / sqrt(SPEED * SPEED - 100.0 * 100.0)
	assert_true(r["ok"])
	assert_almost_eq(float(r["t"]), expected_t, EPS)
	# The bolt flies the hypotenuse: sideways 100 t, forward sqrt(s² - 100²) t = 1000.
	var aim: Vector3 = r["aim_dir"]
	assert_almost_eq(aim.x, 100.0 / SPEED, 1e-6)
	assert_almost_eq(aim.z, -1000.0 / (SPEED * expected_t), 1e-6)
	assert_almost_eq(aim.length(), 1.0, 1e-6)
	var lead: Vector3 = r["lead_point"]
	assert_almost_eq(lead.x, 100.0 * expected_t, 1e-3)
	assert_almost_eq(lead.z, -1000.0, 1e-3)
	assert_lt(_miss_distance(r, Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, -1000), Vector3(100, 0, 0), SPEED), MEET_TOL_M)


func test_receding_faster_than_the_bolt_has_no_solution() -> void:
	var r: Dictionary = InterceptMath.solve(Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, -1000), Vector3(0, 0, -500), SPEED, 100.0)
	assert_false(r["ok"])


func test_receding_slower_than_the_bolt_is_caught() -> void:
	var r: Dictionary = InterceptMath.solve(Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, -1000), Vector3(0, 0, -100), SPEED, 10.0)
	assert_true(r["ok"])
	assert_almost_eq(float(r["t"]), 1000.0 / 300.0, EPS)
	assert_eq(r["aim_dir"], Vector3(0, 0, -1))


func test_target_at_exactly_bolt_speed_uses_the_linear_case() -> void:
	# Running away at the bolt's speed: never caught. Running towards the shooter at the bolt's speed: 1000 m of gap
	# closes at 400 m/s relative... the bolt and target cover 500 m each after 1.25 s.
	var away: Dictionary = InterceptMath.solve(Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, -1000), Vector3(0, 0, -SPEED), SPEED, 100.0)
	assert_false(away["ok"])
	var towards: Dictionary = InterceptMath.solve(Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, -1000), Vector3(0, 0, SPEED), SPEED, 100.0)
	assert_true(towards["ok"])
	assert_almost_eq(float(towards["t"]), 1.25, 1e-6)
	assert_lt(_miss_distance(towards, Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, -1000), Vector3(0, 0, SPEED), SPEED), MEET_TOL_M)


func test_crossing_faster_than_the_bolt_at_right_angles_has_no_solution() -> void:
	var r: Dictionary = InterceptMath.solve(Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, -1000), Vector3(500, 0, 0), SPEED, 100.0)
	assert_false(r["ok"], "u = 500 > s and no closing component: the discriminant is negative")


func test_two_positive_roots_pick_the_earlier() -> void:
	# A fast target (|u| = 500 > s) with enough closing speed can be met twice; the first meeting is the answer.
	var p_t := Vector3(0, 0, -1000)
	var v_t := Vector3(300, 0, 400)
	var r: Dictionary = InterceptMath.solve(Vector3.ZERO, Vector3.ZERO, p_t, v_t, SPEED, 60.0)
	var a: float = 300.0 * 300.0 + 400.0 * 400.0 - SPEED * SPEED
	var b: float = 2.0 * (-1000.0 * 400.0)
	var c: float = 1000.0 * 1000.0
	var disc: float = b * b - 4.0 * a * c
	assert_gt(disc, 0.0)
	var early: float = (-b - sqrt(disc)) / (2.0 * a)
	var late: float = (-b + sqrt(disc)) / (2.0 * a)
	assert_gt(early, 0.0)
	assert_gt(late, early)
	assert_true(r["ok"])
	assert_almost_eq(float(r["t"]), early, 1e-9)
	assert_lt(_miss_distance(r, Vector3.ZERO, Vector3.ZERO, p_t, v_t, SPEED), MEET_TOL_M)
	# With a window that ends between the roots the early one is still reported.
	var short: Dictionary = InterceptMath.solve(Vector3.ZERO, Vector3.ZERO, p_t, v_t, SPEED, (early + late) * 0.5)
	assert_true(short["ok"])
	assert_almost_eq(float(short["t"]), early, 1e-9)


func test_a_double_root_is_a_hit() -> void:
	# u = (400, 0, 200) against r = (0, 0, -1000): the discriminant is exactly zero and the bolt just catches the
	# target at t = 5, 2 000 m out to the side.
	var v_t := Vector3(SPEED, 0, 200)
	var r: Dictionary = InterceptMath.solve(Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, -1000), v_t, SPEED, 6.0)
	assert_true(r["ok"])
	assert_almost_eq(float(r["t"]), 5.0, 1e-6)
	assert_eq(r["aim_dir"], Vector3(1, 0, 0))


func test_the_shooters_velocity_is_inherited() -> void:
	# Flying 250 m/s at a static target 1 km ahead: the bolt closes at 400 + 250, aim stays dead ahead.
	var v_s := Vector3(0, 0, -250)
	var r: Dictionary = InterceptMath.solve(Vector3.ZERO, v_s, Vector3(0, 0, -1000), Vector3.ZERO, SPEED, 4.0)
	assert_true(r["ok"])
	assert_almost_eq(float(r["t"]), 1000.0 / 650.0, EPS)
	assert_eq(r["aim_dir"], Vector3(0, 0, -1))
	var lead: Vector3 = r["lead_point"]
	assert_almost_eq(lead.z, -1000.0 + 250.0 * float(r["t"]), 1e-3, "the lead is shifted by the relative velocity")


func test_sideways_drift_of_the_shooter_is_cancelled_by_the_aim() -> void:
	# The shooter slides right at 100 m/s; the bolt inherits that, so the aim must tilt left to hit a static target.
	var v_s := Vector3(100, 0, 0)
	var p_t := Vector3(0, 0, -1000)
	var r: Dictionary = InterceptMath.solve(Vector3.ZERO, v_s, p_t, Vector3.ZERO, SPEED, 4.0)
	assert_true(r["ok"])
	assert_lt((r["aim_dir"] as Vector3).x, 0.0)
	assert_lt(_miss_distance(r, Vector3.ZERO, v_s, p_t, Vector3.ZERO, SPEED), MEET_TOL_M)


func test_lead_point_lies_on_the_aim_line_whatever_the_shooter_velocity() -> void:
	var p_s := Vector3(120, -40, 300)
	var v_s := Vector3(35, 10, -80)
	var p_t := Vector3(-800, 200, -1500)
	var v_t := Vector3(60, -20, 90)
	var r: Dictionary = InterceptMath.solve(p_s, v_s, p_t, v_t, SPEED, 6.0)
	assert_true(r["ok"])
	var to_lead: Vector3 = (r["lead_point"] as Vector3) - p_s
	assert_almost_eq(to_lead.length(), SPEED * float(r["t"]), 1e-2, "the lead is one bolt flight away")
	assert_almost_eq(to_lead.normalized().dot(r["aim_dir"]), 1.0, 1e-6)


func test_aim_dir_is_a_unit_vector() -> void:
	var r: Dictionary = InterceptMath.solve(Vector3(5, 6, 7), Vector3(10, 0, 3), Vector3(900, -300, 2500), Vector3(-30, 40, 5), SPEED, 10.0)
	assert_true(r["ok"])
	assert_almost_eq((r["aim_dir"] as Vector3).length(), 1.0, 1e-6)


func test_translating_the_scene_changes_nothing() -> void:
	# Both positions shifted by a rebase-sized offset (exact in float32): same time and direction.
	var shift := Vector3(5000, -2048, 1024)
	var p_s := Vector3(16, -8, 4)
	var p_t := Vector3(900, 250, -1300)
	var v_t := Vector3(40, -15, 25)
	var near: Dictionary = InterceptMath.solve(p_s, Vector3.ZERO, p_t, v_t, SPEED, 10.0)
	var far: Dictionary = InterceptMath.solve(p_s + shift, Vector3.ZERO, p_t + shift, v_t, SPEED, 10.0)
	assert_true(near["ok"])
	assert_true(far["ok"])
	assert_almost_eq(float(far["t"]), float(near["t"]), 1e-9)
	assert_almost_eq((far["aim_dir"] as Vector3).distance_to(near["aim_dir"]), 0.0, 1e-9)
	assert_almost_eq((far["lead_point"] as Vector3).distance_to((near["lead_point"] as Vector3) + shift), 0.0, 5e-3)


# --- limits and degenerate input -----------------------------------------------------------------------------


func test_time_beyond_the_window_has_no_solution() -> void:
	var p_t := Vector3(0, 0, -1000)
	assert_false(InterceptMath.solve(Vector3.ZERO, Vector3.ZERO, p_t, Vector3.ZERO, SPEED, 2.0)["ok"], "t 2.5 > 2.0")
	assert_false(InterceptMath.solve(Vector3.ZERO, Vector3.ZERO, p_t, Vector3.ZERO, SPEED, 2.499)["ok"])
	assert_true(InterceptMath.solve(Vector3.ZERO, Vector3.ZERO, p_t, Vector3.ZERO, SPEED, 2.5)["ok"], "inclusive")
	assert_true(InterceptMath.solve(Vector3.ZERO, Vector3.ZERO, p_t, Vector3.ZERO, SPEED, INF)["ok"])
	assert_false(InterceptMath.solve(Vector3.ZERO, Vector3.ZERO, p_t, Vector3.ZERO, SPEED, 0.0)["ok"])
	assert_false(InterceptMath.solve(Vector3.ZERO, Vector3.ZERO, p_t, Vector3.ZERO, SPEED, -1.0)["ok"])
	assert_false(InterceptMath.solve(Vector3.ZERO, Vector3.ZERO, p_t, Vector3.ZERO, SPEED, NAN)["ok"])


func test_no_solution_reports_the_line_of_sight() -> void:
	var p_t := Vector3(300, 400, 0)
	var r: Dictionary = InterceptMath.solve(Vector3.ZERO, Vector3.ZERO, p_t, Vector3(600, 800, 0), SPEED, 100.0)
	assert_false(r["ok"])
	assert_eq(float(r["t"]), -1.0)
	assert_eq(r["lead_point"], p_t, "the lead falls back to the target")
	assert_almost_eq((r["aim_dir"] as Vector3).distance_to(Vector3(0.6, 0.8, 0.0)), 0.0, 1e-6)


func test_target_on_the_shooter_has_no_solution_and_no_direction() -> void:
	var p := Vector3(10, 20, 30)
	var r: Dictionary = InterceptMath.solve(p, Vector3.ZERO, p, Vector3(1, 0, 0), SPEED, 10.0)
	assert_false(r["ok"])
	assert_eq(r["aim_dir"], Vector3.ZERO)
	assert_eq(r["lead_point"], p)


func test_a_bolt_that_cannot_fly_has_no_solution() -> void:
	var p_t := Vector3(0, 0, -1000)
	for speed: float in [0.0, -400.0, NAN]:
		var r: Dictionary = InterceptMath.solve(Vector3.ZERO, Vector3.ZERO, p_t, Vector3.ZERO, speed, 10.0)
		assert_false(r["ok"], "bolt speed %s" % speed)


func test_result_always_carries_all_four_keys() -> void:
	var good: Dictionary = InterceptMath.solve(Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, -1000), Vector3.ZERO, SPEED, 4.0)
	var bad: Dictionary = InterceptMath.solve(Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, -1000), Vector3.ZERO, 0.0, 4.0)
	for r: Dictionary in [good, bad]:
		assert_eq(r.size(), 4)
		for key: String in ["ok", "t", "aim_dir", "lead_point"]:
			assert_true(r.has(key), key)


# --- random cases --------------------------------------------------------------------------------------------


func _random_vec(extent: float) -> Vector3:
	return Vector3(rng.randf_range(-extent, extent), rng.randf_range(-extent, extent), rng.randf_range(-extent, extent))


func test_random_cases_meet_or_have_no_earlier_meeting() -> void:
	var solved: int = 0
	var unsolved: int = 0
	var failures: Array[String] = []
	for i: int in RANDOM_CASES:
		var p_s: Vector3 = _random_vec(3000.0)
		var v_s: Vector3 = _random_vec(150.0)
		var p_t: Vector3 = _random_vec(3000.0)
		var v_t: Vector3 = _random_vec(350.0)
		var speed: float = rng.randf_range(300.0, 1500.0)
		# The bolt flies at most 8 km: the float32 rounding of the aim direction stays well inside 1 mm.
		var window: float = rng.randf_range(2.0, 8000.0 / speed)
		var r: Dictionary = InterceptMath.solve(p_s, v_s, p_t, v_t, speed, window)
		var t: float = r["t"]
		var steps: int = 400
		if r["ok"]:
			solved += 1
			var miss: float = _miss_distance(r, p_s, v_s, p_t, v_t, speed)
			if not (t > 0.0 and t <= window):
				failures.append("#%d t %.6f outside (0, %.3f]" % [i, t, window])
			if miss > MEET_TOL_M:
				failures.append("#%d bolt misses by %.6f m" % [i, miss])
			# The root is the smallest: the bolt trails the target at every earlier time.
			for k: int in steps:
				var earlier: float = t * float(k) / steps
				if _gap(p_s, v_s, p_t, v_t, speed, earlier) < -1e-6:
					failures.append("#%d bolt has already caught the target at t %.6f < %.6f" % [i, earlier, t])
					break
		else:
			unsolved += 1
			for k: int in steps + 1:
				var sampled: float = window * float(k) / steps
				if _gap(p_s, v_s, p_t, v_t, speed, sampled) < -1e-6:
					failures.append("#%d reported no solution but the bolt reaches the target by t %.6f <= %.3f" % [
							i, sampled, window])
					break
		if failures.size() >= 5:
			break
	gut.p("%d random cases: %d solved, %d without a solution" % [RANDOM_CASES, solved, unsolved])
	assert_eq(failures.size(), 0, str(failures))
	assert_gt(solved, 100, "enough solvable cases")
	assert_gt(unsolved, 100, "enough unsolvable cases")
