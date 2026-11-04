extends GutTest
## AC8 on the real main scene (architecture §18 D55, M5-T08), on `tests/fixtures/missions/test_cinematic.json`: the mission's intro
## shot plays on the cinematic camera with the HUD hidden, the letterbox in and the subtitles still up; the player's commands are
## zeroed while the ship keeps its physics; a rebase mid-shot moves nothing on screen; A or Start skips the shot (the A that skipped
## does not fire); `mission skip` cuts it; `lock_controls` alone zeroes the commands without the camera; the comms menu waits.

const MISSION_PATH: String = "res://tests/fixtures/missions/test_cinematic.json"
## The intro's length in the fixture.
const SHOT_S: float = 3.0

var main: Main
var source: FakeInputSource
var shots_fired: int = 0
var _game_state: GameFlow.State
var _game_result: Dictionary
var _show_hud_backup: Variant


func before_each() -> void:
	get_tree().paused = false
	_game_state = Game.flow.state
	_game_result = Game.flow.last_result
	_show_hud_backup = Settings.get_value(&"show_hud")
	Settings.set_value(&"show_hud", true)
	shots_fired = 0
	source = FakeInputSource.new()


func after_each() -> void:
	get_tree().paused = false
	Settings.set_value(&"show_hud", _show_hud_backup)
	Game.flow.state = _game_state
	Game.flow.last_result = _game_result


func _make_main(path: String = MISSION_PATH) -> void:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	main.scenario_path = path
	add_child_autofree(main)
	main.cannon.projectile_fired.connect(func(_i: int, _p: Projectile) -> void: shots_fired += 1)
	await _ticks(2)


func _ticks(n: int) -> void:
	for _i: int in n:
		await get_tree().physics_frame


func _frames(n: int) -> void:
	for _i: int in n:
		await get_tree().process_frame


func _press(action: StringName) -> void:
	source.hold(action)
	await _ticks(1)
	source.release(action)
	await _ticks(1)


func _rig() -> CameraRig:
	return main.camera_rig


func _api() -> MissionApi:
	return main.mission.api


func _until(done: Callable, limit: int = 400) -> bool:
	for _i: int in limit:
		if done.call():
			return true
		await _ticks(1)
	return bool(done.call())


func _assert_free_camera() -> void:
	assert_false(_rig().is_playing_shot(), "no shot playing")
	assert_eq(_rig().mode, CameraRig.Mode.CHASE)
	assert_true(main.hud.visible, "the HUD is back")
	assert_false(main.letterbox.shown, "the bars slide out")


# Sets the ship moving and returns its velocity.
func _set_drift() -> Vector3:
	var v := Vector3(5.0, 0.0, -40.0)
	main.ship.linear_velocity = v
	main.ship.angular_velocity = Vector3.ZERO
	return v


# --- the shot on screen --------------------------------------------------------------------------------------------------------


func test_the_intro_plays_on_the_cinematic_camera_with_the_hud_hidden_and_the_letterbox_in() -> void:
	await _make_main()
	assert_true(_rig().is_playing_shot(), "the first step plays the intro")
	assert_eq(_rig().playing_shot().id, &"intro")
	assert_eq(_rig().mode, CameraRig.Mode.CINEMATIC)
	assert_eq(CameraRig.mode_name(_rig().mode), &"cinematic")
	assert_eq(_rig().active_camera(), _rig().cinematic_camera)
	assert_eq(get_viewport().get_camera_3d(), _rig().cinematic_camera, "the cinematic camera is current")
	assert_false(main.hud.visible, "the HUD hides")
	assert_almost_eq(_rig().cinematic_camera.fov, 55.0, 1.0, "the first key's field of view")
	var to_ship: Vector3 = main.ship.global_position - _rig().cinematic_camera.global_position
	assert_gt((-_rig().cinematic_camera.global_basis.z).dot(to_ship.normalized()), 0.99, "framed on the player")
	assert_true(main.letterbox.shown)
	assert_true(await _until(func() -> bool: return main.letterbox.amount >= 1.0, 120), "the bars slide fully in")
	assert_almost_eq(main.letterbox.bar_height_px(), get_viewport().get_visible_rect().size.y * Letterbox.BAR_FRACTION, 0.5)
	assert_true(main.mission.comms.visible, "the subtitles stay")
	assert_gt(main.mission.comms.layer, main.letterbox.layer, "a line shows over the bottom bar")


func test_the_shot_ends_by_itself_and_hands_the_camera_back() -> void:
	await _make_main()
	var finished: Array[StringName] = []
	_rig().shot_finished.connect(func(id: StringName) -> void: finished.append(id))
	_rig().set_mode(CameraRig.Mode.COCKPIT)
	assert_eq(_rig().mode, CameraRig.Mode.CINEMATIC, "a mode asked for during a shot waits for its end")
	assert_true(await _until(func() -> bool: return not _rig().is_playing_shot(), int(SHOT_S * 60.0) + 60))
	assert_almost_eq(_api().time_s(), SHOT_S, 0.1, "the shot lasted its keys")
	assert_eq(finished, [&"intro"] as Array[StringName])
	assert_eq(_rig().mode, CameraRig.Mode.COCKPIT, "back to the mode asked for")
	assert_true(main.hud.visible)
	await _ticks(1)
	assert_eq(_api().step_name(), &"fly", "the script moved on")


# --- commands ----------------------------------------------------------------------------------------------------------------


func test_the_player_commands_are_zeroed_and_the_ship_keeps_its_physics() -> void:
	await _make_main()
	var assist: bool = main.ship.assist_on
	var v: Vector3 = _set_drift()
	var start: Vector3 = main.ship.global_position
	for action: StringName in [InputAdapter.MAIN_LEFT, InputAdapter.MAIN_RIGHT, InputAdapter.PITCH_UP, InputAdapter.STRAFE_UP,
			InputAdapter.BRAKE]:
		source.hold(action)
	await _ticks(30)
	assert_true(_rig().is_playing_shot())
	assert_almost_eq(main.ship.linear_velocity, v, Vector3.ONE * 0.01, "no thrust and no brake: the ship drifts on")
	assert_almost_eq(main.ship.angular_velocity, Vector3.ZERO, Vector3.ONE * 1e-3, "no turn")
	assert_almost_eq(main.ship.global_position, start + v * 0.5, Vector3.ONE * 0.5, "half a second of drift")
	assert_eq(main.ship.assist_on, assist, "assist stays as set")


func test_a_held_from_before_the_shot_neither_skips_it_nor_fires() -> void:
	source.hold(InputAdapter.FIRE)
	await _make_main()
	await _ticks(30)
	assert_true(_rig().is_playing_shot(), "the trigger finger from before is not a skip")
	assert_eq(shots_fired, 0, "the guns are held")


func test_a_fresh_press_of_a_skips_the_shot_and_does_not_fire() -> void:
	await _make_main()
	await _ticks(5)
	source.hold(InputAdapter.FIRE)
	await _ticks(2)
	_assert_free_camera()
	assert_true(_api().journal.has("cinematic intro"))
	await _ticks(1)
	assert_eq(_api().step_name(), &"fly", "the script moved on")
	await _ticks(20)
	assert_eq(shots_fired, 0, "the A that skipped does not fire while held")
	source.release(InputAdapter.FIRE)
	await _ticks(2)
	source.hold(InputAdapter.FIRE)
	assert_true(await _until(func() -> bool: return shots_fired > 0, 60), "a new press fires")


func test_start_skips_the_shot_and_the_pause_menu_stays_shut() -> void:
	await _make_main()
	await _ticks(5)
	await _press(InputAdapter.PAUSE)
	_assert_free_camera()
	assert_false(main.pause_menu.is_open(), "Start skipped; it did not pause")
	assert_false(get_tree().paused)
	await _press(InputAdapter.PAUSE)
	assert_true(main.pause_menu.is_open(), "with no shot Start pauses again")


func test_mission_skip_cuts_the_shot() -> void:
	await _make_main()
	var result: ConsoleResult = DebugConsole.registry.execute("mission skip")[0]
	assert_true(result.ok, result.error)
	_assert_free_camera()
	assert_eq(_api().step_name(), &"fly")


func test_lock_controls_alone_zeroes_the_commands_without_the_camera() -> void:
	await _make_main()
	DebugConsole.registry.execute("mission skip")
	_api().lock_controls(true)
	assert_true(main.controls_locked())
	var v: Vector3 = _set_drift()
	source.hold(InputAdapter.MAIN_LEFT)
	source.hold(InputAdapter.MAIN_RIGHT)
	await _ticks(20)
	assert_almost_eq(main.ship.linear_velocity, v, Vector3.ONE * 0.01, "held: no thrust")
	assert_eq(_rig().mode, CameraRig.Mode.CHASE, "no camera change")
	assert_true(main.hud.visible, "the HUD stays")
	assert_false(main.letterbox.shown)
	_api().lock_controls(false)
	await _ticks(20)
	assert_gt(main.ship.linear_velocity.distance_to(v), 1.0, "free again: the pods push")
	source.release_all()
	_api().lock_controls(true)
	await _press(InputAdapter.PAUSE)
	assert_true(main.pause_menu.is_open(), "Start still opens the pause menu under the lock alone")


func test_the_comms_menu_closes_and_waits_while_the_controls_are_held() -> void:
	await _make_main()
	await _press(InputAdapter.COMMS_MENU)
	assert_false(main.comms_menu.is_open(), "no comms menu over a shot")
	DebugConsole.registry.execute("mission skip")
	await _press(InputAdapter.COMMS_MENU)
	assert_true(main.comms_menu.is_open(), "it opens with the controls free")
	_api().lock_controls(true)
	await _ticks(1)
	assert_false(main.comms_menu.is_open(), "locking the controls closes it")
	assert_false(main.adapter.comms_open, "and the D-pad is the D-pad again")
	await _press(InputAdapter.COMMS_MENU)
	assert_false(main.comms_menu.is_open(), "and it stays shut")


# --- rebase --------------------------------------------------------------------------------------------------------------------


func test_a_rebase_mid_shot_moves_nothing_on_screen() -> void:
	await _make_main()
	await _ticks(30)
	assert_true(_rig().is_playing_shot())
	var cam: Camera3D = _rig().cinematic_camera
	var buoy: NavBuoy = main.buoys[0]
	_rig().update_cinematic(1.0)
	var uni_before: UniversePos = main.world.to_universe(cam.global_position)
	var ship_px: Vector2 = cam.unproject_position(main.ship.global_position)
	var buoy_px: Vector2 = cam.unproject_position(buoy.global_position)
	var basis_before: Basis = cam.global_basis
	var offset := Vector3(3000.0, -500.0, 1200.0)
	main.world.rebase(offset)
	for stage: String in ["shifted with the world", "placed again from the shot"]:
		if stage != "shifted with the world":
			_rig().update_cinematic(1.0)
		var uni_after: UniversePos = main.world.to_universe(cam.global_position)
		assert_lt(uni_before.distance_to(uni_after), 0.01, "%s: the camera's universe position" % stage)
		assert_almost_eq(cam.global_basis.z, basis_before.z, Vector3.ONE * 1e-4, "%s: its aim" % stage)
		assert_almost_eq(cam.unproject_position(main.ship.global_position), ship_px, Vector2.ONE * 0.05, "%s: the ship" % stage)
		assert_almost_eq(cam.unproject_position(buoy.global_position), buoy_px, Vector2.ONE * 0.05, "%s: the buoy" % stage)


func test_the_camera_path_runs_smoothly_through_a_rebase() -> void:
	await _make_main()
	await _ticks(20)
	var cam: Camera3D = _rig().cinematic_camera
	var path: Array[UniversePos] = []
	for i: int in 40:
		if i == 20:
			main.world.rebase(Vector3(-2500.0, 800.0, 4000.0))  # between frames, as the console does
		await get_tree().process_frame
		path.append(main.world.to_universe(cam.global_position))
	assert_true(_rig().is_playing_shot(), "still mid-shot")
	var steps: Array[float] = []
	for i: int in range(1, path.size()):
		steps.append(path[i - 1].distance_to(path[i]))
	var before_max: float = 0.0
	for i: int in range(0, 18):
		before_max = maxf(before_max, steps[i])
	for i: int in range(18, steps.size()):
		assert_lt(steps[i], before_max * 2.0 + 0.5, "frame %d: no jump (%.2f m against %.2f m before)" % [i, steps[i], before_max])


# --- settings and modes --------------------------------------------------------------------------------------------------------


func test_the_cinematic_camera_comes_only_with_a_shot() -> void:
	assert_eq((SettingsSchema.ENTRIES[&"camera_default"] as Dictionary)["choices"], [&"chase", &"cockpit"],
			"the start camera is chase or cockpit only")
	assert_eq(CameraRig.mode_from_name(&"cinematic"), CameraRig.Mode.CHASE)
	await _make_main()
	DebugConsole.registry.execute("mission skip")
	_rig().set_mode(CameraRig.Mode.CINEMATIC)
	assert_eq(_rig().mode, CameraRig.Mode.CHASE, "no shot, no cinematic camera")
	assert_eq(String(DebugConsole.registry.execute("camera")[0].lines[0]).contains("cockpit"), true, "the toggle is unchanged")
