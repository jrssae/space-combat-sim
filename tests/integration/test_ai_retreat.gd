extends GutTest
## AC9, retreat (M3-T06, architecture §16 D34): an allied Starfury on the `ally_starfury` profile with a raider 800 m ahead.
## Below the profile's `retreat_below` (25 %) it turns away and opens the range at cruise + 50 m/s; at full hull the same
## pilot attacks and closes it. The real ships in Jolt and the real drivers. Both setups fly at once in one world, 10 km
## apart (beyond the 5 km sensor range), at mirrored positions.

const STARFURY_SPEC: String = "res://assets/ships/starfury_aurora.tres"
const RAIDER_SPEC: String = "res://assets/ships/raider_delta_v.tres"
## `Engine.time_scale` scales the physics step: 6 makes each 60 Hz tick 0.1 s of sim time.
const SPEED_UP: float = 6.0
const RUN_S: float = 30.0
const START_RANGE_M: float = 800.0
const APART_M: float = 10000.0

var _scale_backup: float = 1.0


class Ticker extends Node:
	var ticks: int = 0
	var on_tick: Callable = Callable()

	func _init() -> void:
		process_physics_priority = 500

	func _physics_process(_delta: float) -> void:
		ticks += 1
		on_tick.call()


func before_each() -> void:
	_scale_backup = Engine.time_scale
	ContactScan.invalidate()


func after_each() -> void:
	Engine.time_scale = _scale_backup
	ContactScan.invalidate()


## An ally at `at` (nose -Z) at `hull` of its hull, an idle raider `START_RANGE_M` ahead of it.
func _setup(world: WorldFrame, projectiles: Node3D, at: Vector3, hull: float, tag: String) -> Dictionary:
	var ally: Combatant = ShipAssembly.build(load(STARFURY_SPEC) as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE,
		ShipAssembly.OPT_DISPLAY_NAME: "ALPHA %s" % tag,
		ShipAssembly.OPT_FORCE_ASSIST: true,
		ShipAssembly.OPT_AI: true,
	})
	world.spawn(ally.ship, world.to_universe(at))
	ally.damageable.hull.apply(ally.damageable.hull.max_hp * (1.0 - hull))
	var raider: Combatant = ShipAssembly.build(load(RAIDER_SPEC) as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: Factions.RAIDERS,
		ShipAssembly.OPT_DISPLAY_NAME: "RAIDER %s" % tag,
		ShipAssembly.OPT_FORCE_ASSIST: true,
		ShipAssembly.OPT_AI: true,
	})
	world.spawn(raider.ship, world.to_universe(at + Vector3(0.0, 0.0, -START_RANGE_M)), Basis(Vector3.UP, PI))
	raider.damageable.hull = HullHealth.new(1.0e6)  # the attacking run must not end with a kill
	raider.driver.brain = IdleBrain.new()
	var made: Dictionary = BrainFactory.from_behaviour({"type": "ai", "profile": "ally_starfury"}, UniversePos.new(), 3)
	ally.driver.brain = made["brain"] as AiPilot
	return {"ally": ally, "raider": raider, "pilot": made["brain"], "min_range_m": INF, "behaviours": {}}


func _record(run: Dictionary) -> void:
	var ally: Combatant = run["ally"]
	var raider: Combatant = run["raider"]
	run["range_m"] = ally.ship.global_position.distance_to(raider.ship.global_position)
	run["min_range_m"] = minf(run["min_range_m"], run["range_m"])
	var pilot: AiPilot = run["pilot"]
	if pilot.current != null:
		(run["behaviours"] as Dictionary)[String(pilot.current.id)] = true


func test_below_a_quarter_hull_it_opens_the_range_and_at_full_hull_it_closes_it() -> void:
	var world := WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	var projectiles := Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	var resolver := HitResolver.new()
	add_child_autofree(resolver)
	var hurt: Dictionary = _setup(world, projectiles, Vector3(-APART_M / 2.0, 0.0, 0.0), 0.2, "A")
	var whole: Dictionary = _setup(world, projectiles, Vector3(APART_M / 2.0, 0.0, 0.0), 1.0, "B")
	var hits_on_b: Array[int] = [0]
	var raider_b_id: int = (whole["raider"] as Combatant).ship.get_instance_id()
	resolver.hit_resolved.connect(func(info: HitInfo) -> void:
		if info.target_id == raider_b_id:
			hits_on_b[0] += 1)
	var ticker := Ticker.new()
	ticker.on_tick = func() -> void:
		_record(hurt)
		_record(whole)
	add_child_autofree(ticker)
	Engine.time_scale = SPEED_UP
	var ticks: int = roundi(RUN_S * float(Engine.physics_ticks_per_second) / SPEED_UP)
	while ticker.ticks < ticks:
		await get_tree().physics_frame
	Engine.time_scale = 1.0
	var profile: AiProfile = (hurt["pilot"] as AiPilot).profile
	var ally: Ship = (hurt["ally"] as Combatant).ship
	var away: Vector3 = (ally.global_position - (hurt["raider"] as Combatant).ship.global_position).normalized()
	gut.p("retreat: at 20 %% hull the range went from %.0f to %.0f m (behaviours %s, speed %.1f m/s); at full hull the closest was %.0f m (behaviours %s, %d hits)" % [
			START_RANGE_M, hurt["range_m"], str((hurt["behaviours"] as Dictionary).keys()), ally.linear_velocity.length(),
			whole["min_range_m"], str((whole["behaviours"] as Dictionary).keys()), hits_on_b[0]])
	assert_eq((hurt["behaviours"] as Dictionary).keys(), ["retreat"], "it retreated the whole run")
	assert_gt(float(hurt["range_m"]), START_RANGE_M + 2000.0, "the range opened")
	assert_almost_eq(ally.linear_velocity.length(), profile.cruise_mps + BehaviourRetreat.EXTRA_MPS, 5.0,
			"at cruise + 50 m/s")
	assert_gt(ally.linear_velocity.normalized().dot(away), 0.95, "straight away from the raider")
	assert_true((whole["behaviours"] as Dictionary).has("attack"), "at full hull the same pilot attacks")
	assert_false((whole["behaviours"] as Dictionary).has("retreat"))
	assert_lt(float(whole["min_range_m"]), START_RANGE_M - 300.0, "and closes the range")
	assert_gt(hits_on_b[0], 0, "with the Starfury tactics it lands hits")
