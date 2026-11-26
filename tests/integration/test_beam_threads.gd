extends GutTest
## Capital beams with threads (M10-T12, D12.9, architecture §17.13): the beam rows step on the main thread over the rows of the
## tick's sync, so two hostile Omegas beaming each other across the seeded battle (`SeededBattle`), their lines crossing its
## fighters, land the same beam hits, damage and points byte for byte with one thread and six. Reports the beams' cost there.

const TICKS: int = 300
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


func test_two_omegas_across_a_seeded_battle_land_the_same_beams_with_one_thread_and_six() -> void:
	var one: Array = await _battle_beams(1)
	var six: Array = await _battle_beams(6)
	assert_gt(one.size(), 100, "the beams land (%d hits)" % one.size())
	var on_fighters: int = one.filter(func(e: Array) -> bool: return int(e[0]) >= 0).size()
	gut.p("beam hits: %d, on fighters crossing the lines %d" % [one.size(), on_fighters])
	assert_eq(one.size(), six.size(), "the same count of beam hits")
	var first: int = -1
	for i: int in mini(one.size(), six.size()):
		if one[i] != six[i]:
			first = i
			break
	assert_eq(first, -1, "the same hits, damage and points byte for byte (first difference at %d)" % first)


# The seeded battle with `threads` threads and an Earth Alliance and a raider Omega either side of its first fight, facing
# each other: every beam hit as [the hull's place in the battle (-1, -2 the Omegas), the tick, damage, point], from the beams'
# native hit log.
func _battle_beams(threads: int) -> Array:
	Settings.set_value(&"perf_threads", threads)
	var fight: Dictionary = await SeededBattle.start(self)
	var ships: Array[Combatant] = fight["ships"]
	var index_of: Dictionary = fight["index_of"]
	var world: WorldFrame = fight["world"]
	var centre: Vector3 = ships[0].ship.global_position
	var a: CapitalShip = _omega(world, Factions.EARTH_ALLIANCE, "Omega A", centre + Vector3(0.0, 0.0, GAP_M), Basis.IDENTITY)
	var b: CapitalShip = _omega(world, Factions.RAIDERS, "Omega B", centre - Vector3(0.0, 0.0, GAP_M), Basis(Vector3.UP, PI))
	var log: Array = []
	var who: Dictionary = {}
	for pair: Array in [[a, -1], [b, -2]]:
		var cap: CapitalShip = pair[0]
		cap.damageable.invulnerable = true
		who[cap.damageable.get_instance_id()] = pair[1]
		for rotor: CapitalRotor in cap.rotors:
			who[rotor.hull.get_instance_id()] = pair[1]
	var beams: CapitalBeams = CapitalBeams.of(world)
	beams.set_hit_log(true)  # the beams' native hit log (M10-T75: they land in one batch a tick, with no `hit_taken` a hit)
	var cost: Array[float] = []
	var kernel: Array[float] = []
	var landing: Array[float] = []
	for t: int in TICKS:
		await get_tree().physics_frame
		for e: Array in beams.hit_log():
			log.append([who.get(int(e[0]), index_of.get(int(e[1]), -3)), t, e[3], e[5]])
		beams.set_hit_log(true)
		if beams != null:
			cost.append(beams.step_us)
			kernel.append(beams.kernel_us)
			landing.append(float(beams.land_us))
	if threads == 1 and not cost.is_empty():
		for list: Array[float] in [cost, kernel, landing]:
			list.sort()
		gut.p("beams among %d rows, 12 emitters, median (max) us: step %.1f (%.1f), its kernel %.1f (%.1f), landing %.1f (%.1f)" % [
				int((fight["sim"] as SimCore).core.row_count()), cost[cost.size() / 2], cost.back(), kernel[kernel.size() / 2],
				kernel.back(), landing[landing.size() / 2], landing.back()])
	await SeededBattle.finish(fight)
	return log


func _omega(world: WorldFrame, faction: StringName, label: String, at: Vector3, basis: Basis) -> CapitalShip:
	var cap: CapitalShip = CapitalShip.create(TYPE, faction, label, Vector3.ZERO)
	assert_not_null(cap, "the Omega is generated (scripts/gen_assets.sh)")
	world.spawn(cap, world.to_universe(at), basis)
	cap.set_course(-basis.z, Vector3.ZERO)
	return cap
