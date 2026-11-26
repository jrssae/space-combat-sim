extends GutTest
## The station's run in free flight (M7-T56, maintainer's m5-056: "Civilian traffic did not appear to go from Babylon 5 to the
## jumpgate and back. it instead was in strange places. needs to be a bit busier"): the run starts full, its civilians spread
## between the gate and the station, arriving ones flying at the station and leaving ones at the gate; a ship leaving after its lane
## flies on to the gate instead of being let go where its lane ended; it refills one ship at a time; an encounter's traffic event
## joins it as a convoy past the player's radar, heading for the station, its Saturn 3 a civilian on the radar (never an ally);
## an encounter raid drawn for the station goes for it and its wing is scrambled. Flown with the physics rate and the time scale
## raised together.

const SPEED_UP: float = 8.0
const SHIPPED_POOLS: String = "res://data/encounters/free_flight.json"
## A point put on the run lies on its side of the line from a lane's first point to the gate, within float rounding at 50 km.
const ON_RUN_M: float = StationTraffic.RUN_SIDE_M + 5.0

var main: Main
var _rate_backup: int = 60
var _scale_backup: float = 1.0
var _steps_backup: int = 8


func before_each() -> void:
	get_tree().paused = false
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	_steps_backup = Engine.max_physics_steps_per_frame


func after_each() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup
	DebugConsole.flags.invulnerable = false
	get_tree().paused = false


func _start(encounters_on: bool = false) -> bool:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.scenario_seed = 5
	main.encounters = encounters_on
	main.encounter_pools_path = SHIPPED_POOLS
	add_child_autofree(main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if main.far_props.station == null or main.gates.gate() == null or not main.traffic.lanes_ready():
		return false
	main.combatant.damageable.invulnerable = true
	return true


func _fast() -> void:
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))


# Flies until `done` or `limit_s` of sim time; whether it was done.
func _until(done: Callable, limit_s: float) -> bool:
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < limit_s:
		if done.call():
			return true
		await get_tree().physics_frame
	return bool(done.call())


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


func _lane_start(lane: Array[Dictionary]) -> Vector3:
	return main.far_props.station.global_transform * (lane[0]["at"] as Vector3)


# Distance from `p` to the run from the nearer of the two lanes' first points to the gate.
func _off_run(p: Vector3) -> float:
	var gate: Vector3 = main.gates.gate().global_position
	var best: float = INF
	for lane: Array[Dictionary] in [main.traffic.plan.dock_in, main.traffic.plan.freighter]:
		var closest: Vector3 = Geometry3D.get_closest_point_to_segment(p, _lane_start(lane), gate)
		best = minf(best, p.distance_to(closest))
	return best


# The unit direction `c` flies in, against the World's rest.
func _heading(c: Combatant) -> Vector3:
	return (c.ship.linear_velocity - main.world.rest_velocity()).normalized()


# Where `c`'s route takes it next (World).
func _next_waypoint(c: Combatant) -> Vector3:
	var route: Route = ((c.driver as AiPilotDriver).brain as AiPilot).context.route
	return main.world.universe_to_local(route.waypoint(0).position)


func test_the_run_starts_full_its_civilians_between_the_gate_and_the_station() -> void:
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	assert_true(_run("traffic auto on").ok)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var traffic: StationTraffic = main.traffic
	var ships: Array[Combatant] = traffic.ships(true)
	assert_eq(ships.size(), traffic.lane_ships, "%d civilians on the run from the start" % traffic.lane_ships)
	var gate: Vector3 = main.gates.gate().global_position
	var arriving: int = 0
	var leaving: int = 0
	for c: Combatant in ships:
		assert_true(ShipCatalog.is_civilian(main.ships.type_of(c)), "%s is a civilian hull" % c.display_name)
		assert_lt(_off_run(c.ship.global_position), ON_RUN_M, "%s is on the run between the gate and the station" % c.display_name)
		match traffic.state_of(c):
			&"transit":
				arriving += 1
				var entry: Vector3 = _next_waypoint(c)
				assert_lt(entry.distance_to(main.far_props.station.global_position), 12000.0, "%s is bound for the station" % c.display_name)
				assert_gt(_heading(c).dot((entry - c.ship.global_position).normalized()), 0.99, "%s flies at it" % c.display_name)
			&"leave":
				leaving += 1
				var out: Vector3 = _next_waypoint(c)
				assert_lt(out.distance_to(gate), StationTraffic.GATE_CLEAR_M + StationTraffic.RUN_SIDE_M + 1.0,
						"%s is bound for the gate" % c.display_name)
				assert_gt(_heading(c).dot((out - c.ship.global_position).normalized()), 0.99, "%s flies at it" % c.display_name)
			_:
				fail_test("%s is neither arriving nor leaving: %s" % [c.display_name, traffic.state_of(c)])
	assert_gte(arriving, 2, "arrivals")
	assert_gte(leaving, 2, "and departures")


func test_a_ship_leaving_after_its_lane_flies_on_to_the_gate() -> void:
	# The bug (m5-056): a route given after the lane took the lane's end for its own, so the ship was let go 5 km out.
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	assert_true(_run("traffic undock skylark_transport").ok)
	var c: Combatant = main.traffic.last_ship()
	_fast()
	assert_true(await _until(func() -> bool: return main.traffic.state_of(c) == &"leave", 240.0), "it flew its lane out")
	var gate: Vector3 = main.gates.gate().global_position
	var from_gate: float = c.ship.global_position.distance_to(gate)
	var undocked: int = main.traffic.undocked_count
	await _until(func() -> bool: return false, 90.0)
	assert_eq(main.traffic.state_of(c), &"leave", "still on its way 90 s later")
	assert_eq(main.traffic.undocked_count, undocked, "not let go where its lane ended")
	assert_lt(c.ship.global_position.distance_to(gate), from_gate - 1000.0, "closing on the gate")


func test_ships_coming_in_along_the_run_queue_and_dock_without_touching_the_station() -> void:
	# The bugs (M7-T56): a ship crossing the lane's axis at 120 m/s overshot its first point and rammed the drum beside the mouth;
	# two arrivals met at one entry point, and a docking ship met an undocking one in the tunnel.
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	var traffic: StationTraffic = main.traffic
	# Joined 10 km out on the run, 800 m apart (the run's own placing), so the test flies the approach, not the whole 50 km.
	var length: float = traffic._run_length(traffic.plan.dock_in)
	var ships: Array[Combatant] = [traffic._join_inbound(&"centauri_brezebel", 10000.0 / length, {}),
			traffic._join_inbound(&"skylark_transport", 10800.0 / length, {})]
	var entries: Array[Vector3] = [_next_waypoint(ships[0]), _next_waypoint(ships[1])]
	assert_almost_eq(entries[0].distance_to(entries[1]), StationTraffic.QUEUE_SPACING_M, 1.0, "each waits at its own place")
	var rams: Array[int] = [0]
	var both_on_lane: Array[bool] = [false]
	for c: Combatant in ships:
		c.damageable.hit_taken.connect(func(_info: HitInfo) -> void: rams[0] += 1)
	_fast()
	assert_true(await _until(func() -> bool:
		if traffic.state_of(ships[0]) == &"lane" and traffic.state_of(ships[1]) == &"lane":
			both_on_lane[0] = true
		return traffic.docked_count >= 2 or rams[0] > 0, 900.0), "both docked")
	assert_eq(traffic.docked_count, 2)
	assert_eq(rams[0], 0, "without touching the bay, its doors or each other")
	assert_false(both_on_lane[0], "one at a time on the bay's lane")


func test_a_new_route_starts_at_its_first_waypoint() -> void:
	var made: Dictionary = BrainFactory.from_behaviour({"type": "ai", "profile": "civilian"}, UniversePos.new(0.0, 0.0, 0.0), 1)
	var pilot := made["brain"] as AiPilot
	var first := Route.new()
	first.add(UniversePos.new(0.0, 0.0, -1000.0))
	var b: BehaviourFollowPath = BehaviourFollowPath.attach(pilot, first)
	b.phase = BehaviourFollowPath.Phase.DONE
	b.index = 1
	assert_eq(BehaviourFollowPath.attach(pilot, first), b, "the same route again")
	assert_eq(b.phase, BehaviourFollowPath.Phase.DONE, "keeps its progress")
	var second := Route.new()
	second.add(UniversePos.new(0.0, 0.0, -9000.0))
	BehaviourFollowPath.attach(pilot, second)
	assert_eq(b.phase, BehaviourFollowPath.Phase.LEAD, "another route is flown from the start")
	assert_eq(b.index, 0)


func test_the_run_refills_one_ship_at_a_time() -> void:
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	assert_true(_run("traffic auto on").ok)
	await get_tree().physics_frame
	var traffic: StationTraffic = main.traffic
	traffic.clear()
	var events: int = traffic.events
	_fast()
	assert_true(await _until(func() -> bool: return traffic.events > events, traffic.lane_spacing_s + 1.0), "one more starts")
	assert_eq(traffic.events, events + 1)
	assert_eq(traffic.flow_count(), 1, "one ship on its way (or asked of the gate)")
	await _until(func() -> bool: return false, traffic.lane_spacing_s - 2.0)
	assert_eq(traffic.events, events + 1, "and the next only after the spacing")


func test_an_encounter_convoy_joins_the_run_past_the_radar_heading_for_the_station() -> void:
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	var e := EncounterEvent.new()
	e.index = 3
	e.kind = &"traffic"
	e.types.assign([&"saturn_3_freighter", &"skylark_transport", &"brakiri_bokmai"])
	var traffic: StationTraffic = main.traffic
	var before: int = traffic.alive_count()
	assert_true(traffic.lane_event(e, 5))
	assert_eq(traffic.alive_count(), before + 3, "three ships on the run")
	var convoy: Array[Combatant] = traffic.ships().slice(before)
	var saturn: Combatant = null
	for c: Combatant in convoy:
		var type: StringName = main.ships.type_of(c)
		assert_eq(traffic.state_of(c), &"transit", "%s arrives" % c.display_name)
		assert_lt(_off_run(c.ship.global_position), ON_RUN_M, "%s on the run" % c.display_name)
		assert_gte(c.ship.global_position.distance_to(main.ship.global_position), StationTraffic.JOIN_CLEAR_OF_PLAYER_M - 1.0,
				"%s joins it past the radar" % c.display_name)
		var entry: Vector3 = _next_waypoint(c)
		assert_lt(entry.distance_to(main.far_props.station.global_position), 12000.0, "%s is bound for the station" % c.display_name)
		assert_gt(_heading(c).dot((entry - c.ship.global_position).normalized()), 0.99, "%s flies at it" % c.display_name)
		if type == &"saturn_3_freighter":
			saturn = c
		else:
			assert_true(DockingPlan.tunnel_types().has(type), "%s fits the docking tunnel" % type)
	assert_not_null(saturn, "the Saturn 3 goes to the cargo bay")
	if saturn == null:
		return
	assert_eq(traffic.alive_of(&"freighter"), 1)
	assert_eq(saturn.faction, Factions.EARTH_ALLIANCE, "its people's faction (Q24)")
	assert_eq(saturn.targetable.role, Targetable.Role.CIVILIAN, "with the civilian role")
	await get_tree().physics_frame
	var contacts: RadarContacts = RadarContacts.gather(get_tree(), main.ship, 100000.0)
	var k: int = contacts.ids.find(saturn.targetable.get_instance_id())
	assert_gte(k, 0, "on the radar's rows")
	if k < 0:
		return
	assert_eq(contacts.civilian[k], 1, "the core knows it for a civilian")
	var colour: Color = Color.BLACK
	# Seen from 1 km off it, inside the radar's reach.
	var plot: RadarPlot = RadarModel.plot(contacts, 0, saturn.ship.global_position + Vector3(0.0, 0.0, 1000.0), Basis.IDENTITY,
			main.combatant.faction, 0, INF)
	for dot: RadarModel.Dot in plot.to_dots():
		if dot.id == saturn.targetable.get_instance_id():
			colour = dot.color
	assert_eq(colour, Factions.CIVILIAN_COLOR, "drawn as a civilian, not an ally")


func test_a_convoys_visitors_that_do_not_dock_fly_out_to_the_gate_as_themselves() -> void:
	# M10 Q97: the Centauri shuttle and the Flyer are free flight's traffic, each of its own faction.
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	var e := EncounterEvent.new()
	e.index = 4
	e.kind = &"traffic"
	e.types.assign([&"minbari_flyer", &"centauri_shuttle"])
	for type: StringName in e.types:
		if not Hardpoints.load_file(ShipCatalog.spec_for(type).hardpoints_path()).valid:
			pending("%s is not generated" % type)
			return
	var traffic: StationTraffic = main.traffic
	var before: int = traffic.alive_count()
	assert_true(traffic.lane_event(e, 5))
	var convoy: Array[Combatant] = traffic.ships().slice(before)
	assert_eq(convoy.size(), 2, "both on the run")
	var factions: Dictionary = {&"minbari_flyer": &"minbari", &"centauri_shuttle": &"centauri"}
	for k: int in convoy.size():
		var c: Combatant = convoy[k]
		assert_eq(main.ships.type_of(c), e.types[k], "no tunnel hull stands in for it")
		assert_eq(c.faction, factions[e.types[k]], "of its own people")
		assert_eq(c.targetable.role, Targetable.Role.CIVILIAN)
		assert_eq(traffic.state_of(c), &"leave", "%s is on its way out" % c.display_name)
		assert_lt(_off_run(c.ship.global_position), ON_RUN_M, "%s on the run" % c.display_name)
		assert_gt(_heading(c).dot((main.gates.gate().global_position - c.ship.global_position).normalized()), 0.9,
				"%s flies for the gate" % c.display_name)


func test_an_encounter_raid_drawn_for_the_station_goes_for_it_and_scrambles_its_wing() -> void:
	DebugConsole.flags.invulnerable = true
	if not await _start(true):
		pending("the babylon5_station asset is not generated")
		return
	var director: EncounterDirector = main.encounter_director
	assert_true(director.station_run, "the shipped pools put traffic on the run")
	assert_eq(main.ships.free_count(ShipPool.ALLY_TYPE), 24, "the encounters' 12 Starfuries on top of the wing the station keeps")
	var e: EncounterEvent = null
	for i: int in 400:
		var drawn: EncounterEvent = director.plan.event(EncounterDirector.FORCED_INDEX + i, &"raid")
		if drawn.at_station:
			e = drawn
			break
	assert_not_null(e, "the shipped share draws raids for the station")
	if e == null:
		return
	assert_true(director.start(e))
	var station: Station = main.far_props.station
	for c: Combatant in director.alive():
		if main.ships.type_of(c) != ShipPool.DEFAULT_TYPE:
			continue
		var pilot := c.driver.brain as AiPilot
		assert_eq(pilot.context.objective_name, Station.DISPLAY_NAME, "%s goes for the station" % c.display_name)
		assert_between(c.ship.global_position.distance_to(station.global_position), 11000.0, 17200.0,
				"%s comes out clear of its hull" % c.display_name)
	assert_true(main.launches.is_launching("alpha") or main.launches.has_flown("alpha"), "its wing scrambled")


# Council round 1 (O6): an encounter's convoy on the run counts against the encounters' cap, as their other ships do: one
# that would pass it waits, as a raid does.
func test_an_encounter_convoy_on_the_run_holds_no_slot_under_the_cap() -> void:
	# Maintainer, 2026-11-21: the run's civilians are bounded by their pools; counting them stalled the encounter schedule.
	var cap_backup: Variant = Settings.get_value(&"encounter_max_ships")
	Settings.set_value(&"encounter_max_ships", 4)
	if not await _start(true):
		Settings.set_value(&"encounter_max_ships", cap_backup)
		pending("the babylon5_station asset is not generated")
		return
	var director: EncounterDirector = main.encounter_director
	var traffic: StationTraffic = main.traffic
	var first := EncounterEvent.new()
	first.index = 3
	first.kind = &"traffic"
	first.types.assign([&"skylark_transport", &"brakiri_bokmai", &"skylark_transport"])
	assert_true(director.start(first))
	assert_eq(traffic.encounter_count(), 3, "three ships of the encounters on the run")
	var second := EncounterEvent.new()
	second.index = 4
	second.kind = &"traffic"
	second.types.assign([&"skylark_transport", &"brakiri_bokmai"])
	assert_true(director.start(second), "the first convoy holds no slot: the second joins too")
	assert_eq(traffic.encounter_count(), 5)
	var raid: EncounterEvent = director.plan.event(EncounterDirector.FORCED_INDEX + 700, &"raid")
	assert_true(director.start(raid), "and a raid is not held back by the convoys")
	assert_lte(director.alive_count(), 4, "the raid itself keeps to the cap")
	Settings.set_value(&"encounter_max_ships", cap_backup)


# M8-T28: the station's run follows the civilian-traffic switch.
func test_the_station_run_follows_the_civilian_traffic_switch() -> void:
	var backup: Variant = Settings.get_value(&"encounters_civilian")
	Settings.set_value(&"encounters_civilian", false)
	if not await _start(true):
		Settings.set_value(&"encounters_civilian", backup)
		pending("the babylon5_station asset is not generated")
		return
	await get_tree().physics_frame
	assert_false(main.traffic.auto, "civilian traffic off: no run")
	assert_eq(main.traffic.flow_count(), 0)
	Settings.set_value(&"encounters_civilian", true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_true(main.traffic.auto, "civilian traffic on: the run starts")
	Settings.set_value(&"encounters_civilian", backup)
