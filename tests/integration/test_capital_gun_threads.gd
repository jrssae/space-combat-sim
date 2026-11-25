extends GutTest
## Capital guns and launchers with threads (M10-T14, D12.9, architecture §17.13): the gun rows step on the main thread over the
## rows of the tick's sync, after the AI job's commands are applied, so two hostile Omegas side by side across the seeded battle
## (`SeededBattle`), their turrets and missiles taking its fighters and each other, fire the same shots and land the same hits
## byte for byte with one thread and six. Reports the guns' cost there.

## 20 s: Q76's slower turrets (10 deg/s) and 3 s bursts take that long to land a fair sample.
const TICKS: int = 1200
const TYPE: StringName = &"ea_omega"
const GAP_M: float = 1600.0

var _threads_backup: Variant = null


func before_each() -> void:
	_threads_backup = Settings.get_value(&"perf_threads")


func after_each() -> void:
	Settings.set_value(&"perf_threads", _threads_backup)


func test_two_omegas_across_a_seeded_battle_fire_and_land_the_same_with_one_thread_and_six() -> void:
	var one: Dictionary = await _battle_guns(1)
	var six: Dictionary = await _battle_guns(6)
	var hits: Array = one["hits"]
	assert_gt(hits.size(), 20, "the guns land (%d hits)" % hits.size())
	assert_gt(int(one["missiles"]), 0, "missiles launched")
	gut.p("capital gun hits: %d (on fighters %d), shots %d, missiles %d" % [hits.size(),
			hits.filter(func(e: Array) -> bool: return int(e[0]) >= 0).size(), int(one["shots"]), int(one["missiles"])])
	assert_eq(one["digests"], six["digests"], "every mount's aim, target, gate and shots alike each tick")
	assert_eq(hits.size(), (six["hits"] as Array).size(), "the same count of hits")
	var first: int = -1
	for i: int in mini(hits.size(), (six["hits"] as Array).size()):
		if hits[i] != six["hits"][i]:
			first = i
			break
	assert_eq(first, -1, "the same hits, damage and points byte for byte (first difference at %d)" % first)


# The seeded battle with `threads` threads and an Earth Alliance and a raider Omega either side of its first fight, side by
# side: every hit an Omega's gun, missile or warhead lands as [the hull's place in the battle (-1, -2 the Omegas), the tick,
# cause, damage, point], the guns' digest each tick, and the shots and missiles fired.
func _battle_guns(threads: int) -> Dictionary:
	Settings.set_value(&"perf_threads", threads)
	var fight: Dictionary = await SeededBattle.start(self)
	var ships: Array[Combatant] = fight["ships"]
	var index_of: Dictionary = fight["index_of"]
	var world: WorldFrame = fight["world"]
	var centre: Vector3 = ships[0].ship.global_position
	var a: CapitalShip = _omega(world, Factions.EARTH_ALLIANCE, "Omega A", centre + Vector3(GAP_M, 0.0, 0.0))
	var b: CapitalShip = _omega(world, Factions.RAIDERS, "Omega B", centre - Vector3(GAP_M, 0.0, 0.0))
	var omega_ids: Array[int] = [a.get_instance_id(), b.get_instance_id()]
	var log: Array = []
	var tick: Array[int] = [0]
	var note: Callable = func(place: int, info: HitInfo) -> void:
		if omega_ids.has(info.shooter_id):
			log.append([place, tick[0], info.cause, info.damage, info.point])
	for c: Combatant in ships:
		c.damageable.hit_taken.connect(func(info: HitInfo) -> void: note.call(int(index_of.get(info.target_id, -3)), info))
	for pair: Array in [[a, -1], [b, -2]]:
		var cap: CapitalShip = pair[0]
		cap.damageable.invulnerable = true
		CapitalBeams.of(world).hold(cap, true)
		CapitalGuns.of(world).hold_interceptors(cap, true)  # the guns alone; the batteries: test_capital_interceptor_threads
		cap.damageable.hit_taken.connect(func(info: HitInfo) -> void: note.call(int(pair[1]), info))
	var guns: CapitalGuns = CapitalGuns.of(world)
	guns.reset_stats()
	var digests: Array[int] = []
	var cost: Array[float] = []
	var kernel: Array[float] = []
	for t: int in TICKS:
		tick[0] = t
		await get_tree().physics_frame
		digests.append(guns.digest())
		cost.append(guns.step_us)
		kernel.append(guns.kernel_us)
	if threads == 1:
		cost.sort()
		kernel.sort()
		gut.p("capital guns among %d rows, 36 mounts, median (max) us: step %.1f (%.1f), its kernel %.1f (%.1f)" % [
				int((fight["sim"] as SimCore).core.row_count()), cost[cost.size() / 2], cost.back(), kernel[kernel.size() / 2],
				kernel.back()])
	var out: Dictionary = {"hits": log, "digests": digests, "shots": guns.shots, "missiles": guns.missiles_launched}
	await SeededBattle.finish(fight)
	return out


func _omega(world: WorldFrame, faction: StringName, label: String, at: Vector3) -> CapitalShip:
	var cap: CapitalShip = CapitalShip.create(TYPE, faction, label, Vector3.ZERO)
	assert_not_null(cap, "the Omega is generated (scripts/gen_assets.sh)")
	world.spawn(cap, world.to_universe(at), Basis.IDENTITY)
	cap.set_course(Vector3.FORWARD, Vector3.ZERO)
	return cap
