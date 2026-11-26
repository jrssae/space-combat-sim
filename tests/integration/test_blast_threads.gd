extends GutTest
## The blast model with threads (M10-T09, D12.6, architecture §17.13): blasts land on the main thread from the rows of the
## tick's sync, so the seeded battle (`SeededBattle`) with a civilian's blast set off every few ticks gives the same blast
## hits, damage and points byte for byte with one thread and six. Reports what a blast costs among its fighters.

const TICKS: int = 240
const BLAST_EVERY: int = 12

var _threads_backup: Variant = null


func before_each() -> void:
	_threads_backup = Settings.get_value(&"perf_threads")
	BlastResolver.reset_stats()


func after_each() -> void:
	Settings.set_value(&"perf_threads", _threads_backup)


func test_a_seeded_battle_lands_the_same_blasts_with_one_thread_and_six() -> void:
	var one: Array = await _battle_blasts(1)
	var six: Array = await _battle_blasts(6)
	assert_gt(one.size(), TICKS / BLAST_EVERY, "the blasts hurt hulls (%d hits)" % one.size())
	assert_eq(one.size(), six.size(), "the same count of blast hits")
	var first: int = -1
	for i: int in mini(one.size(), six.size()):
		if one[i] != six[i]:
			first = i
			break
	assert_eq(first, -1, "the same hits, damage and points byte for byte (first difference at %d)" % first)
	gut.p("blast cost in the battle: mean %.0f us (the core's reach %.0f us), max %d us over %d blasts (%d hulls hurt)" % [
			float(BlastResolver.stats()["mean_us"]), float(BlastResolver.stats()["reach_mean_us"]), BlastResolver.max_us,
			BlastResolver.blasts, BlastResolver.hulls_hurt])


# The seeded battle with `threads` threads, a civilian's blast (300 m) set off every few ticks beside a fighter: every blast
# hit as [the hull's place in the battle, damage, point].
func _battle_blasts(threads: int) -> Array:
	Settings.set_value(&"perf_threads", threads)
	var fight: Dictionary = await SeededBattle.start(self)
	var ships: Array[Combatant] = fight["ships"]
	var index_of: Dictionary = fight["index_of"]
	var log: Array = []
	var spec: BlastSpec = BlastTable.spec(&"civilian_death")
	BlastResolver.set_hit_log(true)
	for t: int in TICKS:
		await get_tree().physics_frame
		if t % BLAST_EVERY == 0:
			var c: Combatant = ships[(t / BLAST_EVERY * 7) % ships.size()]
			if not c.damageable.hull.destroyed:
				BlastResolver.set_off(spec, c.ship.global_position + Vector3(25.0, 0.0, 0.0))
		for info: HitInfo in BlastResolver.hit_log():  # the native batch's hits (M10-T76), in landing order
			log.append([index_of.get(info.target_id, -2), info.damage, info.point, info.applied])
		BlastResolver.set_hit_log(true)
	BlastResolver.set_hit_log(false)
	await SeededBattle.finish(fight)
	return log
