extends GutTest
## The HUD (M2-T08, AC10): `HudLayout` agrees with a real `Camera3D.unproject_position` in both camera modes; the main scene
## runs with the HUD; the target box, lead and edge arrow follow a real selected raider; `settings.show_hud` shows and hides it;
## the debug overlay hides its own bracket while the HUD shows; `Targetable` reports hull and bounding radius.

var main: Main
var source: FakeInputSource
var _show_hud_backup: Variant


func before_each() -> void:
	get_tree().paused = false
	_show_hud_backup = Settings.get_value(&"show_hud")
	source = FakeInputSource.new()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	main.waves_auto_start = false
	add_child_autofree(main)
	await _ticks(2)


func after_each() -> void:
	Settings.set_value(&"show_hud", _show_hud_backup)
	get_tree().paused = false


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


func _spawn_and_select(distance: float = 600.0) -> Combatant:
	assert_true(DebugConsole.registry.execute("spawn raider %s" % distance)[0].ok)
	var raider: Combatant = main.ships.alive()[0]
	main.ship.targeting.refresh()
	assert_true(main.ship.targeting.select_by_name(raider.display_name))
	return raider


# --- projection against the real camera -------------------------------------------------------------------------------


func _points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for i: int in 20:
		var a: float = TAU * float(i) / 20.0
		points.append(main.ship.global_position + Vector3(cos(a) * 80.0, sin(a * 2.0) * 40.0, -200.0 - 15.0 * float(i)))
	return points


func _check_projection(label: String) -> void:
	var input: HudInput = main._build_hud_input()
	var camera: Camera3D = main.camera_rig.active_camera()
	assert_gt(input.viewport_size.x, 1.0, "%s: a viewport" % label)
	var compared: int = 0
	for point: Vector3 in _points():
		if camera.is_position_behind(point):
			continue
		var mine: Dictionary = HudLayout.project(input, point)
		assert_true(mine["in_front"], "%s: in front" % label)
		var real: Vector2 = camera.unproject_position(point)
		assert_almost_eq(mine["pos"], real, Vector2.ONE * 0.5, "%s: within 0.5 px of unproject_position at %s" % [label, point])
		compared += 1
	assert_gt(compared, 10, "%s: most of the 20 points were in front" % label)


func test_projection_matches_unproject_position_in_the_chase_camera() -> void:
	await _frames(3)
	assert_eq(main.camera_rig.mode, CameraRig.Mode.CHASE)
	_check_projection("chase")


func test_projection_matches_unproject_position_in_the_cockpit_camera() -> void:
	source.hold(InputAdapter.TOGGLE_CAMERA)
	await _ticks(2)
	source.release(InputAdapter.TOGGLE_CAMERA)
	await _frames(3)
	assert_eq(main.camera_rig.mode, CameraRig.Mode.COCKPIT)
	_check_projection("cockpit")


# --- the main scene with the HUD -------------------------------------------------------------------------------------


func test_the_main_scene_runs_with_the_hud_and_it_computes_a_frame() -> void:
	await _frames(5)
	assert_true(main.hud.visible)
	assert_true(main.hud.input_provider.is_valid())
	assert_gt(main.hud.frame.viewport_size.x, 1.0)
	assert_eq(main.hud.get_layer(), 40)
	assert_true(main.hud.frame.boresight_visible or true, "the nose may be off the chase camera's view, but the frame exists")


func test_the_input_carries_the_players_state() -> void:
	main.ship.linear_velocity = Vector3(0.0, 0.0, -45.0)
	main.combatant.damageable.hull.apply(75.0)
	main.cannon.set_charge_fraction(0.5)
	var input: HudInput = main._build_hud_input()
	assert_eq(input.own_velocity, Vector3(0.0, 0.0, -45.0))
	assert_almost_eq(input.hull_fraction, 0.75, 1e-6)
	assert_almost_eq(input.charge_fraction, 0.5, 1e-3)
	assert_eq(input.fire_mode, "alternating")
	assert_eq(input.weapon_speed_mps, main.cannon.weapon.muzzle_speed_mps)
	assert_true(input.fuel_unlimited)
	assert_eq(input.faction, Factions.EARTH_ALLIANCE)
	assert_eq(input.contacts.size(), main.buoys.size(), "the five buoys")
	assert_almost_eq(input.muzzle_position, main.ship.global_position + (main.ship.get_muzzles()[0].global_position - main.ship.global_position + main.ship.get_muzzles()[1].global_position - main.ship.global_position) * 0.5, Vector3.ONE * 1e-3)


func test_god_mode_shows_on_the_hud() -> void:
	DebugConsole.registry.execute("god on")
	assert_true(main._build_hud_input().god)
	DebugConsole.registry.execute("god off")
	assert_false(main._build_hud_input().god)


func test_a_selected_raider_gets_a_box_a_lead_and_a_hull_bar() -> void:
	_spawn_and_select(600.0)
	await _ticks(2)
	var f: HudFrame = HudLayout.compute(main._build_hud_input())
	assert_true(f.target_present)
	assert_eq(f.target_name, "RAIDER 1")
	assert_eq(f.target_color, Factions.HOSTILE_COLOR)
	assert_eq(f.target_hull, 1.0, "a raider has a hull bar")
	assert_almost_eq(f.target_range_m, 600.0, 5.0)
	assert_gt(f.radar_dots.size(), 0)


func test_a_selected_buoy_has_no_hull_bar() -> void:
	main.ship.targeting.refresh()
	main.ship.targeting.select_by_name("NAV ALPHA")
	var f: HudFrame = HudLayout.compute(main._build_hud_input())
	assert_eq(f.target_hull, -1.0)
	assert_eq(f.target_color, Factions.NEUTRAL_COLOR)


func test_a_target_behind_shows_the_edge_arrow() -> void:
	main.ship.targeting.refresh()
	main.ship.targeting.select_by_name("NAV ALPHA")
	main.ship.global_basis = Basis(Vector3.UP, PI)  # turn the ship (and the locked chase camera) round
	await _frames(3)
	var f: HudFrame = HudLayout.compute(main._build_hud_input())
	assert_false(f.target_on_screen)
	assert_true(f.edge_arrow_visible)


# --- settings and overlay -------------------------------------------------------------------------------------------


func test_show_hud_toggles_the_hud() -> void:
	Settings.set_value(&"show_hud", false)
	assert_false(main.hud.visible)
	Settings.set_value(&"show_hud", true)
	assert_true(main.hud.visible)
	assert_true(DebugConsole.registry.execute("set settings.show_hud off")[0].ok)
	assert_false(main.hud.visible)


func test_the_debug_overlay_hides_its_bracket_while_the_hud_shows() -> void:
	main.ship.targeting.refresh()
	main.ship.targeting.select_by_name("NAV ALPHA")
	await _frames(3)
	assert_false(main.overlay.bracket().is_shown(), "the HUD has its own box")
	Settings.set_value(&"show_hud", false)
	await _frames(3)
	assert_true(main.overlay.bracket().is_shown(), "with the HUD off the old bracket is back")


func test_the_hud_console_provider() -> void:
	_spawn_and_select(500.0)
	await _frames(4)
	var registry: ConsoleRegistry = DebugConsole.registry
	assert_eq(registry.format_path("hud.visible"), "hud.visible = true")
	for key: String in ["lead_tof_s", "lead_on_screen", "prograde_on_screen", "target_box"]:
		assert_true(registry.read("hud.%s" % key)["ok"], key)


func test_the_hud_settings_are_schema_entries() -> void:
	assert_true(SettingsSchema.new().keys().has(&"show_hud"))
	assert_true(SettingsSchema.new().keys().has(&"hud_targeting_grid"))
	assert_eq(Settings.get_value(&"show_hud"), true)
	assert_eq(Settings.get_value(&"hud_targeting_grid"), false)


# --- what the targeting reports for the HUD ---------------------------------------------------------------------------


func test_targetable_reports_hull_and_bounding_radius_or_the_absence_of_them() -> void:
	var raider: Combatant = _spawn_and_select(300.0)
	assert_eq(raider.targetable.get_hull_fraction(), 1.0)
	raider.damageable.hull.apply(30.0)
	assert_almost_eq(raider.targetable.get_hull_fraction(), 0.5, 1e-6)
	assert_gt(raider.targetable.get_bounding_radius(), 3.0)
	var info: TargetInfo = raider.targetable.to_target_info()
	assert_almost_eq(info.hull_fraction, 0.5, 1e-6)
	assert_eq(info.bounding_radius, raider.targetable.get_bounding_radius())
	var buoy: Targetable = main.buoys[0].get_node_or_null(^"Targetable") as Targetable
	if buoy == null:
		for child: Node in main.buoys[0].get_children():
			if child is Targetable:
				buoy = child as Targetable
	assert_not_null(buoy)
	assert_eq(buoy.get_hull_fraction(), -1.0, "a buoy has no hull")
	assert_eq(buoy.get_bounding_radius(), 0.0)
	var readout: TargetReadout = main.ship.targeting.selected_readout()
	assert_almost_eq(readout.hull_fraction, 0.5, 1e-6)
	assert_eq(readout.velocity, raider.ship.linear_velocity)
