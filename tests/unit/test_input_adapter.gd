extends GutTest

const DT := 1.0 / 60.0

var adapter: InputAdapter
var source: FakeInputSource


func before_each() -> void:
	adapter = InputAdapter.new()
	source = FakeInputSource.new()


func test_neutral_input_is_a_zero_command() -> void:
	var cmd: PilotCommand = adapter.sample(source, DT)
	assert_eq(cmd.flight.main_left, 0.0)
	assert_eq(cmd.flight.main_right, 0.0)
	assert_eq(cmd.flight.strafe, Vector2.ZERO)
	assert_eq(cmd.flight.rot, Vector3.ZERO)
	assert_false(cmd.flight.brake)
	assert_false(cmd.combat.fire)
	assert_almost_eq(source.polled_dt, DT, 1e-12, "source is polled once per sample")


func test_triggers_and_bumpers_map_per_side() -> void:
	source.hold(InputAdapter.MAIN_RIGHT, 0.8)
	source.hold(InputAdapter.MAIN_LEFT, 0.3)
	source.hold(InputAdapter.RETRO_LEFT)
	var flight: FlightCommand = adapter.sample(source, DT).flight
	assert_almost_eq(flight.main_right, 0.8, 1e-9)
	assert_almost_eq(flight.main_left, 0.3, 1e-9)
	assert_eq(flight.retro_left, 1.0)
	assert_eq(flight.retro_right, 0.0)


func test_strafe_radial_deadzone_and_signs() -> void:
	adapter.stick_deadzone = 0.15
	source.hold(InputAdapter.STRAFE_RIGHT, 0.1)
	assert_eq(adapter.sample(source, DT).flight.strafe, Vector2.ZERO, "inside the radial deadzone")
	source.hold(InputAdapter.STRAFE_RIGHT, 0.575)
	assert_almost_eq(adapter.sample(source, DT).flight.strafe.x, 0.5, 1e-6, "rescaled outside it")
	source.release_all()
	source.hold(InputAdapter.STRAFE_UP, 1.0)
	assert_almost_eq(adapter.sample(source, DT).flight.strafe.y, 1.0, 1e-6, "stick up = heave up")
	source.release_all()
	source.hold(InputAdapter.STRAFE_LEFT, 1.0)
	source.hold(InputAdapter.STRAFE_DOWN, 1.0)
	var diag: Vector2 = adapter.sample(source, DT).flight.strafe
	assert_almost_eq(diag.length(), 1.0, 1e-6, "full diagonal is unit length")
	assert_lt(diag.x, 0.0)
	assert_lt(diag.y, 0.0)


func test_aim_expo_and_pilot_signs() -> void:
	adapter.stick_deadzone = 0.0
	source.hold(InputAdapter.YAW_RIGHT, 0.5)  # right stick right
	assert_almost_eq(adapter.sample(source, DT).flight.rot.y, pow(0.5, 1.5), 1e-6, "expo 1.5 on yaw, stick right = yaw right")
	source.release_all()
	source.hold(InputAdapter.YAW_LEFT, 1.0)
	assert_almost_eq(adapter.sample(source, DT).flight.rot.y, -1.0, 1e-6, "stick left = yaw left")
	source.release_all()
	source.hold(InputAdapter.PITCH_UP, 1.0)  # stick back
	assert_almost_eq(adapter.sample(source, DT).flight.rot.x, 1.0, 1e-6, "stick back = nose up")
	source.release_all()
	source.hold(InputAdapter.PITCH_DOWN, 0.5)
	assert_almost_eq(adapter.sample(source, DT).flight.rot.x, -pow(0.5, 1.5), 1e-6)


func test_strafe_is_linear_not_expo() -> void:
	adapter.stick_deadzone = 0.0
	source.hold(InputAdapter.STRAFE_RIGHT, 0.5)
	assert_almost_eq(adapter.sample(source, DT).flight.strafe.x, 0.5, 1e-6)


func test_invert_y() -> void:
	adapter.invert_y = true
	source.hold(InputAdapter.PITCH_UP, 1.0)
	assert_almost_eq(adapter.sample(source, DT).flight.rot.x, -1.0, 1e-6)


# The stick at `deg` clockwise from straight up, full deflection: (pitch, yaw, roll).
func _split_at(deg: float, length: float = 1.0) -> Vector3:
	var r: float = deg_to_rad(deg)
	return InputAdapter.split_stick(Vector2(sin(r), cos(r)) * length)


func test_the_stick_splits_into_pitch_yaw_and_roll_by_direction() -> void:
	assert_almost_eq(_split_at(0.0), Vector3(1.0, 0.0, 0.0), Vector3.ONE * 1e-6, "straight up: pitch up")
	assert_almost_eq(_split_at(22.0), Vector3(1.0, 0.0, 0.0), Vector3.ONE * 1e-6, "inside the pitch sector")
	assert_almost_eq(_split_at(23.0), Vector3(0.0, 0.0, 1.0), Vector3.ONE * 1e-6, "up-right diagonal: roll right")
	assert_almost_eq(_split_at(45.0), Vector3(0.0, 0.0, 1.0), Vector3.ONE * 1e-6)
	assert_almost_eq(_split_at(67.0), Vector3(0.0, 0.0, 1.0), Vector3.ONE * 1e-6)
	assert_almost_eq(_split_at(68.0), Vector3(0.0, 1.0, 0.0), Vector3.ONE * 1e-6, "inside the yaw sector")
	assert_almost_eq(_split_at(90.0), Vector3(0.0, 1.0, 0.0), Vector3.ONE * 1e-6, "straight right: yaw right")
	assert_almost_eq(_split_at(135.0), Vector3(0.0, 0.0, 1.0), Vector3.ONE * 1e-6, "down-right rolls right too")
	assert_almost_eq(_split_at(180.0), Vector3(-1.0, 0.0, 0.0), Vector3.ONE * 1e-6, "straight down: pitch down")
	assert_almost_eq(_split_at(225.0), Vector3(0.0, 0.0, -1.0), Vector3.ONE * 1e-6, "down-left rolls left")
	assert_almost_eq(_split_at(270.0), Vector3(0.0, -1.0, 0.0), Vector3.ONE * 1e-6, "straight left: yaw left")
	assert_almost_eq(_split_at(315.0), Vector3(0.0, 0.0, -1.0), Vector3.ONE * 1e-6, "up-left rolls left")
	assert_almost_eq(_split_at(45.0, 0.5).z, pow(0.5, 1.5), 1e-6, "one axis, at the deflection after expo")
	assert_eq(InputAdapter.split_stick(Vector2.ZERO), Vector3.ZERO)
	assert_eq(InputAdapter.STICK_SECTOR_HALF_DEG, 22.5)


func test_the_right_stick_drives_one_axis_at_a_time_inside_its_radial_deadzone() -> void:
	adapter.stick_deadzone = 0.15
	source.hold(InputAdapter.YAW_RIGHT, 0.1)
	source.hold(InputAdapter.PITCH_UP, 0.1)
	assert_eq(adapter.sample(source, DT).flight.rot, Vector3.ZERO, "|(0.1, 0.1)| = 0.14 is inside the radial deadzone")
	source.hold(InputAdapter.YAW_RIGHT, 0.575)
	source.release(InputAdapter.PITCH_UP)
	var rot: Vector3 = adapter.sample(source, DT).flight.rot
	assert_almost_eq(rot.y, pow(0.5, 1.5), 1e-6, "rescaled (to 0.5), then expo")
	assert_eq(rot.x, 0.0)
	assert_eq(rot.z, 0.0)
	source.hold(InputAdapter.YAW_LEFT, 1.0)
	source.release(InputAdapter.YAW_RIGHT)
	source.hold(InputAdapter.PITCH_DOWN, 1.0)
	var diag: Vector3 = adapter.sample(source, DT).flight.rot
	assert_almost_eq(diag.z, -1.0, 1e-6, "a full down-left diagonal rolls left at full rate")
	assert_eq(diag.x, 0.0, "and neither pitches")
	assert_eq(diag.y, 0.0, "nor yaws")


func test_the_roll_keys_add_to_the_sticks_roll() -> void:
	adapter.stick_deadzone = 0.0
	source.hold(InputAdapter.ROLL_LEFT)  # Caps Lock
	assert_eq(adapter.sample(source, DT).flight.rot, Vector3(0.0, 0.0, -1.0), "full roll from the first tick")
	source.release_all()
	source.hold(InputAdapter.ROLL_RIGHT)  # G
	source.hold(InputAdapter.YAW_RIGHT, 0.5)
	source.hold(InputAdapter.PITCH_UP, 0.5)  # up-right diagonal: roll right too
	assert_eq(adapter.sample(source, DT).flight.rot.z, 1.0, "clamped at full")
	source.release(InputAdapter.ROLL_RIGHT)
	source.hold(InputAdapter.ROLL_LEFT)
	assert_almost_eq(adapter.sample(source, DT).flight.rot.z, pow(sqrt(0.5), 1.5) - 1.0, 1e-6, "the key against the stick")


func test_invert_y_flips_only_the_sticks_pitch() -> void:
	adapter.invert_y = true
	adapter.stick_deadzone = 0.0
	source.hold(InputAdapter.YAW_RIGHT, 1.0)
	source.hold(InputAdapter.PITCH_UP, 1.0)  # up-right diagonal
	assert_almost_eq(adapter.sample(source, DT).flight.rot.z, 1.0, 1e-6, "the diagonal still rolls right")


func test_wing_orders_are_one_tick_edges_in_the_ui_command() -> void:
	# Keys 1-4 (M3-T07): orders reach the WingDirector as UiCommand edges, never through Input.
	source.hold(InputAdapter.WING_FORM, 1.0, true)
	var first: PilotCommand = adapter.sample(source, DT)
	assert_true(first.ui.wing_form)
	assert_false(first.ui.wing_attack or first.ui.wing_engage or first.ui.wing_cover)
	assert_true(first.ui.to_dict()["wing_form"])
	assert_false(adapter.sample(source, DT).ui.wing_form, "held is not a second order")
	source.keyboard_mouse_enabled = false
	source.release_all()
	adapter.sample(source, DT)
	source.hold(InputAdapter.WING_COVER, 1.0, true)
	assert_false(adapter.sample(source, DT).ui.wing_cover, "the console has the keyboard")


func test_edges_fire_for_one_tick() -> void:
	source.hold(InputAdapter.TOGGLE_ASSIST)
	source.hold(InputAdapter.TOGGLE_CAMERA)
	source.hold(InputAdapter.TARGET_AHEAD)
	var first: PilotCommand = adapter.sample(source, DT)
	assert_true(first.flight.toggle_assist)
	assert_true(first.ui.toggle_camera)
	assert_true(first.combat.target_ahead, "R3 / G: target ahead on the press")
	var second: PilotCommand = adapter.sample(source, DT)
	assert_false(second.flight.toggle_assist, "held is not a second edge")
	assert_false(second.ui.toggle_camera)
	assert_false(second.combat.target_ahead)
	source.release_all()
	adapter.sample(source, DT)
	source.hold(InputAdapter.TOGGLE_ASSIST)
	assert_true(adapter.sample(source, DT).flight.toggle_assist, "press again, edge again")


func test_every_edge_maps_to_its_field() -> void:
	var fields: Dictionary = {
		InputAdapter.WEAPON_NEXT: func(c: PilotCommand) -> bool: return c.combat.weapon_next,
		InputAdapter.TARGET_AHEAD: func(c: PilotCommand) -> bool: return c.combat.target_ahead,
		InputAdapter.TOGGLE_ASSIST: func(c: PilotCommand) -> bool: return c.flight.toggle_assist,
		InputAdapter.TOGGLE_CAMERA: func(c: PilotCommand) -> bool: return c.ui.toggle_camera,
		InputAdapter.RESET_SHIP: func(c: PilotCommand) -> bool: return c.ui.reset,
		InputAdapter.PAUSE: func(c: PilotCommand) -> bool: return c.ui.pause,
		InputAdapter.TOGGLE_OVERLAY: func(c: PilotCommand) -> bool: return c.ui.toggle_overlay,
		InputAdapter.TOGGLE_FALLBACK: func(c: PilotCommand) -> bool: return c.ui.toggle_fallback_mesh,
		InputAdapter.TARGET_PREV: func(c: PilotCommand) -> bool: return c.combat.target_prev,
		InputAdapter.SCREENSHOT: func(c: PilotCommand) -> bool: return c.ui.screenshot,
		InputAdapter.AUTOTRACK: func(c: PilotCommand) -> bool: return c.flight.autotrack,
		InputAdapter.WING_ATTACK: func(c: PilotCommand) -> bool: return c.ui.wing_attack,
		InputAdapter.WING_FORM: func(c: PilotCommand) -> bool: return c.ui.wing_form,
		InputAdapter.WING_ENGAGE: func(c: PilotCommand) -> bool: return c.ui.wing_engage,
		InputAdapter.WING_COVER: func(c: PilotCommand) -> bool: return c.ui.wing_cover,
	}
	assert_eq(fields.size(), InputAdapter.EDGE_ACTIONS.size(), "every edge action is covered")
	for action: StringName in fields.keys():
		adapter.reset()
		source.release_all()
		source.hold(action)
		var cmd: PilotCommand = adapter.sample(source, DT)
		assert_true((fields[action] as Callable).call(cmd), String(action))


# --- D-pad Up: tap = next target (on release), hold = target nearest the nose (once, at the threshold) -----------


## Holds the tap-or-hold button for `ticks` samples of `dt`, then releases it for one more. Returns per-tick flags.
func _press_for(ticks: int, dt: float = DT) -> Dictionary:
	var next_ticks: Array[int] = []
	var ahead_ticks: Array[int] = []
	source.hold(InputAdapter.TARGET_NEXT)
	for i: int in ticks + 1:
		if i == ticks:
			source.release(InputAdapter.TARGET_NEXT)
		var combat: CombatCommand = adapter.sample(source, dt).combat
		if combat.target_next:
			next_ticks.append(i)
		if combat.target_ahead:
			ahead_ticks.append(i)
	return {"next": next_ticks, "ahead": ahead_ticks}


func test_target_hold_default_matches_the_setting() -> void:
	assert_almost_eq(adapter.target_hold_s, InputAdapter.TARGET_HOLD_S, 1e-9)
	assert_almost_eq(float(SettingsSchema.new().get_default(&"target_hold_s")), InputAdapter.TARGET_HOLD_S, 1e-9)


func test_short_tap_selects_next_target_on_release() -> void:
	var r: Dictionary = _press_for(3)
	assert_eq(r["next"], [3] as Array[int], "target_next once, on the release tick")
	assert_eq(r["ahead"], [] as Array[int], "a tap never targets ahead")


func test_tap_just_under_the_threshold_is_still_a_tap() -> void:
	var ticks: int = ceili(adapter.target_hold_s / DT - 1e-6) - 1  # 20 ticks = 0.333 s at 60 Hz
	var r: Dictionary = _press_for(ticks)
	assert_eq(r["next"], [ticks] as Array[int])
	assert_eq(r["ahead"], [] as Array[int])


func test_hold_targets_ahead_once_at_the_threshold_and_never_cycles() -> void:
	var crossing: int = ceili(adapter.target_hold_s / DT - 1e-6) - 1  # tick index 20: the 21st tick held = 0.35 s
	var r: Dictionary = _press_for(60)
	assert_eq(r["ahead"], [crossing] as Array[int], "target_ahead once, when the hold crosses %.2f s" % adapter.target_hold_s)
	assert_eq(r["next"], [] as Array[int], "the release after a hold does not cycle")


func test_hold_threshold_is_tunable() -> void:
	adapter.target_hold_s = 0.5
	var r: Dictionary = _press_for(40, 0.05)
	assert_eq(r["ahead"], [9] as Array[int], "10 ticks of 0.05 s")
	assert_eq(r["next"], [] as Array[int])
	adapter.target_hold_s = 0.15
	r = _press_for(2, 0.05)
	assert_eq(r["next"], [2] as Array[int], "0.10 s held: a tap (the release tick does not count as held)")
	assert_eq(r["ahead"], [] as Array[int])
	r = _press_for(3, 0.05)
	assert_eq(r["ahead"], [2] as Array[int], "0.15 s held: the hold")
	assert_eq(r["next"], [] as Array[int])


func test_the_target_ahead_key_targets_ahead_on_the_press() -> void:
	source.hold(InputAdapter.TARGET_AHEAD)
	var cmd: PilotCommand = adapter.sample(source, DT)
	assert_true(cmd.combat.target_ahead)
	assert_false(cmd.combat.target_next)


func test_console_transition_drops_a_press_in_progress() -> void:
	source.hold(InputAdapter.TARGET_NEXT, 1.0, true)  # B held on the keyboard
	adapter.sample(source, DT)
	source.keyboard_mouse_enabled = false  # console opens: B now reads released
	adapter.resync_edges(source)
	var cmd: PilotCommand = adapter.sample(source, DT)
	assert_false(cmd.combat.target_next, "no phantom tap from the mask")
	source.keyboard_mouse_enabled = true  # console closes with B still down
	adapter.resync_edges(source)
	var fired: bool = false
	for i: int in 60:
		var combat: CombatCommand = adapter.sample(source, DT).combat
		fired = fired or combat.target_next or combat.target_ahead
	source.release_all()
	var released: CombatCommand = adapter.sample(source, DT).combat
	assert_false(fired or released.target_next or released.target_ahead, "a press already down at the transition never fires")


func test_reset_drops_a_press_in_progress() -> void:
	source.hold(InputAdapter.TARGET_NEXT)
	adapter.sample(source, DT)
	adapter.reset()
	source.release_all()
	assert_false(adapter.sample(source, DT).combat.target_next)


func test_held_actions() -> void:
	source.hold(InputAdapter.FIRE)
	source.hold(InputAdapter.BRAKE)
	for i: int in 3:
		var cmd: PilotCommand = adapter.sample(source, DT)
		assert_true(cmd.combat.fire)
		assert_true(cmd.flight.brake)


func test_keyboard_mask_drops_keys_but_not_pad() -> void:
	source.hold(InputAdapter.MAIN_RIGHT, 1.0, true)  # E on the keyboard
	source.hold(InputAdapter.MAIN_LEFT, 0.6)  # LT on the pad
	source.keyboard_mouse_enabled = false
	var flight: FlightCommand = adapter.sample(source, DT).flight
	assert_eq(flight.main_right, 0.0, "typing w in the console never thrusts")
	assert_almost_eq(flight.main_left, 0.6, 1e-9, "the pad keeps flying")


func test_mask_toggle_with_key_held_fires_no_edge() -> void:
	source.hold(InputAdapter.TOGGLE_CAMERA, 1.0, true)  # Tab held
	adapter.sample(source, DT)  # edge consumed
	source.keyboard_mouse_enabled = false  # console opens
	adapter.resync_edges(source)
	assert_false(adapter.sample(source, DT).ui.toggle_camera)
	source.keyboard_mouse_enabled = true  # console closes, Tab still down
	adapter.resync_edges(source)
	assert_false(adapter.sample(source, DT).ui.toggle_camera, "no phantom edge on unmask")


func test_last_command_is_kept() -> void:
	source.hold(InputAdapter.MAIN_RIGHT, 0.4)
	var cmd: PilotCommand = adapter.sample(source, DT)
	assert_eq(adapter.last, cmd)
	assert_almost_eq(float(cmd.flight.to_dict()["main_right"]), 0.4, 1e-9)


# --- Auto-track, camera look, mouse, wheel (post-M2 controls) -----------------------------------------------------


func test_autotrack_is_a_toggle_and_brake_is_separate() -> void:
	source.hold(InputAdapter.AUTOTRACK)
	var cmd: PilotCommand = adapter.sample(source, DT)
	assert_true(cmd.flight.autotrack, "first press: on")
	assert_false(cmd.flight.brake, "X no longer brakes")
	assert_true(adapter.sample(source, DT).flight.autotrack, "holding it does not toggle again")
	source.release(InputAdapter.AUTOTRACK)
	assert_true(adapter.sample(source, DT).flight.autotrack, "letting go leaves it on")
	source.hold(InputAdapter.AUTOTRACK)
	assert_false(adapter.sample(source, DT).flight.autotrack, "second press: off")
	source.release(InputAdapter.AUTOTRACK)
	source.hold(InputAdapter.BRAKE)
	cmd = adapter.sample(source, DT)
	assert_true(cmd.flight.brake)
	assert_false(cmd.flight.autotrack)


func test_reset_switches_autotrack_off() -> void:
	source.hold(InputAdapter.AUTOTRACK)
	adapter.sample(source, DT)
	assert_true(adapter.autotrack_on)
	adapter.reset()
	assert_false(adapter.autotrack_on)


func test_the_mouse_speed_is_the_turn_rate_and_stopping_the_mouse_stops_the_turn() -> void:
	adapter.mouse_full_rate_px_s = 1200.0
	# 20 px in a 1/60 s tick is 1200 px/s: a full-rate command once the smoothing has caught up.
	var yaw: float = 0.0
	for i: int in 30:
		source.push_mouse(Vector2(20.0, 0.0))
		yaw = adapter.sample(source, DT).flight.rot.y
	assert_almost_eq(yaw, 1.0, 0.01, "mouse right = yaw right at full rate")
	var cmd: PilotCommand
	for i: int in 30:
		cmd = adapter.sample(source, DT)
	assert_eq(cmd.flight.rot.y, 0.0, "a still mouse is no turn")


func test_the_mouse_pulled_back_pitches_up_and_invert_flips_it() -> void:
	adapter.mouse_full_rate_px_s = 1200.0
	var pitch: float = 0.0
	for i: int in 30:
		source.push_mouse(Vector2(0.0, 10.0))  # toward the user (screen down)
		pitch = adapter.sample(source, DT).flight.rot.x
	assert_gt(pitch, 0.4, "pulled back = nose up")
	adapter.reset()
	adapter.invert_y = true
	for i: int in 30:
		source.push_mouse(Vector2(0.0, 10.0))
		pitch = adapter.sample(source, DT).flight.rot.x
	assert_lt(pitch, -0.4, "inverted")


func test_camera_look_gives_the_stick_and_mouse_to_the_camera() -> void:
	adapter.stick_deadzone = 0.0
	source.hold(InputAdapter.CAMERA_LOOK)
	source.hold(InputAdapter.YAW_RIGHT, 1.0)
	source.hold(InputAdapter.PITCH_UP, 1.0)  # stick pulled back
	source.push_mouse(Vector2(30.0, -10.0))
	var cmd: PilotCommand = adapter.sample(source, DT)
	assert_true(cmd.ui.look_active)
	assert_eq(cmd.flight.rot.x, 0.0, "no pitch while looking")
	assert_eq(cmd.flight.rot.z, 0.0, "no roll while looking")
	assert_eq(cmd.flight.rot.y, 0.0, "no yaw while looking")
	assert_gt(cmd.ui.look_stick.x, 0.6, "stick right = look right (a full diagonal is 0.707 each)")
	assert_lt(cmd.ui.look_stick.y, -0.6, "stick pulled back = look down, as on a camera stick")
	assert_eq(cmd.ui.look_mouse_px, Vector2(30.0, 10.0), "the mouse up is look up")
	source.release_all()
	cmd = adapter.sample(source, DT)
	assert_false(cmd.ui.look_active)
	assert_eq(cmd.ui.look_stick, Vector2.ZERO)


func test_the_mouse_does_not_turn_the_ship_while_looking() -> void:
	source.hold(InputAdapter.CAMERA_LOOK)
	var cmd: PilotCommand
	for i: int in 10:
		source.push_mouse(Vector2(50.0, 50.0))
		cmd = adapter.sample(source, DT)
	assert_eq(cmd.flight.rot, Vector3.ZERO)


func test_the_wheel_cycles_targets() -> void:
	source.push_wheel(1)
	var cmd: PilotCommand = adapter.sample(source, DT)
	assert_true(cmd.combat.target_next, "wheel toward the user = next")
	assert_false(cmd.combat.target_prev)
	source.push_wheel(-1)
	cmd = adapter.sample(source, DT)
	assert_true(cmd.combat.target_prev, "wheel away = previous")
	assert_false(cmd.combat.target_next)
	cmd = adapter.sample(source, DT)
	assert_false(cmd.combat.target_prev, "one notch, one step")


# --- pad B: tap next, hold previous (M3-T15) --------------------------------------------------------------------------


func _press_cycle_for(ticks: int) -> Dictionary:
	var seen: Dictionary = {"next": 0, "prev": 0, "ahead": 0}
	for i: int in ticks + 3:
		if i == 0:
			source.hold(InputAdapter.TARGET_CYCLE)
		elif i == ticks:
			source.release(InputAdapter.TARGET_CYCLE)
		var combat: CombatCommand = adapter.sample(source, DT).combat
		seen["next"] += int(combat.target_next)
		seen["prev"] += int(combat.target_prev)
		seen["ahead"] += int(combat.target_ahead)
	return seen


func test_pad_b_tapped_selects_the_next_target_on_release() -> void:
	assert_eq(_press_cycle_for(5), {"next": 1, "prev": 0, "ahead": 0})


func test_pad_b_held_selects_the_previous_target_once_and_never_repeats() -> void:
	assert_eq(_press_cycle_for(int(InputAdapter.TARGET_HOLD_S / DT) + 120), {"next": 0, "prev": 1, "ahead": 0},
			"a long press steps back one target, as the mouse wheel")


func test_the_two_tap_or_hold_buttons_run_on_separate_timers() -> void:
	source.hold(InputAdapter.TARGET_NEXT, 1.0, true)  # keyboard B
	for i: int in 15:
		adapter.sample(source, DT)
	source.hold(InputAdapter.TARGET_CYCLE)  # pad B, pressed later
	var ahead: int = 0
	var prev: int = 0
	for i: int in 15:
		var combat: CombatCommand = adapter.sample(source, DT).combat
		ahead += int(combat.target_ahead)
		prev += int(combat.target_prev)
	assert_eq(ahead, 1, "keyboard B reached its hold")
	assert_eq(prev, 0, "pad B has not yet")


func test_reset_and_focus_changes_drop_a_pad_b_press() -> void:
	source.hold(InputAdapter.TARGET_CYCLE)
	adapter.sample(source, DT)
	adapter.reset()
	source.release(InputAdapter.TARGET_CYCLE)
	assert_false(adapter.sample(source, DT).combat.target_next, "reset: no tap on the release")
	source.hold(InputAdapter.TARGET_CYCLE)
	adapter.sample(source, DT)
	adapter.resync_edges(source)
	for i: int in 60:
		assert_false(adapter.sample(source, DT).combat.target_prev, "resync: the press in progress never fires")
