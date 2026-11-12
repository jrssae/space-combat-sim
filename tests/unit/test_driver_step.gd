extends GutTest
## The drivers' step decided in the native host (M4-T35b, architecture §17.13): once a native
## pilot's slot is bound, its driver hands the host its think rate's state and stops ticking; the host decides the stagger,
## the wake, the time since the last think and the hold of a declined think in the batch's call. The seeded battle with a
## player among the fighters (near and far ships) flies the same bits as the drivers' own step did (the far-rate case is
## checked in `test_row_commands`, one thread against six in `test_core_threads`, since M6-T18); a changed wing order
## reaches a hosted pilot; a hand step takes the step back.

const TICKS: int = 240
const SETTINGS: Array[StringName] = [&"perf_threads", &"ai_think_rate",
		&"ai_think_far_hz", &"ai_think_near_m"]

var _saved: Dictionary = {}


func before_each() -> void:
	for key: StringName in SETTINGS:
		_saved[key] = Settings.get_value(key)
	Settings.set_value(&"ai_think_rate", true)
	Factions.reset()
	ContactScan.invalidate()


func after_each() -> void:
	for key: StringName in SETTINGS:
		if _saved[key] != null:
			Settings.set_value(key, _saved[key])
	Factions.reset()
	ContactScan.invalidate()


const FIXTURE: String = "driver_step"


## The seeded battle's fighters (`SeededBattle`) flown `ticks` ticks hosted with `threads` threads, a "player" ship among
## them when `with_player` (so some ships are near and think every tick, the rest at the far rate). Returns per tick the
## rows' digest, the commands' digest and a digest of the hits; the counts; the most drivers hosted and processing.
func _battle(threads: int, with_player: bool, ticks: int = TICKS) -> Dictionary:
	Settings.set_value(&"perf_threads", threads)
	var fight: Dictionary = await SeededBattle.start(self, {SeededBattle.OPT_PLAYER: with_player})
	var sim: SimCore = fight["sim"]
	var ships: Array[Combatant] = fight["ships"]
	var index_of: Dictionary = fight["index_of"]
	var tick_hits: Array = []
	SeededBattle.log_hits(fight, tick_hits)
	var rows := PackedInt64Array()
	var commands := PackedInt64Array()
	var hits := PackedInt64Array()
	var hosted_max: int = 0
	var processing_min: int = ships.size()
	var native_thinks: int = 0
	var held_ticks := PackedInt64Array()
	for t: int in ticks:
		tick_hits.clear()
		await get_tree().physics_frame
		rows.append(int(sim.core.rows_digest()))
		commands.append(int(sim.core.commands_digest()))
		hits.append(hash(tick_hits))
		native_thinks += AiPilotDriver.thinks_native()
		held_ticks.append(AiPilotDriver.held())
		hosted_max = maxi(hosted_max, AiPilotDriver.hosted())
		if t % 40 == 39:
			var processing: int = 0
			for c: Combatant in ships:
				if c.driver.is_physics_processing():
					processing += 1
			processing_min = mini(processing_min, processing)
	var pilots := PackedInt64Array()
	for c: Combatant in ships:
		pilots.append(SeededBattle.pilot_digest(c, index_of))
	var out: Dictionary = {"rows": rows, "commands": commands, "hits": hits, "hits_total": (fight["resolver"] as HitResolver).hits_total,
			"pilots": pilots, "native_thinks": native_thinks, "held_ticks": held_ticks, "hosted_max": hosted_max,
			"processing_min": processing_min, "first": SeededBattle.pilot_parts(ships[0], index_of)}
	await SeededBattle.finish(fight)
	return out


# Flies the battle hosted and holds it to the drivers' own step, recorded in `tests/fixtures/parity/driver_step.json`
# before M4-T37 removed the switch that kept every driver on it. The far-rate case (no player) is checked in
# `test_row_commands`, which flies the same battle (M6-T18).
func test_the_hosted_step_flies_the_same_battle_with_near_and_far_ships() -> void:
	var label: String = "a player among them"
	var recorded: Variant = ParityFixture.stored(FIXTURE, "battle_near_and_far")
	var hosted: Dictionary = await _battle(1, true)
	assert_not_null(recorded, "%s: the drivers' own step was recorded" % label)
	if recorded == null:
		return
	assert_gt(int(recorded["hits_total"]), 10, "%s: hits landed (%d)" % [label, int(recorded["hits_total"])])
	assert_gt(int(hosted["hosted_max"]), SeededBattle.SHIPS / 2, "%s: most drivers were hosted (%d)" % [label, int(hosted["hosted_max"])])
	assert_lt(int(hosted["processing_min"]), SeededBattle.SHIPS / 10, "%s: hosted drivers do not tick (%d still processing at the fewest)" % [
			label, int(hosted["processing_min"])])
	assert_eq(ParityFixture.encode(SeededBattle.hosted_digest(hosted, 1)), recorded,
			"%s: the same thinks, held ticks, rows, commands, hits and pilots as the drivers' own step (recorded); ship 0: %s" % [
			label, hosted["first"]])
	gut.p("%s: %d thinks, %d hits; %d drivers hosted at most" % [label, int(hosted["native_thinks"]),
			int(hosted["hits_total"]), int(hosted["hosted_max"])])


# A fight of the battle's first fighters in a space of its own, flown a few ticks so every driver is hosted.
func _small_fight() -> Dictionary:
	Settings.set_value(&"perf_threads", 6)
	return await SeededBattle.small_fight(self)


func test_a_changed_wing_order_reaches_a_hosted_pilot_and_a_hand_step_takes_the_step_back() -> void:
	var fight: Dictionary = await _small_fight()
	var ships: Array[Combatant] = fight["ships"]
	var hosted: int = 0
	for c: Combatant in ships:
		if c.driver.is_hosted():
			hosted += 1
	assert_gt(hosted, ships.size() / 2, "most drivers are hosted after a few ticks (%d of %d)" % [hosted, ships.size()])
	var c0: Combatant = ships[0]
	assert_true(c0.driver.is_hosted(), "the first is")
	assert_false(c0.driver.is_physics_processing(), "and does not tick itself")
	var pilot := c0.driver.brain as AiPilot
	pilot.context.order = AiContext.Order.COVER_ME
	assert_ne(pilot._pushed_order, int(AiContext.Order.COVER_ME), "the order is not in the slot yet")
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(pilot._pushed_order, int(AiContext.Order.COVER_ME), "the next batch pushed the changed context to the slot")
	# A hand step takes the step back, as a test would want.
	c0.driver.step(1.0 / 60.0)
	assert_false(c0.driver.is_hosted(), "a driver stepped by hand decides for itself again")
	assert_true(c0.driver.is_physics_processing(), "and ticks")
	await get_tree().physics_frame
	assert_true(c0.driver.is_hosted(), "and its next engine tick hands the step to the host again")
	await get_tree().physics_frame
	assert_gt(AiPilotDriver.thinks_native(), 0, "and the battle thinks on")
	(fight["space"] as SubViewport).queue_free()
	await get_tree().physics_frame


func test_a_pilot_and_its_context_free_each_other_when_dropped() -> void:
	# Fix round 4 (CI: "110 ObjectDB instances were leaked at exit"): the context's back-reference to the pilot whose slot
	# mirrors it must not keep the pair alive once nothing else holds them.
	var pilot := AiPilot.new()
	pilot.context.native_pilot = pilot
	assert_eq(pilot.context.native_pilot, pilot, "the context names its pilot")
	var pilot_ref: WeakRef = weakref(pilot)
	var context_ref: WeakRef = weakref(pilot.context)
	pilot = null
	assert_null(pilot_ref.get_ref(), "the pilot is freed when dropped: no reference cycle through its context")
	assert_null(context_ref.get_ref(), "and its context with it")
