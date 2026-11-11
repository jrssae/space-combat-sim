extends GutTest
## The player's gate jump (M6-T14): the prompt's rule (range and target), X as a jump request only while it is offered, the jump's
## state machine and its flash and fade, and the autopilot's line-up and run-in.

const DT: float = 1.0 / 60.0
const DEPARTURE: Vector3 = Vector3(0.0, 0.0, -1440.0)


# --- the prompt --------------------------------------------------------------------------------------------------------


func test_prompt_needs_the_gate_targeted_within_ten_km() -> void:
	assert_true(GateJumpPrompt.offered(9999.0, true, true, true, true))
	assert_true(GateJumpPrompt.offered(GateJumpPrompt.RANGE_M, true, true, true, true), "10 km is within about 10 km")
	assert_false(GateJumpPrompt.offered(10001.0, true, true, true, true), "too far")
	assert_false(GateJumpPrompt.offered(500.0, false, true, true, true), "not targeted")
	assert_false(GateJumpPrompt.offered(500.0, true, false, true, true), "the ship is lost")
	assert_false(GateJumpPrompt.offered(500.0, true, true, false, true), "a mission or a shot holds the controls")
	assert_false(GateJumpPrompt.offered(500.0, true, true, true, false), "a jump is already under way")
	assert_eq(GateJumpPrompt.line(500.0, true, true, true, true), "X: REQUEST JUMP")
	assert_eq(GateJumpPrompt.line(50000.0, true, true, true, true), "")


func test_x_requests_a_jump_only_while_offered() -> void:
	var adapter := InputAdapter.new()
	var source := FakeInputSource.new()
	adapter.jump_offered = true
	source.hold(InputAdapter.AUTOTRACK)
	var cmd: PilotCommand = adapter.sample(source, DT)
	assert_true(cmd.ui.request_jump, "X beside the targeted gate asks for the jump")
	assert_false(adapter.autotrack_on, "and leaves auto-track off")
	assert_false(cmd.flight.autotrack)
	source.release(InputAdapter.AUTOTRACK)
	adapter.sample(source, DT)
	adapter.jump_offered = false
	source.hold(InputAdapter.AUTOTRACK)
	cmd = adapter.sample(source, DT)
	assert_false(cmd.ui.request_jump, "anywhere else X is auto-track")
	assert_true(adapter.autotrack_on)


func test_a_control_lock_drops_the_request() -> void:
	var pc := PilotCommand.new()
	pc.ui.request_jump = true
	ControlLock.new().apply(pc, true, false)
	assert_false(pc.ui.request_jump)


func test_hud_shows_the_prompt_on_the_acknowledgement_line() -> void:
	var input := HudInput.new()
	input.prompt_line = GateJumpPrompt.TEXT
	assert_eq(HudLayout.compute(input).ack_line, GateJumpPrompt.TEXT)
	input.ack_line = "ALPHA 2: COPY"
	assert_eq(HudLayout.compute(input).ack_line, "ALPHA 2: COPY", "an acknowledgement takes the line for its few seconds")


# --- the state machine ---------------------------------------------------------------------------------------------


func _run(jump: GateJump, seconds: float, local: Vector3, through: bool = false, placed: bool = false) -> PackedStringArray:
	var all := PackedStringArray()
	var ticks: int = roundi(seconds / DT)
	for i: int in ticks:
		all.append_array(jump.step(DT, local, DEPARTURE, true, through and i == 0, placed and i == 0))
	return all


func test_the_jump_goes_out_and_comes_back() -> void:
	var jump := GateJump.new()
	assert_eq(jump.start(), PackedStringArray([GateJump.EV_START]))
	assert_eq(jump.state, GateJump.State.LINE_UP)
	assert_true(jump.autopilot_on())
	assert_eq(_run(jump, 1.0, Vector3(0.0, 0.0, -5000.0)), PackedStringArray(), "lining up, far from the departure point")
	assert_eq(_run(jump, DT, DEPARTURE + Vector3(50.0, 0.0, 0.0)), PackedStringArray([GateJump.EV_RUN_IN]))
	assert_eq(jump.state, GateJump.State.RUN_IN)
	assert_eq(_run(jump, DT, Vector3(0.0, 0.0, 5.0), true), PackedStringArray([GateJump.EV_THROUGH]))
	assert_true(jump.ship_hidden())
	assert_false(jump.autopilot_on())
	var away: PackedStringArray = _run(jump, GateJump.FLASH_S + GateJump.FADE_OUT_S + GateJump.AWAY_S + DT, Vector3.ZERO)
	assert_eq(away, PackedStringArray([GateJump.EV_ASK_ARRIVAL]), "after the flash, the fade and the time away")
	assert_eq(jump.state, GateJump.State.ARRIVING)
	assert_eq(_run(jump, DT, Vector3(0.0, 0.0, -72.0), false, true), PackedStringArray([GateJump.EV_ARRIVED]))
	assert_false(jump.ship_hidden())
	assert_eq(_run(jump, DT, Vector3(0.0, 0.0, -72.0 - GateJump.CLEAR_M - 1.0)), PackedStringArray([GateJump.EV_DONE]))
	assert_false(jump.is_active())
	assert_eq(jump.completed, 1)
	assert_eq(jump.start(), PackedStringArray([GateJump.EV_START]), "another jump may follow")


func test_clearing_also_ends_on_time() -> void:
	var jump := GateJump.new()
	jump.start()
	jump.state = GateJump.State.CLEARING
	assert_eq(_run(jump, GateJump.CLEAR_S + DT, Vector3(0.0, 0.0, -100.0)), PackedStringArray([GateJump.EV_DONE]))


func test_the_jump_ends_early_when_it_must() -> void:
	var jump := GateJump.new()
	jump.start()
	assert_eq(jump.step(DT, Vector3.ZERO, DEPARTURE, false, false, false), PackedStringArray([GateJump.EV_ABORT]))
	assert_eq(jump.ended_why, "the ship was lost")
	jump.start()
	assert_eq(_run(jump, GateJump.LINE_UP_TIMEOUT_S + 1.0, Vector3(0.0, 0.0, -9000.0)), PackedStringArray([GateJump.EV_ABORT]))
	assert_string_contains(jump.ended_why, "line up")
	jump.start()
	assert_eq(jump.cancel("respawn"), PackedStringArray([GateJump.EV_ABORT]))
	assert_eq(jump.ended_why, "respawn")
	assert_eq(jump.cancel(), PackedStringArray(), "nothing to cancel")
	assert_eq(jump.aborted, 3)
	assert_eq(jump.start().size(), 1)
	assert_eq(jump.start().size(), 0, "one jump at a time")


func test_flash_then_black_then_the_fade_lifts() -> void:
	assert_eq(GateJump.screen_at(GateJump.State.RUN_IN, 3.0), Vector2.ZERO)
	var peak: Vector2 = GateJump.screen_at(GateJump.State.FLASH, GateJump.FLASH_S)
	assert_almost_eq(peak.x, 1.0, 1e-4, "the flash peaks")
	assert_almost_eq(peak.y, 0.0, 1e-4, "before the black comes in")
	var black: Vector2 = GateJump.screen_at(GateJump.State.FLASH, GateJump.FLASH_S + GateJump.FADE_OUT_S)
	assert_almost_eq(black.y, 1.0, 1e-4)
	assert_almost_eq(black.x, 0.0, 1e-4)
	assert_eq(GateJump.screen_at(GateJump.State.AWAY, 1.0), Vector2(0.0, 1.0))
	assert_almost_eq(GateJump.screen_at(GateJump.State.ARRIVING, GateJump.FADE_IN_S * 0.5).y, 0.5, 1e-4)
	assert_eq(GateJump.screen_at(GateJump.State.ARRIVING, GateJump.FADE_IN_S + 1.0), Vector2.ZERO)


# --- the autopilot --------------------------------------------------------------------------------------------------


func test_line_up_goes_round_a_gate_seen_from_behind() -> void:
	assert_eq(GateAutopilot.line_up_target(Vector3(0.0, 0.0, -6000.0), DEPARTURE), DEPARTURE, "in front: straight there")
	var behind: Vector3 = GateAutopilot.line_up_target(Vector3(0.0, 1500.0, 2000.0), DEPARTURE)
	assert_almost_eq(Vector2(behind.x, behind.y).length(), GateAutopilot.DETOUR_RADIUS_M, 0.1, "out past the arms first")
	assert_almost_eq(absf(behind.x), absf(behind.y), 0.1, "between two arms, never along one")
	assert_eq(behind.z, 2000.0, "without crossing the plane")
	var outside := Vector3(GateAutopilot.DETOUR_RADIUS_M, GateAutopilot.DETOUR_RADIUS_M, 3000.0)
	assert_eq(GateAutopilot.line_up_target(outside, DEPARTURE), DEPARTURE, "clear of the arms: round to the front")


func test_run_in_waits_for_the_vortex() -> void:
	var cap := ShipCapability.new()
	var basis := Basis.IDENTITY  # nose along -Z, the way a departure flies in a gate facing +Z
	var axis := Vector3.FORWARD
	var at := Vector3(0.0, 0.0, 1440.0)
	var moving := Vector3(0.0, 0.0, -240.0)
	var closed: FlightCommand = GateAutopilot.run_in(at, moving, basis, Vector3.ZERO, axis, Vector3.UP, INF, cap)
	var opening: FlightCommand = GateAutopilot.run_in(at, moving, basis, Vector3.ZERO, axis, Vector3.UP, 3.5, cap)
	assert_gt(opening.main_left, 0.0, "toward an opening vortex it keeps accelerating to the run-in speed")
	assert_gt(closed.retro_left, 0.0, "while the vortex is not yet opening it holds back")
	var fast: FlightCommand = GateAutopilot.run_in(Vector3(0.0, 0.0, 300.0), Vector3(0.0, 0.0, -250.0), basis, Vector3.ZERO,
			axis, Vector3.UP, 3.0, cap)
	assert_gt(fast.retro_left, 0.0, "too fast for a vortex 3 s from open: it slows")
