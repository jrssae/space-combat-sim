extends GutTest
## CameraRig with plain nodes standing in for the ship (architecture §3, §8; AC10 camera part). The Ship class does
## not exist yet, so `setup` takes a Node3D body, a Marker3D anchor, the chase offset and a visibility callable.
## What the cameras look like on screen is (H); this checks the wiring, the numbers and the console.

const SCENE_PATH: String = "res://src/camera/camera_rig.tscn"
const CHASE_OFFSET: Vector3 = Vector3(0.0, 2.5, 9.0)
const ANCHOR_LOCAL: Vector3 = Vector3(0.0, 0.7, -3.0)
const TOL: float = 1e-3

var world: Node3D
var ship: Node3D
var anchor: Marker3D
var rig: CameraRig
var interior_calls: Array[bool] = []
var _camera_default_backup: Variant


func before_each() -> void:
	_camera_default_backup = Settings.get_value(&"camera_default")
	Settings.set_value(&"camera_default", &"chase")
	interior_calls.clear()
	world = Node3D.new()
	world.name = "WorldStandIn"
	add_child_autofree(world)
	ship = Node3D.new()
	ship.name = "Ship"
	# Teleporting the stand-in must show up at once, not blended by physics interpolation.
	ship.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	world.add_child(ship)
	anchor = Marker3D.new()
	anchor.name = "CockpitAnchor"
	anchor.position = ANCHOR_LOCAL
	ship.add_child(anchor)


func after_each() -> void:
	Settings.set_value(&"camera_default", _camera_default_backup)


func _make_rig(parent: Node = null) -> CameraRig:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	assert_not_null(packed, "scene loads")
	var made: CameraRig = packed.instantiate() as CameraRig
	assert_not_null(made, "root script is CameraRig")
	(parent if parent != null else world).add_child(made)
	return made


func _on_interior(shown: bool) -> void:
	interior_calls.append(shown)


func _make_wired_rig() -> CameraRig:
	var made: CameraRig = _make_rig()
	made.setup(ship, anchor, CHASE_OFFSET, _on_interior)
	return made


func _vec_tol(tol: float = TOL) -> Vector3:
	return Vector3(tol, tol, tol)


func _remote_under_anchor() -> RemoteTransform3D:
	for child: Node in anchor.get_children():
		if child is RemoteTransform3D:
			return child as RemoteTransform3D
	return null


func _console(line: String) -> ConsoleResult:
	var results: Array[ConsoleResult] = DebugConsole.registry.execute(line)
	assert_eq(results.size(), 1, "one statement: " + line)
	return results[0]


# --- scene ---------------------------------------------------------------------------------------------------


func test_scene_has_two_cameras_with_the_design_lens_values() -> void:
	rig = _make_rig()
	assert_not_null(rig.cockpit_camera)
	assert_not_null(rig.chase_camera)
	assert_eq(rig.cockpit_camera.name, &"CockpitCamera")
	assert_eq(rig.chase_camera.name, &"ChaseCamera")
	assert_eq(rig.cockpit_camera.fov, 75.0)
	assert_eq(rig.chase_camera.fov, 70.0)
	for camera: Camera3D in [rig.cockpit_camera, rig.chase_camera]:
		assert_almost_eq(camera.near, 0.05, 1e-6, "%s near" % camera.name)
		assert_eq(camera.far, 50000.0, "%s far" % camera.name)


func test_chase_camera_is_top_level_and_shiftable_the_cockpit_camera_is_not() -> void:
	rig = _make_rig()
	assert_true(rig.chase_camera.top_level, "top_level: it does not follow the rig")
	assert_true(rig.chase_camera.is_in_group(WorldFrame.SHIFTABLE_GROUP), "rebase moves it")
	assert_false(rig.cockpit_camera.top_level)
	assert_false(rig.cockpit_camera.is_in_group(WorldFrame.SHIFTABLE_GROUP), "the anchor drives it, not the rebase")
	assert_eq(rig.chase_camera.physics_interpolation_mode, Node.PHYSICS_INTERPOLATION_MODE_OFF,
			"smoothed in _process, so physics interpolation must not touch it")


# --- mode and settings ---------------------------------------------------------------------------------------


func test_default_mode_comes_from_settings_chase() -> void:
	Settings.set_value(&"camera_default", &"chase")
	rig = _make_rig()
	assert_eq(rig.mode, CameraRig.Mode.CHASE)
	assert_true(rig.chase_camera.current)
	assert_false(rig.cockpit_camera.current)


func test_default_mode_comes_from_settings_cockpit() -> void:
	Settings.set_value(&"camera_default", &"cockpit")
	rig = _make_rig()
	assert_eq(rig.mode, CameraRig.Mode.COCKPIT)
	assert_true(rig.cockpit_camera.current)
	assert_false(rig.chase_camera.current)


func test_toggle_flips_current_and_calls_the_interior_callable() -> void:
	rig = _make_wired_rig()
	assert_eq(interior_calls, [false], "setup syncs the interior with the starting (chase) mode once")
	watch_signals(rig)

	rig.toggle()
	assert_eq(rig.mode, CameraRig.Mode.COCKPIT)
	assert_true(rig.cockpit_camera.current, "cockpit camera is current")
	assert_false(rig.chase_camera.current)
	assert_eq(interior_calls, [false, true], "interior shown in the cockpit")
	assert_signal_emit_count(rig, "mode_changed", 1)
	assert_signal_emitted_with_parameters(rig, "mode_changed", [CameraRig.Mode.COCKPIT])
	assert_eq(rig.active_camera(), rig.cockpit_camera)

	rig.toggle()
	assert_eq(rig.mode, CameraRig.Mode.CHASE)
	assert_true(rig.chase_camera.current, "chase camera is current again")
	assert_false(rig.cockpit_camera.current)
	assert_eq(interior_calls, [false, true, false], "interior hidden in chase")
	assert_signal_emit_count(rig, "mode_changed", 2)
	assert_eq(rig.active_camera(), rig.chase_camera)


func test_set_mode_to_the_active_mode_does_nothing() -> void:
	rig = _make_wired_rig()
	watch_signals(rig)
	rig.set_mode(CameraRig.Mode.CHASE)
	assert_signal_not_emitted(rig, "mode_changed")
	assert_eq(interior_calls, [false], "no extra callable call")
	rig.set_mode(CameraRig.Mode.COCKPIT)
	rig.set_mode(CameraRig.Mode.COCKPIT)
	assert_signal_emit_count(rig, "mode_changed", 1)
	assert_eq(interior_calls, [false, true])


func test_mode_property_assignment_goes_through_set_mode() -> void:
	rig = _make_wired_rig()
	rig.mode = CameraRig.Mode.COCKPIT
	assert_true(rig.cockpit_camera.current)
	assert_eq(interior_calls, [false, true])


func test_toggle_and_set_mode_work_before_setup() -> void:
	rig = _make_rig()
	rig.toggle()
	assert_eq(rig.mode, CameraRig.Mode.COCKPIT)
	assert_true(rig.cockpit_camera.current)
	rig.update_chase(0.016)  # no target yet: nothing to follow, nothing to crash
	rig.snap_chase()


func test_setup_with_cockpit_default_shows_the_interior() -> void:
	Settings.set_value(&"camera_default", &"cockpit")
	rig = _make_wired_rig()
	assert_eq(interior_calls, [true])


func test_an_invalid_callable_is_skipped() -> void:
	rig = _make_rig()
	rig.setup(ship, anchor, CHASE_OFFSET, Callable())
	rig.toggle()
	assert_eq(rig.mode, CameraRig.Mode.COCKPIT, "toggling still works without a callback")


func test_mode_name_round_trip() -> void:
	assert_eq(CameraRig.mode_name(CameraRig.Mode.COCKPIT), &"cockpit")
	assert_eq(CameraRig.mode_name(CameraRig.Mode.CHASE), &"chase")
	assert_eq(CameraRig.mode_from_name(&"cockpit"), CameraRig.Mode.COCKPIT)
	assert_eq(CameraRig.mode_from_name(&"chase"), CameraRig.Mode.CHASE)
	assert_eq(CameraRig.mode_from_name(&"orbit"), CameraRig.Mode.CHASE, "unknown falls back to chase")


# --- cockpit camera ------------------------------------------------------------------------------------------


func test_setup_adds_a_remote_transform_under_the_anchor_pointing_at_the_cockpit_camera() -> void:
	rig = _make_wired_rig()
	var remote: RemoteTransform3D = _remote_under_anchor()
	assert_not_null(remote, "RemoteTransform3D under CockpitAnchor")
	if remote == null:
		return
	assert_eq(remote.get_node_or_null(remote.remote_path), rig.cockpit_camera, "remote_path resolves to the camera")
	assert_true(remote.use_global_coordinates)
	assert_false(remote.update_scale, "only the pose is pushed")
	assert_almost_eq(rig.cockpit_camera.global_position, anchor.global_position, _vec_tol(), "placed at setup")


func test_cockpit_camera_follows_the_anchor_as_the_ship_moves() -> void:
	rig = _make_wired_rig()
	ship.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(35.0)), Vector3(120.0, -4.0, 60.0))
	await get_tree().process_frame
	await get_tree().process_frame
	assert_almost_eq(rig.cockpit_camera.global_position, anchor.global_position, _vec_tol(), "position follows")
	assert_almost_eq(rig.cockpit_camera.global_transform.basis.z, anchor.global_transform.basis.z, _vec_tol(),
			"orientation follows")


func test_calling_setup_again_replaces_the_remote() -> void:
	rig = _make_wired_rig()
	rig.setup(ship, anchor, CHASE_OFFSET, _on_interior)
	await get_tree().process_frame
	var remotes: int = 0
	for child: Node in anchor.get_children():
		if child is RemoteTransform3D:
			remotes += 1
	assert_eq(remotes, 1, "one remote after a second setup")


func test_setup_before_the_rig_is_in_the_tree_is_an_error_not_a_crash() -> void:
	var loose: CameraRig = (load(SCENE_PATH) as PackedScene).instantiate() as CameraRig
	autofree(loose)
	loose.setup(ship, anchor, CHASE_OFFSET, _on_interior)
	assert_push_error("must be in the scene tree")
	assert_null(_remote_under_anchor(), "nothing was wired")


# --- chase camera --------------------------------------------------------------------------------------------


func test_setup_snaps_the_chase_camera_behind_and_above_the_ship() -> void:
	ship.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3(100.0, 5.0, -20.0))
	rig = _make_wired_rig()
	var offset: Vector3 = rig.chase_camera.global_position - ship.global_position
	assert_almost_eq(offset, ship.global_transform.basis * CHASE_OFFSET, _vec_tol(), "ship-local (0, 2.5, 9)")
	assert_gt(offset.dot(ship.global_transform.basis.z), 8.9, "behind")
	assert_gt(offset.dot(ship.global_transform.basis.y), 2.4, "above")
	assert_eq(rig.chase_config.offset_local, CHASE_OFFSET, "the hardpoints' chase_anchor became the offset")


func test_chase_camera_eases_toward_the_ship_and_converges_behind_and_above() -> void:
	rig = _make_wired_rig()
	var turned := Transform3D(Basis(Vector3.UP, deg_to_rad(-60.0)) * Basis(Vector3.RIGHT, deg_to_rad(15.0)),
			Vector3(-200.0, 30.0, -500.0))
	ship.global_transform = turned
	var before: Vector3 = rig.chase_camera.global_position

	rig.update_chase(1.0 / 60.0)
	var goal: Transform3D = ChaseCameraMath.target_pose(turned, rig.chase_config)
	var after_one: float = rig.chase_camera.global_position.distance_to(goal.origin)
	assert_lt(after_one, before.distance_to(goal.origin), "moved toward the ship")
	assert_gt(after_one, 100.0, "but only part of the way: it is smoothed, not snapped")

	for i: int in 400:
		rig.update_chase(1.0 / 60.0)
	assert_almost_eq(rig.chase_camera.global_position, goal.origin, _vec_tol(), "converged on the goal position")
	var local: Vector3 = turned.affine_inverse() * rig.chase_camera.global_position
	assert_almost_eq(local, CHASE_OFFSET, _vec_tol(), "in the ship's frame the camera is at (0, 2.5, 9)")
	assert_gt(local.z, 0.0, "behind (ship forward is -Z)")
	assert_gt(local.y, 0.0, "above")
	var forward: Vector3 = -rig.chase_camera.global_transform.basis.z
	assert_gt(forward.dot(-turned.basis.z), 0.99, "looks the way the ship points")


func test_chase_camera_is_smoothed_in_process_without_manual_steps() -> void:
	rig = _make_wired_rig()
	ship.global_position = Vector3(0.0, 0.0, -300.0)
	var goal_z: float = ship.global_position.z + CHASE_OFFSET.z
	var start_gap: float = absf(rig.chase_camera.global_position.z - goal_z)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var gap: float = absf(rig.chase_camera.global_position.z - goal_z)
	assert_lt(gap, start_gap, "_process moved the chase camera toward the new goal")


func test_chase_camera_keeps_following_while_the_cockpit_is_active() -> void:
	rig = _make_wired_rig()
	rig.toggle()
	ship.global_position = Vector3(50.0, 0.0, 0.0)
	for i: int in 400:
		rig.update_chase(1.0 / 60.0)
	rig.toggle()
	assert_almost_eq(rig.chase_camera.global_position, Vector3(50.0, 2.5, 9.0), _vec_tol(),
			"switching back finds the chase camera in place, with no sweep from a stale pose")


func test_snap_chase_jumps_to_the_goal_after_a_teleport() -> void:
	rig = _make_wired_rig()
	ship.global_position = Vector3(5000.0, 0.0, 0.0)
	rig.snap_chase()
	assert_almost_eq(rig.chase_camera.global_position, Vector3(5000.0, 2.5, 9.0), _vec_tol())


func test_chase_camera_survives_the_target_being_freed() -> void:
	rig = _make_wired_rig()
	ship.free()
	rig.update_chase(1.0 / 60.0)
	rig.snap_chase()
	assert_true(is_instance_valid(rig.chase_camera), "no crash, camera stays where it was")


# --- world rebase --------------------------------------------------------------------------------------------


func test_world_rebase_keeps_the_chase_camera_with_the_ship() -> void:
	var frame := WorldFrame.new()
	frame.name = "World"
	add_child_autofree(frame)
	var body := Node3D.new()
	body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var marker := Marker3D.new()
	body.add_child(marker)
	frame.spawn(body, UniversePos.new(100.0, 0.0, 40.0), Basis(Vector3.UP, deg_to_rad(25.0)))
	rig = _make_rig(frame)
	rig.setup(body, marker, CHASE_OFFSET, _on_interior)
	for i: int in 30:
		rig.update_chase(1.0 / 60.0)
	var relative_before: Vector3 = rig.chase_camera.global_position - body.global_position
	var rotation_before: Basis = rig.chase_camera.global_transform.basis

	frame.rebase(body.global_position)  # re-centre on the ship, as the automatic rebase would
	assert_almost_eq(rig.chase_camera.global_position - body.global_position, relative_before, _vec_tol(1e-3),
			"the camera moved with the ship")
	assert_lt(body.global_position.length(), 1e-3, "the ship is at the new origin")
	assert_lt(rig.chase_camera.global_position.length(), 20.0, "and the camera is still right behind it")

	rig.update_chase(1.0 / 60.0)
	assert_almost_eq(rig.chase_camera.global_position - body.global_position, relative_before, _vec_tol(1e-3),
			"the next smoothing step does not jump (nothing stale was cached)")
	assert_almost_eq(rig.chase_camera.global_transform.basis.z, rotation_before.z, _vec_tol(1e-3), "same heading")


# --- console -------------------------------------------------------------------------------------------------


func test_console_provider_and_command_are_registered() -> void:
	rig = _make_wired_rig()
	assert_not_null(DebugConsole.registry.get_provider(&"camera"), "camera provider")
	assert_true(DebugConsole.registry.has_command(&"camera"), "camera command")
	var provider: ConsoleStateProvider = DebugConsole.registry.get_provider(&"camera")
	assert_eq(Array(provider.keys()), [&"mode", &"fov"])
	assert_true(provider.is_writable(&"mode"))
	assert_false(provider.is_writable(&"fov"))


func test_console_camera_command_sets_the_mode() -> void:
	rig = _make_wired_rig()
	var result: ConsoleResult = _console("camera cockpit")
	assert_true(result.ok, result.text())
	assert_eq(result.lines, PackedStringArray(["camera.mode = cockpit"]))
	assert_eq(rig.mode, CameraRig.Mode.COCKPIT)
	assert_true(rig.cockpit_camera.current)
	assert_eq(interior_calls, [false, true])

	result = _console("camera chase")
	assert_true(result.ok, result.text())
	assert_eq(result.lines, PackedStringArray(["camera.mode = chase"]))
	assert_eq(rig.mode, CameraRig.Mode.CHASE)
	assert_eq(interior_calls, [false, true, false])


func test_console_camera_command_without_an_argument_toggles() -> void:
	rig = _make_wired_rig()
	assert_eq(_console("camera").lines, PackedStringArray(["camera.mode = cockpit"]))
	assert_eq(rig.mode, CameraRig.Mode.COCKPIT)
	assert_eq(_console("camera").lines, PackedStringArray(["camera.mode = chase"]))
	assert_eq(rig.mode, CameraRig.Mode.CHASE)


func test_console_camera_command_rejects_an_unknown_mode() -> void:
	rig = _make_wired_rig()
	var result: ConsoleResult = _console("camera orbit")
	assert_false(result.ok)
	assert_string_contains(result.error, "cockpit|chase")
	assert_eq(rig.mode, CameraRig.Mode.CHASE, "unchanged")


func test_console_mode_is_writable_through_set_and_readable_through_get() -> void:
	rig = _make_wired_rig()
	assert_eq(_console("get camera.mode").lines, PackedStringArray(["camera.mode = chase"]))
	var result: ConsoleResult = _console("set camera.mode cockpit")
	assert_true(result.ok, result.text())
	assert_eq(rig.mode, CameraRig.Mode.COCKPIT)
	assert_eq(_console("get camera.mode").lines, PackedStringArray(["camera.mode = cockpit"]))
	result = _console("set camera.mode orbit")
	assert_false(result.ok, "only cockpit or chase")
	assert_eq(rig.mode, CameraRig.Mode.COCKPIT)


func test_console_fov_reports_the_active_camera_and_is_read_only() -> void:
	rig = _make_wired_rig()
	assert_eq(_console("get camera.fov").lines, PackedStringArray(["camera.fov = 70.00 deg"]))
	rig.toggle()
	assert_eq(_console("get camera.fov").lines, PackedStringArray(["camera.fov = 75.00 deg"]))
	var result: ConsoleResult = _console("set camera.fov 90")
	assert_false(result.ok)
	assert_string_contains(result.error, "read-only")
	assert_eq(rig.cockpit_camera.fov, 75.0, "unchanged")


func test_console_state_lists_the_camera_provider() -> void:
	rig = _make_wired_rig()
	var text: String = _console("state camera").text()
	assert_string_contains(text, "camera.mode = chase")
	assert_string_contains(text, "camera.fov = 70.00 deg")


func test_console_entries_leave_with_the_rig() -> void:
	rig = _make_wired_rig()
	world.remove_child(rig)
	assert_null(DebugConsole.registry.get_provider(&"camera"), "provider unregistered on exit")
	assert_false(DebugConsole.registry.has_command(&"camera"), "command unregistered on exit")
	rig.free()
	rig = null
