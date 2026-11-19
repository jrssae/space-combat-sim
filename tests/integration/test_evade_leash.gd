extends GutTest
## The evasion's leash in play (M8-T06; maintainer, 2026-11-18): a wingman under FORM ON ME, 3.2 km from its leader and flying
## away with a raider on its tail, evades back toward the leader instead of being dragged off. Flown twice from the same
## start, with the flights' cohesion distance (2.5 km) and with one so long the leash never pulls, by the native brains.

const FREE_FLIGHT: String = "res://data/scenarios/free_flight.json"
const SPEED_UP: float = 8.0
const HEADING: Vector3 = Vector3(0.0, -1.0, 0.0)
const SPEED_MPS: float = 100.0
## Where the wingman starts from the leader, and how fast it is flying on away, m and m/s.
const OUT_M: float = 3200.0
const AWAY_MPS: float = 120.0
const RUN_S: float = 25.0

var main: Main = null
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


# Flies the chase with the flights' cohesion distance `cohesion_m`: `{start_m, end_m, evade_ticks, leashed_ticks}`.
func _chase(cohesion_m: float) -> Dictionary:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.waves_auto_start = false
	main.scenario_path = FREE_FLIGHT
	main.scenario_seed = 5
	main.ally_pool_size = 1
	main.raider_pool_size = 1
	add_child_autofree(main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	main.wings.flight_rules = FlightRules.from_dict({"cohesion_m": cohesion_m, "rejoined_m": 0.4 * cohesion_m})
	main.docking.wingman_auto = false  # the chase, not a trip to the docking bay
	var basis := Basis.looking_at(HEADING, Vector3.BACK)
	main.ship.reset_to(Transform3D(basis, Vector3.ZERO))
	main.ship.linear_velocity = HEADING * SPEED_MPS
	main.combatant.damageable.invulnerable = true
	var out: Vector3 = basis.x
	var wing: Wing = main.wings.player_wing()
	var at: Vector3 = out * OUT_M
	var away: Vector3 = HEADING * SPEED_MPS + out * AWAY_MPS
	var made: Dictionary = BrainFactory.from_behaviour({"type": "ai", "profile": "ally_starfury", "orders": "form"},
			main.world.to_universe(at), 71)
	var ally: Combatant = main.ships.acquire("ALPHA 2", main.world.to_universe(at), Basis.looking_at(out, basis.y), away,
			made["brain"] as PilotBrain, ShipPool.ALLY_TYPE)
	assert_not_null(ally)
	ally.damageable.invulnerable = true
	assert_eq(main.wings.add_member(wing, ally, 1), 1)
	main.wings.give_order(AiContext.Order.FORM_ON_ME)
	# The raider 500 m astern of the wingman on its line of flight, nose on it, sent at it.
	var raider_at: Vector3 = at - out * 500.0
	var raider_made: Dictionary = BrainFactory.from_behaviour({"type": "ai", "profile": "raider", "objective": "ALPHA 2"},
			main.world.to_universe(raider_at), 72)
	var raider: Combatant = main.ships.acquire("RAIDER 1", main.world.to_universe(raider_at), Basis.looking_at(out, basis.y), away,
			raider_made["brain"] as PilotBrain, ShipPool.DEFAULT_TYPE)
	assert_not_null(raider)
	raider.damageable.invulnerable = true
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))
	var result: Dictionary = {"start_m": ally.ship.global_position.distance_to(main.ship.global_position), "evade_ticks": 0,
			"farthest_m": 0.0}
	var pilot := ally.driver.brain as AiPilot
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < RUN_S:
		await get_tree().physics_frame
		var d: float = ally.ship.global_position.distance_to(main.ship.global_position)
		result["farthest_m"] = maxf(float(result["farthest_m"]), d)
		if pilot.current != null and pilot.current.id == &"evade":
			result["evade_ticks"] = int(result["evade_ticks"]) + 1
	result["end_m"] = ally.ship.global_position.distance_to(main.ship.global_position)
	result["leash_m"] = pilot.context.leash_m
	main.queue_free()
	await get_tree().physics_frame
	return result


func test_a_chased_wingman_past_the_cohesion_distance_evades_back_toward_its_leader() -> void:
	var leashed: Dictionary = await _chase(2500.0)
	var free: Dictionary = await _chase(1.0e7)
	assert_almost_eq(float(leashed["leash_m"]), 2500.0, 1e-6, "under FORM ON ME the leash is the flights' cohesion distance")
	assert_gt(int(leashed["evade_ticks"]), 30, "the raider on its tail made it evade (%s)" % str(leashed))
	assert_gt(int(free["evade_ticks"]), 30, "and in the run without a leash (%s)" % str(free))
	assert_gt(float(leashed["start_m"]), 2500.0, "it starts past the cohesion distance")
	assert_lt(float(leashed["end_m"]), float(leashed["start_m"]), "on the leash it ends nearer its leader than it began")
	assert_lt(float(leashed["farthest_m"]), float(free["farthest_m"]) - 300.0,
			"and is never dragged as far out as without one (%.0f m against %.0f m)" % [leashed["farthest_m"], free["farthest_m"]])
