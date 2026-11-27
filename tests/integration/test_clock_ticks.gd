extends GutTest
## The native beats and seeded rolls count the sim clock's ticks (M10-T11 fix): the tier rows' beat, the tier's fire rolls, the
## defensive turrets' and the capital guns' spreads used to count the core's syncs, which also hold whatever ticks a scene ran
## before its clock started (one in a process's first main scene, two in the next), so the same scene played differently as a
## first and a second scene once a test or a mission started its clock. The tier fight runs three times in one process with
## its clock started after the scene's first frames (the first run is the process's first main scene, with a sync fewer, when
## this file runs alone), the last with one thread; the turret fight twice, the second with extra syncs before it starts and
## one thread. Every tick must be the same.

const TICKS: int = 360
const TRANSPORT: StringName = &"starfury_ally"
const RAIDER: StringName = &"raider_fighter"
const RAIDER_AI: Dictionary = {"type": "ai", "profile": "raider"}
const EXTRA_SYNCS: int = 3

var _settings_backup: Dictionary = {}


func before_all() -> void:
	CapitalHangar.stocked_on_spawn = false


func after_all() -> void:
	CapitalHangar.stocked_on_spawn = true


func before_each() -> void:
	get_tree().paused = false
	_settings_backup = {&"perf_threads": Settings.get_value(&"perf_threads"),
			&"physics_max_steps_per_frame": Settings.get_value(&"physics_max_steps_per_frame")}
	Settings.set_value(&"physics_max_steps_per_frame", 1)


func after_each() -> void:
	for key: StringName in _settings_backup:
		Settings.set_value(key, _settings_backup[key])


func test_turret_fire_is_the_same_whatever_ran_before_the_clock() -> void:
	var plain: Dictionary = await _turret_fight(6, 0)
	var shifted: Dictionary = await _turret_fight(1, EXTRA_SYNCS)
	assert_gt(int(plain["shots"]), 4, "the turrets fired (%d shots)" % int(plain["shots"]))
	for key: String in ["turrets", "hits"]:
		assert_eq(_first_difference(plain[key], shifted[key]), -1, "%s: the same every tick" % key)
	assert_eq(int(shifted["shots"]), int(plain["shots"]), "the same shots")


func test_the_tier_flies_and_fires_the_same_as_a_first_and_as_a_later_scene() -> void:
	var first: Dictionary = await _tier_fight(6)
	var second: Dictionary = await _tier_fight(6)
	var one: Dictionary = await _tier_fight(1)
	assert_gt(int(first["tiered"]), 4, "the fight is in the tier (%d rows)" % int(first["tiered"]))
	assert_gt(int(first["beats"]), 0, "rows beat")
	assert_eq(_first_difference(first["rows"], second["rows"]), -1, "a later scene: every row's motion and hull the same")
	assert_eq(_first_difference(second["rows"], one["rows"]), -1, "one thread: every row's motion and hull the same")
	assert_eq(int(second["beats"]), int(first["beats"]), "the same beats")
	gut.p("core syncs before the fight: %d, %d, %d" % [int(first["syncs"]), int(second["syncs"]), int(one["syncs"])])


# Two turreted transports and four AI raiders (`test_turret_threads`' fight), `extra` syncs before the first tick.
func _turret_fight(threads: int, extra: int) -> Dictionary:
	await get_tree().process_frame
	await get_tree().physics_frame
	var scene: TurretScene = TurretScene.build(self, &"threaded", threads)
	var transports: Array[Combatant] = []
	for i: int in 2:
		var t: Combatant = scene.ship(TRANSPORT, Factions.EARTH_ALLIANCE, "TRANSPORT %d" % (i + 1), Vector3(800.0 * i, 0.0, 0.0),
				{}, 1, true)
		scene.mount(t, Vector3(0.0, 3.0, -3.0), Vector3.UP, 200.0, "dorsal_fwd")
		scene.mount(t, Vector3(0.0, -2.0, 3.0), Vector3.DOWN, 200.0, "ventral_aft")
		transports.append(t)
	var raiders: Array[Combatant] = []
	for i: int in 4:
		var at := Vector3(-300.0 + 450.0 * i, 250.0 * (1 - 2 * (i % 2)), -900.0 - 120.0 * i)
		raiders.append(scene.ship(RAIDER, Factions.RAIDERS, "RAIDER %d" % (i + 1), at, RAIDER_AI, 11 + i, false,
				Basis.looking_at(-at.normalized(), Vector3.UP)))
	scene.attach()
	for k: int in extra:
		scene.sim.sync_now()
	var turrets := PackedInt64Array()
	var hits := PackedInt64Array()
	var seen: int = 0
	for t: int in TICKS:
		if t == 2:
			for i: int in raiders.size():
				scene.sim.note_hit(transports[i % 2].ship.get_instance_id(), raiders[i].ship.get_instance_id())
		await get_tree().physics_frame
		turrets.append(int(scene.sim.core.turret_digest()))
		hits.append(hash(_by_ship(scene, scene.hits.slice(seen))))
		seen = scene.hits.size()
	var out: Dictionary = {"turrets": turrets, "hits": hits, "shots": scene.sim.core.turret_readouts()[0]}
	await scene.free_scene(get_tree())
	return out


# Four raiders and four allies on their AI fighting 15 km off in the low-attention tier, in free flight.
func _tier_fight(threads: int) -> Dictionary:
	Settings.set_value(&"perf_threads", threads)
	var main := (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.waves_auto_start = false
	main.raider_pool_size = 4
	main.ally_pool_size = 4
	add_child(main)
	await wait_physics_frames(2)
	DebugConsole.flags.invulnerable = true
	var sim: SimCore = SimCore.for_tree(get_tree())
	var syncs: int = int(sim.core.syncs())
	SimClock.reset()  # the fight's clock starts here in every run, as a test's or a mission's does
	var basis: Basis = main.ship.global_basis
	var centre: Vector3 = main.ship.global_position - basis.z * 15000.0
	var ships: Array[Combatant] = []
	for kind: String in ["raider", "ally"]:
		var type: StringName = ShipPool.DEFAULT_TYPE if kind == "raider" else ShipPool.ALLY_TYPE
		for k: int in 4:
			assert_true(DebugConsole.registry.execute("spawn %s ai 900" % kind)[0].ok)
			var alive: Array[Combatant] = main.ships.alive(type)
			var c: Combatant = alive[alive.size() - 1]
			var side: float = -300.0 if kind == "raider" else 300.0
			c.ship.global_transform = Transform3D(basis, centre + basis * Vector3(side, 40.0 * k, 60.0 * k))
			c.ship.linear_velocity = main.world.rest_velocity()
			ships.append(c)
	var rows := PackedInt64Array()
	var tiered: int = 0
	var beats0: int = int(sim.core.tier_beats())
	for t: int in TICKS:
		await get_tree().physics_frame
		var tick: Array = []
		var in_tier: int = 0
		for c: Combatant in ships:
			var pose: Array = TierDirector.row_pose(c.ship) if c.ship.has_meta(TierDirector.TIER_META) else []
			in_tier += 0 if pose.is_empty() else 1
			tick.append([pose[0] if not pose.is_empty() else c.ship.global_transform,
					pose[1] if not pose.is_empty() else c.ship.linear_velocity, c.damageable.hull.hp])
		tiered = maxi(tiered, in_tier)
		rows.append(hash(var_to_str(tick)))
	var out: Dictionary = {"rows": rows, "tiered": tiered, "beats": int(sim.core.tier_beats()) - beats0, "syncs": syncs}
	DebugConsole.flags.invulnerable = false
	remove_child(main)
	main.queue_free()
	await get_tree().physics_frame
	return out


# Hits with each ship named by its place in the scene (instance ids differ between runs).
static func _by_ship(scene: TurretScene, landed: Array) -> Array:
	var place: Dictionary = {}
	for i: int in scene.ships.size():
		place[scene.ships[i].ship.get_instance_id()] = i
	var out: Array = []
	for h: Array in landed:
		out.append([place.get(int(h[0]), -1), place.get(int(h[1]), -1), h[2]])
	return out


static func _first_difference(a: PackedInt64Array, b: PackedInt64Array) -> int:
	for i: int in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return i
	return -1 if a.size() == b.size() else mini(a.size(), b.size())
