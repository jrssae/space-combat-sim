extends GutTest
## Capital brains with threads (M10-T16, D12.10, Q70, architecture §17.13): the capital brains think in the AI job one tick
## behind on its frozen rows and their helms fly on the main thread, so two Omegas a side released to their brains across the
## seeded battle (`SeededBattle`), its fighters running on them, keep the same brains, helms and orders, and the battle the
## same ships' places, byte for byte with one thread and six. Reports the helm's and the brain's cost per capital per tick.

const TICKS: int = 900
const TYPE: StringName = &"ea_omega"
const GAP_M: float = 2600.0

var _threads_backup: Variant = null


func before_all() -> void:
	CapitalHangar.stocked_on_spawn = false  # its capitals are alone here: their hangars stay empty (M10-T17)


func after_all() -> void:
	CapitalHangar.stocked_on_spawn = true


func before_each() -> void:
	_threads_backup = Settings.get_value(&"perf_threads")


func after_each() -> void:
	Settings.set_value(&"perf_threads", _threads_backup)


func test_four_omegas_across_a_seeded_battle_think_and_steer_the_same_with_one_thread_and_six() -> void:
	var one: Dictionary = await _battle(1)
	var six: Dictionary = await _battle(6)
	assert_gt(int(one["thinks"]), 4 * TICKS / 12 - 8, "every capital thought at 5 Hz (%d thinks)" % int(one["thinks"]))
	assert_true((one["states"] as Dictionary).has(&"engage") or (one["states"] as Dictionary).has(&"approach"),
			"they fought (%s)" % one["states"])
	var first_brain: int = _first_difference(one["brains"], six["brains"])
	var first_ships: int = _first_difference(one["ships"], six["ships"])
	assert_eq(first_brain, -1, "every capital's state, target, aim, attitude, helm and order alike each tick (first at %d)" % first_brain)
	assert_eq(first_ships, -1, "every ship's place alike each tick (first at %d)" % first_ships)


func _first_difference(a: Array, b: Array) -> int:
	if a.size() != b.size():
		return mini(a.size(), b.size())
	for i: int in a.size():
		if a[i] != b[i]:
			return i
	return -1


# The seeded battle with `threads` threads and an Earth Alliance and a raider Omega pair either side of its first fight, left to
# their brains: each tick the capitals' digest and a hash of every ship's place, the thinks, the states at the end.
func _battle(threads: int) -> Dictionary:
	Settings.set_value(&"perf_threads", threads)
	var fight: Dictionary = await SeededBattle.start(self)
	var ships: Array[Combatant] = fight["ships"]
	var world: WorldFrame = fight["world"]
	var sim: SimCore = fight["sim"]
	var centre: Vector3 = ships[0].ship.global_position
	var caps: Array[CapitalShip] = []
	for k: int in 4:
		var side: int = 1 if k < 2 else -1
		var faction: StringName = Factions.EARTH_ALLIANCE if side > 0 else Factions.RAIDERS
		var basis: Basis = Basis.IDENTITY if side > 0 else Basis(Vector3.UP, PI)
		var cap: CapitalShip = CapitalShip.create(TYPE, faction, "Omega %d" % k, Vector3.ZERO)
		assert_not_null(cap, "the Omega is generated (scripts/gen_assets.sh)")
		world.spawn(cap, world.to_universe(centre + Vector3(1400.0 * float(k % 2) - 700.0, 0.0, GAP_M * side)), basis)
		cap.damageable.invulnerable = true
		caps.append(cap)
	var start: PackedInt64Array = sim.core.capital_readouts()
	var flight: CapitalFlight = CapitalFlight.of(world)
	var brains: Array[int] = []
	var places: Array[int] = []
	var flight_us: Array[float] = []
	for t: int in TICKS:
		await get_tree().physics_frame
		brains.append(int(sim.core.capital_digest()))
		var text: String = ""
		for c: Combatant in ships:
			if is_instance_valid(c.ship):
				text += str(c.ship.global_position)
		for cap: CapitalShip in caps:
			text += str(cap.global_position) + str(cap.global_basis)
		places.append(text.hash())
		flight_us.append(float(flight.last_us))
	var end: PackedInt64Array = sim.core.capital_readouts()
	var states: Dictionary = {}
	for cap: CapitalShip in caps:
		var s: StringName = CapitalBrains.of(world).brain_state(cap).get("state", &"")
		states[s] = int(states.get(s, 0)) + 1
	if threads == 1:
		flight_us.sort()
		var thinks: int = int(end[3] - start[3])
		var helms: int = int(end[6] - start[6])
		gut.p("capital brains among %d rows, 4 Omegas: brain %.2f us a think (%.2f us a tick a capital at 5 Hz), helm %.2f us a capital a tick (the packing included); the whole capital flight median %.1f us (%.1f a capital)" % [
				int(sim.core.row_count()), float(end[4] - start[4]) / 1000.0 / maxf(thinks, 1),
				float(end[4] - start[4]) / 1000.0 / float(TICKS * caps.size()), float(end[7] - start[7]) / 1000.0 / maxf(helms, 1),
				flight_us[flight_us.size() / 2], flight_us[flight_us.size() / 2] / float(caps.size())])
	var out: Dictionary = {"brains": brains, "ships": places, "thinks": int(end[3] - start[3]), "states": states}
	await SeededBattle.finish(fight)
	return out
