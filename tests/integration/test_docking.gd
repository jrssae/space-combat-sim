extends GutTest
## Docking for repair on the real main scene (M8-T06, D82, AC5), in `station_dock` (the player off Babylon 5's bow with two
## wingmen): the bay offers DOCK only within its reach; a hold of X hands the ship to the autopilot, which flies it through the
## mouth and the inner doors; inside it leaves play, is repaired by a clock set from its damage and launches again from a Cobra
## bay with the controls back; a ship that comes in fast is slowed first; the skip jumps a stage ahead; a cancel gives the ship
## back; a rebase moves nothing; a wingman docks on the order and by itself below the hull threshold, keeps its slot while
## away and rejoins. Flown with the physics rate and the time scale raised together.

const SCENARIO: String = "res://data/scenarios/station_dock.json"
const SPEED_UP: float = 8.0

var main: Main
var station: Station
var source: FakeInputSource
var rams: int = 0
var shots_seen: PackedStringArray = PackedStringArray()
var _rate_backup: int = 60
var _scale_backup: float = 1.0
var _steps_backup: int = 8


func before_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()
	rams = 0
	shots_seen = PackedStringArray()
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	_steps_backup = Engine.max_physics_steps_per_frame


func after_each() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup
	get_tree().paused = false
	ContactScan.invalidate()


func _start(scenario: String = SCENARIO) -> bool:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	source = FakeInputSource.new()
	main.input_source = source
	main.scenario_path = scenario
	main.raider_pool_size = 0
	main.waves_auto_start = false
	add_child_autofree(main)
	await _ticks(2)
	station = main.far_props.station
	if station == null:
		return scenario != SCENARIO  # a scenario without a station is what some tests want
	main.combatant.damageable.hit_taken.connect(func(info: HitInfo) -> void:
		rams += 1 if info != null and info.cause == HitInfo.CAUSE_RAM else 0)
	return true


func _fast() -> void:
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame
		_note_shot()


func _note_shot() -> void:
	var shot: CinematicShot = main.camera_rig.playing_shot() if main != null and is_instance_valid(main) else null
	if shot != null and (shots_seen.is_empty() or shots_seen[-1] != String(shot.id)):
		shots_seen.append(String(shot.id))


# Flies until `done` or `limit_s` of sim time; whether it was done.
func _until(done: Callable, limit_s: float) -> bool:
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < limit_s:
		if done.call():
			return true
		await get_tree().physics_frame
		_note_shot()
	return bool(done.call())


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


func _ship(ship_name: String) -> Combatant:
	for c: Combatant in main.ships.alive():
		if c.display_name == ship_name:
			return c
	return null


func _local(ship: Ship) -> Vector3:
	return station.global_transform.affine_inverse() * ship.global_position


func _speed(ship: Ship) -> float:
	return (ship.linear_velocity - main.world.anchored_velocity()).length()


func _state() -> String:
	return String(DebugConsole.registry.read("dock.player")["value"])


func _damage(c: Combatant, hull_left: float) -> void:
	c.damageable.hull.apply(c.damageable.hull.max_hp * (1.0 - hull_left))


# What the roster says `ship_name` is doing: the director's row and the HUD's line for it.
func _roster(ship_name: String) -> Array[String]:
	var behaviour: String = ""
	for row: Dictionary in main.wings.hud_roster():
		if row["callsign"] == ship_name:
			behaviour = str(row["behaviour"])
	var line: String = ""
	for row: HudLayout.RosterRow in HudLayout.compute(main._build_hud_input()).roster_rows:
		if row.text.begins_with(ship_name):
			line = row.text
	return [behaviour, line]


func _select_bay() -> void:
	assert_true(main.ship.targeting.select_id(station.docking_bay.targetable.get_instance_id()), "the bay can be selected")
	await _ticks(1)


func test_the_bay_offers_docking_only_within_its_reach() -> void:
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	await _select_bay()
	assert_lt(main.ship.global_position.distance_to(station.docking_bay.global_position), Station.BAY_REACH_M, "the scenario starts in reach")
	var offer: TargetInteraction = main.interactions.offer()
	assert_not_null(offer, "within 2 km the bay offers its interaction")
	assert_eq(offer.kind, &"dock")
	assert_true(offer.is_available(), "and it does something now")
	assert_eq(main.interactions.prompt_line(), "HOLD X / SHIFT / MOUSE 4: DOCK")
	# 3 km off the bow: nothing is offered, the line says how close to come, and a hold runs nothing.
	var out: Vector3 = station.docking_bay.global_position + station.global_basis * Vector3(0.0, 0.0, -3000.0)
	main.ship.reset_to(Transform3D(main.ship.global_basis, out))
	await _ticks(2)
	assert_null(main.interactions.offer(), "out of reach nothing is offered")
	assert_string_contains(main.interactions.prompt_line(), "CLOSE TO 2.0 km TO DOCK")
	assert_eq(main.interactions.run_offered(), "nothing to interact with")
	source.hold(InputAdapter.AUTOTRACK)
	await _ticks(140)
	source.release(InputAdapter.AUTOTRACK)
	await _ticks(2)
	assert_null(main.docking.player_visit(), "a hold out of reach docks nobody")
	assert_false(main.controls_locked())


func test_the_player_docks_is_repaired_and_launches_again_from_a_cobra_bay() -> void:
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	var ship: Ship = main.ship
	var hull: HullHealth = main.combatant.damageable.hull
	_damage(main.combatant, 0.4)
	main.cannon.set_charge_fraction(0.1)
	ship.assist_on = false
	await _select_bay()
	var docked: Array[float] = []
	var relaunched: Array[bool] = []
	# What the ship is as it leaves play behind the doors: the hull it came in with, hidden, sheltered, touching nothing.
	var inside: Dictionary = {}
	main.docking.player_docked.connect(func() -> void:
		docked.append(hull.fraction())
		inside.merge({"at_s": SimClock.now(), "visible": ship.visible, "sheltered": ship.inside_station, "layer": ship.collision_layer,
				"active": main.combatant.damageable.is_active(), "doors_shut": station.airlock.doors.is_shut(),
				"repair_s": main.docking.player_visit().repair_s}))
	main.docking.player_relaunched.connect(func() -> void: relaunched.append(true))
	# The real path: X held for the hold time on the selected bay.
	source.hold(InputAdapter.AUTOTRACK)
	await _ticks(130)
	source.release(InputAdapter.AUTOTRACK)
	await _ticks(2)
	assert_eq(main.interactions.last_kind, &"dock")
	assert_eq(main.interactions.last_result, "", "the hold started the docking")
	assert_eq(_state(), "approach")
	assert_true(main.controls_locked(), "the controls are held")
	assert_null(main.interactions.offer(), "and nothing more is offered")
	assert_true(ship.assist_on, "the autopilot flies with the assist on")
	_fast()
	var lock: StationAirlock = station.airlock
	var seen: Dictionary = {"off_axis": 0.0, "open_at_nose": -1.0, "fastest": 0.0}
	var reach: Vector2 = StationAirlock.hull_reach(ship)
	var ok: bool = await _until(func() -> bool:
		if docked.is_empty():
			var local: Vector3 = _local(ship)
			var depth: float = lock.depth_of(local)
			seen["fastest"] = maxf(float(seen["fastest"]), _speed(ship))
			if local.z > main.docking.plan.mouth.z - 60.0:
				seen["off_axis"] = maxf(float(seen["off_axis"]), Vector2(local.x, local.y).length())
			if float(seen["open_at_nose"]) < 0.0 and depth + reach.x >= 0.0:
				seen["open_at_nose"] = lock.doors.fraction
		return not docked.is_empty(), 150.0)
	assert_true(ok, "it docked (%s)" % main.docking.describe())
	if not ok:
		return
	assert_eq(rams, 0, "without touching the station")
	assert_lt(float(seen["off_axis"]), 10.0, "down the middle of the mouth and the tunnel")
	assert_eq(float(seen["open_at_nose"]), 1.0, "the inner doors stood open before its nose reached them")
	assert_lte(float(seen["fastest"]), main.docking.approach_mps + 5.0, "never faster than the approach speed")
	# Inside: out of play behind the shut doors, the damage still on it.
	var visit: DockVisit = main.docking.player_visit()
	assert_false(visit.skipped, "it flew the whole way in")
	assert_true(bool(inside["doors_shut"]), "behind shut doors")
	assert_false(bool(inside["visible"]), "the ship left sight")
	assert_true(bool(inside["sheltered"]), "and was unavailable to everyone outside (M7-T62)")
	assert_false(bool(inside["active"]), "nothing could hit it")
	assert_eq(int(inside["layer"]), 0)
	assert_almost_eq(docked[0], 0.4, 0.01, "it came in with the damage it had")
	# The player does not wait (maintainer, 2026-11-18): repaired on the way through, straight onto a Cobra bay's rack.
	assert_eq(float(inside["repair_s"]), 0.0, "no repair time for the player")
	assert_eq(visit.state, DockVisit.State.LAUNCHING, "the launch has begun (%s)" % main.docking.describe())
	assert_lt(SimClock.now() - float(inside["at_s"]), 0.5, "as it docked: no wait")
	assert_true(main.controls_locked(), "the controls stay held")
	assert_eq(hull.fraction(), 1.0, "a whole hull")
	assert_gt(main.cannon.charge_fraction(), 0.99, "charged guns")
	assert_eq(ship.get_fuel_tank().fraction(), 1.0, "a full tank")
	assert_true(ship.visible, "back in sight, on the rack")
	assert_false(ship.inside_station)
	assert_true(main.launches.locks_controls(), "the launch has it now")
	assert_true(main.launches.filmed_exterior(), "the relaunch is filmed from outside the station (M8-T03)")
	ok = await _until(func() -> bool: return not relaunched.is_empty(), 30.0)
	assert_true(ok, "launched and handed over")
	await _ticks(2)
	assert_false(main.controls_locked(), "the controls are the pilot's again")
	assert_null(main.docking.player_visit())
	assert_eq(main.docking.last_visit.state, DockVisit.State.DONE)
	assert_false(ship.assist_on, "the assist is as the pilot left it")
	assert_ne(ship.collision_layer, 0, "the ship touches things again")
	var handoff: Dictionary = main.launches.last_handoff
	assert_eq(handoff["bay"], "cobra_bay_%s_%d" % [main.docking.relaunch_wing, main.docking.relaunch_door], "from the Cobra bay the data names")
	var radial: Vector3 = _local(ship) - station.drum_origin
	assert_gt(Vector2(radial.x, radial.y).length(), float(station.hardpoints.cobra_arm["door_floor_r"]), "outside the arm's doors")
	assert_gt(_speed(ship), 20.0, "flying, with the rail's speed")
	assert_eq(main.docking.docked_count, 1)
	assert_eq(main.docking.relaunched_count, 1)
	for id: String in ["dock_approach", "dock_entry"]:
		assert_has(shots_seen, id, "the docking's %s shot played" % id)
	assert_does_not_have(shots_seen, "dock_wait", "no repair shot: the docking runs straight into the launch")
	assert_gt(shots_seen.size(), 2, "then the launch's own shots")
	var outside: Array = Array(shots_seen).filter(func(id: String) -> bool: return id.begins_with("ext_"))
	assert_false(outside.is_empty(), "the exterior launch shots played after the dock (%s)" % ", ".join(shots_seen))


func test_a_ship_coming_in_fast_is_slowed_and_still_docks() -> void:
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	var ship: Ship = main.ship
	# 450 m/s across the bow when the docking starts.
	ship.linear_velocity = main.world.anchored_velocity() + station.global_basis * Vector3(450.0, 0.0, 0.0)
	await _ticks(1)
	assert_true(_run("dock player").ok)
	_fast()
	var slowed: bool = await _until(func() -> bool: return _speed(ship) <= main.docking.approach_mps, 60.0)
	assert_true(slowed, "the autopilot sheds the speed it was handed (%.0f m/s left)" % _speed(ship))
	assert_eq(_state(), "approach", "before it takes the lane")
	var ok: bool = await _until(func() -> bool: return main.docking.docked_count == 1, 200.0)
	assert_true(ok, "and it docks all the same (%s)" % main.docking.describe())
	assert_eq(rams, 0, "without touching the station")
	assert_false(main.docking.player_visit().skipped, "flown, not jumped")


func test_the_skip_jumps_a_stage_and_a_cancel_gives_the_ship_back() -> void:
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	var ship: Ship = main.ship
	_damage(main.combatant, 0.5)
	# A cancel outside the doors: the pilot has the ship again, where it is.
	assert_true(_run("dock player").ok)
	await _ticks(30)
	assert_true(main.controls_locked())
	assert_true(main.camera_rig.is_playing_shot())
	assert_true(_run("dock cancel").ok)
	await _ticks(2)
	assert_false(main.controls_locked(), "cancelled: the controls are back")
	assert_null(main.docking.player_visit())
	assert_eq(main.docking.last_visit.state, DockVisit.State.CANCELLED)
	assert_false(main.camera_rig.is_playing_shot(), "and the cinematic ends")
	assert_true(ship.visible)
	assert_almost_eq(main.combatant.damageable.hull.fraction(), 0.5, 0.01, "nothing was repaired")
	assert_false(_run("dock cancel").ok, "nothing left to cancel")
	# The cinematic's skip (Start): straight through the bay onto the launch, then the launch's own skip.
	assert_true(_run("dock player").ok)
	await _ticks(5)
	source.hold(InputAdapter.PAUSE)
	await _ticks(2)
	source.release(InputAdapter.PAUSE)
	await _ticks(2)
	var visit: DockVisit = main.docking.player_visit()
	assert_eq(visit.state, DockVisit.State.LAUNCHING, "the first skip lands on a Cobra bay's rack: no repair to wait for")
	assert_true(visit.skipped)
	assert_eq(main.combatant.damageable.hull.fraction(), 1.0, "repaired on the way through")
	assert_true(ship.visible, "on the rack")
	assert_false(get_tree().paused, "Start skipped the shot, it did not pause")
	var refused: ConsoleResult = _run("dock cancel")
	assert_false(refused.ok, "inside, it cannot be called off")
	assert_string_contains(refused.error, "inside the station")
	await _ticks(30)  # the launch's first shot comes up
	source.hold(InputAdapter.PAUSE)
	await _ticks(2)
	source.release(InputAdapter.PAUSE)
	assert_true(await _until(func() -> bool: return main.docking.player_visit() == null, 15.0), "the second skips the launch")
	await _ticks(2)
	assert_false(main.controls_locked(), "skipped through: the controls are back")
	assert_false(main.launches.last_handoff.is_empty(), "at the launch's hand-off")
	assert_true(ship.visible)
	assert_ne(ship.collision_layer, 0)


func test_a_respawn_ends_a_docking_wherever_it_is() -> void:
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	# On the way in: the pilot has the ship again at once.
	assert_true(_run("dock player").ok)
	await _ticks(30)
	main.respawn()
	await _ticks(3)
	assert_null(main.docking.player_visit(), "the respawn ends the visit")
	assert_eq(main.docking.last_visit.cancel_reason, "respawn")
	assert_true(main.ship.visible)
	assert_false(main.ship.inside_station)
	assert_ne(main.ship.collision_layer, 0)
	assert_false(main.ship.clamped)
	assert_false(main.controls_locked())
	# Skipped onto the rack: the visit ends too, and the launch under way lets the ship go as any launch does.
	assert_true(_run("dock player").ok)
	await _ticks(3)
	assert_true(_run("dock skip").ok)
	await _ticks(2)
	assert_eq(_state(), "launching")
	main.respawn()
	await _ticks(3)
	assert_null(main.docking.player_visit())
	assert_true(await _until(func() -> bool: return not main.controls_locked(), 20.0), "handed over by the launch")
	assert_true(main.ship.visible)
	assert_false(main.ship.inside_station)
	assert_ne(main.ship.collision_layer, 0)


func test_a_rebase_during_docking_moves_nothing() -> void:
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	var ship: Ship = main.ship
	assert_true(_run("dock player").ok)
	_fast()
	assert_true(await _until(func() -> bool: return _state() == "lane", 120.0), "on the lane (%s)" % main.docking.describe())
	var before: Vector3 = _local(ship)
	var target: Vector3 = station.global_transform.affine_inverse() * (station.global_transform * main.docking.plan.airlock)
	main.world.rebase(Vector3(4000.0, -1500.0, 2500.0))
	assert_almost_eq(_local(ship), before, Vector3.ONE * 1e-2, "the ship stays where it was on the lane")
	assert_almost_eq(main.docking.plan.airlock, target, Vector3.ONE * 1e-3, "the lane is the station's, not the World's")
	var ok: bool = await _until(func() -> bool: return main.docking.docked_count == 1, 120.0)
	assert_true(ok, "and it docks all the same (%s)" % main.docking.describe())
	assert_false(main.docking.player_visit().skipped)
	assert_eq(rams, 0)


func test_wingmen_dock_on_the_order_and_below_the_hull_threshold_and_rejoin() -> void:
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	var wing: Wing = main.wings.player_wing()
	var two: Combatant = _ship("ALPHA 2")
	var three: Combatant = _ship("ALPHA 3")
	assert_not_null(two)
	assert_not_null(three)
	var slot_two: int = wing.slot_of(two)
	var slot_three: int = wing.slot_of(three)
	var pilot_two: PilotBrain = two.driver.brain
	var pilot_three: PilotBrain = three.driver.brain
	var wing_rams: Array[int] = [0]
	for c: Combatant in [two, three]:
		c.damageable.hit_taken.connect(func(info: HitInfo) -> void:
			wing_rams[0] += 1 if info != null and info.cause == HitInfo.CAUSE_RAM else 0)
	# Nobody damaged: the order is refused, by the key (6) and by the comms menu alike.
	source.hold(InputAdapter.WING_DOCK, 1.0, true)
	await _ticks(2)
	source.release(InputAdapter.WING_DOCK)
	await _ticks(1)
	assert_string_contains(main.docking.last_notice, "NO DAMAGE TO REPAIR")
	assert_eq(main.docking.visits().size(), 0)
	assert_string_contains(HudLayout.compute(main._build_hud_input()).ack_line, "NO DAMAGE TO REPAIR", "the answer is on the HUD's line")
	# ALPHA 2 is hurt but above the threshold: it goes on the order (the comms menu's DOCK).
	_damage(two, 0.7)
	await _ticks(2)
	assert_null(main.docking.visit_of("ALPHA 2"), "above the threshold it stays until ordered")
	assert_true(_run("commsmenu open").ok)
	assert_true(_run("commsmenu pick dock").ok)
	await _ticks(2)
	assert_eq(main.docking.last_notice, "ALPHA 2: COPY, DOCKING FOR REPAIRS")
	assert_eq(main.docking.visit_of("ALPHA 2").why, DockVisit.WHY_ORDER)
	assert_null(main.docking.visit_of("ALPHA 3"), "an undamaged wingman stays")
	assert_ne(two.driver.brain, pilot_two, "a docking pilot flies it in")
	assert_eq(_roster("ALPHA 2")[0], "docking", "the roster says so while it flies in")
	assert_string_ends_with(_roster("ALPHA 2")[1], "DOCKING", "on the HUD too")
	assert_ne(_roster("ALPHA 3")[0], "docking", "the others read as they did")
	# ALPHA 3 falls below the threshold (a quarter of its hull: maintainer, 2026-11-18): it goes by itself and says so.
	assert_almost_eq(main.docking.wingman_hull_below, 0.25, 1e-6, "the threshold is the data's")
	_damage(three, 0.3)
	await _ticks(2)
	assert_null(main.docking.visit_of("ALPHA 3"), "at 30 % it fights on")
	three.damageable.hull.apply(three.damageable.hull.max_hp * 0.15)
	await _ticks(2)
	assert_lt(three.damageable.hull.fraction(), 0.25)
	assert_eq(main.docking.visit_of("ALPHA 3").why, DockVisit.WHY_HULL)
	assert_eq(main.docking.last_notice, "ALPHA 3: HULL CRITICAL, DOCKING FOR REPAIRS")
	_fast()
	var docked := PackedStringArray()
	var rejoined := PackedStringArray()
	var docked_at: Dictionary = {}
	var inside_s: Dictionary = {}
	main.docking.wingman_docked.connect(func(ship_name: String) -> void:
		docked.append(ship_name)
		docked_at[ship_name] = SimClock.now())
	main.docking.wingman_rejoined.connect(func(ship_name: String) -> void:
		rejoined.append(ship_name)
		inside_s[ship_name] = SimClock.now() - float(docked_at[ship_name]))
	var both_on_lane: Array[bool] = [false]
	var away_checked: Array[bool] = [false]
	var ok: bool = await _until(func() -> bool:
		var on_lane: int = 0
		for visit: DockVisit in main.docking.visits():
			on_lane += 1 if visit.state == DockVisit.State.LANE or visit.state == DockVisit.State.INSIDE else 0
		both_on_lane[0] = both_on_lane[0] or on_lane > 1
		if not away_checked[0] and not docked.is_empty():
			away_checked[0] = true
			var first: Combatant = two if docked[0] == "ALPHA 2" else three
			assert_true(wing.is_away(first), "inside, it is away")
			assert_eq(wing.slot_of(first), slot_two if first == two else slot_three, "with its slot kept")
			assert_false(wing.is_lost(wing.slot_of(first)), "not lost")
			assert_eq(_roster(first.display_name)[0], "docked", "the roster says it is inside")
			assert_string_ends_with(_roster(first.display_name)[1], "DOCKED")
			var other: Combatant = three if first == two else two
			assert_eq(wing.slot_of(other), slot_three if first == two else slot_two, "and the formation does not close over its place")
			assert_false(first.ship.visible, "out of play")
			assert_true(first.ship.inside_station)
			assert_lt(first.damageable.hull.fraction(), 1.0, "its repair has only begun")
			assert_eq(main.docking.visit_of(first.display_name).repair_s, 30.0, "an AI wingman waits a fixed 30 s (maintainer)")
			assert_lt(_local(first.ship).distance_to(main.docking.plan.airlock), 1.0, "held in the void behind the doors")
			main.world.rebase(Vector3(-900.0, 300.0, 1200.0))
			assert_lt(_local(first.ship).distance_to(main.docking.plan.airlock), 1.0, "and stays there through a rebase")
		return rejoined.size() == 2, 420.0)
	assert_true(ok, "both docked, were repaired and launched again (%s)" % main.docking.describe())
	if not ok:
		return
	assert_false(both_on_lane[0], "one at a time through the tunnel")
	assert_eq(wing_rams[0], 0, "without touching the station or each other")
	assert_eq(docked.size(), 2)
	for ship_name: String in docked:
		assert_gte(float(inside_s[ship_name]), 30.0, "%s was inside 30 s before its launch (the player waits none)" % ship_name)
	for pair: Array in [[two, pilot_two, slot_two], [three, pilot_three, slot_three]]:
		var c: Combatant = pair[0]
		assert_eq(c.damageable.hull.fraction(), 1.0, "%s is whole again" % c.display_name)
		assert_eq(c.driver.brain, pair[1], "%s has its own pilot back" % c.display_name)
		assert_eq(wing.slot_of(c), pair[2], "%s flies its old slot" % c.display_name)
		assert_false(wing.is_away(c))
		assert_false(_roster(c.display_name)[0].begins_with("dock"), "%s reads as any wingman again" % c.display_name)
		assert_true(c.ship.visible)
		assert_false(c.ship.inside_station)
		assert_ne(c.ship.collision_layer, 0)
	assert_eq(main.docking.visits().size(), 0)
	# Back with the wing: under FORM ON ME they close on the leader again.
	var leader: Ship = main.ship
	var far: float = two.ship.global_position.distance_to(leader.global_position)
	ok = await _until(func() -> bool:
		return two.ship.global_position.distance_to(leader.global_position) < 600.0 \
				and three.ship.global_position.distance_to(leader.global_position) < 600.0, 240.0)
	assert_true(ok, "they rejoin the leader (ALPHA 2 from %.0f m, now %.0f m and %.0f m)" % [far,
			two.ship.global_position.distance_to(leader.global_position), three.ship.global_position.distance_to(leader.global_position)])
	assert_eq(wing_rams[0], 0)


func _press_dock_key() -> void:
	source.hold(InputAdapter.WING_DOCK, 1.0, true)
	await _ticks(2)
	source.release(InputAdapter.WING_DOCK)
	await _ticks(1)


func test_a_fighter_docks_only_at_its_own_home_dock() -> void:
	# Maintainer, 2026-11-18: each fighter has a home (the scenario's `home`, or the station whose bays launched it).
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	var two: Combatant = _ship("ALPHA 2")
	var three: Combatant = _ship("ALPHA 3")
	assert_eq(main.combatant.home, Station.HOME_ID, "the scenario's player.home")
	assert_eq(two.home, Station.HOME_ID, "the wing's home goes to its members")
	assert_eq(main.docking.home_dock(two), station.docking_bay, "found among the docks by its id")
	assert_eq(main.docking.dock_refusal(two), "")
	# A Starfury that belongs to a capital ship does not dock at Babylon 5, however hurt.
	three.home = &"hyperion"
	_damage(three, 0.1)
	await _ticks(5)
	assert_null(main.docking.visit_of("ALPHA 3"), "its home is elsewhere: it stays and fights")
	var refused: ConsoleResult = _run("dock wing ALPHA 3")
	assert_false(refused.ok)
	assert_string_contains(refused.error, "home dock (hyperion) is not here")
	assert_ne(_roster("ALPHA 3")[0], "docking")
	# Nor one the scenario assigned to nothing.
	three.home = &""
	await _ticks(5)
	assert_null(main.docking.visit_of("ALPHA 3"))
	assert_string_contains(_run("dock wing ALPHA 3").error, "has no home dock")
	# The player too: the bay offers DOCK only to its own.
	await _select_bay()
	assert_not_null(main.interactions.offer(), "Babylon 5's own pilot is offered the bay")
	main.combatant.home = &"hyperion"
	assert_null(main.interactions.offer(), "a visitor is not")
	assert_false(_run("dock player").ok)
	main.combatant.home = Station.HOME_ID
	# Tied to Babylon 5 again, the hurt wingman goes by itself.
	three.home = Station.HOME_ID
	await _ticks(3)
	assert_eq(main.docking.visit_of("ALPHA 3").why, DockVisit.WHY_HULL, "Babylon 5's own wingman near Babylon 5 docks")


func test_with_the_home_dock_out_of_range_they_fight_on_and_the_order_cannot_be_given() -> void:
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	var two: Combatant = _ship("ALPHA 2")
	var pilot: PilotBrain = two.driver.brain
	assert_almost_eq(main.docking.dock_range_m, 60000.0, 1.0, "the range is the data's: the station's space out to its jumpgate")
	assert_true(main.docking.order_available(), "1.2 km from the bay the order can be given")
	assert_true(_run("commsmenu open").ok)
	assert_has(DebugConsole.registry.read("comms_menu.entries")["value"], "dock", "and DOCK is on the ring")
	assert_true(_run("commsmenu close").ok)
	main.docking.dock_range_m = 500.0  # the bay is 1.2 km off: out of range now
	_damage(two, 0.1)
	await _ticks(5)
	assert_null(main.docking.visit_of("ALPHA 2"), "below 25 % with no dock in range it stays and fights")
	assert_eq(two.driver.brain, pilot, "its own pilot flies on")
	assert_false(main.docking.order_available())
	var notice: String = main.docking.last_notice
	await _press_dock_key()
	assert_eq(main.docking.last_notice, notice, "key 6 does nothing: no order, no answer")
	assert_eq(main.docking.visits().size(), 0)
	assert_true(_run("commsmenu open").ok)
	assert_does_not_have(DebugConsole.registry.read("comms_menu.entries")["value"], "dock", "the menu leaves DOCK out")
	assert_eq(DebugConsole.registry.read("comms_menu.entries")["value"].size(), 6, "its slice leaves the ring with it (M8-T24)")
	assert_does_not_have(DebugConsole.registry.read("comms_menu.entries")["value"], "-", "no blank slice")
	assert_false(_run("commsmenu pick dock").ok, "so it cannot be picked")
	assert_true(_run("commsmenu close").ok)
	assert_false(_run("dock wing").ok, "the console is told why")
	assert_eq(main.docking.last_notice, "ALPHA 2: NEGATIVE, NO DOCK IN RANGE")
	# In range again: the same wingman goes.
	main.docking.dock_range_m = 60000.0
	await _ticks(3)
	assert_not_null(main.docking.visit_of("ALPHA 2"), "with its home dock in range it docks")


func test_without_a_station_a_hurt_wingman_keeps_fighting() -> void:
	# The dock scenario with no station placed: the wing still names Babylon 5 as its home, but that dock is not here.
	assert_true(await _start("res://tests/fixtures/docking/no_dock_wing.json"))
	assert_null(main.docking.station(), "no station in this scenario")
	var wing: Wing = main.wings.player_wing()
	var member: Combatant = _ship("ALPHA 2")
	assert_eq(member.home, Station.HOME_ID)
	var pilot: PilotBrain = member.driver.brain
	_damage(member, 0.1)
	await _ticks(10)
	assert_eq(main.docking.visits().size(), 0, "no dock, no docking")
	assert_eq(member.driver.brain, pilot, "it flies on under its own pilot")
	assert_eq(wing.slot_of(member), 1)
	assert_string_contains(main.docking.dock_refusal(member), "is not here")
	assert_false(main.docking.order_available())
	await _press_dock_key()
	assert_eq(main.docking.last_notice, "", "key 6 does nothing")
	assert_true(_run("commsmenu open").ok)
	assert_does_not_have(DebugConsole.registry.read("comms_menu.entries")["value"], "dock", "the menu leaves DOCK out")
	assert_true(_run("commsmenu close").ok)
	assert_false(_run("dock wing").ok)
	assert_ne(_roster(member.display_name)[0], "docking")


func test_ships_launched_from_the_cobra_bays_belong_to_the_station() -> void:
	assert_true(await _start("res://data/scenarios/station_launch.json"))
	if station == null:
		pending("the babylon5_station asset is not generated")
		return
	assert_eq(main.combatant.home, Station.HOME_ID, "the player on Alpha 3's rack")
	assert_eq(main.wings.player_wing().home, Station.HOME_ID, "and its wing")
	for member: Combatant in main.wings.player_wing().members():
		assert_eq(member.home, Station.HOME_ID, "%s on the next rack" % member.display_name)
	assert_true(_run("launch wing beta").ok)
	await _ticks(2)
	var beta: Wing = main.wings.wing_named("BETA")
	assert_eq(beta.home, Station.HOME_ID, "a station wing")
	assert_eq(beta.leader.home, Station.HOME_ID)


func test_an_ai_flight_docks_by_itself_and_keeps_the_docked_ships_place() -> void:
	# Maintainer, 2026-11-18: Babylon 5's own flights of three dock below 25 % like the player's wingmen.
	assert_true(await _start("res://data/scenarios/station_launch.json"))
	if station == null:
		pending("the babylon5_station asset is not generated")
		return
	assert_true(_run("launch wing beta").ok)
	_fast()
	assert_true(await _until(func() -> bool: return not main.launches.is_launching("beta"), 90.0), "Beta is away")
	var flights: Array[Wing] = main.wings.flights_of("BETA")
	assert_gt(flights.size(), 1, "Beta flies in flights of three")
	var flight: Wing = flights[0]
	var lead: Combatant = flight.leader
	var wingman: Combatant = flight.member_at(1)
	var mate: Combatant = flight.member_at(2)
	assert_eq(wingman.home, Station.HOME_ID, "launched from Babylon 5: it is its home")
	var notice: String = main.docking.last_notice
	# A wingman of an AI flight: it goes by itself, and its flight keeps its place.
	_damage(wingman, 0.15)
	await _ticks(3)
	assert_not_null(main.docking.visit_of(wingman.display_name), "below 25 % with its home in range it goes to dock")
	assert_eq(main.docking.visit_of(wingman.display_name).why, DockVisit.WHY_HULL)
	assert_true(flight.is_docking(wingman))
	assert_eq(main.docking.last_notice, notice, "an AI flight says nothing on the player's HUD")
	# A flight's lead: the flight goes on under its first wingman, and the old lead docks as one of its wingmen.
	var other: Wing = flights[1]
	var old_lead: Combatant = other.leader
	var heir: Combatant = other.member_at(1)
	_damage(old_lead, 0.15)
	await _ticks(3)
	assert_eq(other.leader, heir, "its first wingman leads on")
	assert_gt(other.slot_of(old_lead), 0, "the old lead has a place in its flight")
	assert_not_null(main.docking.visit_of(old_lead.display_name), "and is on its way to the bay")
	# A whole fighter of the same flight stays.
	assert_null(main.docking.visit_of(mate.display_name))
	var ok: bool = await _until(func() -> bool: return flight.is_away(wingman), 400.0)
	assert_true(ok, "it docked (%s)" % main.docking.describe())
	if not ok:
		return
	assert_eq(flight.slot_of(wingman), 1, "its place in the flight is kept while it is inside")
	assert_false(flight.is_lost(1), "it is not lost")
	assert_eq(flight.slot_of(mate), 2, "nobody closed up over it")
	assert_eq(flight.leader, lead)
	assert_eq(main.docking.visit_of(wingman.display_name).repair_s, 30.0, "an AI wingman's fixed 30 s")
