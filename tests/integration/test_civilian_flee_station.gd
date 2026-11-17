extends GutTest
## Civilians on the station's run flee a fight (M7-T55, the maintainer's m5-054: "I didn't see the civilians flee at all, but
## i did see them attempt to fight off raiders"): a Skylark leaving Babylon 5 for the gate with a raider coming at it turns
## round and runs back to the station, its own people's shelter (Q24, Q25), the raider falling behind; an Earth Alliance
## freighter within radar range of it, which sees no threat itself, panics and runs for the station too; and a raid an
## encounter draws for a civilian finds the run's traffic. Babylon 5 is a neutral port (the maintainer, 2026-11-16): a Narn
## transport attacked on the run runs to it too, its readout naming the station. Free flight on seed 5, the physics rate and
## the time scale raised together.

const SPEED_UP: float = 8.0
const SHIPPED_POOLS: String = "res://data/encounters/free_flight.json"
const RAIDER: StringName = &"raider_fighter"
## The AI's sensors and a civilian's alarm reach (Q25).
const SENSOR_M: float = 5000.0

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


func _describe(c: Combatant) -> Dictionary:
	var pilot := c.driver.brain as AiPilot if c.driver != null else null
	return pilot.describe() if pilot != null else {}


func _behaviour(c: Combatant) -> String:
	return String(_describe(c).get("behaviour", ""))


# A raider with no pilot of its own (it holds still: a threat that never moves) at `at` (World).
func _raider_at(at: Vector3) -> Combatant:
	main.ensure_free(RAIDER, 1)
	var made: Dictionary = BrainFactory.from_behaviour({"type": "idle"}, main.world.to_universe(at), 1)
	return main.ships.acquire("RAIDER", main.world.to_universe(at), Basis.IDENTITY, main.world.rest_velocity(),
			made["brain"] as PilotBrain, RAIDER)


func test_a_skylark_leaving_runs_back_to_babylon_5_and_the_panic_sends_a_freighter_there_too() -> void:
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	var traffic: StationTraffic = main.traffic
	var length: float = traffic._run_length(traffic.plan.dock_in)
	var station: Vector3 = main.far_props.station.global_position
	# Leaving 9 km out on the run at its cruise; the freighter coming in 3.5 km farther out, on the arrivals' side.
	var skylark: Combatant = traffic._join_outbound(&"skylark_transport", _along(9000.0, length), {})
	var saturn: Combatant = traffic._join_inbound(&"saturn_3_freighter", _along(12500.0, length), {})
	assert_not_null(skylark)
	assert_not_null(saturn)
	if skylark == null or saturn == null:
		return
	# A raider 2 km off the Skylark's beam, on the side away from the freighter: within its flee range (3 km), beyond the freighter's.
	var run_dir: Vector3 = (main.gates.gate().global_position - station).normalized()
	var beam: Vector3 = run_dir.cross(Vector3.UP).normalized()
	if beam.dot(saturn.ship.global_position - skylark.ship.global_position) > 0.0:
		beam = -beam
	var raider: Combatant = _raider_at(skylark.ship.global_position + beam * 2000.0)
	# The player (an Earth Alliance warship, so a shelter too) is 15 km off: the station's skin is the nearer shelter.
	assert_gt(main.ship.global_position.distance_to(skylark.ship.global_position), 12000.0, "the player is far off")
	assert_gt(raider.ship.global_position.distance_to(saturn.ship.global_position), 3200.0, "the freighter is beyond the flee range")
	assert_lt(saturn.ship.global_position.distance_to(skylark.ship.global_position), civilian_panic_m(), "but within the alarm's")
	_fast()
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < 10.0 and (_behaviour(skylark) != "retreat" or _behaviour(saturn) != "retreat"):
		await get_tree().physics_frame
	var seen: Dictionary = _describe(skylark)
	assert_eq(String(seen.get("behaviour", "")), "retreat", "the Skylark runs: %s" % seen)
	assert_eq(String(seen.get("state", "")), "shelter", "to its people's station: %s" % seen)
	assert_eq(String(seen.get("goal", "")), Station.DISPLAY_NAME, "the station by name (the drum goes by it), no ship: %s" % seen)
	var panicked: Dictionary = _describe(saturn)
	assert_eq(String(panicked.get("behaviour", "")), "retreat", "the freighter panics with it: %s" % panicked)
	assert_eq(String(panicked.get("state", "")), "shelter", "and runs for the station: %s" % panicked)
	assert_eq(String(panicked.get("goal", "")), Station.DISPLAY_NAME, "the station, not the Skylark: %s" % panicked)
	var from_raider: float = skylark.ship.global_position.distance_to(raider.ship.global_position)
	var from_station: float = skylark.ship.global_position.distance_to(station)
	var held: bool = true
	t0 = SimClock.now()
	while SimClock.now() - t0 < 120.0:
		await get_tree().physics_frame
		var seen_it: bool = skylark.ship.global_position.distance_to(raider.ship.global_position) < SENSOR_M
		held = held and (_behaviour(skylark) == "retreat" or not seen_it)
	var now_raider: float = skylark.ship.global_position.distance_to(raider.ship.global_position)
	var now_station: float = skylark.ship.global_position.distance_to(station)
	gut.p("skylark: from the raider %.0f -> %.0f m, from the station %.0f -> %.0f m; freighter %s" % [from_raider, now_raider,
			from_station, now_station, _describe(saturn)])
	assert_true(held, "it kept running while the raider was in sight")
	assert_gt(now_raider, from_raider + 1000.0, "away from the raider")
	assert_lt(now_station, from_station - 1000.0, "back toward Babylon 5")
	assert_eq(traffic.state_of(skylark), &"leave", "still the run's ship, its route kept for after the fight")


func test_a_narn_transport_attacked_near_babylon_5_runs_to_the_station() -> void:
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	var traffic: StationTraffic = main.traffic
	var length: float = traffic._run_length(traffic.plan.dock_in)
	var station: Vector3 = main.far_props.station.global_position
	var narn: Combatant = traffic._join_outbound(&"narn_transport", _along(9000.0, length), {})
	assert_not_null(narn)
	if narn == null:
		return
	assert_eq(narn.faction, &"narn", "a Narn ship: no people of its own near Babylon 5")
	# A raider 2 km off its beam on the side away from the station, so the way back never passes it.
	var run_dir: Vector3 = (main.gates.gate().global_position - station).normalized()
	var beam: Vector3 = run_dir.cross(Vector3.UP).normalized()
	if beam.dot(station - narn.ship.global_position) > 0.0:
		beam = -beam
	var raider: Combatant = _raider_at(narn.ship.global_position + beam * 2000.0)
	_fast()
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < 10.0 and _behaviour(narn) != "retreat":
		await get_tree().physics_frame
	var seen: Dictionary = _describe(narn)
	assert_eq(String(seen.get("behaviour", "")), "retreat", "the Narn runs: %s" % seen)
	assert_eq(String(seen.get("state", "")), "shelter", "to the neutral port: %s" % seen)
	assert_eq(String(seen.get("goal", "")), Station.DISPLAY_NAME, "the readout names the station: %s" % seen)
	# Outbound at its cruise, it first slows and turns (a heavy hull) and then closes on the station while it runs; the idle
	# raider never chases, so the run ends `PANIC_HOLD_S` after it left the flee range.
	var from_raider: float = narn.ship.global_position.distance_to(raider.ship.global_position)
	var from_station: float = narn.ship.global_position.distance_to(station)
	var last: float = from_station
	var closing: float = 0.0  # the fastest it closed on the station while running, m/s
	var goals: Dictionary = {}
	t0 = SimClock.now()
	var sample: float = t0
	while SimClock.now() - t0 < 90.0 and _behaviour(narn) == "retreat":
		await get_tree().physics_frame
		var now_seen: Dictionary = _describe(narn)
		if String(now_seen.get("behaviour", "")) == "retreat":
			goals[String(now_seen.get("goal", ""))] = true
		if SimClock.now() - sample >= 2.0:
			var d: float = narn.ship.global_position.distance_to(station)
			closing = maxf(closing, (last - d) / (SimClock.now() - sample))
			last = d
			sample = SimClock.now()
	var now_raider: float = narn.ship.global_position.distance_to(raider.ship.global_position)
	gut.p("narn: from the raider %.0f -> %.0f m, from the station %.0f -> %.0f m, closing on it at up to %.0f m/s; goals %s" % [
			from_raider, now_raider, from_station, last, closing, goals.keys()])
	assert_eq(goals.keys(), [Station.DISPLAY_NAME], "the station all the way")
	assert_gt(now_raider, from_raider + 1000.0, "away from the raider")
	assert_gt(closing, 20.0, "its run turned round onto Babylon 5")


func test_a_raid_drawn_for_a_civilian_finds_the_runs_traffic() -> void:
	if not await _start(true):
		pending("the babylon5_station asset is not generated")
		return
	var traffic: StationTraffic = main.traffic
	var length: float = traffic._run_length(traffic.plan.dock_in)
	# 14 km out on the run: within the raid's reach of the player, who starts 8 km from the station.
	var skylark: Combatant = traffic._join_outbound(&"skylark_transport", _along(14000.0, length), {})
	assert_not_null(skylark)
	var e := EncounterEvent.new()
	e.index = 1
	e.kind = &"raid"
	e.at_civilian = true
	for pick: float in [0.0, 0.5, 0.999]:
		e.target_pick = pick
		var target: Combatant = main.encounter_director._raid_target(e)
		assert_not_null(target, "a raid for a civilian finds one (pick %.1f)" % pick)
		if target != null:
			assert_has(traffic.ships(), target, "one of the run's civilians, not the player")
			assert_has([&"transit", &"leave"], traffic.state_of(target), "between the gate and the station, not on a lane")


# The alarm's reach (Q25), as the native core has it.
static func civilian_panic_m() -> float:
	return SENSOR_M


# The run's place (0..1) `from_station_m` from its first lane point, as `StationTraffic._run_point` spreads it.
static func _along(from_station_m: float, length: float) -> float:
	var ends: float = minf(StationTraffic.RUN_END_M, length * 0.5)
	return (from_station_m - ends) / maxf(length - 2.0 * ends, 1.0)
