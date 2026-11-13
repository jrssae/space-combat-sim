extends GutTest
## Free-flight encounters in the real main scene (architecture §18 D58, M5-T17, AC14, AC16): off by default, so free flight
## stays empty and builds no pools; on, the pools file's ships are built, raids jump in 6-12 km from their target, patrols
## and traffic cruise in from 26-30 km on their routes, ships go back to their pools 40 km out or at their route's end, the
## cap holds (an event waits, one bigger than the cap is trimmed), events come on sim time, raiders sent at a civilian
## attack it and a patrol engages them, the release check looks only at the director's own ships, and the console works.
## Kept small (`tests/fixtures/encounters/small.json`, at most the cap plus the player). The load time with the shipped
## pools is printed (M5-T17's record).

const SMALL: String = "res://tests/fixtures/encounters/small.json"
const SEED: int = 5
## Ticks per real tick: the physics rate and the time scale raised together, so each step is still 1/60 s of sim time.
const SPEED_UP: float = 4.0

var main: Main
var _settings_backup: Dictionary = {}
var _rate_backup: int = 60
var _scale_backup: float = 1.0


func before_each() -> void:
	get_tree().paused = false
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	for key: StringName in [&"encounter_max_ships", &"encounter_interval_s"]:
		_settings_backup[key] = Settings.get_value(key)


func after_each() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	for key: StringName in _settings_backup:
		Settings.set_value(key, _settings_backup[key])
	DebugConsole.flags.invulnerable = false
	get_tree().paused = false


func _make_main(encounters_on: bool, pools_path: String = SMALL) -> Main:
	var m := (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	m.input_source = FakeInputSource.new()
	m.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	m.scenario_seed = SEED
	m.encounters = encounters_on
	m.encounter_pools_path = pools_path
	add_child_autofree(m)
	await wait_physics_frames(2)
	return m


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute_tokens(line.split(" ", false))


func _director() -> EncounterDirector:
	return main.encounter_director


func _range_from_player(c: Combatant) -> float:
	return c.ship.global_position.distance_to(main.ship.global_position)


# Flies `seconds` of sim time at `SPEED_UP`, stopping early when `done` says so.
func _fly(seconds: float, done: Callable = Callable()) -> void:
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < seconds:
		await get_tree().physics_frame
		if done.is_valid() and bool(done.call()):
			break
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup


# A raid of the plan's draws, aimed as asked.
func _raid(at_civilian: bool, min_count: int = 2) -> EncounterEvent:
	for i: int in 200:
		var e: EncounterEvent = _director().plan.event(EncounterDirector.FORCED_INDEX + 500 + i, &"raid")
		if e.count() >= min_count:
			e.at_civilian = at_civilian
			e.target_pick = 0.0
			return e
	return null


# --- off -------------------------------------------------------------------------------------------------------


func test_encounters_off_leave_free_flight_empty_and_build_nothing() -> void:
	main = await _make_main(false, "")
	assert_not_null(_director(), "free flight has a director, from data/encounters/free_flight.json")
	assert_false(_director().on)
	assert_false(_director().pools_built)
	assert_eq(main.ships.pool_size(), 0, "no pool is built")
	assert_eq(DebugConsole.registry.read("raiders.pool_size")["value"], 0, "the smoke line's raiders.pool_size = 0 holds")
	await _fly(5.0)
	assert_eq(main.ships.in_use_count(), 0, "nothing comes")
	assert_eq(_director().elapsed_s, 0.0, "the encounter clock stands still")
	var refused: ConsoleResult = _run("encounters next")
	assert_false(refused.ok, "next is refused while they are off")


func test_other_scenarios_have_no_director() -> void:
	var m := (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	m.input_source = FakeInputSource.new()
	m.scenario_path = "res://data/scenarios/dogfight.json"
	m.encounters = true
	add_child_autofree(m)
	await wait_physics_frames(2)
	assert_null(m.encounter_director, "no pools file for the dogfight, no encounters")


# --- on: the pools and the placing -----------------------------------------------------------------------------


func test_on_builds_the_pools_file_and_the_session_seed_drives_the_plan() -> void:
	main = await _make_main(true)
	assert_true(_director().on)
	assert_eq(main.ships.pool_size(ShipPool.DEFAULT_TYPE), 6)
	assert_eq(main.ships.pool_size(ShipPool.ALLY_TYPE), 2)
	assert_eq(main.ships.pool_size(&"saturn_4_transport"), 1)
	assert_eq(main.ships.pool_size(&"brakiri_bokmai"), 1)
	assert_eq(main.ships.pool_size(), 11)
	assert_eq(_director().seed_value, SEED, "the request's seed")
	assert_eq(_director().plan.event(3).describe(), EncounterPlan.new(SEED, _director().plan.interval_s,
			_director().weights).event(3).describe(), "the same plan as a fresh one of that seed")


func test_a_raid_jumps_in_6_to_12_km_out_and_goes_for_the_player() -> void:
	main = await _make_main(true)
	var e: EncounterEvent = _raid(false)
	var opened: int = _director().jumps.opened
	assert_true(_director().start(e))
	var raiders: Array[Combatant] = _director().alive()
	assert_eq(raiders.size(), e.count())
	assert_gt(_director().jumps.opened, opened, "through a jump point")
	for c: Combatant in raiders:
		assert_eq(main.ships.type_of(c), ShipPool.DEFAULT_TYPE)
		assert_between(_range_from_player(c), 6000.0, 12000.0, "%s jumps in 6-12 km out" % c.display_name)
		var pilot := c.driver.brain as AiPilot
		assert_not_null(pilot, "an AI pilot")
		assert_eq(pilot.context.objective_name, "PLAYER", "sent at the player")
	# Out of the point's funnel first (M6-T22), each leaves it with its spawn's velocity.
	var transits: VortexTransits = VortexTransits.of(main.world)
	for c: Combatant in raiders:
		var ticks: int = 0
		while transits.is_passing(c.ship) and ticks < 12 * 60:
			await get_tree().physics_frame
			ticks += 1
		assert_false(transits.is_passing(c.ship), "%s came out of its funnel" % c.display_name)
		assert_gt(c.ship.linear_velocity.dot((main.ship.global_position - c.ship.global_position).normalized()), 100.0,
				"flying at it")


func test_a_raid_comes_in_behind_a_carrier_that_then_jumps_back() -> void:
	# M6-T23: raiders cannot open a jump point; a cruiser stand-in opens one, they come out with it, and it leaves through its own.
	main = await _make_main(true)
	var carriers: CarrierJumps = CarrierJumps.attach(main.world)
	assert_eq(carriers.size(), EncounterDirector.CARRIERS, "the carriers are built with the pools, not in play (D22)")
	var e: EncounterEvent = _raid(false)
	assert_true(_director().start(e))
	assert_eq(carriers.runs().size(), 1, "one carrier brings the whole raid")
	var run: CarrierRun = carriers.runs()[0]
	assert_eq(run.arrival.opener, run.carrier, "the carrier opened the point and holds it")
	assert_almost_eq(run.arrival.hold_range_m, 2.0 * run.carrier.length_m(), 1e-3)
	assert_eq(run.fighters.size(), e.count(), "every raider comes through it")
	assert_eq(run.carrier.faction, Factions.RAIDERS)
	var departed: int = carriers.carriers_departed
	await _fly(60.0, func() -> bool: return carriers.carriers_departed > departed)
	assert_eq(carriers.carriers_departed, departed + 1, "the carrier jumped back through its own point")
	assert_eq(_director().jumps.opened, 2, "its arrival point and its departure point")
	assert_eq(carriers.free_count(), carriers.size(), "and is back in its pool")
	await _fly(JumpCapability.OWN_DEPARTURE_HOLD_S + 0.5)
	assert_eq(_director().jumps.collapses, 1, "its departure point closed once the short hold was over")
	assert_eq(_director().jumps.collapse_kills, 0, "with nothing in it")
	for c: Combatant in _director().alive():
		assert_false(c.damageable.hull.destroyed, "%s flies on" % c.display_name)


func test_patrols_and_traffic_cruise_in_from_26_to_30_km_on_their_routes() -> void:
	main = await _make_main(true)
	assert_true(_director().start(_director().take_forced(&"patrol")))
	assert_true(_director().start(_director().take_forced(&"traffic")))
	var kinds: Dictionary = {}
	for c: Combatant in _director().alive():
		var type: StringName = main.ships.type_of(c)
		kinds[ShipCatalog.is_civilian(type)] = true
		assert_between(_range_from_player(c), 26000.0, 30000.0, "%s starts past the radar" % c.display_name)
		var path: BehaviourFollowPath = _director().path_of(c)
		assert_not_null(path, "%s flies a route" % c.display_name)
		assert_gt(c.ship.linear_velocity.length(), 100.0, "%s is already cruising" % c.display_name)
		if ShipCatalog.is_civilian(type):
			assert_eq(c.targetable.broadcast_range_m, EncounterDirector.TRANSPONDER_M, "a civilian's transponder")
		else:
			assert_eq(c.faction, Factions.EARTH_ALLIANCE, "an allied patrol")
	assert_eq(kinds.size(), 2, "a patrol and traffic")


func test_a_bokmai_flies_with_the_pods_its_draw_gives() -> void:
	main = await _make_main(true)
	var e: EncounterEvent = _director().take_forced(&"traffic")
	e.trim(1)
	e.types[0] = &"brakiri_bokmai"
	e.cargo_pods[0] = 1
	assert_true(_director().start(e))
	var bokmai: Combatant = _director().alive()[0]
	assert_eq(main.ships.type_of(bokmai), &"brakiri_bokmai")
	assert_eq(bokmai.cargo_pods.count, 1, "one pod, as drawn")


func test_traffic_takes_another_civilian_hull_when_its_pool_is_spent() -> void:
	main = await _make_main(true)
	var e: EncounterEvent = _director().take_forced(&"traffic")
	e.trim(1)
	e.types[0] = &"narn_transport"  # not in the small pools file
	assert_true(_director().start(e))
	assert_true(ShipCatalog.is_civilian(main.ships.type_of(_director().alive()[0])), "a civilian hull with a free ship")


# --- releases --------------------------------------------------------------------------------------------------


func test_ships_go_back_to_their_pools_40_km_out_or_at_their_routes_end() -> void:
	main = await _make_main(true)
	assert_true(_director().start(_director().take_forced(&"patrol")))
	var ships: Array[Combatant] = _director().alive()
	assert_eq(ships.size(), 2)
	var far: Combatant = ships[0]
	var done: Combatant = ships[1]
	far.ship.reset_to(Transform3D(far.ship.global_basis, main.ship.global_position + Vector3(41000.0, 0.0, 0.0)))
	_director().path_of(done).phase = BehaviourFollowPath.Phase.DONE
	_director().check_releases()
	assert_eq(_director().alive_count(), 0, "both released")
	assert_eq(_director().ships_released, 2)
	assert_eq(main.ships.in_use_count(), 0, "back in the pool")
	assert_eq(main.ships.free_count(ShipPool.ALLY_TYPE), 2)
	assert_eq(main.audio.engine_voices_of(far.ship), 0, "no engine voice left on a parked ship")
	assert_eq(main.audio.engine_voices_of(done.ship), 0)


func test_a_ship_still_near_and_on_its_route_stays() -> void:
	main = await _make_main(true)
	assert_true(_director().start(_raid(false)))
	var n: int = _director().alive_count()
	await _fly(2.5)
	assert_eq(_director().alive_count(), n, "raiders 6-12 km out stay")
	assert_gt(_director().checks, 1, "checked meanwhile")


func test_a_destroyed_ship_leaves_the_encounters_at_once() -> void:
	main = await _make_main(true)
	assert_true(_director().start(_raid(false)))
	var n: int = _director().alive_count()
	var victim: Combatant = _director().alive()[0]
	victim.damageable.kill()
	await wait_physics_frames(2)
	assert_eq(_director().alive_count(), n - 1, "counted out of the cap the moment it dies")


# --- the cap and the clock -------------------------------------------------------------------------------------


func test_an_event_that_would_pass_the_cap_waits_until_there_is_room() -> void:
	Settings.set_value(&"encounter_max_ships", 4)
	main = await _make_main(true)
	var first: EncounterEvent = _raid(false, 3)
	first.trim(3)
	assert_true(_director().start(first))
	var second: EncounterEvent = _raid(false, 2)
	second.trim(2)
	_director().waiting = second
	await wait_physics_frames(3)
	assert_eq(_director().alive_count(), 3, "3 + 2 would pass 4: the second waits")
	assert_eq(_director().waiting, second)
	assert_ne(DebugConsole.registry.read("encounters.waiting")["value"], "none", "the provider says so")
	_director().release_all()
	await wait_physics_frames(2)
	assert_null(_director().waiting, "it starts once there is room")
	assert_eq(_director().alive_count(), 2)


func test_an_event_bigger_than_the_cap_is_trimmed_to_it_when_nothing_else_is_in_play() -> void:
	Settings.set_value(&"encounter_max_ships", 4)
	main = await _make_main(true)
	var big: EncounterEvent = _raid(false, 5)
	assert_gt(big.count(), 4)
	assert_true(_director().start(big))
	assert_eq(_director().alive_count(), 4, "trimmed to the cap")


func test_events_come_on_sim_time() -> void:
	Settings.set_value(&"encounter_interval_s", 20.0)
	main = await _make_main(true)
	var plan: EncounterPlan = _director().plan
	assert_eq(plan.interval_s, 20.0, "the setting, read when they turn on")
	_director().elapsed_s = plan.time_of(0) - 0.5
	await wait_physics_frames(3)
	assert_eq(_director().events_started, 0, "not yet")
	main.set_paused(true)
	await wait_physics_frames(60)
	assert_eq(_director().events_started, 0, "the pause stops the clock")
	main.set_paused(false)
	await _fly(0.6)
	assert_eq(_director().next_index, 1, "event 0 taken at its time")
	assert_true(_director().events_started == 1 or _director().waiting != null,
			"and started, or waiting for the small pools (a patrol of 4 or 6)")


# --- the fight (Q9) ---------------------------------------------------------------------------------------------


func test_raiders_sent_at_a_civilian_attack_it_and_a_patrol_engages_them() -> void:
	DebugConsole.flags.invulnerable = true
	main = await _make_main(true)
	var director: EncounterDirector = _director()
	# A Saturn 8 km out, drifting across; the player stays beyond the raiders' sensors.
	var traffic: EncounterEvent = director.take_forced(&"traffic")
	traffic.trim(1)
	traffic.types[0] = &"saturn_4_transport"
	traffic.positions[0] = Vector3(0.0, 0.0, -8000.0)
	traffic.velocities[0] = Vector3(20.0, 0.0, 0.0)
	traffic.routes[0] = PackedVector3Array([Vector3(20000.0, 0.0, -8000.0)])
	traffic.cruise_mps = 20.0
	assert_true(director.start(traffic))
	var saturn: Combatant = director.alive()[0]
	var raid: EncounterEvent = _raid(true, 2)
	raid.trim(2)
	for k: int in 2:  # beyond the Saturn, away from the player
		raid.positions[k] = Vector3(-60.0 + 120.0 * k, 0.0, -6500.0)
		raid.velocities[k] = Vector3(0.0, 0.0, 120.0)
	assert_true(director.start(raid))
	var raiders: Array[Combatant] = director.alive().filter(func(c: Combatant) -> bool:
		return main.ships.type_of(c) == ShipPool.DEFAULT_TYPE)
	assert_eq(raiders.size(), 2)
	for r: Combatant in raiders:
		assert_eq((r.driver.brain as AiPilot).context.objective_name, saturn.display_name, "sent at the civilian")
		assert_between(r.ship.global_position.distance_to(saturn.ship.global_position), 6000.0, 12000.0,
				"jumped in 6-12 km from it")
	# A patrol on a route over the Saturn.
	var patrol: EncounterEvent = director.take_forced(&"patrol")
	patrol.trim(2)
	for k: int in 2:
		patrol.positions[k] = Vector3(-2500.0, 0.0, -8000.0 + 150.0 * k)
		patrol.velocities[k] = Vector3(150.0, 0.0, 0.0)
		patrol.routes[k] = PackedVector3Array([Vector3(0.0, 0.0, -8000.0), Vector3(20000.0, 0.0, -8000.0)])
	patrol.cruise_mps = 150.0
	assert_true(director.start(patrol))
	var allies: Array[Combatant] = director.alive().filter(func(c: Combatant) -> bool:
		return main.ships.type_of(c) == ShipPool.ALLY_TYPE)
	var saturn_id: int = saturn.targetable.get_instance_id()
	var raider_ids: Array[int] = []
	for r: Combatant in raiders:
		raider_ids.append(r.targetable.get_instance_id())
	var seen: Dictionary = {"raider_on_saturn": false, "ally_on_raider": false}
	await _fly(120.0, func() -> bool:
		for r: Combatant in raiders:
			var pilot := r.driver.brain as AiPilot if r.driver != null else null
			if pilot != null and pilot.current != null and pilot.current.id == &"attack" and pilot.wanted_target_id == saturn_id:
				seen["raider_on_saturn"] = true
		for a: Combatant in allies:
			var pilot := a.driver.brain as AiPilot if a.driver != null else null
			if pilot != null and pilot.current != null and pilot.current.id == &"attack" \
					and raider_ids.has(pilot.wanted_target_id):
				seen["ally_on_raider"] = true
		return bool(seen["raider_on_saturn"]) and bool(seen["ally_on_raider"]))
	gut.p("fight: %s; Saturn hull %.0f %%" % [seen, 100.0 * saturn.damageable.hull.fraction()])
	assert_true(bool(seen["raider_on_saturn"]), "a raider attacks the civilian")
	assert_true(bool(seen["ally_on_raider"]), "the patrol engages the raiders")


# --- cost (AC16) ------------------------------------------------------------------------------------------------


func test_the_release_check_looks_only_at_the_directors_own_ships() -> void:
	main = await _make_main(true)
	assert_true(_director().start(_raid(false, 2)))
	var own: int = _director().alive_count()
	_director().check_releases()
	assert_eq(_director().check_work, own)
	# Ships in play that are not the encounters' cost the check nothing.
	var others: int = main.ships.free_count(ShipPool.DEFAULT_TYPE)
	for i: int in others:
		main.ships.acquire("OTHER %d" % (i + 1), main.world.to_universe(Vector3(0.0, 2000.0, -3000.0 - 100.0 * i)))
	assert_gt(main.ships.in_use_count(), own)
	_director().check_releases()
	assert_eq(_director().check_work, own, "the same work with %d more ships in play" % others)
	gut.p("release check: %d units for %d own ships, %d ships in play" % [_director().check_work, own,
			main.ships.in_use_count()])


# --- console ----------------------------------------------------------------------------------------------------


func test_the_console_turns_them_on_forces_one_and_clears() -> void:
	main = await _make_main(false)
	var registry: ConsoleRegistry = DebugConsole.registry
	assert_false(_run("encounters force raid").ok, "refused while off")
	var on: ConsoleResult = _run("encounters on")
	assert_true(on.ok, str(on.error))
	assert_true(_director().pools_built, "on builds the pools")
	assert_eq(main.ships.pool_size(), 11)
	var forced: ConsoleResult = _run("encounters force traffic")
	assert_true(forced.ok, str(forced.error))
	assert_gt(int(registry.read("encounters.traffic")["value"]), 0)
	assert_eq(int(registry.read("encounters.next_index")["value"]), 0, "a forced event leaves the schedule alone")
	var next: ConsoleResult = _run("encounters next")
	assert_true(next.ok, str(next.error))
	assert_eq(int(registry.read("encounters.next_index")["value"]), 1, "the next one now (or waiting, if it does not fit)")
	assert_true(_director().events_started == 2 or _director().waiting != null)
	assert_true(_run("encounters status").ok)
	assert_true(_run("encounters clear").ok)
	assert_eq(int(registry.read("encounters.alive")["value"]), 0)
	assert_true(_run("encounters off").ok)
	assert_false(_director().on)


# --- load time --------------------------------------------------------------------------------------------------


func test_the_free_flight_load_time_with_encounters_on_is_recorded() -> void:
	var off_ms: int = await _load_ms(false)
	var on_ms: int = await _load_ms(true)
	gut.p("free flight load: encounters off %d ms, on %d ms (the pools: %d ms)" % [off_ms, on_ms, _director().build_ms])
	assert_eq(main.ships.pool_size(), 42, "the shipped pools: 12 raiders, 12 Starfuries, two of each civilian hull")
	assert_gt(_director().build_ms, 0)


func _load_ms(encounters_on: bool) -> int:
	if main != null and is_instance_valid(main):
		remove_child(main)
		main.free()
	var m := (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	m.input_source = FakeInputSource.new()
	m.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	m.encounters = encounters_on
	var t0: int = Time.get_ticks_msec()
	add_child_autofree(m)
	var ms: int = Time.get_ticks_msec() - t0
	main = m
	await wait_physics_frames(2)
	return ms
