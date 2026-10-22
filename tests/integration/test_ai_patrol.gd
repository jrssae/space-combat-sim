extends GutTest
## AC9, patrol (M2-T07): a patrol raider visits three waypoints in order within 90 s and never flies above its cruise
## speed plus 20 %. The real raider in Jolt with the real driver; sim time is sped up with `Engine.time_scale`.

const SPEED_UP: float = 6.0
const LIMIT_S: float = 90.0
const CRUISE_MPS: float = 80.0

var _scale_backup: float = 1.0


func before_each() -> void:
	_scale_backup = Engine.time_scale


func after_each() -> void:
	Engine.time_scale = _scale_backup


func test_it_visits_three_waypoints_in_order_within_90_s_at_a_sane_speed() -> void:
	var world := WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	var projectiles := Node3D.new()
	world.add_child(projectiles)
	var raider: Combatant = ShipAssembly.build(load("res://assets/ships/raider_delta_v.tres") as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: Factions.RAIDERS,
		ShipAssembly.OPT_FORCE_ASSIST: true,
		ShipAssembly.OPT_AI: true,
	})
	world.spawn(raider.ship, world.to_universe(Vector3.ZERO))
	var anchor: UniversePos = world.to_universe(Vector3.ZERO)
	var made: Dictionary = BrainFactory.from_behaviour({
		"type": "patrol", "cruise_mps": CRUISE_MPS,
		"waypoints": [[0, 0, -500], [500, 0, -900], [0, 0, -1300]],
	}, anchor, 5)
	assert_true(made["ok"], made["error"])
	var brain: PatrolBrain = made["brain"]
	raider.driver.brain = brain
	var waypoints: Array[UniversePos] = brain.waypoints
	Engine.time_scale = SPEED_UP
	var visited: Array[int] = []
	var max_speed: float = 0.0
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < LIMIT_S and visited.size() < 3:
		await get_tree().physics_frame
		max_speed = maxf(max_speed, raider.ship.linear_velocity.length())
		for i: int in waypoints.size():
			if raider.ship.global_position.distance_to(world.universe_to_local(waypoints[i])) < PatrolBrain.new().arrival_m + 1.0 and (visited.is_empty() or visited[-1] != i):
				visited.append(i)
	Engine.time_scale = 1.0
	var elapsed: float = SimClock.now() - t0
	gut.p("patrol: waypoints visited %s in %.1f s, max speed %.1f m/s (cruise %.0f)" % [str(visited), elapsed, max_speed, CRUISE_MPS])
	assert_eq(visited.slice(0, 3), [0, 1, 2], "three waypoints in order")
	assert_lt(elapsed, LIMIT_S, "within 90 s")
	assert_lt(max_speed, 1.2 * CRUISE_MPS, "never above cruise + 20 %")


func test_a_patrol_survives_a_rebase_in_flight() -> void:
	var world := WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	var projectiles := Node3D.new()
	world.add_child(projectiles)
	var raider: Combatant = ShipAssembly.build(load("res://assets/ships/raider_delta_v.tres") as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: Factions.RAIDERS,
		ShipAssembly.OPT_FORCE_ASSIST: true,
		ShipAssembly.OPT_AI: true,
	})
	world.spawn(raider.ship, world.to_universe(Vector3.ZERO))
	var made: Dictionary = BrainFactory.from_behaviour({"type": "patrol", "waypoints": [[0, 0, -600], [0, 0, -1200]]}, world.to_universe(Vector3.ZERO), 1)
	raider.driver.brain = made["brain"]
	Engine.time_scale = SPEED_UP
	for i: int in 300:
		await get_tree().physics_frame
	var before: UniversePos = world.to_universe(raider.ship.global_position)
	world.rebase(Vector3(3000.0, 0.0, 0.0))
	for i: int in 300:
		await get_tree().physics_frame
	Engine.time_scale = 1.0
	var after: UniversePos = world.to_universe(raider.ship.global_position)
	assert_gt(before.distance_to(after), 100.0, "it kept flying toward its waypoint after the rebase")
	assert_lt(absf(after.x), 50.0, "and it did not chase the shifted frame sideways")
