extends GutTest
## The cockpit's console screens in the real scene (M3-T29, AC40): the window draws only the aiming marks, the screens are given every other
## instrument from the same frame, the chase view is unchanged, the viewports exist once on the player's ship, draw 2D only and only for a new
## frame, and the lamps follow their states. Headless: how it looks is P13's, on the GPU.

const WINDOW_ITEMS: Array[StringName] = [HudSurface.BORESIGHT, HudSurface.VELOCITY, HudSurface.TARGET_MARKS, HudSurface.WAYPOINT]

var main: Main
var screens: CockpitScreens


func before_each() -> void:
	get_tree().paused = false
	DebugConsole.flags.invulnerable = true
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.waves_auto_start = false
	add_child_autofree(main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	screens = main.ship.cockpit_screens


func after_each() -> void:
	DebugConsole.flags.invulnerable = false
	Settings.reset(&"show_hud")


func _frames(count: int) -> void:
	for _i: int in count:
		await get_tree().process_frame


func _cockpit() -> void:
	main.camera_rig.set_mode(CameraRig.Mode.COCKPIT)
	await _frames(3)


func _chase() -> void:
	main.camera_rig.set_mode(CameraRig.Mode.CHASE)
	await _frames(3)


func _select_ally() -> void:
	main.ship.targeting.refresh()
	assert_true(main.ship.targeting.select_by_name("ALPHA 2"), "the sandbox has its wingman")


func _collect(node: Node, type: Variant, out: Array) -> Array:
	if is_instance_of(node, type):
		out.append(node)
	for child: Node in node.get_children():
		_collect(child, type, out)
	return out


# --- what goes where ---------------------------------------------------------------------------------------------------


func test_in_the_cockpit_the_window_draws_only_the_aiming_marks() -> void:
	await _cockpit()
	assert_eq(main.hud.frame.items, WINDOW_ITEMS)
	assert_eq(main.hud.painted_items(), WINDOW_ITEMS, "and that is what the 2D layer was asked to paint")
	for moved: StringName in [HudSurface.HULL_BAR, HudSurface.CHARGE_BAR, HudSurface.RADAR, HudSurface.GRID, HudSurface.SPEED, HudSurface.DRIFT,
			HudSurface.OWN_SILHOUETTE, HudSurface.TARGET_LABEL, HudSurface.ROSTER, HudSurface.STATUS, HudSurface.ACK, HudSurface.TRACKING]:
		assert_does_not_have(main.hud.painted_items(), moved)


func test_each_screen_paints_what_q29_gave_it_from_the_huds_own_frame() -> void:
	await _select_ally()
	await _cockpit()
	var frame: HudFrame = main.hud.frame
	for id: StringName in [&"octagon", &"left", &"right"]:
		var state: Dictionary = screens.screen_state(id)
		assert_eq(state["frame"], frame, "%s has this frame" % id)
		assert_eq(state["surface"], frame.screens[id])
		assert_gt(int(state["paints"]), 0, "%s was painted" % id)
		assert_eq(state["painted"], (frame.screens[id] as HudSurface).items)
	assert_has(screens.screen_state(&"octagon")["painted"], HudSurface.RADAR)
	assert_has(screens.screen_state(&"octagon")["painted"], HudSurface.GRID)
	assert_has(screens.screen_state(&"octagon")["painted"], HudSurface.TRACKING)
	assert_has(screens.screen_state(&"left")["painted"], HudSurface.HULL_BAR)
	assert_has(screens.screen_state(&"left")["painted"], HudSurface.SPEED)
	assert_has(screens.screen_state(&"right")["painted"], HudSurface.CHARGE_BAR)
	assert_has(screens.screen_state(&"right")["painted"], HudSurface.TARGET_PANEL)
	assert_has(screens.screen_state(&"right")["painted"], HudSurface.ROSTER)


func test_the_screens_read_live_numbers() -> void:
	await _select_ally()
	await _cockpit()
	main.ship.linear_velocity = Vector3(0.0, 0.0, -50.0)
	await _frames(2)
	var frame: HudFrame = screens.screen_state(&"left")["frame"]
	assert_almost_eq(frame.speed_mps, main.ship.linear_velocity.length(), 0.5)
	assert_eq(frame.fire_mode, String(PulseCannonGate.mode_name(main.cannon.gate.mode)))
	assert_eq(frame.target_name, "ALPHA 2")
	assert_eq(frame.target_relation, Factions.Relation.FRIENDLY)
	var right: HudSurface = screens.screen_state(&"right")["surface"]
	assert_eq(right.roster_rows.size(), main.wings.hud_roster().size())
	assert_false(frame.radar_dots.is_empty(), "contacts reach the octagon")


func test_a_downed_wingman_reads_red_on_the_right_screen() -> void:
	await _cockpit()
	var roster: Array[Dictionary] = main.wings.hud_roster()
	assert_false(roster.is_empty())
	var input: HudInput = main._build_hud_input()
	input.roster[0]["down"] = true
	var rows: Array[HudLayout.RosterRow] = (HudLayout.compute(input).screens[&"right"] as HudSurface).roster_rows
	assert_true(rows[0].down)
	assert_eq(rows[0].color, HudLayout.RED)


func test_the_edge_arrow_stays_on_the_window_in_the_cockpit() -> void:
	await _select_ally()
	await _cockpit()
	var input: HudInput = main._build_hud_input()
	input.target = main.ship.targeting.selected_readout()
	input.target.position = main.ship.global_position + main.ship.global_basis.z * 500.0  # dead astern
	var frame: HudFrame = HudLayout.compute(input)
	assert_true(frame.edge_arrow_visible)
	assert_has(frame.items, HudSurface.TARGET_MARKS)


func test_the_chase_camera_keeps_the_2d_hud_and_touches_no_screen() -> void:
	await _chase()
	var frame: HudFrame = main.hud.frame
	assert_true(frame.screens.is_empty())
	for item: StringName in [HudSurface.HULL_BAR, HudSurface.CHARGE_BAR, HudSurface.RADAR, HudSurface.SPEED, HudSurface.DRIFT, HudSurface.ROSTER,
			HudSurface.OWN_SILHOUETTE, HudSurface.TARGET_LABEL, HudSurface.STATUS, HudSurface.ACK, HudSurface.TRACKING]:
		assert_has(main.hud.painted_items(), item)
	assert_false(frame.charge_vertical, "the chase view's charge bar lies flat, as before")
	assert_does_not_have(main.hud.painted_items(), HudSurface.TARGET_PANEL)
	assert_eq(main.hud.painted_items().has(HudSurface.GRID), bool(Settings.get_value(&"hud_targeting_grid")), "the grid only by setting")


# --- the viewports ------------------------------------------------------------------------------------------------------


func test_viewports_exist_once_and_draw_2d_only() -> void:
	assert_not_null(screens, "the player's ship has them")
	assert_eq_deep(screens.sizes().keys(), [&"octagon", &"left", &"right"])
	var viewports: Array = _collect(main.ship, SubViewport, [])
	assert_eq(viewports.size(), 3, "exactly three, on the player's ship")
	for viewport: SubViewport in viewports:
		assert_true(viewport.disable_3d, "%s draws 2D only" % viewport.name)
		assert_false(viewport.transparent_bg)
	main.ship.setup(main.ship.spec, main.world)  # a rebuild
	await _frames(1)
	assert_eq(_collect(main.ship, SubViewport, []).size(), 3, "a rebuild builds no more")
	assert_eq(main.ship.cockpit_screens, screens)


func test_no_other_ship_has_screens() -> void:
	var others: Array = main.ships.all_ships()
	assert_false(others.is_empty())
	for combatant: Combatant in others:
		if combatant.ship != main.ship:
			assert_null(combatant.ship.cockpit_screens, "%s" % combatant.ship.name)
			assert_eq(_collect(combatant.ship, SubViewport, []).size(), 0)


func test_screens_sit_where_the_hardpoints_put_them() -> void:
	var hardpoints: Hardpoints = Hardpoints.load_file(main.ship.spec.hardpoints_path())
	for id: String in hardpoints.screens:
		var mesh: MeshInstance3D = screens.screen_mesh(StringName(id))
		assert_almost_eq(mesh.position, hardpoints.screens[id]["center"] as Vector3, Vector3.ONE * 1e-4, id)
		assert_almost_eq(mesh.global_basis.z, main.ship.global_basis * (hardpoints.screens[id]["normal"] as Vector3).normalized(), Vector3.ONE * 1e-3, "%s faces the pilot" % id)
	assert_lt(screens.screen_mesh(&"left").position.x, 0.0, "left is port")
	assert_gt(screens.screen_mesh(&"right").position.x, 0.0, "right is starboard")


func test_screens_are_unshaded_with_their_viewports_texture_and_no_mipmaps() -> void:
	for id: StringName in [&"octagon", &"left", &"right"]:
		var material := screens.screen_mesh(id).material_override as StandardMaterial3D
		assert_eq(material.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED, id)
		assert_eq(material.texture_filter, BaseMaterial3D.TEXTURE_FILTER_LINEAR, "%s: no mip level blurs its text" % id)
		assert_eq(material.albedo_texture, screens.viewport(id).get_texture())


func test_screens_update_only_while_the_cockpit_shows_them() -> void:
	await _cockpit()
	var before: int = screens.screen_state(&"left")["paints"]
	await _frames(4)
	assert_gt(int(screens.screen_state(&"left")["paints"]), before, "a new frame paints")
	assert_true(screens.screen_mesh(&"left").visible)
	await _chase()
	assert_false(screens.screen_mesh(&"left").visible)
	assert_eq(screens.viewport(&"left").render_target_update_mode, SubViewport.UPDATE_DISABLED, "hidden viewports do not update")
	var idle: int = screens.screen_state(&"left")["paints"]
	await _frames(4)
	assert_eq(int(screens.screen_state(&"left")["paints"]), idle, "and nothing paints them")


func test_switching_the_hud_off_takes_the_screens_dark() -> void:
	await _cockpit()
	assert_true(screens.screen_mesh(&"octagon").visible)
	Settings.set_value(&"show_hud", false)
	await _frames(1)
	assert_false(screens.screen_mesh(&"octagon").visible)
	assert_eq(screens.viewport(&"octagon").render_target_update_mode, SubViewport.UPDATE_DISABLED)
	assert_eq(str(DebugConsole.registry.read("screens.lamps")["value"]), "[]", "the lamps go dark with it")
	Settings.set_value(&"show_hud", true)
	await _frames(2)
	assert_true(screens.screen_mesh(&"octagon").visible)


# --- lamps and lights ---------------------------------------------------------------------------------------------------


func test_the_interior_has_all_four_lamps() -> void:
	assert_eq_deep(screens.lamp_ids().size(), HudLayout.LAMP_COLORS.size())
	for lamp: StringName in HudLayout.LAMP_COLORS:
		assert_has(screens.lamp_ids(), lamp)


func test_the_lamps_follow_their_states() -> void:
	await _cockpit()
	main.ship.set_assist(true)
	main.ship.running_lights = true
	await _frames(2)
	assert_true(screens.lamp_lit(&"assist"))
	assert_true(screens.lamp_lit(&"lights"))
	assert_true(screens.lamp_lit(&"guns"), "charged")
	assert_false(screens.lamp_lit(&"track"), "not tracking")
	main.ship.set_assist(false)
	main.ship.running_lights = false
	assert_true(DebugConsole.registry.execute("set weapons.charge 0")[0].ok)
	await _frames(2)
	assert_false(screens.lamp_lit(&"assist"))
	assert_false(screens.lamp_lit(&"lights"))
	assert_false(screens.lamp_lit(&"guns"), "empty")
	main.ship.set_assist(true)
	main.ship.running_lights = true


func test_a_lamps_surface_changes_with_its_state() -> void:
	await _cockpit()
	var surface: int = -1
	var mesh: Mesh = main.ship.cockpit_interior.mesh
	for i: int in mesh.get_surface_count():
		if String(mesh.surface_get_material(i).resource_name) == "ef_cockpit_ind_lights":
			surface = i
	assert_gte(surface, 0)
	main.ship.running_lights = true
	await _frames(2)
	var lit := main.ship.cockpit_interior.get_surface_override_material(surface) as StandardMaterial3D
	main.ship.running_lights = false
	await _frames(2)
	var dark := main.ship.cockpit_interior.get_surface_override_material(surface) as StandardMaterial3D
	assert_ne(lit, dark)
	assert_gt(lit.albedo_color.get_luminance(), dark.albedo_color.get_luminance() * 3.0)
	assert_eq(lit.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED)
	main.ship.running_lights = true


func test_the_screens_and_lamps_add_no_light() -> void:
	await _cockpit()
	assert_eq(_collect(main, Light3D, []).size(), 8, "AC30's 8 hold")
	assert_eq(_collect(screens, Light3D, []).size(), 0)


# --- the overlay fix ----------------------------------------------------------------------------------------------------


func test_in_the_chase_view_the_roster_clears_the_debug_overlay() -> void:
	await _chase()
	assert_true(main.overlay.visible, "on by default")
	assert_false(main.hud.frame.roster_rows.is_empty())
	assert_gt(main.hud.frame.roster_rows[0].bar_rect.position.y, main.overlay.text_bottom_px(), "below its last line")


func test_the_ref_line_can_run_wide_without_touching_lights_or_fuel() -> void:
	var surface: HudSurface = HudLayout._left_screen(screens.sizes()[&"left"])
	var ref_y: float = surface.speed_pos.y + 20.0 * surface.scale
	assert_lt(surface.running_lights_pos.y, surface.speed_pos.y - 22.0 * surface.scale, "lights sit above the speed block")
	assert_lt(surface.fuel_rect.end.y, surface.speed_pos.y - 22.0 * surface.scale, "and so does fuel")
	assert_lt(surface.fuel_rect.end.y, ref_y)


func test_the_console_can_report_the_screens_and_lamps() -> void:
	var provider: ConsoleStateProvider = DebugConsole.registry.get_provider(&"screens")
	assert_not_null(provider)
	assert_eq(provider.keys(), [&"shown", &"powered", &"paints", &"lamps"] as Array[StringName])


# Q29, maintainer: the map uses the same colours and indicators in both views, so a contact keeps its faction colour.
func test_the_octagons_contacts_look_as_they_do_on_the_chase_radar() -> void:
	DebugConsole.registry.execute("spawn raider idle 300")
	await _frames(2)
	await _cockpit()
	var hostile: int = 0
	var friendly: int = 0
	for dot: RadarModel.Dot in main.hud.frame.radar_dots:
		hostile += 1 if dot.color == Factions.hud_color(Factions.Relation.HOSTILE) else 0
		friendly += 1 if dot.color == Factions.hud_color(Factions.Relation.FRIENDLY) else 0
	assert_gt(hostile, 0, "the raider is in the hostile colour")
	assert_gt(friendly, 0, "the wing in the friendly colour")
	var octagon: HudSurface = main.hud.frame.screens[&"octagon"]
	assert_has(octagon.items, HudSurface.RADAR)
	assert_true(octagon.radar_labels, "the one thing the octagon adds: named rings")

