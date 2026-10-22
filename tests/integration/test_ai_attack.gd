extends GutTest
## AC9, attack (M2-T07): a raider with an `AttackBrain` starting 2 km from a stationary drone fires within 20 s, lands at
## least one hit within 30 s and never closes under 100 m. Two runs with the same seed end within 1e-3 m of each other after
## 30 s. Runs the real raider in Jolt, the real `AiPilotDriver` and the real `HitResolver`; sim time is sped up with
## `Engine.time_scale`, so the 30 s take a few real seconds.

const DRONE_SCENE: String = "res://tests/fixtures/target_drone.tscn"
const SPEED_UP: float = 6.0
const RUN_S: float = 30.0

var _scale_backup: float = 1.0


## Records the raider's pose at the end of every physics tick, so two runs are compared tick for tick: at the speed-up one
## rendered frame holds several ticks, and where a loop that waits for frames stops would differ from run to run.
class Recorder extends Node:
	var ship: Ship = null
	var positions: Array[Vector3] = []
	var velocities: Array[Vector3] = []

	func _init() -> void:
		process_physics_priority = 500

	func _physics_process(_delta: float) -> void:
		positions.append(ship.global_position)
		velocities.append(ship.linear_velocity)


func before_each() -> void:
	_scale_backup = Engine.time_scale


func after_each() -> void:
	Engine.time_scale = _scale_backup


## One 30 s attack run in a fresh world; returns the metrics.
func _attack_run(seed_value: int) -> Dictionary:
	var world := WorldFrame.new()
	world.name = "World"
	add_child(world)
	var projectiles := Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	var resolver := HitResolver.new()
	add_child(resolver)
	var hits: Array[HitInfo] = []
	resolver.hit_resolved.connect(func(info: HitInfo) -> void: hits.append(info))
	var drone := (load(DRONE_SCENE) as PackedScene).instantiate() as TargetDrone
	drone.faction = Factions.EARTH_ALLIANCE
	drone.hull_max = 1.0e6
	world.spawn(drone, world.to_universe(Vector3.ZERO))
	var targetable := Targetable.new()
	targetable.display_name = "DRONE"
	targetable.faction = Factions.EARTH_ALLIANCE
	drone.add_child(targetable)
	var raider: Combatant = ShipAssembly.build(load("res://assets/ships/raider_delta_v.tres") as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: Factions.RAIDERS,
		ShipAssembly.OPT_DISPLAY_NAME: "RAIDER 1",
		ShipAssembly.OPT_FORCE_ASSIST: true,
		ShipAssembly.OPT_AI: true,
	})
	world.spawn(raider.ship, world.to_universe(Vector3(0.0, 0.0, -2000.0)), Basis.looking_at(Vector3.BACK, Vector3.UP))
	var brain := AttackBrain.new(load(BrainFactory.DEFAULT_TACTICS_PATH) as RaiderTactics, seed_value)
	raider.driver.brain = brain
	var recorder := Recorder.new()
	recorder.ship = raider.ship
	add_child(recorder)
	Engine.time_scale = SPEED_UP
	var result: Dictionary = {"first_fire_s": -1.0, "first_hit_s": -1.0, "min_range_m": INF, "states": {}}
	var t0: float = SimClock.now()
	var ticks: int = roundi(RUN_S * float(Engine.physics_ticks_per_second))
	while recorder.positions.size() < ticks:
		await get_tree().physics_frame
		var t: float = SimClock.now() - t0
		result["min_range_m"] = minf(result["min_range_m"], raider.ship.global_position.distance_to(drone.global_position))
		if brain.firing and result["first_fire_s"] < 0.0:
			result["first_fire_s"] = t
		if not hits.is_empty() and result["first_hit_s"] < 0.0:
			result["first_hit_s"] = t
		(result["states"] as Dictionary)[String(AttackBrain.STATE_NAMES[brain.state])] = true
	Engine.time_scale = 1.0
	result["position"] = recorder.positions[ticks - 1]
	result["velocity"] = recorder.velocities[ticks - 1]
	result["hits"] = hits.size()
	world.queue_free()
	resolver.queue_free()
	recorder.queue_free()
	await get_tree().process_frame
	return result


func test_it_fires_within_20_s_hits_within_30_s_and_never_closes_under_100_m() -> void:
	var r: Dictionary = await _attack_run(1234)
	gut.p("attack: first fire %.1f s, first hit %.1f s, min range %.0f m, %d hits, states %s" % [r["first_fire_s"], r["first_hit_s"], r["min_range_m"], r["hits"], str((r["states"] as Dictionary).keys())])
	assert_gt(r["first_fire_s"], 0.0, "it fired")
	assert_lt(r["first_fire_s"], 20.0, "within 20 s")
	assert_gt(r["first_hit_s"], 0.0, "it hit the drone")
	assert_lt(r["first_hit_s"], 30.0, "within 30 s")
	assert_gt(r["min_range_m"], 100.0, "it never got closer than 100 m")
	assert_true((r["states"] as Dictionary).has("break"), "and it broke off")


func test_two_runs_with_the_same_seed_match_within_a_millimetre() -> void:
	var a: Dictionary = await _attack_run(77)
	var b: Dictionary = await _attack_run(77)
	gut.p("determinism: positions differ by %s m" % str((a["position"] as Vector3).distance_to(b["position"])))
	assert_lt((a["position"] as Vector3).distance_to(b["position"]), 1e-3)
	assert_lt((a["velocity"] as Vector3).distance_to(b["velocity"]), 1e-3)
	assert_eq(a["hits"], b["hits"])
