extends GutTest
## Babylon 5's commands (M8-T34, maintainer 2026-11-19) on the real main scene off the station's bow with two wingmen: with the
## station targeted the comms menu shows its commands instead of the wing orders, keys 1-N pick, Launch wing opens its ring, and
## each command does its work and has Control answer on the comms panel; the console gives the same commands.

const SCENARIO: String = "res://data/scenarios/station_dock.json"
const SPEED_UP: float = 8.0

var main: Main
var station: Station
var source: FakeInputSource
var _rate_backup: int = 60
var _scale_backup: float = 1.0
var _steps_backup: int = 8


func before_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	_steps_backup = Engine.max_physics_steps_per_frame


func after_each() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup
	get_tree().paused = false
	ContactScan.invalidate()


func _start() -> bool:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	source = FakeInputSource.new()
	main.input_source = source
	main.scenario_path = SCENARIO
	main.raider_pool_size = 2
	main.waves_auto_start = false
	add_child_autofree(main)
	await _ticks(3)
	station = main.far_props.station
	return station != null


func _target_station() -> void:
	assert_true(main.ship.targeting.select_by_name(Station.DISPLAY_NAME), "Babylon 5 selected")
	await _ticks(1)


func test_the_comms_menu_shows_the_station_commands_with_babylon_5_targeted() -> void:
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	await _press(InputAdapter.COMMS_MENU)
	assert_eq(main.comms.menu.page_title(), "WING ORDERS", "nothing targeted: the wing orders")
	await _press(InputAdapter.RADIAL_BACK)
	await _target_station()
	assert_true(main.station_commands.targeted())
	assert_true(_read("station_cmd.targeted"))
	await _press(InputAdapter.COMMS_MENU)
	assert_eq(main.comms.menu.page_title(), CommsMenuDirector.STATION_TITLE, "Babylon 5 targeted: its commands")
	assert_eq(_read("comms_menu.entries"),
			PackedStringArray(["launch wing", "recall", "defense grid", "fire support", "shelter", "sitrep"]))
	assert_eq(main.comms.menu.radial.slice_count(), 6, "one slice each (M8-T24)")
	await _press(InputAdapter.RADIAL_BACK)
	main.ship.targeting.clear_selection()
	await _ticks(1)
	await _press(InputAdapter.COMMS_MENU)
	assert_eq(main.comms.menu.page_title(), "WING ORDERS", "the target changed back: the wing orders again")
	await _press(InputAdapter.RADIAL_BACK)


func test_launch_wing_opens_its_ring_and_a_key_launches_that_wing() -> void:
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	await _target_station()
	await _press(InputAdapter.COMMS_MENU)
	await _press(InputAdapter.RADIAL_ENTRIES[0])  # key 1: LAUNCH WING
	assert_true(main.comms.is_open(), "a follow-up ring, not a pick")
	assert_eq(main.comms.menu.page_title(), "LAUNCH WING")
	assert_eq(_read("comms_menu.entries"), PackedStringArray(["alpha", "beta", "delta", "zeta", "all"]))
	await _press(InputAdapter.RADIAL_ENTRIES[1])  # key 2: BETA
	assert_false(main.comms.is_open(), "the pick closes the menu")
	assert_true(main.launches.is_launching("beta"), "Beta wing launches from its arm")
	assert_eq(main.station_commands.last_line, "BETA WING, CLEARED TO LAUNCH. GOOD HUNTING")
	var again: ConsoleResult = _run("stationcmd launch beta")
	assert_false(again.ok, "a wing in the bay is not launched twice")
	assert_eq(main.station_commands.last_line, "BETA WING IS IN THE BAY, LAUNCHING NOW")
	assert_false(_run("stationcmd launch").ok, "launch names a wing")
	assert_false(_run("stationcmd launch omega").ok)


func test_the_defense_grid_switches_off_and_on_and_fire_support_needs_it() -> void:
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	await _target_station()
	assert_true(station.grid.is_on(), "the grid starts on")
	await _press(InputAdapter.COMMS_MENU)
	await _press(InputAdapter.RADIAL_ENTRIES[2])  # key 3: DEFENSE GRID
	assert_false(station.grid.is_on(), "off: no gun or interceptor fires (the core's flag)")
	assert_false(_read("grid.on"))
	assert_eq(main.station_commands.last_line, "DEFENSE GRID OFFLINE, HOLDING ALL FIRE")
	assert_false(_run("stationcmd support on").ok, "no covering fire from a grid that is off")
	assert_eq(main.station_commands.last_line, "NEGATIVE, THE DEFENSE GRID IS OFFLINE")
	assert_true(_run("stationcmd grid").ok, "a toggle")
	assert_true(station.grid.is_on())
	assert_eq(main.station_commands.last_line, "DEFENSE GRID ONLINE")


func test_fire_support_covers_the_players_ship_until_it_is_ended() -> void:
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	await _target_station()
	await _press(InputAdapter.COMMS_MENU)
	assert_eq(main.comms.menu.radial.slots()[3]["sub"], "cover me")
	await _press(InputAdapter.RADIAL_ENTRIES[3])  # key 4: FIRE SUPPORT
	assert_true(main.station_commands.support_on)
	assert_eq(station.grid.cover_body(), main.ship.get_instance_id(), "the core covers the player's ship")
	assert_eq(_read("grid.cover"), main.ship.get_instance_id())
	assert_eq(main.station_commands.last_line, "COPY, COVERING FIRE ON YOUR POSITION")
	await _press(InputAdapter.COMMS_MENU)
	assert_eq(main.comms.menu.radial.slots()[3]["sub"], "end", "the entry says what a second pick does")
	await _press(InputAdapter.RADIAL_ENTRIES[3])
	assert_false(main.station_commands.support_on)
	assert_eq(station.grid.cover_body(), 0)
	assert_eq(main.station_commands.last_line, "COVERING FIRE ENDED")


func test_shelter_holds_new_traffic_stands_civilians_off_and_releases_them() -> void:
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	assert_true(_run("traffic freighter near").ok, "a freighter on the cargo bay's lane")
	await _ticks(3)
	assert_true(_run("stationcmd shelter").ok)
	assert_true(main.traffic.sheltering)
	assert_eq(main.station_commands.last_line, "ALL CIVILIAN TRAFFIC, HOLD. TAKE SHELTER INSIDE OR BEHIND THE STATION")
	assert_eq(main.traffic.sheltered_count(), 1, "the freighter stands off behind the station")
	var freighter: Combatant = main.traffic.last_ship()
	assert_eq(main.traffic.state_of(freighter), &"shelter")
	assert_true(str(_read("traffic.sheltering")).begins_with("on"))
	assert_true(_run("stationcmd shelter off").ok)
	assert_false(main.traffic.sheltering)
	assert_eq(main.traffic.state_of(freighter), &"leave", "released, it goes on its way")
	assert_eq(main.station_commands.last_line, "CIVILIAN TRAFFIC, YOU ARE CLEARED TO RESUME")


func test_a_lost_shelterer_frees_its_point_and_sheltering_again_moves_nobody() -> void:
	# Council round 2 (N2): each sheltering ship holds its own stand-off point; a new one takes the lowest free point, and asking
	# for shelter while it is on leaves those already standing off where they are.
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	var types: Array[String] = ["saturn_3_freighter", "saturn_4_transport", "saturn_4_tanker"]
	for type: String in types:
		assert_true(_run("traffic freighter %s near" % type).ok, type)
	await _ticks(2)
	assert_eq(main.traffic.set_shelter(true), 3)
	var slots: Dictionary = _slots()
	assert_eq(slots.values(), [0, 1, 2], "points 0, 1 and 2: %s" % [slots])
	assert_eq(main.traffic.set_shelter(true), 0, "on again: nobody already standing off moves")
	assert_eq(_slots(), slots, "every ship keeps its point")
	var lost: Combatant = null
	for c: Combatant in slots:
		if int(slots[c]) == 1:
			lost = c
	lost.damageable.kill()
	await _ticks(3)
	assert_true(_run("traffic freighter saturn_8_transport near").ok)
	await _ticks(2)
	assert_eq(main.traffic.set_shelter(true), 1, "only the newcomer goes to the stand-off")
	var newcomer: Combatant = main.traffic.last_ship()
	assert_eq(int(_slots().get(newcomer, -1)), 1, "it takes the lost ship's point, not point 2 again")


# Each sheltering traffic ship and the stand-off point it holds, in the traffic's order.
func _slots() -> Dictionary:
	var out: Dictionary = {}
	for entry: Dictionary in main.traffic._own:
		if entry["state"] == &"shelter" and is_instance_valid(entry["combatant"]):
			out[entry["combatant"]] = int(entry.get("shelter_slot", -1))
	return out


func test_recall_brings_every_fighter_home_to_stay() -> void:
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	assert_true(_run("stationcmd recall").ok)
	assert_eq(main.station_commands.last_line, "ALL FIGHTERS, RETURN TO BABYLON 5 AND DOCK")
	for name: String in ["ALPHA 2", "ALPHA 3"]:
		var visit: DockVisit = main.docking.visit_of(name)
		assert_not_null(visit, "%s flies home" % name)
		if visit != null:
			assert_eq(visit.why, DockVisit.WHY_RECALL, "the player's own wingmen too")
	_fast()
	var home: bool = await _until(func() -> bool: return main.docking.stowed_count >= 1, 240.0)
	assert_true(home, "a recalled fighter docks (%s)" % main.docking.describe())
	await _ticks(2)
	assert_eq(main.docking.relaunched_count, 0, "and stays inside: no relaunch")
	assert_lt(main.wings.player_wing().members().size(), 2, "it left the player's wing")


func test_sitrep_reports_sections_wings_raiders_and_the_grid() -> void:
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	var result: Dictionary = main.station_commands.run(&"sitrep")
	var said: PackedStringArray = result["lines"]
	assert_eq(said.size(), 4, "sections, wings, raiders, grid: %s" % [said])
	assert_eq(said[0], "SITREP. HULL: ALL SECTIONS INTACT")
	assert_eq(said[1], "WINGS OUT: NONE")
	assert_eq(said[2], "0 RAIDERS WITHIN 30 KM")
	assert_true(said[3].begins_with("DEFENSE GRID ONLINE"), said[3])
	var section: String = str(station.sections.sections[0]["name"])
	station.sections.damage(0, StationSections.SECTION_HEALTH * 0.5)
	assert_true(_run("spawn raider idle").ok)
	_run("stationcmd grid off")
	said = main.station_commands.run(&"sitrep")["lines"]
	assert_eq(said[0], "SITREP. HULL: %s 50%%" % section.to_upper())
	assert_eq(said[2], "1 RAIDERS WITHIN 30 KM")
	assert_eq(said[3], "DEFENSE GRID OFFLINE")
	assert_true(_run("stationcmd sitrep").ok, "the console asks the same")


func test_control_speaks_on_the_comms_panel() -> void:
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	_run("stationcmd grid off")
	var queue: DialogQueue = main.mission.api.dialog if main.mission != null else main.station_commands.queue
	assert_not_null(queue.current, "Control's answer is a comms line")
	if queue.current != null:
		assert_eq(queue.current.speaker, StationCommands.SPEAKER)
		assert_eq(queue.current.text, "DEFENSE GRID OFFLINE, HOLDING ALL FIRE")
	assert_eq(_read("station_cmd.given"), 1)


func _fast() -> void:
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))


func _until(done: Callable, limit_s: float) -> bool:
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < limit_s:
		if done.call():
			return true
		await get_tree().physics_frame
	return bool(done.call())


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _press(action: StringName) -> void:
	source.hold(action, 1.0)
	await _ticks(2)
	source.release(action)
	await _ticks(2)


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


func _read(path: String) -> Variant:
	var read: Dictionary = DebugConsole.registry.read(path)
	assert_true(read["ok"], "%s: %s" % [path, read["error"]])
	return read["value"]
