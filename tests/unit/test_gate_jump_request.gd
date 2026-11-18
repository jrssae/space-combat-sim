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
