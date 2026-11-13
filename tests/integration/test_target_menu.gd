extends TestSteps
## The target menu on the real main scene (architecture §18.19, M5-T25): a tap toggles the nearest and the 2nd nearest enemy;
## a hold pauses the game and opens the radial menu, which the menu's stick, select and back drive and nothing else; a
## picked ship is the target, a picked beacon or objective the HUD waypoint (never the target); an unidentified contact
## reads UNKNOWN; closed, the menu costs nothing per tick.

const DT: float = 1.0 / 60.0
const MISSION_PATH: String = "res://tests/fixtures/missions/test_mission.json"
const UP := 0.0
const DOWN := 180.0

var main: Main
var source: FakeInputSource


func before_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()
	await _boot(ScenarioLoader.FREE_FLIGHT_PATH)


func after_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()


func _boot(scenario: String, raiders: int = 4) -> void:
	if main != null:
		main.queue_free()
		await _ticks(2)
	source = FakeInputSource.new()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	main.scenario_path = scenario
	main.waves_auto_start = false
	main.raider_pool_size = raiders
	add_child_autofree(main)
	await _ticks(2)


func _press(action: StringName) -> void:
	source.hold(action)
	await _ticks(2)
	source.release(action)
	await _ticks(2)


# A parked raider `range_m` ahead of the player, sitting still.
func _raider(label: String, range_m: float, side_m: float = 0.0) -> Combatant:
	var at: UniversePos = main.world.to_universe(main.ship.global_position).plus_local(Vector3(side_m, 0.0, -range_m))
	var raider: Combatant = main.ships.acquire(label, at, Basis.IDENTITY, Vector3.ZERO, IdleBrain.new())
	raider.damageable.invulnerable = true
	return raider


func _hold_open() -> void:
	source.hold(InputAdapter.TARGET_CYCLE)
	await _ticks(ceili(main.adapter.target_hold_s / DT) + 3)
	source.release(InputAdapter.TARGET_CYCLE)
	await _ticks(2)


# Points the menu's stick `deg` clockwise from straight up for two ticks, then lets it centre.
func _point(deg: float) -> void:
	var v := Vector2(sin(deg_to_rad(deg)), cos(deg_to_rad(deg)))
	source.hold(InputAdapter.RADIAL_RIGHT, maxf(v.x, 0.0))
	source.hold(InputAdapter.RADIAL_LEFT, maxf(-v.x, 0.0))
	source.hold(InputAdapter.RADIAL_UP, maxf(v.y, 0.0))
	source.hold(InputAdapter.RADIAL_DOWN, maxf(-v.y, 0.0))
	await _ticks(2)
	for action: StringName in [InputAdapter.RADIAL_RIGHT, InputAdapter.RADIAL_LEFT, InputAdapter.RADIAL_UP, InputAdapter.RADIAL_DOWN]:
		source.release(action)
	await _ticks(1)


func _read(path: String) -> Variant:
	var read: Dictionary = DebugConsole.registry.read(path)
	assert_true(read["ok"], "%s: %s" % [path, read["error"]])
	return read["value"]


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


func _frame() -> HudFrame:
	var input: HudInput = main._build_hud_input()
	if main.hud.extra_input.is_valid():
		main.hud.extra_input.call(input)
	main.hud.final_input.call(input)
	return HudLayout.compute(input)


# --- the tap --------------------------------------------------------------------------------------------------------


func test_a_tap_toggles_between_the_nearest_and_the_second_nearest_enemy() -> void:
	_raider("FAR", 3000.0)
	_raider("NEAR", 800.0)
	_raider("MID", 1500.0)
	await _ticks(3)
	await _press(InputAdapter.TARGET_CYCLE)
	assert_eq(main.ship.targeting.selected_name(), "NEAR", "a tap: the nearest enemy, not the nearer buoy")
	await _press(InputAdapter.TARGET_CYCLE)
	assert_eq(main.ship.targeting.selected_name(), "MID", "a tap on the nearest: the 2nd nearest")
	await _press(InputAdapter.TARGET_NEXT)
	assert_eq(main.ship.targeting.selected_name(), "NEAR", "the next tap (keyboard B): back to the nearest")
	await _press(InputAdapter.TARGET_CYCLE)
	await _press(InputAdapter.TARGET_CYCLE)
	assert_eq(main.ship.targeting.selected_name(), "NEAR", "only those two: FAR is never reached by tapping")
	assert_false(main.target_menu.is_open())
	assert_eq(main.target_menu.opens, 0, "a tap never opens the menu")


# --- the hold: pause, stick, A, B -------------------------------------------------------------------------------------


func test_a_hold_pauses_the_game_and_opens_the_categories() -> void:
	_raider("RAIDER 1", 900.0)
	await _ticks(3)
	source.hold(InputAdapter.TARGET_CYCLE)
	await _ticks(ceili(main.adapter.target_hold_s / DT) + 3)
	assert_true(main.target_menu.is_open(), "held past the threshold: the menu opens")
	assert_true(get_tree().paused, "and the game pauses")
	var t: float = SimClock.now()
	var at: Vector3 = main.ship.global_position
	source.release(InputAdapter.TARGET_CYCLE)
	await _ticks(10)
	assert_true(main.target_menu.is_open(), "it stays open after the button is released")
	assert_eq(SimClock.now(), t, "sim time stops while it is open")
	assert_eq(main.ship.global_position, at, "and so does the world")
	assert_eq(_read("target_menu.page"), "categories")
	assert_eq(_read("target_menu.entries"), PackedStringArray(["enemies", "allies", "civilian", "unknown", "navigation", "objectives"]))
	assert_eq(main.ship.targeting.selected_name(), "", "the hold targeted nothing")
	assert_true(main.target_menu.view.visible)
	main.target_menu.close()
	# With a target selected, the HUD keeps its box and readout behind the open menu.
	await _press(InputAdapter.TARGET_CYCLE)
	assert_eq(main.ship.targeting.selected_name(), "RAIDER 1")
	assert_eq(main.target_menu.open(), "")
	var f: HudFrame = _frame()
	assert_true(f.target_present, "the paused HUD still shows the target")
	assert_eq(f.target_name, "RAIDER 1")
	assert_almost_eq(f.target_range_m, 900.0, 20.0)
	main.target_menu.close()


func test_the_stick_points_a_selects_and_the_game_resumes_with_nothing_fired() -> void:
	_raider("RAIDER 1", 900.0)
	_raider("RAIDER 2", 1400.0)
	await _ticks(3)
	await _hold_open()
	await _point(UP)
	assert_eq(_read("target_menu.highlight"), "ENEMIES")
	await _press(InputAdapter.RADIAL_SELECT)
	assert_eq(_read("target_menu.page"), "enemies")
	assert_eq(_read("target_menu.entries"), PackedStringArray(["raider 1", "raider 2", "-", "none", "-", "-"]))
	assert_true(get_tree().paused, "still paused on the second ring")
	await _point(60.0)
	assert_eq(_read("target_menu.highlight"), "RAIDER 2")
	await _point(120.0)
	assert_eq(_read("target_menu.highlight"), "RAIDER 2", "a blank slice keeps the last highlight")
	# A is also fire, and the stick that points also steers: both stay held through the pick.
	var bolts: int = main.projectiles.get_child_count()
	source.hold(InputAdapter.YAW_RIGHT, 1.0)
	source.hold(InputAdapter.FIRE)
	source.hold(InputAdapter.RADIAL_SELECT)
	await _ticks(4)
	assert_false(main.target_menu.is_open(), "A on a ship closes the menu")
	assert_false(get_tree().paused, "and the game resumes")
	assert_eq(main.ship.targeting.selected_name(), "RAIDER 2", "the picked ship is the target")
	assert_eq(_read("target_menu.closed_by"), "pick")
	assert_eq(main.projectiles.get_child_count(), bolts, "the A that selected does not fire")
	assert_false(main.adapter.last.combat.fire)
	assert_eq(main.adapter.last.flight.rot, Vector3.ZERO, "the stick that pointed does not steer until it centres")
	source.release_all()
	await _ticks(2)
	source.hold(InputAdapter.YAW_RIGHT, 1.0)
	source.hold(InputAdapter.FIRE)
	await _ticks(3)
	assert_true(main.adapter.last.combat.fire, "let go and pressed again, A fires")
	assert_gt(main.adapter.last.flight.rot.y, 0.5, "and the stick steers")


func test_b_goes_back_a_ring_then_closes_and_resumes() -> void:
	await _hold_open()
	await _point(DOWN)
	await _press(InputAdapter.RADIAL_SELECT)
	assert_eq(_read("target_menu.page"), "unknown")
	await _press(InputAdapter.RADIAL_BACK)
	assert_eq(_read("target_menu.page"), "categories", "B on the second ring: the categories")
	assert_true(get_tree().paused)
	await _press(InputAdapter.RADIAL_BACK)
	assert_false(main.target_menu.is_open(), "B on the first ring closes the menu")
	assert_false(get_tree().paused)
	assert_eq(_read("target_menu.closed_by"), "back")
	# B is the target button: the press that closed it must not also tap or reopen.
	assert_eq(main.target_menu.opens, 1)
	assert_eq(main.ship.targeting.selected_name(), "")


func test_only_the_menus_controls_are_read_while_it_is_open() -> void:
	await _hold_open()
	var assist: bool = main.ship.assist_on
	var lights: bool = main.ship.running_lights
	var camera: CameraRig.Mode = main.camera_rig.mode
	for action: StringName in [InputAdapter.TOGGLE_ASSIST, InputAdapter.TOGGLE_RUNNING_LIGHTS, InputAdapter.TOGGLE_CAMERA,
			InputAdapter.AUTOTRACK, InputAdapter.WEAPON_NEXT, InputAdapter.COMMS_MENU, InputAdapter.RESET_SHIP]:
		await _press(action)
	assert_true(main.target_menu.is_open(), "X, Y and the D-pad take no part")
	assert_eq(main.ship.assist_on, assist)
	assert_eq(main.ship.running_lights, lights)
	assert_eq(main.camera_rig.mode, camera)
	assert_false(main.adapter.autotrack_on)
	assert_false(main.comms.is_open())
	# Held when it closes, then let go: still nothing.
	source.hold(InputAdapter.TOGGLE_ASSIST)
	source.hold(InputAdapter.TOGGLE_CAMERA)
	main.target_menu.close()
	await _ticks(3)
	source.release_all()
	await _ticks(2)
	assert_eq(main.ship.assist_on, assist, "a button held as the menu closes fires nothing")
	assert_eq(main.camera_rig.mode, camera)


func test_start_closes_it_and_opens_the_pause_menu() -> void:
	await _hold_open()
	await _press(InputAdapter.PAUSE)
	assert_false(main.target_menu.is_open())
	assert_eq(_read("target_menu.closed_by"), "pause")
	assert_true(main.pause_menu.is_open(), "Start hands over to the pause menu")
	assert_true(get_tree().paused)
	main.pause_menu.close()
	assert_false(get_tree().paused)


func test_it_does_not_open_when_the_controls_are_not_the_pilots() -> void:
	main.pause_menu.open()
	assert_ne(main.target_menu.open(), "", "not over the pause menu")
	main.pause_menu.close()
	main.player_alive = false
	assert_ne(main.target_menu.open(), "", "not with the player down")
	main.player_alive = true
	await _press(InputAdapter.COMMS_MENU)
	assert_true(main.comms.is_open())
	assert_ne(main.target_menu.open(), "", "not over the comms menu")
	main.comms.close()
	assert_eq(main.target_menu.open(), "")
	assert_ne(main.target_menu.open(), "", "not twice")
	main.target_menu.close()


func test_closing_restores_a_pause_that_was_there_before() -> void:
	main.set_paused(true)
	assert_eq(main.target_menu.open(), "")
	main.target_menu.close()
	assert_true(get_tree().paused, "a game paused from the console stays paused")
	main.set_paused(false)


# --- waypoints ------------------------------------------------------------------------------------------------------


func test_a_picked_beacon_is_the_hud_waypoint_and_never_the_target() -> void:
	_raider("RAIDER 1", 900.0)
	await _ticks(3)
	await _press(InputAdapter.TARGET_CYCLE)
	assert_eq(main.ship.targeting.selected_name(), "RAIDER 1")
	assert_false(_frame().waypoint_present, "free flight: no waypoint to start with")
	await _hold_open()
	await _point(240.0)
	assert_eq(_read("target_menu.highlight"), "NAVIGATION")
	await _press(InputAdapter.RADIAL_SELECT)
	var entries: PackedStringArray = _read("target_menu.entries")
	assert_eq(entries[0], "nav alpha", "the nearest beacon first")
	assert_eq(entries[3], "none")
	await _press(InputAdapter.RADIAL_SELECT)
	assert_false(main.target_menu.is_open())
	assert_eq(main.ship.targeting.selected_name(), "RAIDER 1", "the ship keeps its target: a beacon is never the facing target")
	assert_eq(_read("target_menu.waypoint"), "NAV ALPHA")
	var f: HudFrame = _frame()
	assert_true(f.waypoint_present)
	assert_eq(f.waypoint_label, "NAV ALPHA")
	assert_almost_eq(f.waypoint_range_m, 500.0, 10.0)
	assert_gt(f.waypoint_radar_index, -1, "its radar entry is marked")
	assert_eq(f.radar_plot.ids[f.waypoint_radar_index], main.buoys[0].get_node(^"Targetable").get_instance_id())
	# None on the navigation ring clears it, and leaves the target alone.
	assert_true(_run("targetmenu open").ok)
	assert_true(_run("targetmenu pick navigation").ok)
	assert_true(_run("targetmenu pick none").ok)
	assert_false(_frame().waypoint_present, "none clears the waypoint")
	assert_eq(_frame().waypoint_radar_index, -1)
	assert_eq(main.ship.targeting.selected_name(), "RAIDER 1")
	assert_eq(_read("target_menu.last_pick"), "clear_waypoint")
	# None on a ship ring clears the target.
	_run("targetmenu open")
	_run("targetmenu pick enemies")
	_run("targetmenu pick none")
	assert_eq(main.ship.targeting.selected_name(), "", "none on a ship ring clears the target")


func test_a_picked_waypoint_is_dropped_when_its_beacon_is_destroyed() -> void:
	_run("targetmenu open")
	_run("targetmenu pick navigation")
	_run("targetmenu pick 0")
	assert_true(_frame().waypoint_present)
	main.buoys[0].set_destroyed(true)
	assert_false(_frame().waypoint_present)
	assert_eq(_read("target_menu.waypoint"), "none")


func test_the_later_of_the_pilots_pick_and_the_missions_waypoint_wins() -> void:
	await _boot(MISSION_PATH)
	var api: MissionApi = main.mission.api
	api.skip()
	await _ticks(3)
	assert_eq(api.waypoint_name, "NAV ALPHA", "the script marked the buoy")
	assert_eq(_frame().waypoint_label, "NAV ALPHA")
	assert_eq(_read("target_menu.waypoint"), "script")
	assert_gt(_frame().waypoint_radar_index, -1, "a script's waypoint marks its radar entry too")
	# The objectives ring: the active objectives that name an actor, as waypoints.
	_run("targetmenu open")
	assert_eq((_read("target_menu.entries") as PackedStringArray)[5], "objectives")
	_run("targetmenu pick objectives")
	var entries: PackedStringArray = _read("target_menu.entries")
	assert_eq(entries[3], "none", "none is the down slice here too")
	assert_eq(entries[1], "keep nav alpha…", "an active objective that names an actor is listed, cut to its slice: %s" % [entries])
	assert_eq(entries.count("-"), 3, "the objectives not shown yet are not listed")
	_run("targetmenu pick none")
	assert_false(_frame().waypoint_present, "the pilot's none hides the script's waypoint")
	api.waypoint("NAV ALPHA")
	assert_eq(_frame().waypoint_label, "NAV ALPHA", "the script sets it anew: the later word wins")
	_run("targetmenu open")
	_run("targetmenu pick objectives")
	_run("targetmenu pick 1")
	assert_eq(_read("target_menu.last_pick"), "waypoint NAV ALPHA")
	api.waypoint(null)
	assert_false(_frame().waypoint_present, "and when the script clears it after the pick, it is clear")
	assert_eq(main.ship.targeting.selected_name(), "", "an objective is never the target")


# --- unknown contacts ---------------------------------------------------------------------------------------------


func test_a_silent_contact_beyond_five_km_reads_unknown_until_it_is_near() -> void:
	var far: Combatant = _raider("RAIDER 1", 7000.0)
	_raider("RAIDER 2", 2000.0)
	await _ticks(3)
	var f: HudFrame = _frame()
	var far_id: int = far.targetable.get_instance_id()
	var dots: Array[RadarModel.Dot] = f.radar_dots
	var seen: Dictionary = {}
	for dot: RadarModel.Dot in dots:
		seen[dot.id] = dot.color
	assert_eq(seen[far_id], Factions.UNIDENTIFIED_COLOR, "the radar: grey, no faction colour")
	assert_eq(seen[main.buoys[1].get_node(^"Targetable").get_instance_id()], Factions.NEUTRAL_COLOR, "a buoy broadcasts: identified at any range")
	# It is offered under UNKNOWN, not ENEMIES, and has no name there.
	_run("targetmenu open")
	_run("targetmenu pick enemies")
	assert_eq(_read("target_menu.entries"), PackedStringArray(["raider 2", "-", "-", "none", "-", "-"]))
	_run("targetmenu back")
	_run("targetmenu pick unknown")
	assert_eq((_read("target_menu.entries") as PackedStringArray)[0], "unknown")
	_run("targetmenu pick 0")
	assert_eq(main.ship.targeting.selected_id(), far_id, "picked from the ring, it is the target")
	f = _frame()
	assert_eq(f.target_name, "UNKNOWN", "the HUD: no name")
	assert_eq(f.target_color, Factions.UNIDENTIFIED_COLOR)
	assert_eq(f.target_hull, -1.0, "no hull bar")
	assert_eq(_read("target_menu.selection"), "UNKNOWN")
	# Within 5 km it is identified, and stays so while selected even if the range opens again.
	far.ship.global_position = main.ship.global_position + Vector3(0.0, 0.0, -4000.0)
	far.ship.reset_physics_interpolation()
	await _ticks(3)
	f = _frame()
	assert_eq(f.target_name, "RAIDER 1")
	assert_eq(f.target_color, Factions.HOSTILE_COLOR)
	far.ship.global_position = main.ship.global_position + Vector3(0.0, 0.0, -8000.0)
	far.ship.reset_physics_interpolation()
	await _ticks(3)
	f = _frame()
	assert_eq(f.target_name, "RAIDER 1", "a target once identified keeps its name while it is selected")
	assert_eq(f.radar_dots[f.radar_plot.selected_index].color, Factions.HOSTILE_COLOR)
	main.ship.targeting.clear_selection()
	await _ticks(2)
	for dot: RadarModel.Dot in _frame().radar_dots:
		if dot.id == far_id:
			assert_eq(dot.color, Factions.UNIDENTIFIED_COLOR, "deselected and far: unknown again")


func test_a_tap_with_only_unknown_contacts_takes_the_nearest_of_them() -> void:
	var far: Combatant = _raider("RAIDER 1", 7000.0)
	await _ticks(3)
	await _press(InputAdapter.TARGET_CYCLE)
	assert_eq(main.ship.targeting.selected_id(), far.targetable.get_instance_id())
	assert_eq(_frame().target_name, "UNKNOWN")


# --- cost and console ---------------------------------------------------------------------------------------------


func test_closed_it_costs_nothing_per_tick() -> void:
	# No AI ship in play: their own targeting builds a `TargetInfo` now and then, which is not the menu's work.
	await _ticks(5)
	assert_false(main.target_menu.view.visible)
	assert_false(main.target_menu.view.is_processing(), "the view does not process while closed")
	assert_false(main.target_menu.is_processing() or main.target_menu.is_physics_processing(), "the director has no tick of its own")
	var built: int = TargetInfo.built_count
	var draws: int = main.target_menu.view.draws
	await _ticks(30)
	assert_eq(TargetInfo.built_count, built, "no candidate is built while it is closed (the list is read when it opens)")
	assert_eq(main.target_menu.view.draws, draws, "nothing is drawn")
	_run("targetmenu open")
	assert_eq(TargetInfo.built_count - built, int(_read("target_menu.last_candidates")), "opening reads the list once")
	# The buoys and the jumpgate (M6-T14) are the scene's broadcasters.
	assert_eq(int(_read("target_menu.last_candidates")), main.buoys.size() + main.gates.gates.size())
	built = TargetInfo.built_count
	await _ticks(10)
	_run("targetmenu pick navigation")
	await _ticks(10)
	assert_eq(TargetInfo.built_count, built, "and never again while it is open: the rings come from that one read")
	_run("targetmenu close")
	assert_false(main.target_menu.view.is_processing())


func test_the_console_opens_picks_and_closes_it() -> void:
	_raider("RAIDER 1", 900.0)
	await _ticks(3)
	assert_false(_run("targetmenu pick enemies").ok, "pick needs it open")
	var opened: ConsoleResult = _run("targetmenu open")
	assert_true(opened.ok)
	assert_true(get_tree().paused)
	assert_false(_run("targetmenu open").ok, "already open")
	assert_false(_run("pause off").ok, "the pause command is refused while it is open")
	assert_false(_run("targetmenu pick nonsense").ok)
	assert_false(_run("targetmenu back enemies").ok, "only pick takes an entry")
	assert_true(_run("targetmenu pick enemies").ok)
	assert_eq(_read("target_menu.page"), "enemies")
	assert_false(_run("targetmenu pick 1").ok, "a blank slice is not an entry")
	assert_true(_run("targetmenu pick \"raider 1\"").ok)
	assert_false(_read("target_menu.open"))
	assert_false(get_tree().paused)
	assert_eq(_read("target_menu.selection"), "RAIDER 1")
	assert_eq(_read("target_menu.last_pick"), "target RAIDER 1")
	assert_gt(float(_read("target_menu.last_open_ms")), 0.0)
	assert_true(_run("targetmenu open").ok)
	assert_true(_run("targetmenu close").ok)
	assert_eq(_read("target_menu.closed_by"), "close")
	assert_false(get_tree().paused)


func test_the_ring_is_drawn_vertically_centred_at_the_left_with_its_entries() -> void:
	_raider("RAIDER 1", 900.0)
	await _ticks(3)
	_run("targetmenu open")
	await wait_process_frames(3)
	var view: RadialMenuView = main.target_menu.view
	var size: Vector2 = get_viewport().get_visible_rect().size
	assert_gt(view.draws, 0)
	assert_eq(view.layer, RadialMenuView.LAYER)
	assert_gt(view.layer, main.hud.layer, "above the HUD")
	assert_lt(view.layer, main.pause_menu.layer, "below the pause menu")
	assert_almost_eq(view.drawn_centre.y, size.y * 0.5, 1.0, "vertically centred")
	assert_lt(view.drawn_centre.x, size.x * 0.5 + 1.0, "at the left side")
	assert_eq(view.drawn_labels, ["ENEMIES", "ALLIES", "CIVILIAN", "UNKNOWN", "NAVIGATION", "OBJECTIVES"] as Array[String])
	assert_eq(view.drawn_heading, "TACTICAL PAUSE")
	_run("targetmenu pick enemies")
	await wait_process_frames(3)
	assert_eq(view.drawn_labels, ["RAIDER 1", "", "", "NONE", "", ""] as Array[String])
	assert_eq(view.drawn_heading, "TACTICAL PAUSE · ENEMIES")
	assert_eq(view.hint, TargetMenuDirector.HINT_TARGET)
	_run("targetmenu close")


# --- focus pull (T44) ---------------------------------------------------------------------------------------------


func _pull_view() -> FocusPullView:
	return main.target_menu.get_node("FocusPull") as FocusPullView


func test_focus_pull_eases_in_and_out_on_real_time() -> void:
	var blur: FocusPullView = _pull_view()
	assert_not_null(blur)
	assert_false(blur.visible, "hidden at rest")
	assert_false(blur.is_processing())
	assert_eq(main.target_menu.open(), "")
	assert_true(blur.visible)
	assert_true(blur.layer > main.hud.layer and blur.layer < main.target_menu.view.layer, "above the HUD, below the menu")
	assert_true(blur.layer < main.target_menu.preview.layer + 1)
	await get_tree().create_timer(0.4, true, false, true).timeout
	assert_eq(blur.amount(), 1.0, "full after 0.2 s even though the tree is paused")
	assert_eq(_read("target_menu.focus"), 1.0)
	main.target_menu.close()
	await get_tree().create_timer(0.4, true, false, true).timeout
	assert_eq(blur.amount(), 0.0)
	assert_false(blur.visible, "hidden again once back in focus")
	assert_false(blur.is_processing())


func test_focus_pull_setting_zero_never_shows() -> void:
	Settings.set_value(&"target_menu_blur", 0.0)
	assert_eq(main.target_menu.open(), "")
	await get_tree().create_timer(0.3, true, false, true).timeout
	assert_false(_pull_view().visible)
	assert_eq(_pull_view().amount(), 0.0)
	main.target_menu.close()
	Settings.set_value(&"target_menu_blur", 0.35)
