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
		InputAdapter.TARGET_PREV: func(c: PilotCommand) -> bool: return c.combat.target_prev,
		InputAdapter.SCREENSHOT: func(c: PilotCommand) -> bool: return c.ui.screenshot,
		InputAdapter.AUTOTRACK: func(c: PilotCommand) -> bool: return c.flight.autotrack,
		InputAdapter.WING_ATTACK: func(c: PilotCommand) -> bool: return c.ui.wing_attack,
		InputAdapter.WING_FORM: func(c: PilotCommand) -> bool: return c.ui.wing_form,
		InputAdapter.WING_ENGAGE: func(c: PilotCommand) -> bool: return c.ui.wing_engage,
		InputAdapter.WING_COVER: func(c: PilotCommand) -> bool: return c.ui.wing_cover,
		InputAdapter.TOGGLE_RUNNING_LIGHTS: func(c: PilotCommand) -> bool: return c.ui.toggle_running_lights,
		InputAdapter.COMMS_MENU: func(c: PilotCommand) -> bool: return c.ui.comms_open,
	}
	assert_eq(fields.size(), InputAdapter.EDGE_ACTIONS.size(), "every edge action is covered")
	for action: StringName in fields.keys():
		adapter.reset()
		source.release_all()
		source.hold(action)
		var cmd: PilotCommand = adapter.sample(source, DT)
		assert_true((fields[action] as Callable).call(cmd), String(action))


# --- The target button (M5-T25): tap = the nearest enemy (on release), hold = the target menu (once, at the threshold) --


## Holds the tap-or-hold button for `ticks` samples of `dt`, then releases it for one more. Returns the ticks its tap
## (`next`: `CombatCommand.target_nearest`) and its hold (`ahead`: `UiCommand.target_menu_open`) fired on, and whether
## anything of the old behaviour (cycling, nearest the nose) fired at all.
func _press_for(ticks: int, dt: float = DT) -> Dictionary:
	var next_ticks: Array[int] = []
	var ahead_ticks: Array[int] = []
	var old: bool = false
	source.hold(InputAdapter.TARGET_NEXT)
	for i: int in ticks + 1:
		if i == ticks:
			source.release(InputAdapter.TARGET_NEXT)
		var cmd: PilotCommand = adapter.sample(source, dt)
		if cmd.combat.target_nearest:
			next_ticks.append(i)
		if cmd.ui.target_menu_open:
			ahead_ticks.append(i)
		old = old or cmd.combat.target_next or cmd.combat.target_ahead or cmd.combat.target_prev
	return {"next": next_ticks, "ahead": ahead_ticks, "old": old}


func test_target_hold_default_matches_the_setting() -> void:
	assert_almost_eq(adapter.target_hold_s, InputAdapter.TARGET_HOLD_S, 1e-9)
	assert_almost_eq(float(SettingsSchema.new().get_default(&"target_hold_s")), InputAdapter.TARGET_HOLD_S, 1e-9)


func test_short_tap_selects_next_target_on_release() -> void:
	var r: Dictionary = _press_for(3)
	assert_eq(r["next"], [3] as Array[int], "target_nearest once, on the release tick")
	assert_eq(r["ahead"], [] as Array[int], "a tap never opens the menu")
	assert_false(r["old"], "the button no longer cycles or picks the target nearest the nose")


func test_tap_just_under_the_threshold_is_still_a_tap() -> void:
	var ticks: int = ceili(adapter.target_hold_s / DT - 1e-6) - 1  # 20 ticks = 0.333 s at 60 Hz
	var r: Dictionary = _press_for(ticks)
	assert_eq(r["next"], [ticks] as Array[int])
	assert_eq(r["ahead"], [] as Array[int])


func test_hold_targets_ahead_once_at_the_threshold_and_never_cycles() -> void:
	var crossing: int = ceili(adapter.target_hold_s / DT - 1e-6) - 1  # tick index 20: the 21st tick held = 0.35 s
	var r: Dictionary = _press_for(60)
	assert_eq(r["ahead"], [crossing] as Array[int], "the target menu once, when the hold crosses %.2f s" % adapter.target_hold_s)
	assert_eq(r["next"], [] as Array[int], "the release after a hold does not tap")
	assert_false(r["old"], "a hold is no longer the target nearest the nose")


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
	assert_false(cmd.combat.target_nearest, "no phantom tap from the mask")
	source.keyboard_mouse_enabled = true  # console closes with B still down
	adapter.resync_edges(source)
	var fired: bool = false
	for i: int in 60:
		var held: PilotCommand = adapter.sample(source, DT)
		fired = fired or held.combat.target_nearest or held.ui.target_menu_open
	source.release_all()
	var released: PilotCommand = adapter.sample(source, DT)
	assert_false(fired or released.combat.target_nearest or released.ui.target_menu_open, "a press already down at the transition never fires")


func test_reset_drops_a_press_in_progress() -> void:
	source.hold(InputAdapter.TARGET_NEXT)
	adapter.sample(source, DT)
	adapter.reset()
	source.release_all()
	assert_false(adapter.sample(source, DT).combat.target_nearest)


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


# --- pad B: tap the nearest enemy, hold the target menu (M5-T25) ------------------------------------------------------


func _press_cycle_for(ticks: int) -> Dictionary:
	var seen: Dictionary = {"tap": 0, "menu": 0, "old": 0}
	for i: int in ticks + 3:
		if i == 0:
			source.hold(InputAdapter.TARGET_CYCLE)
		elif i == ticks:
			source.release(InputAdapter.TARGET_CYCLE)
		var cmd: PilotCommand = adapter.sample(source, DT)
		seen["tap"] += int(cmd.combat.target_nearest)
		seen["menu"] += int(cmd.ui.target_menu_open)
		seen["old"] += int(cmd.combat.target_next) + int(cmd.combat.target_prev) + int(cmd.combat.target_ahead)
	return seen


func test_pad_b_tapped_picks_the_nearest_enemy_on_release() -> void:
	assert_eq(_press_cycle_for(5), {"tap": 1, "menu": 0, "old": 0})


func test_pad_b_held_opens_the_target_menu_once_and_never_repeats() -> void:
	assert_eq(_press_cycle_for(int(InputAdapter.TARGET_HOLD_S / DT) + 120), {"tap": 0, "menu": 1, "old": 0},
			"a long press asks for the menu once; it no longer steps back a target")


func test_the_two_tap_or_hold_buttons_run_on_separate_timers() -> void:
	source.hold(InputAdapter.TARGET_NEXT, 1.0, true)  # keyboard B
	for i: int in 15:
		adapter.sample(source, DT)
	source.hold(InputAdapter.TARGET_CYCLE)  # pad B, pressed later
	var holds: int = 0
	for i: int in 15:
		holds += int(adapter.sample(source, DT).ui.target_menu_open)
	assert_eq(holds, 1, "keyboard B reached its hold; pad B has not yet")
	for i: int in 15:
		holds += int(adapter.sample(source, DT).ui.target_menu_open)
	assert_eq(holds, 2, "pad B reaches its own later")


func test_reset_and_focus_changes_drop_a_pad_b_press() -> void:
	source.hold(InputAdapter.TARGET_CYCLE)
	adapter.sample(source, DT)
	adapter.reset()
	source.release(InputAdapter.TARGET_CYCLE)
	assert_false(adapter.sample(source, DT).combat.target_nearest, "reset: no tap on the release")
	source.hold(InputAdapter.TARGET_CYCLE)
	adapter.sample(source, DT)
	adapter.resync_edges(source)
	for i: int in 60:
		assert_false(adapter.sample(source, DT).ui.target_menu_open, "resync: the press in progress never fires")


# --- While a menu has the pad (M5-T02 review): only the pause edge is read -------------------------------------------


func test_a_menu_reads_only_the_pause_edge() -> void:
	var ui: UiCommand = adapter.sample_menu(source, DT)
	assert_false(ui.pause)
	source.hold(InputAdapter.PAUSE)
	assert_true(adapter.sample_menu(source, DT).pause, "Start closes the menu")
	assert_false(adapter.sample_menu(source, DT).pause, "an edge, not a level")
	assert_almost_eq(source.polled_dt, DT, 1e-12, "the source is still polled")


func test_buttons_that_move_a_menu_do_not_act_behind_it() -> void:
	for action: StringName in [InputAdapter.RESET_SHIP, InputAdapter.TOGGLE_CAMERA, InputAdapter.TOGGLE_RUNNING_LIGHTS,
			InputAdapter.AUTOTRACK, InputAdapter.TOGGLE_ASSIST, InputAdapter.WEAPON_NEXT, InputAdapter.TARGET_CYCLE,
			InputAdapter.COMMS_MENU]:
		source.hold(action)
	var ui: UiCommand = adapter.sample_menu(source, DT)
	assert_false(ui.comms_open, "D-pad Right does not open the comms menu behind the pause menu")
	assert_false(ui.reset)
	assert_false(ui.toggle_camera)
	assert_false(ui.toggle_running_lights)
	assert_false(adapter.autotrack_on, "X does not switch auto-track on behind the menu")
	# Still held when the menu closes, and then let go: none of it fires.
	var held: PilotCommand = adapter.sample(source, DT)
	assert_false(held.ui.reset or held.ui.toggle_camera or held.ui.toggle_running_lights, "no edge at the first flight tick")
	assert_false(held.flight.toggle_assist or held.combat.weapon_next or held.flight.autotrack or held.ui.comms_open)
	source.release_all()
	var released: PilotCommand = adapter.sample(source, DT)
	assert_false(released.combat.target_nearest or released.ui.target_menu_open, "a target button held through the menu taps nothing")


func test_a_menu_drains_the_mouse_and_the_wheel() -> void:
	source.push_mouse(Vector2(500.0, 300.0))
	source.push_wheel(3)
	adapter.sample_menu(source, DT)
	var cmd: PilotCommand = adapter.sample(source, DT)
	assert_eq(cmd.flight.rot, Vector3.ZERO, "the mouse moved behind the menu does not turn the ship afterwards")
	assert_false(cmd.combat.target_next, "nor does the wheel step a target")


# --- The comms menu (D54, M5-T46): D-pad Right opens it, and the radial menu owns the pad until it closes -------------------


func test_dpad_right_opens_the_comms_menu_for_one_tick() -> void:
	source.hold(InputAdapter.COMMS_MENU)
	var cmd: PilotCommand = adapter.sample(source, DT)
	assert_true(cmd.ui.comms_open)
	assert_true(cmd.ui.to_dict()["comms_open"])
	assert_false(adapter.sample(source, DT).ui.comms_open, "held is not a second press")


func test_dpad_right_closes_the_comms_menu_again_but_not_the_press_that_opened_it() -> void:
	source.hold(InputAdapter.COMMS_MENU)
	adapter.begin_radial(source)
	assert_false(adapter.sample_radial(source, DT).comms_open, "the press that opened it is not a close")
	source.release(InputAdapter.COMMS_MENU)
	assert_false(adapter.sample_radial(source, DT).comms_open)
	source.hold(InputAdapter.COMMS_MENU)
	assert_true(adapter.sample_radial(source, DT).comms_open, "a fresh press is")
	assert_false(adapter.sample_radial(source, DT).comms_open, "an edge, not a level")


func test_the_dpad_does_not_point_the_radial_menu() -> void:
	adapter.begin_radial(source)
	for action: StringName in [InputAdapter.TOGGLE_ASSIST, InputAdapter.COMMS_MENU, InputAdapter.WEAPON_NEXT,
			InputAdapter.TOGGLE_RUNNING_LIGHTS]:
		source.hold(action)
	var ui: UiCommand = adapter.sample_radial(source, DT)
	assert_eq(ui.radial_point, Vector2.ZERO, "only the stick, the arrows and the mouse point")
	assert_false(ui.radial_select or ui.radial_back)


func test_a_dpad_press_held_through_the_comms_menu_fires_nothing_when_it_closes() -> void:
	adapter.begin_radial(source)
	source.hold(InputAdapter.TOGGLE_ASSIST)
	source.hold(InputAdapter.WEAPON_NEXT)
	adapter.sample_radial(source, DT)
	adapter.end_radial(source)
	var after: PilotCommand = adapter.sample(source, DT)
	assert_false(after.flight.toggle_assist or after.combat.weapon_next, "D-pad Up and Down still held: nothing toggles")


# --- A radial menu (M5-T25): only its stick, select, back and Start are read ------------------------------------------


func test_a_radial_menu_reads_its_stick_as_a_direction() -> void:
	adapter.begin_radial(source)
	assert_eq(adapter.sample_radial(source, DT).radial_point, Vector2.ZERO, "a centred stick points at nothing")
	source.hold(InputAdapter.RADIAL_UP, 1.0)
	var up: Vector2 = adapter.sample_radial(source, DT).radial_point
	assert_almost_eq(up, Vector2(0.0, 1.0), Vector2(1e-6, 1e-6), "stick up: y up")
	source.release_all()
	source.hold(InputAdapter.RADIAL_RIGHT, 1.0)
	source.hold(InputAdapter.RADIAL_DOWN, 1.0)
	var v: Vector2 = adapter.sample_radial(source, DT).radial_point
	assert_gt(v.x, 0.5)
	assert_lt(v.y, -0.5, "two arrow keys: the diagonal")
	source.release_all()
	source.hold(InputAdapter.RADIAL_LEFT, adapter.stick_deadzone * 0.5)
	assert_eq(adapter.sample_radial(source, DT).radial_point, Vector2.ZERO, "inside the deadzone: nothing")
	assert_almost_eq(source.polled_dt, DT, 1e-12, "the source is still polled")


func test_a_radial_menus_select_and_back_are_edges_seeded_from_what_is_held() -> void:
	# B opened the menu and is still down: it must not also go back.
	source.hold(InputAdapter.RADIAL_BACK)
	adapter.begin_radial(source)
	assert_false(adapter.sample_radial(source, DT).radial_back, "the press that opened it is not a back")
	source.release(InputAdapter.RADIAL_BACK)
	assert_false(adapter.sample_radial(source, DT).radial_back)
	source.hold(InputAdapter.RADIAL_BACK)
	assert_true(adapter.sample_radial(source, DT).radial_back, "a fresh press is")
	assert_false(adapter.sample_radial(source, DT).radial_back, "an edge, not a level")
	source.hold(InputAdapter.RADIAL_SELECT)
	var ui: UiCommand = adapter.sample_radial(source, DT)
	assert_true(ui.radial_select)
	assert_false(adapter.sample_radial(source, DT).radial_select)
	source.release_all()
	source.hold(InputAdapter.PAUSE)
	assert_true(adapter.sample_radial(source, DT).pause, "Start is read, for the pause menu")
	assert_false(adapter.sample_radial(source, DT).pause)


func test_the_mouse_points_a_radial_menu_by_its_direction_of_travel() -> void:
	adapter.begin_radial(source)
	source.push_mouse(Vector2(0.0, -200.0))  # up the screen
	var up: Vector2 = adapter.sample_radial(source, DT).radial_point
	assert_almost_eq(up, Vector2(0.0, 1.0), Vector2(1e-6, 1e-6), "the mouse pushed away points up, at full reach")
	assert_eq(adapter.sample_radial(source, DT).radial_point, Vector2.ZERO, "a still mouse points at nothing new: the highlight stays")
	source.push_mouse(Vector2(120.0, 240.0))
	var v: Vector2 = adapter.sample_radial(source, DT).radial_point
	assert_gt(v.x, 0.5, "it travels on from where it pointed")
	assert_lt(v.y, 0.0)
	assert_almost_eq(v.length(), 1.0, 1e-6, "never past the rim")
	# The stick wins while it leans.
	source.push_mouse(Vector2(-500.0, 0.0))
	source.hold(InputAdapter.RADIAL_UP, 1.0)
	assert_almost_eq(adapter.sample_radial(source, DT).radial_point, Vector2(0.0, 1.0), Vector2(1e-6, 1e-6))
	# A menu opened again starts from the centre.
	source.release_all()
	adapter.begin_radial(source)
	source.push_mouse(Vector2(30.0, 0.0))
	assert_almost_eq(adapter.sample_radial(source, DT).radial_point.x, 30.0 / InputAdapter.RADIAL_MOUSE_REACH_PX, 1e-6)


func test_nothing_else_is_read_behind_a_radial_menu() -> void:
	adapter.begin_radial(source)
	for action: StringName in [InputAdapter.RESET_SHIP, InputAdapter.TOGGLE_CAMERA, InputAdapter.TOGGLE_RUNNING_LIGHTS,
			InputAdapter.AUTOTRACK, InputAdapter.TOGGLE_ASSIST, InputAdapter.WEAPON_NEXT, InputAdapter.TARGET_CYCLE,
			InputAdapter.TARGET_NEXT, InputAdapter.FIRE, InputAdapter.WING_ATTACK]:
		source.hold(action)
	source.push_wheel(2)
	var ui: UiCommand = adapter.sample_radial(source, DT)
	assert_false(ui.reset or ui.toggle_camera or ui.toggle_running_lights or ui.comms_open or ui.wing_attack or ui.target_menu_open)
	assert_false(adapter.autotrack_on, "X takes no part in the menu")
	assert_false(adapter.last.combat.fire or adapter.last.combat.target_next, "the last command holds no flight or combat input")
	# The menu closes with all of it still down: nothing fires, taps or steps, then or on the release.
	adapter.end_radial(source)
	for _i: int in 40:
		var held: PilotCommand = adapter.sample(source, DT)
		assert_false(held.combat.fire, "the button that selected is also fire: held over, it does not shoot")
		assert_false(held.ui.reset or held.ui.toggle_camera or held.ui.toggle_running_lights or held.ui.comms_open or held.ui.wing_attack)
		assert_false(held.flight.toggle_assist or held.combat.weapon_next or held.flight.autotrack)
		assert_false(held.combat.target_nearest or held.ui.target_menu_open or held.combat.target_next, "no tap, no reopening, no wheel step")
	source.release_all()
	var released: PilotCommand = adapter.sample(source, DT)
	assert_false(released.combat.target_nearest or released.combat.fire)
	source.hold(InputAdapter.FIRE)
	assert_true(adapter.sample(source, DT).combat.fire, "pressed again, fire fires")


func test_the_stick_that_pointed_does_not_steer_until_it_centres() -> void:
	adapter.begin_radial(source)
	source.hold(InputAdapter.YAW_RIGHT, 1.0)
	adapter.sample_radial(source, DT)
	source.push_mouse(Vector2(900.0, 0.0))
	adapter.end_radial(source)
	for _i: int in 5:
		assert_eq(adapter.sample(source, DT).flight.rot, Vector3.ZERO, "held over from the menu: no turn, from the stick or the mouse")
	source.release(InputAdapter.YAW_RIGHT)
	assert_eq(adapter.sample(source, DT).flight.rot, Vector3.ZERO)
	source.hold(InputAdapter.YAW_RIGHT, 1.0)
	assert_almost_eq(adapter.sample(source, DT).flight.rot.y, 1.0, 1e-6, "centred once, the stick flies again")
	# A stick at rest when the menu closes is not held over at all.
	adapter.end_radial(source)
	adapter.reset()
	source.release_all()
	adapter.end_radial(source)
	source.hold(InputAdapter.PITCH_UP, 1.0)
	assert_almost_eq(adapter.sample(source, DT).flight.rot.x, 1.0, 1e-6)
