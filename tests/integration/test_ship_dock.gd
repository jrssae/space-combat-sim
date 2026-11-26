extends GutTest
## Docking at a ship (M10-T53, Q84) in the real main scene, on the generated liner and shuttles: the `liner_dock` scene puts
## the player in a crew shuttle off an Asimov that holds station; an AI crew shuttle flies to a collar, backs onto it, rides
## mated and leaves again; the player docks with the hold of X on the collars and leaves with the same hold; a Kestrel has no
## lock and is refused; a docking under way can be called off.

const SCENARIO: String = "res://data/scenarios/liner_dock.json"
const SPEED_UP: float = 4.0

var main: Main
var _rate_backup: int = 60
var _scale_backup: float = 1.0
var _steps_backup: int = 8


func before_each() -> void:
	get_tree().paused = false
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	_steps_backup = Engine.max_physics_steps_per_frame
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = SCENARIO
	main.scenario_seed = 5
	add_child_autofree(main)
	await wait_physics_frames(3)


func after_each() -> void:
	(main.input_source as FakeInputSource).release_all()
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup


func _liner() -> CapitalShip:
	var found: CapitalShip = main.scenario_capitals[0] as CapitalShip if not main.scenario_capitals.is_empty() else null
	assert_not_null(found, "the scene's liner is generated (scripts/gen_assets.sh)")
	return found


func _fly(seconds: float, done: Callable = Callable()) -> void:
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < seconds:
		await get_tree().physics_frame
		if done.is_valid() and bool(done.call()):
			break
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup


func test_the_scene_puts_the_player_in_a_crew_shuttle_off_a_liner_with_four_collars() -> void:
	var liner: CapitalShip = _liner()
	if liner == null:
		return
	assert_true(Main.SCENARIO_CHOICES.has(&"liner_dock"), "the scene is in the scenario list")
	assert_eq(main.ship.spec.asset_id, "ea_shuttle", "the player flies a crew shuttle (Q84)")
	assert_false(ShipDock.lock_of(main.ship).is_empty(), "with its stern hatch")
	var dock: ShipDock = liner.dock
	assert_not_null(dock, "the liner has a dock")
	assert_eq(ShipDock.of(liner), dock)
	assert_eq(dock.ports.count(), 4, "four docking collars (Q84)")
	assert_eq(dock.free_count(), 4)
	assert_eq(dock.closed_reason(), "", "it holds station, so craft may dock")
	assert_true(dock.nav.is_in_group(NavPoint.DOCKS_GROUP), "its collars are a dock the player can target")
	var bow: Vector3 = -liner.global_basis.z
	for i: int in dock.ports.count():
		assert_gt((liner.global_basis * dock.ports.outs[i]).dot(bow), 0.99, "%s faces forward" % dock.ports.names[i])
	assert_eq(main.ship_docks.docks().size(), 1)
	assert_eq(main.ship_docks.dock_named("ea_asimov"), dock)
	assert_null(main.ship_docks.dock_named("no such ship"))


func test_an_ai_crew_shuttle_docks_at_a_collar_rides_mated_and_leaves_again() -> void:
	var liner: CapitalShip = _liner()
	if liner == null:
		return
	var dock: ShipDock = liner.dock
	var events: Array[String] = []
	dock.docked.connect(func(_craft: Ship, port: int) -> void: events.append("docked %s" % dock.ports.names[port]))
	dock.undocked.connect(func(_craft: Ship, port: int) -> void: events.append("undocked %s" % dock.ports.names[port]))
	var why: Array[String] = []
	var shuttle: Combatant = main.ship_docks.send_craft(dock, &"ea_shuttle", dock.ports.index_of("collar_upper_l"), why)
	assert_not_null(shuttle, "a pooled crew shuttle is sent in: %s" % [why])
	if shuttle == null:
		return
	var craft: Ship = shuttle.ship
	assert_eq(dock.port_of(craft), dock.ports.index_of("collar_upper_l"))
	assert_true(dock.is_taken(dock.port_of(craft)), "its collar is kept for it")
	assert_true(shuttle.driver.in_passage, "the dock flies it, not its pilot")
	assert_eq(dock.refusal(craft), "it is docking here already")
	var nearest: Array[float] = [INF]
	await _fly(200.0, func() -> bool:
		nearest[0] = minf(nearest[0], dock.distance_left(craft))
		return dock.docked_count() == 1)
	assert_eq(events, ["docked collar_upper_l"], "it mated (nearest %.1f m, %s)" % [nearest[0], dock.describe_visits()])
	if dock.docked_count() != 1:
		return
	await wait_physics_frames(5)
	var lock: Dictionary = ShipDock.lock_of(craft)
	var port: int = dock.port_of(craft)
	var hatch: Vector3 = liner.global_transform.affine_inverse() * (craft.global_transform * (lock["position"] as Vector3))
	assert_almost_eq(hatch, dock.ports.positions[port] + dock.ports.outs[port] * float(dock.options["gap_m"]), Vector3.ONE * 0.02,
			"its stern hatch on the collar")
	assert_gt((-craft.global_basis.z).dot(liner.global_basis * dock.ports.outs[port]), 0.999, "nose out, stern to the collar")
	assert_almost_eq(craft.linear_velocity, liner.linear_velocity, Vector3.ONE * 0.01, "moving with the liner")
	assert_eq(shuttle.damageable.hull.fraction(), 1.0, "and it never touched the hull")
	assert_true(dock.is_busy(), "a liner with a visitor stays")
	assert_eq(main.ship_docks.undock_ship(shuttle.display_name), "", "it is sent on its way")
	await _fly(60.0, func() -> bool: return events.size() == 2)
	assert_eq(events, ["docked collar_upper_l", "undocked collar_upper_l"])
	assert_false(shuttle.driver.in_passage, "its pilot has it again")
	assert_eq(dock.free_count(), 4, "the collar is free")
	assert_false(dock.is_busy())
	assert_gt(craft.global_position.distance_to(liner.global_transform * dock.ports.positions[port]), 60.0, "well clear of it")
	assert_eq([dock.dockings, dock.undockings, dock.given_up], [1, 1, 0])
	assert_eq(shuttle.damageable.hull.fraction(), 1.0)


func test_the_player_docks_with_a_hold_of_x_and_leaves_with_another() -> void:
	var liner: CapitalShip = _liner()
	if liner == null:
		return
	var dock: ShipDock = liner.dock
	assert_true(main.ship.targeting.select_id(dock.nav.targetable.get_instance_id()), "the collars can be selected")
	await wait_physics_frames(2)
	assert_eq(main.interactions.prompt_line(), "HOLD X / SHIFT / MOUSE 4: DOCK", "pad and keyboard both named")
	assert_eq(main.interactions.run_offered(), "", "the hold starts the docking")
	assert_eq(main.interactions.last_kind, &"dock")
	assert_true(main.controls_locked(), "the autopilot has the ship")
	assert_eq(main.autopilot_abort.offered(), AutopilotAbort.SHIP_DOCK, "and a hold of X calls it off on the way in")
	await _fly(240.0, func() -> bool: return main.ship_docks.undock_offered())
	var visit: DockVisit = main.ship_docks.player_visit()
	assert_not_null(visit, "the player's visit runs")
	if visit == null:
		return
	assert_eq(visit.state, DockVisit.State.INSIDE, "the player's shuttle is mated: %s" % [dock.describe_visits()])
	assert_true(main.controls_locked(), "mated, the controls stay held")
	assert_eq(main.autopilot_abort.offered(), AutopilotAbort.UNDOCK, "now the hold leaves")
	await wait_physics_frames(3)
	assert_eq(main.autopilot_abort.prompt_line(), "HOLD X / SHIFT / MOUSE 4: UNDOCK")
	assert_almost_eq(main.ship.linear_velocity, liner.linear_velocity, Vector3.ONE * 0.01)
	(main.input_source as FakeInputSource).hold(InputAdapter.AUTOTRACK)
	await _fly(20.0, func() -> bool: return visit.state == DockVisit.State.LAUNCHING)
	(main.input_source as FakeInputSource).release_all()
	assert_eq(visit.state, DockVisit.State.LAUNCHING, "the held X sends it out")
	await _fly(60.0, func() -> bool: return not main.controls_locked())
	assert_false(main.controls_locked(), "clear of the collar the controls come back")
	assert_null(main.ship_docks.player_visit())
	assert_eq([dock.dockings, dock.undockings], [1, 1])
	assert_eq(main.combatant.damageable.hull.fraction(), 1.0, "without a scratch")


func test_a_docking_on_its_way_in_is_aborted_with_the_hold() -> void:
	var liner: CapitalShip = _liner()
	if liner == null:
		return
	var dock: ShipDock = liner.dock
	assert_eq(main.ship_docks.start_player(dock, dock.ports.index_of("collar_lower_r")), "")
	assert_eq(dock.port_of(main.ship), dock.ports.index_of("collar_lower_r"), "the collar asked for")
	await _fly(3.0)
	assert_gt((main.ship.linear_velocity - liner.linear_velocity).length(), 1.0, "the autopilot flies it in")
	assert_eq(main.autopilot_abort.abort(), "", "the abort is taken")
	assert_eq(main.autopilot_abort.last, AutopilotAbort.SHIP_DOCK)
	assert_false(main.controls_locked(), "the controls are back")
	assert_eq([dock.free_count(), dock.given_up], [4, 1])
	assert_eq(main.autopilot_abort.offered(), &"")


func test_a_kestrel_has_no_lock_and_a_taken_collar_is_refused() -> void:
	var liner: CapitalShip = _liner()
	if liner == null:
		return
	var dock: ShipDock = liner.dock
	var why: Array[String] = []
	assert_null(main.ship_docks.send_craft(dock, &"ea_atmo_shuttle", -1, why), "a Kestrel only lands in bays (Q93)")
	assert_string_contains(why[0] if not why.is_empty() else "", "no docking lock")
	assert_eq(dock.free_count(), 4, "and it kept no collar")
	var first: Combatant = main.ship_docks.send_craft(dock, &"ea_shuttle", 0)
	assert_not_null(first)
	if first == null:
		return
	var gave_up: Array[String] = []
	dock.gave_up.connect(func(_craft: Ship, reason: String) -> void: gave_up.append(reason))
	assert_string_contains(main.ship_docks.start_player(dock, 0), "is taken")
	assert_eq(main.ship_docks.dock_ship("player"), "the player docks with a hold of X (shipdock player)")
	assert_string_contains(main.ship_docks.dock_ship(first.display_name), "docking here already")
	assert_string_contains(main.ship_docks.dock_ship("NOBODY"), "no craft")
	assert_eq(main.ship_docks.cancel_ship(first.display_name), "", "a craft on its way in can be called off")
	assert_eq(gave_up, ["cancelled"])
	assert_false(first.driver.in_passage, "its pilot has it again")
	assert_eq(dock.free_count(), 4)
	assert_eq(main.ship_docks.dock_ship(first.display_name, "ea_asimov", "collar_lower_l"), "", "and sent again by name, as a mission does")
	assert_eq(dock.port_of(first.ship), dock.ports.index_of("collar_lower_l"))


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


func test_the_console_lists_the_docks_and_sends_a_shuttle() -> void:
	var liner: CapitalShip = _liner()
	if liner == null:
		return
	var listed: ConsoleResult = _run("shipdock list")
	assert_true(listed.ok, "shipdock list")
	assert_string_contains(listed.lines[0], "4 collars, 4 free")
	assert_true(_run("shipdock hold").ok)
	var sent: ConsoleResult = _run("shipdock send ea_shuttle collar_upper_r")
	assert_true(sent.ok, "shipdock send: %s" % sent.error)
	assert_eq(liner.dock.free_count(), 3)
	assert_false(_run("shipdock send ea_shuttle nowhere").ok, "an unknown collar is an error")
	assert_false(_run("shipdock undock NOBODY").ok)
	assert_eq(int(DebugConsole.registry.read("ship_docks.visiting")["value"]), 1)


func test_a_mission_journals_its_docking_orders() -> void:
	var api := MissionApi.new()
	assert_true(api.dock_at("SHUTTLE 1", "EAS Asimov"))
	assert_true(api.undock("SHUTTLE 1"))
	assert_eq(Array(api.journal.slice(api.journal.size() - 2)), ["dock SHUTTLE 1 at EAS Asimov", "undock SHUTTLE 1"])
