extends GutTest
## M7-T28: a gate takes the player's jump request only from within 2 km (the range and the answer are data), and the jump's
## autopilot leaves a ship's roll alone unless the ship is too wide for the mouth.


func test_a_request_is_taken_only_within_the_data_range() -> void:
	assert_eq(GateJumpRequest.range_m(), 2000.0, "data/jump/gate_request.json: 2 km (maintainer, 2026-11-14)")
	assert_eq(GateJumpRequest.refusal(0.0), "")
	assert_eq(GateJumpRequest.refusal(GateJumpRequest.range_m()), "", "at the range it is still taken")
	assert_eq(GateJumpRequest.refusal(GateJumpRequest.range_m() + 1.0), GateJumpRequest.out_of_range_text())
	assert_eq(GateJumpRequest.out_of_range_text(), "out of range", "the answer is the data file's")


func test_only_a_ship_too_wide_for_the_mouth_is_rolled() -> void:
	assert_eq(GateAutopilot.roll_up(Vector3.UP, 754.0, 9.0), Vector3.ZERO, "a fighter fits any way up: no roll asked")
	assert_eq(GateAutopilot.roll_up(Vector3.UP, 754.0, 600.0), Vector3.UP, "a ship wider than the mouth's half height is turned")


func test_the_run_in_keeps_the_ships_roll() -> void:
	var cap := ShipCapability.new()
	var axis := Vector3.FORWARD
	var at := Vector3(0.0, 0.0, 1440.0)
	var moving := Vector3(0.0, 0.0, -240.0)
	for roll_deg: float in [30.0, 90.0, 150.0, 180.0, -120.0]:
		var rolled := Basis(Vector3.BACK, deg_to_rad(roll_deg))  # nose on the axis, rolled about it
		var kept: FlightCommand = GateAutopilot.run_in(at, moving, rolled, Vector3.ZERO, axis, Vector3.ZERO, 3.5, cap)
		assert_eq(kept.rot.z, 0.0, "rolled %.0f degrees from the gate's up: no roll commanded" % roll_deg)
		var turned: FlightCommand = GateAutopilot.run_in(at, moving, rolled, Vector3.ZERO, axis, Vector3.UP, 3.5, cap)
		assert_ne(turned.rot.z, 0.0, "given a way up (a ship too wide for the mouth), it is turned to it")


# M8-T18 (D84): the reach grows with the closing speed: the hold flown at that speed plus the autopilot's slowdown to its run-in,
# capped by the data.
func test_the_reach_grows_with_the_closing_speed_up_to_the_cap() -> void:
	assert_eq(GateJumpRequest.range_m(0.0), 2000.0, "at rest: the base 2 km")
	assert_eq(GateJumpRequest.range_m(-300.0), 2000.0, "opening: no more than the base")
	assert_almost_eq(GateJumpRequest.range_m(200.0, 30.0), 2400.0, 1e-3, "under the run-in's speed: only the 2 s hold is added")
	var margin: float = StoppingDistance.PLAN_MARGIN
	var expected: float = 2000.0 + 500.0 * 2.0 + (500.0 * 500.0 - 250.0 * 250.0) / (2.0 * 30.0 * margin * margin)
	assert_almost_eq(GateJumpRequest.range_m(500.0, 30.0), expected, 1e-2, "500 m/s: the hold and the slowdown")
	assert_gt(GateJumpRequest.range_m(500.0, 10.0), GateJumpRequest.range_m(500.0, 30.0), "weaker brakes: offered farther out")
	assert_eq(GateJumpRequest.range_m(1000.0, 30.0), 10000.0, "1 km/s: the data's 10 km cap")
	assert_eq(GateJumpRequest.range_m(5000.0, 30.0), 10000.0, "5 km/s: still the cap")
	var last: float = 0.0
	for speed: float in [0.0, 100.0, 250.0, 400.0, 700.0, 2000.0]:
		var reach: float = GateJumpRequest.range_m(speed, 30.0)
		assert_true(reach >= last, "%.0f m/s: the reach never shrinks as the speed grows" % speed)
		last = reach


func test_a_live_reach_decides_the_refusal() -> void:
	assert_eq(GateJumpRequest.refusal(5000.0, GateJumpRequest.range_m(500.0, 30.0)), "", "5 km out at 500 m/s: taken")
	assert_eq(GateJumpRequest.refusal(5000.0), GateJumpRequest.out_of_range_text(), "5 km out at rest: refused")


# M8-T18: the autopilot carries a lined-up ship's speed down to the run-in's; one off the axis or heading elsewhere still slows
# to the line-up's.
func test_a_ship_lined_up_with_the_mouth_carries_its_speed_to_the_run_in() -> void:
	var departure := Vector3(0.0, 0.0, -1500.0)
	var forward := Vector3.BACK
	var inbound := Vector3(0.0, 0.0, 900.0)
	assert_true(GateAutopilot.lined_up(Vector3(0.0, 50.0, -9000.0), inbound, departure, forward))
	assert_eq(GateAutopilot.line_up_arrival(Vector3(0.0, 50.0, -9000.0), inbound, departure, forward), GateAutopilot.RUN_IN_MPS)
	assert_false(GateAutopilot.lined_up(Vector3(600.0, 0.0, -9000.0), inbound, departure, forward), "off the axis")
	assert_false(GateAutopilot.lined_up(Vector3(0.0, 0.0, -9000.0), Vector3(400.0, 0.0, 400.0), departure, forward), "heading across")
	assert_false(GateAutopilot.lined_up(Vector3(0.0, 0.0, -1000.0), inbound, departure, forward), "already past the point")
	assert_false(GateAutopilot.lined_up(Vector3(0.0, 0.0, -9000.0), Vector3(0.0, 0.0, 20.0), departure, forward), "barely moving")
	assert_eq(GateAutopilot.line_up_arrival(Vector3(600.0, 0.0, -9000.0), inbound, departure, forward), GateAutopilot.LINE_UP_MPS)


func test_the_line_up_brakes_from_any_speed_and_lets_a_lined_up_ship_arrive_at_the_run_in() -> void:
	var cap := ShipCapability.new()
	cap.a_main = 30.0
	var nose := Basis.looking_at(Vector3.BACK)
	# 3 km/s toward a point 5 km ahead: the command is to slow (thrust against the motion).
	var fast: FlightCommand = GateAutopilot.line_up(Vector3.ZERO, Vector3(0.0, 0.0, 3000.0), nose, Vector3(0.0, 0.0, 5000.0), cap)
	assert_gt(fast.retro_left, 0.0, "it brakes, its retros on while the nose still faces the motion")
	assert_eq(fast.main_left, 0.0)
	# Close to the point, a lined-up ship at the run-in's speed is not slowed to the line-up's 80 m/s.
	var near := Vector3(0.0, 0.0, 300.0)
	var kept: FlightCommand = GateAutopilot.line_up(Vector3.ZERO, Vector3(0.0, 0.0, 250.0), nose, near, cap, GateAutopilot.RUN_IN_MPS)
	var slowed: FlightCommand = GateAutopilot.line_up(Vector3.ZERO, Vector3(0.0, 0.0, 250.0), nose, near, cap)
	assert_almost_eq(kept.retro_left + kept.main_left, 0.0, 1e-3, "at the run-in's speed already: nothing to shed")
	assert_gt(slowed.retro_left + slowed.main_left, 0.0, "the line-up's own arrival would brake it to 80 m/s")


# M8-T18: the run-in's predicted arrival at the mouth (the departure shots are timed from it, M8-T29).
func test_the_run_in_predicts_its_arrival_at_the_mouth() -> void:
	assert_almost_eq(GateAutopilot.predicted_arrival_s(1500.0, 2.0), 6.0, 1e-6, "1.5 km at 250 m/s")
	assert_almost_eq(GateAutopilot.predicted_arrival_s(1500.0, 9.0), 9.0, 1e-6, "no sooner than the vortex opens")
	assert_almost_eq(GateAutopilot.predicted_arrival_s(1500.0, INF), 6.0, 1e-6)
	var cap := ShipCapability.new()
	cap.a_main = 30.0
	cap.a_retro = 30.0
	var carried: float = GateAutopilot.predicted_arrival_s(1500.0, 4.6, 250.0, cap)
	var slow: float = GateAutopilot.predicted_arrival_s(1500.0, 4.6, 80.0, cap)
	assert_almost_eq(carried, 6.0, 0.3, "at the run-in's speed already: about 1.5 km / 250 m/s")
	assert_gt(slow, carried + 1.5, "from 80 m/s it first gathers speed")
	assert_almost_eq(GateAutopilot.predicted_arrival_s(1500.0, 9.0, 250.0, cap), 9.0, 0.5, "it paces itself to the vortex")
	var travel: PackedFloat32Array = GateAutopilot.run_in_travel_m(PackedFloat32Array([0.0, carried, carried + 2.0]), 1500.0, 4.6,
			250.0, cap)
	assert_eq(travel[0], 0.0)
	assert_almost_eq(travel[1], 1500.0, 30.0, "at the predicted arrival it is at the mouth")
	assert_gt(travel[2], 1800.0, "and flies on down the funnel")


# M8-T18: a ship passing the departure point too fast for the run-in carries on in the line-up (it turns and comes back), and a
# jump asked at speed gets the time for that.
func test_the_run_in_waits_for_a_speed_it_can_carry_and_the_line_up_gets_time() -> void:
	var departure := Vector3(0.0, 0.0, -1500.0)
	var jump := GateJump.new()
	jump.start()
	assert_eq(jump.step(0.1, departure, departure, true, false, false, 2000.0), PackedStringArray(), "too fast: still lining up")
	assert_eq(jump.state, GateJump.State.LINE_UP)
	assert_eq(jump.step(0.1, departure, departure, true, false, false, 250.0), PackedStringArray([GateJump.EV_RUN_IN]))
	assert_eq(GateJump.line_up_timeout_for(0.0, 30.0), GateJump.LINE_UP_TIMEOUT_S)
	assert_gt(GateJump.line_up_timeout_for(3000.0, 30.0), 400.0, "3 km/s: time to stop, come back and slow again")
	var slow := GateJump.new()
	slow.start(GateJump.line_up_timeout_for(3000.0, 30.0))
	assert_eq(slow.line_up_timeout_s, GateJump.line_up_timeout_for(3000.0, 30.0))
