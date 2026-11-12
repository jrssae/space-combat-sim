extends TestSteps
## AC20 in Jolt (M3-T13, Q12): on the same seeded runs an `ace` raider lands more hits on a straight-flying drone than a
## `rookie`; a `cautious` Starfury retreats at a higher hull than an `aggressive` one; a `rookie` reacts to a hit within 0.6 s
## (AC9), later than a regular; a `civilian` never fires, flees a hostile within 3 km and evades when hit; spawns take `skill=`
## and `aggression=` and `ai <name> skill|aggression` changes them live. The real main scene, Jolt and the real drivers.

const SPEED_UP: float = 4.0

var main: Main
var _scale_backup: float = 1.0


func before_each() -> void:
	_scale_backup = Engine.time_scale
	get_tree().paused = false
	DebugConsole.flags.invulnerable = true
	ContactScan.invalidate()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.waves_auto_start = false
	main.ally_pool_size = 8
	add_child_autofree(main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	DebugConsole.registry.execute("despawn all")


func after_each() -> void:
	Engine.time_scale = _scale_backup
	DebugConsole.flags.invulnerable = false
	ContactScan.invalidate()


func _at(offset: Vector3) -> UniversePos:
	return main.world.to_universe(main.ship.global_position).plus_local(offset)


func _ai(ship_name: String, type: StringName, at: UniversePos, behaviour: Dictionary, velocity: Vector3 = Vector3.ZERO,
		basis: Basis = Basis.IDENTITY) -> Combatant:
	var spec: Dictionary = {"type": "ai", "profile": "raider" if type == ShipPool.DEFAULT_TYPE else "ally_starfury"}
	spec.merge(behaviour, true)
	var made: Dictionary = BrainFactory.from_behaviour(spec, at, hash(ship_name))
	assert_true(bool(made["ok"]), str(made.get("error", "")))
	return main.ships.acquire(ship_name, at, basis, velocity, made["brain"] as PilotBrain, type)


func _ticks_for(seconds: float) -> void:
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < seconds:
		await get_tree().physics_frame


func test_an_ace_lands_more_hits_on_a_drone_than_a_rookie() -> void:
	# Two runs at once, 10 km apart, mirrored: a raider 1.5 km behind a Starfury drone flying straight at 60 m/s.
	var hits: Dictionary = {}
	var resolver := main.get_node(^"Combat/HitResolver") as HitResolver
	var drones: Dictionary = {}
	for skill: String in ["ace", "rookie"]:
		var side: float = 5000.0 if skill == "ace" else -5000.0
		var drone: Combatant = main.ships.acquire("DRONE %s" % skill.to_upper(), _at(Vector3(side, 0.0, -3000.0)), Basis.IDENTITY,
				Vector3(0.0, 0.0, -60.0), IdleBrain.new(false), ShipPool.ALLY_TYPE)
		drone.damageable.hull = HullHealth.new(1.0e6)
		drones[drone.ship.get_instance_id()] = skill
		hits[skill] = 0
		# The same seed for both: only the skill differs.
		var made: Dictionary = BrainFactory.from_behaviour({"type": "ai", "profile": "raider", "skill": skill, "aggression": "balanced"},
				_at(Vector3.ZERO), 4242)
		main.ships.acquire("RAIDER %s" % skill.to_upper(), _at(Vector3(side, 0.0, -1500.0)), Basis.IDENTITY, Vector3(0.0, 0.0, -60.0),
				made["brain"] as PilotBrain, ShipPool.DEFAULT_TYPE)
	resolver.hit_resolved.connect(func(info: HitInfo) -> void:
		if drones.has(info.target_id):
			hits[drones[info.target_id]] = int(hits[drones[info.target_id]]) + 1)
	Engine.time_scale = SPEED_UP
	await _ticks_for(90.0)
	Engine.time_scale = 1.0
	gut.p("skill: ace %d hits, rookie %d hits on a drone in 90 s" % [hits["ace"], hits["rookie"]])
	assert_gt(int(hits["ace"]), int(hits["rookie"]), "the ace lands more")
	assert_gt(int(hits["ace"]), 0)


func test_a_cautious_ship_retreats_at_a_higher_hull_than_an_aggressive_one() -> void:
	var retreat_at: Dictionary = {}
	for level: String in ["cautious", "aggressive"]:
		var side: float = 5000.0 if level == "cautious" else -5000.0
		var threat: Combatant = main.ships.acquire("RAIDER %s" % level.to_upper(), _at(Vector3(side, 0.0, -1800.0)), Basis.IDENTITY,
				Vector3.ZERO, IdleBrain.new(true), ShipPool.DEFAULT_TYPE)
		threat.damageable.invulnerable = true  # it must stay in sight: retreat runs from a hostile
		var ally: Combatant = _ai("ALPHA %s" % level.to_upper(), ShipPool.ALLY_TYPE, _at(Vector3(side, 0.0, 0.0)), {"aggression": level})
		retreat_at[level] = ally
	Engine.time_scale = SPEED_UP
	var found: Dictionary = {}
	for step: int in 49:  # 2 % of the hull every half second, with no shooter (no hit reaction), down to 2 %
		for level: String in retreat_at:
			var ally: Combatant = retreat_at[level]
			if found.has(level) or ally.damageable.hull.fraction() <= 0.03:
				continue
			ally.damageable.apply_hit(HitInfo.new(ally.ship.get_instance_id(), 0, &"", ally.damageable.hull.max_hp * 0.02,
					ally.ship.global_position, Vector3.UP, 0.0, HitInfo.CAUSE_CONSOLE))
		await _ticks_for(0.5)
		for level: String in retreat_at:
			var ally: Combatant = retreat_at[level]
			var pilot := ally.driver.brain as AiPilot if ally.driver != null else null
			if not found.has(level) and pilot != null and pilot.current != null and pilot.current.id == &"retreat":
				found[level] = ally.damageable.hull.fraction()
	Engine.time_scale = 1.0
	gut.p("retreat: cautious at %s hull, aggressive at %s (null: fought on to 2 %%)" % [str(found.get("cautious")),
			str(found.get("aggressive"))])
	assert_true(found.has("cautious"), "the cautious one retreated")
	assert_between(float(found.get("cautious", 0.0)), 0.4, 0.5, "below its doubled threshold (0.5), soon after")
	assert_gt(float(found.get("cautious", 0.0)), float(found.get("aggressive", 0.0)), "the cautious one went first")


func test_a_rookie_reacts_to_a_hit_within_0_6_s() -> void:
	var rookie: Combatant = _ai("RAIDER 7", ShipPool.DEFAULT_TYPE, _at(Vector3(0.0, 0.0, -1500.0)), {"skill": "rookie"})
	_ai("ALPHA 6", ShipPool.ALLY_TYPE, _at(Vector3(0.0, 0.0, -2500.0)), {"aggression": "passive"})  # something to attack
	await _ticks_for(0.5)
	var pilot := rookie.driver.brain as AiPilot
	assert_eq(pilot.current.id, &"attack")
	var hit_s: float = SimClock.now()
	rookie.damageable.apply_hit(HitInfo.new(rookie.ship.get_instance_id(), 0, Factions.EARTH_ALLIANCE, 1.0,
			rookie.ship.global_position, Vector3.UP, 1000.0, HitInfo.CAUSE_BOLT))
	while pilot.current.id != &"evade" and SimClock.now() - hit_s < 2.0:
		await get_tree().physics_frame
	var reaction: float = SimClock.now() - hit_s
	gut.p("rookie: evading %.3f s after the hit" % reaction)
	assert_eq(pilot.current.id, &"evade")
	# The AI step is one tick behind on the delayed and threaded schedules (M4-T24, Q53): the evade lands 16.7 ms later.
	var delay_s: float = 1.0 / float(Engine.physics_ticks_per_second)  # the AI step hands its commands over one tick later (Q53)
	assert_lte(reaction, 0.6 + delay_s + 1e-6, "within 0.6 s (AC9), plus the step's tick on the threaded schedule")
	assert_gt(reaction, 0.5, "slower than a regular's 0.25 s")


func test_a_civilian_never_fires_flees_and_evades_when_hit() -> void:
	var civ: Combatant = _ai("TRADER 1", ShipPool.ALLY_TYPE, _at(Vector3(0.0, 0.0, -1000.0)), {"profile": "civilian"})
	var raider: Combatant = main.ships.acquire("RAIDER 8", _at(Vector3(0.0, 0.0, -3500.0)), Basis.IDENTITY, Vector3.ZERO,
			IdleBrain.new(true), ShipPool.DEFAULT_TYPE)
	var shots: Array[int] = [0]
	civ.cannon.shot_fired.connect(func(_i: int, _at: Vector3) -> void: shots[0] += 1)  # both bolt paths signal it (M4-T35)
	Engine.time_scale = SPEED_UP
	await _ticks_for(3.0)
	var pilot := civ.driver.brain as AiPilot
	assert_eq(pilot.current.id, &"retreat", "a hostile within 3 km: it flees")
	var start_m: float = civ.ship.global_position.distance_to(raider.ship.global_position)
	await _ticks_for(10.0)
	assert_gt(civ.ship.global_position.distance_to(raider.ship.global_position), start_m + 300.0, "opening the range")
	civ.damageable.apply_hit(HitInfo.new(civ.ship.get_instance_id(), raider.ship.get_instance_id(), Factions.RAIDERS, 1.0,
			civ.ship.global_position, Vector3.UP, 300.0, HitInfo.CAUSE_BOLT))
	var hit_s: float = SimClock.now()
	while pilot.current.id != &"evade" and SimClock.now() - hit_s < 2.0:
		await get_tree().physics_frame
	Engine.time_scale = 1.0
	assert_eq(pilot.current.id, &"evade", "it evades when hit")
	assert_eq(shots[0], 0, "it never fires")


func test_spawns_and_the_console_set_skill_and_aggression() -> void:
	assert_true(_exec("spawn raider ai 2000 skill=ace aggression=reckless").ok)
	var raider: Combatant = main.ships.alive(ShipPool.DEFAULT_TYPE)[0]
	var pilot := raider.driver.brain as AiPilot
	assert_eq(pilot.temperament.skill, 0.95)
	assert_eq(pilot.temperament.aggression, 1.0)
	assert_false(_exec("spawn raider idle 2000 skill=ace").ok, "only an ai spawn takes them")
	assert_false(_exec("spawn raider ai 2000 skill=godlike").ok)
	var result: ConsoleResult = _exec("ai %s skill rookie" % raider.display_name)
	assert_true(result.ok, str(result.lines))
	assert_eq(pilot.temperament.skill, 0.2)
	assert_almost_eq(pilot.profile.aim_error_deg, pilot.base_profile.aim_error_deg * 2.5, 1e-9, "retuned: the rookie's aim")
	assert_almost_eq((pilot.behaviour(&"attack") as BehaviourAttack).aim_error_rad, deg_to_rad(pilot.profile.aim_error_deg), 1e-9)
	assert_true(_exec("ai %s aggression 0.3" % raider.display_name).ok)
	assert_eq(pilot.temperament.aggression, 0.3)
	assert_false(_exec("ai %s aggression berserk" % raider.display_name).ok)
	var lines: String = "\n".join(_exec("ai %s" % raider.display_name).lines)
	assert_string_contains(lines, "skill rookie 0.20")
	assert_string_contains(lines, "aggression cautious 0.30")
