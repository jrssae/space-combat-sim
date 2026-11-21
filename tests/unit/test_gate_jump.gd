extends GutTest
## The player's gate jump (M6-T14): the prompt's rule (range and target), a hold of X as a jump request only while it is offered
## (M7-T27), the jump's state machine and its flash and fade, and the autopilot's line-up and run-in.

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
	assert_eq(GateJumpPrompt.line(500.0, true, true, true, true), "HOLD X: JUMP")
	assert_eq(GateJumpPrompt.line(50000.0, true, true, true, true), "")


func test_a_hold_of_x_requests_a_jump_only_while_offered() -> void:
	var adapter := InputAdapter.new()
	var source := FakeInputSource.new()
	adapter.interaction_offered = true
	source.hold(InputAdapter.AUTOTRACK)
	var asked: int = 0
	for i: int in 120:
		asked += int(adapter.sample(source, DT).ui.interact)
	assert_eq(asked, 1, "a 2 s hold of X beside the targeted gate asks for the jump, once")
	assert_false(adapter.autotrack_on, "and leaves auto-track off")
	source.release(InputAdapter.AUTOTRACK)
	adapter.sample(source, DT)
	adapter.interaction_offered = false
	source.hold(InputAdapter.AUTOTRACK)
	var cmd: PilotCommand = adapter.sample(source, DT)
	assert_false(cmd.ui.interact, "anywhere else X is auto-track")
	assert_true(adapter.autotrack_on)


func test_a_control_lock_drops_the_request() -> void:
	var pc := PilotCommand.new()
	pc.ui.interact = true
	pc.ui.interact_progress = 0.5
	ControlLock.new().apply(pc, true, false)
	assert_false(pc.ui.interact)
	assert_eq(pc.ui.interact_progress, 0.0, "no bar while the controls are held")


func test_hud_shows_the_prompt_on_the_acknowledgement_line() -> void:
	var input := HudInput.new()
	input.prompt_line = GateJumpPrompt.TEXT
	assert_eq(HudLayout.compute(input).ack_line, GateJumpPrompt.TEXT)
	input.ack_line = "ALPHA 2: COPY"
	assert_eq(HudLayout.compute(input).ack_line, "ALPHA 2: COPY", "an acknowledgement takes the line for its few seconds")


# --- the state machine ---------------------------------------------------------------------------------------------


func _run(jump: GateJump, seconds: float, local: Vector3, through: bool = false, placed: bool = false,
		closing_mps: float = 0.0) -> PackedStringArray:
	var all := PackedStringArray()
	var ticks: int = roundi(seconds / DT)
	for i: int in ticks:
		all.append_array(jump.step(DT, local, DEPARTURE, true, through and i == 0, placed and i == 0, closing_mps))
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
	var away: PackedStringArray = _run(jump, GateJump.RING_HOLD_S + GateJump.FADE_OUT_S + GateJump.AWAY_S + 3.0 * DT, Vector3.ZERO)
	assert_eq(away, PackedStringArray([GateJump.EV_ASK_ARRIVAL]), "straight after the ring's flash")
	assert_eq(jump.state, GateJump.State.ARRIVING)
	assert_eq(_run(jump, DT, Vector3(0.0, 0.0, 1200.0), false, true), PackedStringArray([GateJump.EV_ARRIVED]),
			"brought out at the funnel's ring (M6-T22)")
	assert_false(jump.ship_hidden())
	assert_eq(_run(jump, 6.0, Vector3(0.0, 0.0, 600.0)), PackedStringArray(), "still flying out of the funnel: not clear yet")
	assert_eq(_run(jump, DT, Vector3(0.0, 0.0, -GateJump.CLEAR_M - 1.0)), PackedStringArray([GateJump.EV_DONE]))
	assert_false(jump.is_active())
	assert_eq(jump.completed, 1)
	assert_eq(jump.start(), PackedStringArray([GateJump.EV_START]), "another jump may follow")


# Following wingmen still on their way through (M8-T17): at the ring flash's peak the jump cuts outside on the gate and holds
# there with no black for as long as the host wants it, never past `HOLD_MAX_S`, then the black and the arrival as usual.
func test_the_jump_holds_for_following_wingmen_without_black_then_goes_on() -> void:
	var jump := GateJump.new()
	jump.start()
	_run(jump, DT, DEPARTURE)
	jump.hold_wanted = true
	assert_eq(_run(jump, DT, Vector3(0.0, 0.0, 5.0), true), PackedStringArray([GateJump.EV_THROUGH, GateJump.EV_HOLD]),
			"straight outside at the ring's flash, never held on its white")
	assert_eq(jump.state, GateJump.State.HOLD)
	assert_eq(_run(jump, 3.0, Vector3.ZERO), PackedStringArray(), "held while wingmen are on their way")
	assert_eq(jump.black_level, 0.0, "no black while held")
	assert_true(jump.ship_hidden())
	jump.hold_wanted = false
	assert_eq(_run(jump, DT, Vector3.ZERO), PackedStringArray([GateJump.EV_HOLD_END]))
	assert_eq(jump.state, GateJump.State.AWAY, "then the black, as long as ever")
	assert_eq(_run(jump, GateJump.AWAY_S + 2.0 * DT, Vector3.ZERO), PackedStringArray([GateJump.EV_ASK_ARRIVAL]))
	var capped := GateJump.new()
	capped.start()
	_run(capped, DT, DEPARTURE)
	capped.hold_wanted = true
	_run(capped, DT, Vector3(0.0, 0.0, 5.0), true)
	var events: PackedStringArray = _run(capped, GateJump.HOLD_MAX_S + 3.0 * DT, Vector3.ZERO)
	assert_eq(events, PackedStringArray([GateJump.EV_HOLD_END]), "never held past its cap")
	assert_almost_eq(GateJump.FOLLOW_RANGE_M, 3000.0, 1e-3, "data/jump/player_jump.json")


# A ship just out of the gate crosses the departure point flying away: the run-in (and with it the vortex and the shot) waits
# until it has turned round (M7-T28).
func test_the_run_in_waits_for_a_ship_flying_away_from_the_gate() -> void:
	var jump := GateJump.new()
	jump.start()
	assert_eq(_run(jump, 1.0, DEPARTURE, false, false, -175.0), PackedStringArray(), "at the departure point, outbound: not yet")
	assert_eq(jump.state, GateJump.State.LINE_UP)
	assert_eq(_run(jump, DT, DEPARTURE, false, false, -GateJump.LINE_UP_RECEDE_MAX_MPS - 1.0), PackedStringArray())
	assert_eq(_run(jump, DT, DEPARTURE, false, false, 80.0), PackedStringArray([GateJump.EV_RUN_IN]), "inbound: the run-in starts")
	jump = GateJump.new()
	jump.start()
	assert_eq(_run(jump, DT, DEPARTURE), PackedStringArray([GateJump.EV_RUN_IN]), "at rest there: it starts at once")


func test_clearing_also_ends_on_time_once_out_of_the_mouth() -> void:
	var jump := GateJump.new()
	jump.start()
	jump.state = GateJump.State.CLEARING
	assert_eq(_run(jump, GateJump.CLEAR_S + DT, Vector3(0.0, 0.0, 300.0)), PackedStringArray(), "still in the funnel")
	assert_eq(_run(jump, GateJump.CLEAR_S + DT, Vector3(0.0, 0.0, -100.0)), PackedStringArray([GateJump.EV_DONE]))
	jump.start()
	jump.state = GateJump.State.CLEARING
	assert_eq(_run(jump, GateJump.CLEARING_TIMEOUT_S + DT, Vector3(0.0, 0.0, 300.0)), PackedStringArray([GateJump.EV_DONE]),
			"never longer than the timeout")


func test_the_jump_ends_early_when_it_must() -> void:
	var jump := GateJump.new()
	jump.start()
	assert_eq(jump.step(DT, Vector3.ZERO, DEPARTURE, false, false, false, 0.0), PackedStringArray([GateJump.EV_ABORT]))
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


func test_the_ring_flash_cuts_to_a_moment_of_black_then_straight_to_the_arrival() -> void:
	# Hard cuts (maintainer, 2026-11-19): the ring's own flash, then black for a beat, then the arrival; no fades. Data-driven.
	assert_almost_eq(GateJump.RING_HOLD_S, 0.3, 1e-6, "data/jump/player_jump.json")
	assert_between(GateJump.AWAY_S, 0.5, 1.0, "the black between the entry and the return")
	assert_between(GateJump.SWALLOW_S, 1.0, 1.5, "swallowed within a second or so of the mouth")
	assert_almost_eq(GateJump.BURST_OUT_S, 1.0, 1e-6)
	for t: float in [0.0, 0.2, 0.29]:
		assert_eq(GateJump.screen_at(GateJump.State.FLASH, t), Vector2.ZERO, "the ring's flash is in the shot, not on the screen")
	for t: float in [0.0, 0.4, 0.74]:
		assert_eq(GateJump.screen_at(GateJump.State.AWAY, t), Vector2(0.0, 1.0), "black, cut in, not faded")
	for t: float in [0.0, 0.1, 2.0]:
		assert_eq(GateJump.screen_at(GateJump.State.ARRIVING, t), Vector2.ZERO, "the arrival opens at once, no fade-in")
	assert_eq(GateJump.screen_at(GateJump.State.RUN_IN, 3.0), Vector2.ZERO)


# --- the autopilot --------------------------------------------------------------------------------------------------


func test_line_up_goes_round_the_arms_from_behind_or_beside() -> void:
	assert_eq(GateAutopilot.line_up_target(Vector3(0.0, 0.0, -6000.0), DEPARTURE), DEPARTURE, "in front: straight there")
	var behind: Vector3 = GateAutopilot.line_up_target(Vector3(0.0, 1500.0, 2000.0), DEPARTURE)
	assert_almost_eq(Vector2(behind.x, behind.y).length(), GateAutopilot.DETOUR_RADIUS_M, 0.1, "out past the arms first")
	assert_almost_eq(absf(behind.x), absf(behind.y), 0.1, "between two arms, never along one")
	assert_eq(behind.z, 2000.0, "without crossing the plane")
	var outside := Vector3(GateAutopilot.DETOUR_RADIUS_M, GateAutopilot.DETOUR_RADIUS_M, 3000.0)
	assert_eq(GateAutopilot.line_up_target(outside, DEPARTURE), DEPARTURE, "clear of the arms: round to the front")
	var inside := Vector3(100.0, 200.0, 600.0)
	assert_eq(GateAutopilot.line_up_target(inside, DEPARTURE), DEPARTURE, "within the four arms: straight out of the front")
	var beside: Vector3 = GateAutopilot.line_up_target(Vector3(900.0, 0.0, 600.0), DEPARTURE)
	assert_almost_eq(absf(beside.x), absf(beside.y), 0.1, "next to an arm (they run along the axis): out to a diagonal first")


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
