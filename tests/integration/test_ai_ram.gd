extends GutTest
## AC20, the last-ditch ram in Jolt (M3-T13, Q12): a committed rammer (a reckless raider at 20 % hull) flies into a Starfury
## drone (no brain, so no avoidance of its own) crossing ahead of it and hits it (`RamResolver` reports the ram) in at least 8
## of 10 seeded runs, its own avoidance leaving that one target out; and in the dogfight no ship below reckless ever rams, while a
## hurt reckless raider left alone there chooses the ram from the fight at the AI's far think rate (M4-T04). The
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
	var run: Dictionary = await _dogfight(Callable())
	var rammers: Dictionary = run["rammers"]
	var seen: Dictionary = run["seen"]
	gut.p("dogfight rammers: %s of %d pilots" % [str(rammers), seen.size()])
	assert_gt(seen.size(), 0, "the dogfight flew AI pilots")
	for ship_name: Variant in seen:
		if float(seen[ship_name]) < 1.0:
			assert_false(rammers.has(ship_name), "%s rammed below reckless" % ship_name)


func test_in_the_dogfight_a_hurt_reckless_raider_left_alone_rams_at_the_far_rate() -> void:
	# Whether the full dogfight gets a reckless raider low enough to ram depends on how it goes, so this pins the case: RAIDER 4
	# (reckless) at 20 % hull, kept there, with the rest of the raiders gone and the player 30 km off, so it decides at the far
	# rate (M4-T04). It must choose the ram itself, from the fight, and no ally below reckless may.
	var setup := func(main: Main) -> void:
		main.ship.global_position += Vector3(30000.0, 0.0, 0.0)
		for c: Combatant in main.ships.alive(ShipPool.DEFAULT_TYPE):
			if c.display_name == "RAIDER 4":
				c.damageable.hull.apply(c.damageable.hull.max_hp * 0.8)
				c.damageable.invulnerable = true
			else:
				main.ships.release(c)
	var run: Dictionary = await _dogfight(setup, &"RAIDER 4")
	var rammers: Dictionary = run["rammers"]
	gut.p("hurt reckless raider alone: rammers %s, first ram at %.1f s, near the player then: %s" % [str(rammers),
			float(run["ram_at_s"]), str(run["ram_near"])])
	assert_true(rammers.has("RAIDER 4"), "the hurt reckless raider chose the ram")
	assert_false(bool(run["ram_near"]), "at the far rate (the player 30 km off)")
	for ship_name: Variant in run["seen"] as Dictionary:
		if float((run["seen"] as Dictionary)[ship_name]) < 1.0:
			assert_false(rammers.has(ship_name), "%s rammed below reckless" % ship_name)


# Flies the dogfight scenario at 6x for up to 360 s of sim time, or until one side is gone, or (with `until_ram`) until that
# ship rams. `setup` changes the scene after launch. Returns the pilots seen and their aggression, who flew a ram, and when and
# whether near the player `until_ram` first did.
func _dogfight(setup: Callable, until_ram: String = "") -> Dictionary:
	Engine.time_scale = 6.0
	await get_tree().process_frame  # the scale counts from the next main-loop iteration
	await get_tree().physics_frame
	SimClock.reset()
	var main: Main = await _launch("res://data/scenarios/dogfight.json")
	if setup.is_valid():
		setup.call(main)
	var out: Dictionary = {"rammers": {}, "seen": {}, "ram_at_s": -1.0, "ram_near": false}
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < 360.0 and main.ships.alive(ShipPool.ALLY_TYPE).size() > 0 \
			and main.ships.alive(ShipPool.DEFAULT_TYPE).size() > 0 and not (out["rammers"] as Dictionary).has(until_ram):
		await get_tree().physics_frame
		for c: Combatant in main.ships.alive():
			var pilot := c.driver.brain as AiPilot
			if pilot == null:
				continue
			out["seen"][c.display_name] = pilot.temperament.aggression
			if pilot.current != null and pilot.current.id == &"ram" and not (out["rammers"] as Dictionary).has(c.display_name):
				out["rammers"][c.display_name] = pilot.temperament.aggression
				if c.display_name == until_ram:
					out["ram_at_s"] = SimClock.now() - t0
					out["ram_near"] = c.driver.near_player
	Engine.time_scale = 1.0
	await _close(main)
	return out
