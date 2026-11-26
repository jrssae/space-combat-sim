extends GutTest
## Carriers launching with threads (M10-T17, D12.10, architecture §17.13): an Earth Alliance Nova and a raider Omega either side
## of the seeded battle (`SeededBattle`), their hangars stocked and left to launch on the threats their native brains count, keep
## the same brains (threats, the Launch state), the same launches and the same ships' places, byte for byte with one thread and
## six. Reports the hangars' cost per carrier per tick.

const TICKS: int = 1200
const GAP_M: float = 2600.0

var _threads_backup: Variant = null


func before_each() -> void:
	_threads_backup = Settings.get_value(&"perf_threads")


func after_each() -> void:
	Settings.set_value(&"perf_threads", _threads_backup)


func test_two_carriers_launch_the_same_with_one_thread_and_six() -> void:
	var one: Dictionary = await _battle(1)
	var six: Dictionary = await _battle(6)
	assert_gt(int(one["sent"]), 6, "they launched (%d craft)" % int(one["sent"]))
	assert_true((one["states"] as Dictionary).has(&"launch"), "a carrier held its course while launching (%s)" % one["states"])
	assert_eq(int(one["sent"]), int(six["sent"]), "the same launches")
	var first_brain: int = _first_difference(one["brains"], six["brains"])
	var first_ships: int = _first_difference(one["ships"], six["ships"])
	assert_eq(first_brain, -1, "every capital's brain, threats included, alike each tick (first at %d)" % first_brain)
	assert_eq(first_ships, -1, "every ship's place, launched craft included, alike each tick (first at %d)" % first_ships)


func _first_difference(a: Array, b: Array) -> int:
	if a.size() != b.size():
		return mini(a.size(), b.size())
	for i: int in a.size():
		if a[i] != b[i]:
			return i
	return -1


func _battle(threads: int) -> Dictionary:
	Settings.set_value(&"perf_threads", threads)
	var fight: Dictionary = await SeededBattle.start(self)
	var ships: Array[Combatant] = fight["ships"]
	var world: WorldFrame = fight["world"]
	var sim: SimCore = fight["sim"]
	var pool := ShipPool.new()
	pool.name = "ShipPool"
	pool.world = world
	pool.projectiles = world.get_node("Projectiles") as Node3D
	world.add_child(pool)
	var centre: Vector3 = ships[0].ship.global_position
	var caps: Array[CapitalShip] = []
	var plan: Array = [[&"ea_nova", Factions.EARTH_ALLIANCE, 1.0], [&"ea_omega", Factions.RAIDERS, -1.0]]
	for p: Array in plan:
		var basis: Basis = Basis.IDENTITY if float(p[2]) > 0.0 else Basis(Vector3.UP, PI)
		var cap: CapitalShip = CapitalShip.create(p[0], p[1], String(p[0]), Vector3.ZERO)
		assert_not_null(cap, "%s is generated (scripts/gen_assets.sh)" % p[0])
		world.spawn(cap, world.to_universe(centre + Vector3(0.0, 0.0, GAP_M * float(p[2]))), basis)
		cap.damageable.invulnerable = true
		cap.hangar.stock_from_loadout()
		cap.hangar.prepare_pool()
		caps.append(cap)
	var brains: Array[int] = []
	var places: Array[int] = []
	var states: Dictionary = {}
	for t: int in TICKS:
		await get_tree().physics_frame
		brains.append(int(sim.core.capital_digest()))
		var text: String = ""
		for c: Combatant in pool.all_ships() + ships:
			if is_instance_valid(c.ship) and c.ship.visible:
				text += str(c.ship.global_position)
		for cap: CapitalShip in caps:
			text += str(cap.global_position) + str(cap.hangar.sent) + str(cap.hangar.queued_count())
			var s: StringName = CapitalBrains.of(world).brain_state(cap).get("state", &"")
			states[s] = int(states.get(s, 0)) + 1
		places.append(text.hash())
	var sent: int = 0
	for cap: CapitalShip in caps:
		sent += cap.hangar.sent
	if threads == 1:
		var us: float = 0.0
		for cap: CapitalShip in caps:
			us += cap.hangar.tick_us / maxf(float(cap.hangar.ticks), 1.0)
		gut.p("two carriers: %d craft sent, %d wings, states %s; the hangar %.1f us a carrier a tick" % [sent,
				caps[0].hangar.wings_sent + caps[1].hangar.wings_sent, states, us / float(caps.size())])
	var out: Dictionary = {"brains": brains, "ships": places, "sent": sent, "states": states}
	await SeededBattle.finish(fight)
	return out
