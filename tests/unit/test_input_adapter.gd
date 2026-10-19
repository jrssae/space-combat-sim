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
	source.hold(InputAdapter.YAW_RIGHT, 0.5)
	assert_almost_eq(adapter.sample(source, DT).flight.rot.y, pow(0.5, 1.5), 1e-6, "expo 1.5 on yaw")
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


func test_roll_ramp_release_and_reversal() -> void:
	adapter.roll_ramp_s = 0.25
	source.hold(InputAdapter.ROLL_RIGHT)
	var roll: float = 0.0
	for i: int in 3:
		roll = adapter.sample(source, 0.125 / 3.0).flight.rot.z
	assert_almost_eq(roll, 0.5, 1e-6, "half way after half the ramp time")
	for i: int in 30:
		roll = adapter.sample(source, DT).flight.rot.z
	assert_almost_eq(roll, 1.0, 1e-9, "saturates at full")
	source.release_all()
	assert_eq(adapter.sample(source, DT).flight.rot.z, 0.0, "release snaps to zero")
	source.hold(InputAdapter.ROLL_RIGHT)
	adapter.sample(source, 0.1)
	source.release_all()
	source.hold(InputAdapter.ROLL_LEFT)
	roll = adapter.sample(source, 0.05).flight.rot.z
	assert_almost_eq(roll, -0.2, 1e-6, "reversal restarts from zero")
	source.hold(InputAdapter.ROLL_RIGHT)
	assert_eq(adapter.sample(source, DT).flight.rot.z, 0.0, "both held cancels")


func test_edges_fire_for_one_tick() -> void:
	source.hold(InputAdapter.TOGGLE_ASSIST)
	source.hold(InputAdapter.TOGGLE_CAMERA)
	source.hold(InputAdapter.TARGET_NEXT)
	var first: PilotCommand = adapter.sample(source, DT)
	assert_true(first.flight.toggle_assist)
	assert_true(first.ui.toggle_camera)
	assert_true(first.combat.target_next)
	var second: PilotCommand = adapter.sample(source, DT)
	assert_false(second.flight.toggle_assist, "held is not a second edge")
	assert_false(second.ui.toggle_camera)
	assert_false(second.combat.target_next)
	source.release_all()
	adapter.sample(source, DT)
	source.hold(InputAdapter.TOGGLE_ASSIST)
	assert_true(adapter.sample(source, DT).flight.toggle_assist, "press again, edge again")


func test_every_edge_maps_to_its_field() -> void:
	var fields: Dictionary = {
		InputAdapter.WEAPON_NEXT: func(c: PilotCommand) -> bool: return c.combat.weapon_next,
		InputAdapter.TARGET_NEXT: func(c: PilotCommand) -> bool: return c.combat.target_next,
		InputAdapter.TARGET_AHEAD: func(c: PilotCommand) -> bool: return c.combat.target_ahead,
		InputAdapter.TOGGLE_ASSIST: func(c: PilotCommand) -> bool: return c.flight.toggle_assist,
		InputAdapter.TOGGLE_CAMERA: func(c: PilotCommand) -> bool: return c.ui.toggle_camera,
		InputAdapter.RESET_SHIP: func(c: PilotCommand) -> bool: return c.ui.reset,
		InputAdapter.PAUSE: func(c: PilotCommand) -> bool: return c.ui.pause,
		InputAdapter.TOGGLE_OVERLAY: func(c: PilotCommand) -> bool: return c.ui.toggle_overlay,
		InputAdapter.TOGGLE_FALLBACK: func(c: PilotCommand) -> bool: return c.ui.toggle_fallback_mesh,
	}
	assert_eq(fields.size(), InputAdapter.EDGE_ACTIONS.size(), "every edge action is covered")
	for action: StringName in fields.keys():
		adapter.reset()
		source.release_all()
		source.hold(action)
		var cmd: PilotCommand = adapter.sample(source, DT)
		assert_true((fields[action] as Callable).call(cmd), String(action))


func test_held_actions() -> void:
	source.hold(InputAdapter.FIRE)
	source.hold(InputAdapter.BRAKE)
	for i: int in 3:
		var cmd: PilotCommand = adapter.sample(source, DT)
		assert_true(cmd.combat.fire)
		assert_true(cmd.flight.brake)


func test_keyboard_mask_drops_keys_but_not_pad() -> void:
	source.hold(InputAdapter.MAIN_RIGHT, 1.0, true)  # W on the keyboard
	source.hold(InputAdapter.MAIN_LEFT, 0.6)  # LT on the pad
	source.keyboard_mouse_enabled = false
	var flight: FlightCommand = adapter.sample(source, DT).flight
	assert_eq(flight.main_right, 0.0, "typing w in the console never thrusts")
	assert_almost_eq(flight.main_left, 0.6, 1e-9, "the pad keeps flying")


func test_mask_toggle_with_key_held_fires_no_edge() -> void:
	source.hold(InputAdapter.TOGGLE_CAMERA, 1.0, true)  # V held
	adapter.sample(source, DT)  # edge consumed
	source.keyboard_mouse_enabled = false  # console opens
	adapter.resync_edges(source)
	assert_false(adapter.sample(source, DT).ui.toggle_camera)
	source.keyboard_mouse_enabled = true  # console closes, V still down
	adapter.resync_edges(source)
	assert_false(adapter.sample(source, DT).ui.toggle_camera, "no phantom edge on unmask")


func test_last_command_is_kept() -> void:
	source.hold(InputAdapter.MAIN_RIGHT, 0.4)
	var cmd: PilotCommand = adapter.sample(source, DT)
	assert_eq(adapter.last, cmd)
	assert_almost_eq(float(cmd.flight.to_dict()["main_right"]), 0.4, 1e-9)
