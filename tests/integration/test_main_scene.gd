extends GutTest
## AC10: the real main scene runs headless, spawns the scenario, and reacts to pilot input end to end.

var main: Main
var source: FakeInputSource


func before_each() -> void:
	get_tree().paused = false
	source = FakeInputSource.new()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	add_child_autofree(main)
	await _ticks(2)


func after_each() -> void:
	get_tree().paused = false


func test_runs_180_physics_frames_and_spawns_the_scenario() -> void:
	await _ticks(180)
	assert_not_null(main.ship)
	assert_true(main.ship.is_inside_tree())
	assert_eq(main.buoys.size(), 5, "five nav buoys from free_flight.json")
	for buoy: NavBuoy in main.buoys:
		assert_eq(buoy.get_parent(), main.targets)
		assert_true(buoy.is_in_group(WorldFrame.SHIFTABLE_GROUP))
	assert_almost_eq(main.ship.linear_velocity.length(), 0.0, 1e-4, "no input, no motion")
	assert_eq(main.thrusters.glow_count(), main.ship.get_layout().nozzle_count() + main.ship.get_layout().rcs_nozzles.size())


func test_camera_toggle_flips_current_and_cockpit_interior() -> void:
	assert_eq(main.camera_rig.mode, CameraRig.Mode.CHASE, "Settings.camera_default is chase")
	assert_false(main.ship.is_cockpit_interior_visible())
	await _tap(InputAdapter.TOGGLE_CAMERA)
	assert_eq(main.camera_rig.mode, CameraRig.Mode.COCKPIT)
	assert_true(main.camera_rig.cockpit_camera.current)
	assert_true(main.ship.is_cockpit_interior_visible())
	await _tap(InputAdapter.TOGGLE_CAMERA)
	assert_eq(main.camera_rig.mode, CameraRig.Mode.CHASE)
	assert_true(main.camera_rig.chase_camera.current)
	assert_false(main.ship.is_cockpit_interior_visible())


func test_target_next_selects_the_nearest_buoy() -> void:
	await _tap(InputAdapter.TARGET_NEXT)
	assert_eq(main.ship.targeting.selected_name(), "NAV ALPHA")
	var snap: Dictionary = main.snapshot()
	assert_eq(snap["target_name"], "NAV ALPHA")
	assert_almost_eq(float(snap["target_range_m"]), 500.0, 5.0)


func test_triggers_fly_the_ship() -> void:
	source.hold(InputAdapter.MAIN_LEFT, 1.0)
	source.hold(InputAdapter.MAIN_RIGHT, 1.0)
	await _ticks(30)
	source.release_all()
	await _ticks(2)
	assert_lt(main.ship.body_velocity().z, -1.0, "both mains push the ship forward (-Z)")


func test_fire_spawns_projectiles() -> void:
	source.hold(InputAdapter.FIRE)
	await _ticks(20)
	source.release_all()
	assert_gt(main.projectiles.get_child_count(), 0)


func test_pause_toggles_and_freezes_the_world() -> void:
	await _tap(InputAdapter.PAUSE)
	assert_true(get_tree().paused)
	var t: float = SimClock.now()
	await _ticks(10)
	assert_eq(SimClock.now(), t, "sim time stops while paused")
	await _tap(InputAdapter.PAUSE)
	assert_false(get_tree().paused, "Main still reads input while paused, so Start unpauses")


func test_respawn_returns_to_start_at_rest() -> void:
	main.ship.linear_velocity = Vector3(0.0, 0.0, -50.0)
	await _ticks(30)
	await _tap(InputAdapter.RESET_SHIP)
	await _ticks(2)
	assert_almost_eq(main.ship.linear_velocity.length(), 0.0, 1e-3)
	assert_almost_eq(main.ship.position.length(), 0.0, 0.5)


func test_overlay_toggle_and_snapshot() -> void:
	var shown: bool = bool(Settings.get_value(&"show_overlay"))
	await _tap(InputAdapter.TOGGLE_OVERLAY)
	assert_eq(bool(Settings.get_value(&"show_overlay")), not shown)
	assert_eq(main.overlay.visible, not shown)
	Settings.set_value(&"show_overlay", shown)
	var snap: Dictionary = main.snapshot()
	for key: String in ["speed_mps", "assist_on", "camera_mode", "weapon_mode", "splat_backend", "universe_position"]:
		assert_true(snap.has(key), key)
	assert_eq(snap["splat_backend"], "headless")


func test_console_commands() -> void:
	DebugConsole.registry.execute("pause on")
	assert_true(get_tree().paused)
	DebugConsole.registry.execute("pause off")
	assert_false(get_tree().paused)
	main.ship.linear_velocity = Vector3(5.0, 0.0, 0.0)
	DebugConsole.registry.execute("respawn")
	await _ticks(2)
	assert_almost_eq(main.ship.linear_velocity.length(), 0.0, 1e-3)


# Physics ticks that keep counting while the tree is paused.
func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _tap(action: StringName) -> void:
	source.hold(action)
	await _ticks(2)
	source.release(action)
	await _ticks(2)


func test_rebase_keeps_flying() -> void:
	main.ship.linear_velocity = Vector3(0.0, 0.0, -30.0)
	await _ticks(10)
	var before: UniversePos = main.world.to_universe(main.ship.position)
	DebugConsole.registry.execute("rebase 5000 0 0")
	await _ticks(1)
	var after: UniversePos = main.world.to_universe(main.ship.position)
	assert_almost_eq(after.distance_to(before), 30.0 / 60.0, 0.05, "one tick of motion, no jump in universe space")
	assert_almost_eq(main.ship.linear_velocity.z, -30.0, 1e-3)
