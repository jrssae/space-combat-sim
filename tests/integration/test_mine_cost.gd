extends GutTest
## What the mine rows cost a tick (M10-T15, D12.9): 500 mines of no side's (so none goes off: the steady cost of the triggers and
## touches, the worst case) laid through the seeded battle's first fight, with the fighters flying round and through them. Reports
## the median and the 99th percentile of the rows' step, with one thread and six, and keeps the median under a budget.

const TICKS: int = 600
const MINES: int = 500
## The step's median must stay under this, us: the whole battle's tick is milliseconds, so a field of hundreds is cheap beside it.
const BUDGET_MEDIAN_US: float = 150.0

var _threads_backup: Variant = null


func before_each() -> void:
	_threads_backup = Settings.get_value(&"perf_threads")


func after_each() -> void:
	Settings.set_value(&"perf_threads", _threads_backup)


func test_five_hundred_mines_through_a_furball_cost_little_a_tick() -> void:
	for threads: int in [1, 6]:
		var cost: Array[float] = await _measure(threads)
		cost.sort()
		var median: float = cost[cost.size() / 2]
		gut.p("500 mines, %d thread(s): median %.1f us, p99 %.1f us, max %.1f us a tick" % [threads, median, cost[cost.size() * 99 / 100], cost.back()])
		assert_lt(median, BUDGET_MEDIAN_US, "the mine rows' median step with %d thread(s)" % threads)


func _measure(threads: int) -> Array[float]:
	Settings.set_value(&"perf_threads", threads)
	var fight: Dictionary = await SeededBattle.start(self)
	var ships: Array[Combatant] = fight["ships"]
	var world: WorldFrame = fight["world"]
	var centre: Vector3 = ships[0].ship.global_position
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var rows: Array[Dictionary] = []
	for i: int in MINES:
		rows.append({"offset": Vector3(rng.randf_range(-700.0, 700.0), rng.randf_range(-700.0, 700.0), rng.randf_range(-700.0, 700.0)),
				"faction": Factions.NEUTRAL, "kind": &"mine_prox"})
	var field: MineField = MineField.spawn_in(world, world.to_universe(centre), true)
	field.build(rows)
	var cost: Array[float] = []
	for t: int in TICKS:
		await get_tree().physics_frame
		cost.append(field.step_us)
	assert_gt(field.alive_count(), MINES - 25, "(a few were touched by a fighter flying through)")
	await SeededBattle.finish(fight)
	return cost
