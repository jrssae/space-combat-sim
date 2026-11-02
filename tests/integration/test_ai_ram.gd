extends GutTest
## AC20, the last-ditch ram in Jolt (M3-T13, Q12): a committed rammer (a reckless raider at 20 % hull) flies into a Starfury
## drone (no brain, so no avoidance of its own) crossing ahead of it and hits it (`RamResolver` reports the ram) in at least 8
## of 10 seeded runs, its own avoidance leaving that one target out; and in the dogfight no ship below reckless ever rams. The
## real main scene, Jolt, the real drivers and resolvers; sim time sped up.

const SPEED_UP: float = 4.0
const RUNS: int = 10

var _scale_backup: float = 1.0


func before_each() -> void:
	_scale_backup = Engine.time_scale
	get_tree().paused = false
	DebugConsole.flags.invulnerable = true
	ContactScan.invalidate()


func after_each() -> void:
	Engine.time_scale = _scale_backup
	DebugConsole.flags.invulnerable = false
	ContactScan.invalidate()


func _launch(path: String = "") -> Main:
	var main := (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.waves_auto_start = false
	if not path.is_empty():
		main.scenario_path = path
	add_child(main)
	await get_tree().physics_frame
	return main


func _close(main: Main) -> void:
	remove_child(main)
	main.free()
	ContactScan.invalidate()
	await get_tree().physics_frame


func test_a_committed_rammer_hits_its_target_in_at_least_8_of_10_runs() -> void:
	var main: Main = await _launch()
	DebugConsole.registry.execute("despawn all")
	var hit_runs: int = 0
	var lines := PackedStringArray()
	for run: int in RUNS:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(["ram run", run])
		var origin: UniversePos = main.world.to_universe(main.ship.global_position).plus_local(Vector3(0.0, 3000.0 + 2000.0 * run, 0.0))
		# The target crosses ahead at 40-90 m/s; the rammer starts 1-2 km away, at an angle, at rest.
		var crossing := Vector3(rng.randf_range(40.0, 90.0), 0.0, 0.0).rotated(Vector3.UP, rng.randf_range(-0.5, 0.5))
		# A drone: no brain, so no avoidance (every AI driver dodges, an idle one too, and a dodging AI ship slips a ram).
		var target: Combatant = main.ships.acquire("ALPHA 9", origin, Basis.IDENTITY, crossing, null, ShipPool.ALLY_TYPE)
		target.damageable.hull = HullHealth.new(1.0e6)
		var start := Vector3(rng.randf_range(-600.0, 600.0), rng.randf_range(-300.0, 300.0), rng.randf_range(1000.0, 2000.0))
		var made: Dictionary = BrainFactory.from_behaviour({"type": "ai", "profile": "raider", "aggression": "reckless"},
				origin, hash(["rammer", run]))
		var rammer: Combatant = main.ships.acquire("RAIDER 9", origin.plus_local(start), ScenarioLoader.basis_facing(-start),
				Vector3.ZERO, made["brain"] as PilotBrain, ShipPool.DEFAULT_TYPE)
		rammer.damageable.hull.apply(rammer.damageable.hull.max_hp * 0.8)  # 20 % left
		await get_tree().physics_frame
		await get_tree().physics_frame
		var pilot := rammer.driver.brain as AiPilot
		var ram := pilot.behaviour(&"ram") as BehaviourRam
		assert_true(ram.commit(pilot.context), "run %d: committed" % run)
		var rammed: Array[bool] = [false]
		var ids: Array[int] = [rammer.ship.get_instance_id(), target.ship.get_instance_id()]
		var on_ram := func(info: HitInfo) -> void:
			if ids.has(info.target_id) and ids.has(info.shooter_id):
				rammed[0] = true
		main.rams.ram_resolved.connect(on_ram)
		Engine.time_scale = SPEED_UP
		var t0: float = SimClock.now()
		var flew_ram: bool = false
		var closest: float = INF
		while not rammed[0] and SimClock.now() - t0 < 40.0 and rammer.ship.can_process():
			await get_tree().physics_frame
			flew_ram = flew_ram or pilot.current.id == &"ram"
			closest = minf(closest, rammer.ship.global_position.distance_to(target.ship.global_position))

		Engine.time_scale = 1.0
		main.rams.ram_resolved.disconnect(on_ram)
		lines.append("%d:%s%s" % [run, "hit" if rammed[0] else "miss", "" if flew_ram else " (never flew it)"])
		hit_runs += 1 if rammed[0] else 0
		main.ships.release(rammer)
		main.ships.release(target)
		await get_tree().physics_frame
	gut.p("rams: %d of %d hit (%s)" % [hit_runs, RUNS, ", ".join(lines)])
	assert_gte(hit_runs, 8, "a committed rammer hits its target in at least 8 of 10 runs")
	await _close(main)


func test_in_the_dogfight_no_ship_below_reckless_ever_rams() -> void:
	Engine.time_scale = 6.0
	await get_tree().physics_frame
	SimClock.reset()
	var main: Main = await _launch("res://data/scenarios/dogfight.json")
	var rammers: Dictionary = {}
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < 360.0 and main.ships.alive(ShipPool.ALLY_TYPE).size() > 0 \
			and main.ships.alive(ShipPool.DEFAULT_TYPE).size() > 0:
		await get_tree().physics_frame
		for c: Combatant in main.ships.alive():
			var pilot := c.driver.brain as AiPilot
			if pilot != null and pilot.current != null and pilot.current.id == &"ram":
				rammers[c.display_name] = pilot.temperament.aggression
	Engine.time_scale = 1.0
	gut.p("dogfight rammers: %s" % str(rammers))
	for ship_name: Variant in rammers:
		assert_eq(float(rammers[ship_name]), 1.0, "%s rammed below reckless" % ship_name)
	await _close(main)
