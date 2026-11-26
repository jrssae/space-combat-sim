extends GutTest
## Capital interceptors with threads (M10-T13, Q81, architecture §17.13): the batteries step on the main thread over the rows of
## the tick's sync, after the AI job's commands are applied, so two hostile Omegas side by side across the seeded battle
## (`SeededBattle`), their guns, missiles and batteries working on each other and on its fighters' shots, fire the same pulses
## and shoot down the same shots byte for byte with one thread and six. Reports the batteries' counts.

const TICKS: int = 900
const TYPE: StringName = &"ea_omega"
const GAP_M: float = 1600.0

var _threads_backup: Variant = null


func before_all() -> void:
	CapitalHangar.stocked_on_spawn = false  # its capitals are alone here: their hangars stay empty (M10-T17)


func after_all() -> void:
	CapitalHangar.stocked_on_spawn = true


func before_each() -> void:
	_threads_backup = Settings.get_value(&"perf_threads")


func after_each() -> void:
	Settings.set_value(&"perf_threads", _threads_backup)


func test_two_omegas_across_a_seeded_battle_intercept_the_same_with_one_thread_and_six() -> void:
	var one: Dictionary = await _battle(1)
	var six: Dictionary = await _battle(6)
	var r: PackedInt64Array = one["readouts"]
	gut.p("interceptors: %d pulses, %d met; down bolts %d, heavy %d, missiles %d, torpedoes %d" % [r[0], r[1], r[2], r[3], r[4],
			r[5]])
	assert_gt(r[0], 20, "the batteries fire")
	assert_gt(r[1], 0, "and meet shots")
	assert_eq(one["readouts"], six["readouts"], "the same counts")
	var first: int = -1
	for i: int in mini((one["digests"] as Array).size(), (six["digests"] as Array).size()):
		if one["digests"][i] != six["digests"][i]:
			first = i
			break
	assert_eq(first, -1, "every mount's aim, gate and pulses alike each tick (first difference at tick %d)" % first)
	assert_eq(one["pulses"], six["pulses"], "the same pulses, tick by tick")


# The seeded battle with `threads` threads and an Earth Alliance and a raider Omega either side of its first fight: the guns'
# digest each tick (it holds the batteries' state and counts), the pulses fired each tick, and the batteries' readouts.
func _battle(threads: int) -> Dictionary:
	Settings.set_value(&"perf_threads", threads)
	var fight: Dictionary = await SeededBattle.start(self)
	var ships: Array[Combatant] = fight["ships"]
	var world: WorldFrame = fight["world"]
	var centre: Vector3 = ships[0].ship.global_position
	for pair: Array in [[Factions.EARTH_ALLIANCE, "Omega A", 1.0], [Factions.RAIDERS, "Omega B", -1.0]]:
		var cap: CapitalShip = CapitalShip.create(TYPE, pair[0], pair[1], Vector3.ZERO)
		assert_not_null(cap, "the Omega is generated (scripts/gen_assets.sh)")
		world.spawn(cap, world.to_universe(centre + Vector3(GAP_M * float(pair[2]), 0.0, 0.0)), Basis.IDENTITY)
		cap.set_course(Vector3.FORWARD, Vector3.ZERO)
		cap.damageable.invulnerable = true
		CapitalBeams.of(world).hold(cap, true)
	var guns: CapitalGuns = CapitalGuns.of(world)
	guns.reset_stats()
	var digests: Array[int] = []
	var pulses: Array[int] = []
	for t: int in TICKS:
		await get_tree().physics_frame
		digests.append(guns.digest())
		pulses.append(guns.pulses)
	var out: Dictionary = {"digests": digests, "pulses": pulses, "readouts": guns.intercept_readouts()}
	await SeededBattle.finish(fight)
	return out
