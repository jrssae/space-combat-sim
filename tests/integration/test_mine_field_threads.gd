extends GutTest
## Mines with threads (M10-T15, D12.9, architecture §17.13): the mine rows step on the main thread over the rows of the tick's
## sync, so a minefield laid across the seeded battle's first fight (its fighters triggering, touching and chaining it) goes off
## in the same order, with the same state each tick and the same hits, byte for byte with one thread and six. Reports the rows'
## cost there.

const TICKS: int = 600
const MINES: int = 150

var _threads_backup: Variant = null


func before_each() -> void:
	_threads_backup = Settings.get_value(&"perf_threads")


func after_each() -> void:
	Settings.set_value(&"perf_threads", _threads_backup)


func test_a_field_across_the_seeded_battle_goes_off_the_same_with_one_thread_and_six() -> void:
	var one: Dictionary = await _battle_mines(1)
	var six: Dictionary = await _battle_mines(6)
	assert_gt(int(one["gone"]), 5, "the fighters set mines off (%d of %d)" % [int(one["gone"]), MINES])
	gut.p("%d of %d mines went off, %d hits from their blasts" % [int(one["gone"]), MINES, (one["hits"] as Array).size()])
	assert_eq(one["digests"], six["digests"], "every mine's state and place alike each tick")
	assert_eq(one["order"], six["order"], "the mines went off in the same order")
	assert_eq(one["hits"], six["hits"], "the same blasts landed the same damage on the same hulls")


# The seeded battle with `threads` threads and a minefield of every side's mines laid round the first fight: the rows' digest each
# tick, the order the mines went off in, and every blast hit as [tick, hull's place in the battle, damage].
func _battle_mines(threads: int) -> Dictionary:
	Settings.set_value(&"perf_threads", threads)
	var fight: Dictionary = await SeededBattle.start(self)
	var ships: Array[Combatant] = fight["ships"]
	var index_of: Dictionary = fight["index_of"]
	var world: WorldFrame = fight["world"]
	var centre: Vector3 = ships[0].ship.global_position
	var sides: Array[StringName] = []
	for c: Combatant in ships:
		if not sides.has(c.damageable.faction):
			sides.append(c.damageable.faction)
	var rows: Array[Dictionary] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i: int in MINES:
		rows.append({"offset": Vector3(rng.randf_range(-250.0, 250.0), rng.randf_range(-250.0, 250.0), rng.randf_range(-250.0, 250.0)),
				"faction": sides[i % sides.size()], "kind": &"mine_prox"})
	var field: MineField = MineField.spawn_in(world, world.to_universe(centre), true)
	field.build(rows)
	var log: Array = []
	var order: Array[int] = []
	var tick: Array[int] = [0]
	field.detonated.connect(func(slot: int, _kind: int, _at: Vector3) -> void: order.append(slot))
	for c: Combatant in ships:
		c.damageable.hit_taken.connect(func(info: HitInfo) -> void:
			if info.cause == HitInfo.CAUSE_BLAST:
				log.append([tick[0], int(index_of.get(info.target_id, -3)), info.damage]))
	var digests: Array[int] = []
	var cost: Array[float] = []
	for t: int in TICKS:
		tick[0] = t
		await get_tree().physics_frame
		digests.append(int(field.rows.digest()))
		cost.append(field.step_us)
	if threads == 1:
		cost.sort()
		gut.p("mine rows, %d mines among %d rows, median (max) us: step %.1f (%.1f)" % [MINES,
				int((fight["sim"] as SimCore).core.row_count()), cost[cost.size() / 2], cost.back()])
	var out: Dictionary = {"digests": digests, "order": order, "hits": log, "gone": field.total_set_off()}
	await SeededBattle.finish(fight)
	return out
