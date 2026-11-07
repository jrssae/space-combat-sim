extends GutTest
## The drivers' step decided in the native host (M4-T35b, architecture §17.13): once a native
## pilot's slot is bound, its driver hands the host its think rate's state and stops ticking; the host decides the stagger,
## the wake, the time since the last think and the hold of a declined think in the batch's call. The seeded battle flies
## the same bits with the setting off and on, with and without a player (near and far ships), with one thread and six; a
## hit wakes a hosted far ship; a changed wing order reaches a hosted pilot; the setting off gives every driver its tick back.
## Skips, saying why, when the library is not built.

const SHIPS: int = 120
const SEED: int = 1
const TICKS: int = 240
const SETTINGS: Array[StringName] = [&"perf_native", &"perf_native_core", &"perf_native_brains", &"perf_native_flight",
		&"perf_threads", &"perf_native_commands", &"perf_native_driver_step", &"perf_native_bolt_rows", &"ai_think_rate",
		&"ai_think_far_hz", &"ai_think_near_m"]

var _saved: Dictionary = {}
var _index_of: Dictionary = {}


func before_each() -> void:
	for key: StringName in SETTINGS:
		_saved[key] = Settings.get_value(key)
	Settings.set_value(&"perf_native", true)
	Settings.set_value(&"perf_native_core", true)
	Settings.set_value(&"perf_native_brains", true)
	Settings.set_value(&"perf_native_flight", true)
	Settings.set_value(&"perf_native_commands", true)
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


func _skipped() -> bool:
	if NativeLib.has_class(NativeProbe.NATIVE_CLASS):
		return false
	pending("the native library is not built (scripts/build_native.sh), so there is no host to step the drivers")
	return true


# A space of its own with a world and its projectiles.
func _space() -> SubViewport:
	var space := SubViewport.new()
	space.own_world_3d = true
	space.world_3d = World3D.new()
	add_child(space)
	var world := WorldFrame.new()
	world.name = "World"
	space.add_child(world)
	var bolts := Node3D.new()
	bolts.name = "Projectiles"
	world.add_child(bolts)
	return space


## The seeded battle's fighters flown `ticks` ticks hosted with `threads` threads, a "player" ship
## among them when `with_player` (so some ships are near and think every tick, the rest at the far rate). Returns per tick
## the rows' digest, the commands' digest and a digest of the hits; the counts; the most drivers hosted and processing.
func _battle(threads: int, with_player: bool, ticks: int = TICKS) -> Dictionary:
	Settings.set_value(&"perf_threads", threads)
	Factions.reset()
	Factions.use_table(BenchLayout.faction_table(BenchLayout.BATTLE))
	ContactScan.invalidate()
	await get_tree().process_frame
	await get_tree().physics_frame
	SimClock.reset()
	var space := _space()
	var world := space.get_node("World") as WorldFrame
	var bolts := world.get_node("Projectiles") as Node3D
	var resolver := HitResolver.new()
	resolver.name = "HitResolver"
	space.add_child(resolver)
	var anchor: UniversePos = world.to_universe(Vector3.ZERO)
	var numbers: Dictionary = {}
	var ships: Array[Combatant] = []
	var drivers: Array[AiPilotDriver] = []
	for e: Dictionary in BenchLayout.plan(BenchLayout.BATTLE, SHIPS, SEED):
		if StringName(e["kind"]) != BenchLayout.KIND_FIGHTER:
			continue
		var type: StringName = e["type"]
		numbers[type] = int(numbers.get(type, 0)) + 1
		var c: Combatant = ShipAssembly.build(ShipCatalog.spec_for(type), world, bolts, {
			ShipAssembly.OPT_FACTION: StringName(e["faction"]), ShipAssembly.OPT_DISPLAY_NAME: "%s %d" % [type, int(numbers[type])],
			ShipAssembly.OPT_FORCE_ASSIST: true, ShipAssembly.OPT_AI: true, ShipAssembly.OPT_LEAN: true})
		world.spawn(c.ship, anchor.plus_local(e["offset"]), e["basis"])
		c.ship.linear_velocity = e["velocity"]
		var made: Dictionary = BrainFactory.from_behaviour(e["behaviour"], anchor, int(e["seed"]))
		c.driver.brain = made["brain"] as PilotBrain
		ships.append(c)
		drivers.append(c.driver)
	if with_player:
		# One fighter stands for the player: the ships within the near distance of it think every tick.
		var player: Combatant = ShipAssembly.build(ShipCatalog.spec_for(ships[0].ship.spec.asset_id), world, bolts, {
			ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE, ShipAssembly.OPT_DISPLAY_NAME: "PLAYER", ShipAssembly.OPT_IS_PLAYER: true,
			ShipAssembly.OPT_LEAN: true})
		world.spawn(player.ship, anchor.plus_local(ships[0].ship.position + Vector3(300.0, 0.0, 0.0)))
		player.ship.linear_velocity = ships[0].ship.linear_velocity
	_index_of.clear()
	for i: int in ships.size():
		_index_of[ships[i].ship.get_instance_id()] = i
		_index_of[ships[i].targetable.get_instance_id()] = i
	var sim: SimCore = SimCore.attach(world)
	sim.core.set_parallel_min(2)
	sim.core.set_flight_parallel_min(2)
	var tick_hits: Array = []
	resolver.hit_resolved.connect(func(info: HitInfo) -> void:
		tick_hits.append([_index_of.get(info.target_id, -2), _index_of.get(info.shooter_id, -2), info.damage, info.applied, info.point]))
	var rows := PackedInt64Array()
	var commands := PackedInt64Array()
	var hits := PackedInt64Array()
	var hosted_max: int = 0
	var processing_min: int = drivers.size()
	var native_thinks: int = 0
	var held: int = 0
	var held_ticks := PackedInt64Array()
	for t: int in ticks:
		tick_hits.clear()
		await get_tree().physics_frame
		rows.append(int(sim.core.rows_digest()))
		commands.append(int(sim.core.commands_digest()))
		hits.append(hash(tick_hits))
		native_thinks += AiPilotDriver.thinks_native()
		held += AiPilotDriver.held()
		held_ticks.append(AiPilotDriver.held())
		hosted_max = maxi(hosted_max, AiPilotDriver.hosted())
		if t % 40 == 39:
			var processing: int = 0
			for d: AiPilotDriver in drivers:
				if d.is_physics_processing():
					processing += 1
			processing_min = mini(processing_min, processing)
	var parts: Array = _pilot_parts(ships[0])  # the first read of ship 0, printed when the digests differ
	var pilots := PackedInt64Array()
	for c: Combatant in ships:
		pilots.append(_pilot_digest(c))
	var out: Dictionary = {"rows": rows, "commands": commands, "hits": hits, "hits_total": resolver.hits_total, "pilots": pilots,
			"native_thinks": native_thinks, "held": held, "held_ticks": held_ticks, "hosted_max": hosted_max, "processing_min": processing_min,
			"first": parts}
	space.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	return out


# The pilot digest's parts, readable (a failure prints the first ship's on both paths).
func _pilot_parts(c: Combatant) -> Array:
	var pilot := c.driver.brain as AiPilot
	var scores := PackedFloat64Array()
	for id: StringName in AiPilot.TIE_ORDER:
		scores.append(pilot.score_of(id))
		scores.append(pilot.raw_score_of(id))
	var wanted: int = pilot.wanted_target_id
	return [String(pilot.current.id) if pilot.current != null else "none", _index_of.get(wanted, -2) if wanted > 0 else -1,
			pilot.dwell_s, pilot.switches, c.driver.avoiding, c.driver.avoiding_urgent, scores, pilot.desired_velocity,
			pilot.has_desired_velocity]


# What the game reads of a pilot: the behaviour in control, the wanted target, the dodge, dwell, switches and the scores.
func _pilot_digest(c: Combatant) -> int:
	var pilot := c.driver.brain as AiPilot
	if pilot == null:
		return 0
	var scores := PackedFloat64Array()
	for id: StringName in AiPilot.TIE_ORDER:
		scores.append(pilot.score_of(id))
		scores.append(pilot.raw_score_of(id))
	var wanted: int = pilot.wanted_target_id
	return hash([String(pilot.current.id) if pilot.current != null else "none", _index_of.get(wanted, -2) if wanted > 0 else -1,
			pilot.dwell_s, pilot.switches, c.driver.avoiding, c.driver.avoiding_urgent, scores, pilot.desired_velocity,
			pilot.has_desired_velocity])


static func _first_difference(a: PackedInt64Array, b: PackedInt64Array) -> int:
	for i: int in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return i
	return -1 if a.size() == b.size() else mini(a.size(), b.size())


# What a battle is held to (M4-T37): its thinks, its held ticks (read one tick later when hosted on a step one tick behind)
# and digests of every tick's rows, commands and hits and of the pilots at the end.
static func _digest_of(battle: Dictionary, shift: int) -> Dictionary:
	var held: PackedInt64Array = battle["held_ticks"]
	var held_sum: int = 0
	for t: int in held.size() - 1:
		held_sum += held[t + shift]
	return {"native_thinks": battle["native_thinks"], "held": held_sum, "hits_total": battle["hits_total"],
			"rows": ParityFixture.digest(battle["rows"]), "commands": ParityFixture.digest(battle["commands"]),
			"hits": ParityFixture.digest(battle["hits"]), "pilots": ParityFixture.digest(battle["pilots"])}


# Flies the battle hosted and holds it to the drivers' own step, recorded in `tests/fixtures/parity/driver_step.json`
# before M4-T37 removed the switch that kept every driver on it.
func _assert_recorded(case: String, with_player: bool, label: String) -> void:
	var recorded: Variant = ParityFixture.stored(FIXTURE, case)
	var hosted: Dictionary = await _battle(1, with_player)
	assert_not_null(recorded, "%s: the drivers' own step was recorded" % label)
	if recorded == null:
		return
	assert_gt(int(recorded["hits_total"]), 10, "%s: hits landed (%d)" % [label, int(recorded["hits_total"])])
	assert_gt(int(hosted["hosted_max"]), SHIPS / 2, "%s: most drivers were hosted (%d)" % [label, int(hosted["hosted_max"])])
	assert_lt(int(hosted["processing_min"]), SHIPS / 10, "%s: hosted drivers do not tick (%d still processing at the fewest)" % [label,
			int(hosted["processing_min"])])
	# A hosted driver's held tick is counted when its job is joined (the step one tick behind, M4-T24), a driver's own at its
	# step: the same decisions, read one tick later.
	assert_eq(ParityFixture.encode(_digest_of(hosted, 1)), recorded,
			"%s: the same thinks, held ticks, rows, commands, hits and pilots as the drivers' own step (recorded)" % label)
	gut.p("%s: %d thinks, %d hits; %d drivers hosted at most" % [label, int(hosted["native_thinks"]),
			int(hosted["hits_total"]), int(hosted["hosted_max"])])


func test_the_hosted_step_flies_the_same_battle_at_the_far_rate() -> void:
	if _skipped():
		return
	await _assert_recorded("battle_far_rate", false, "no player, every ship far")


func test_the_hosted_step_flies_the_same_battle_with_near_and_far_ships() -> void:
	if _skipped():
		return
	await _assert_recorded("battle_near_and_far", true, "a player among them")


func test_one_thread_and_six_give_the_same_hosted_battle() -> void:
	if _skipped():
		return
	var one: Dictionary = await _battle(1, true)
	var six: Dictionary = await _battle(6, true)
	var first: int = _first_difference(one["rows"], six["rows"])
	assert_eq(first, -1, "the rows are the same bits with one thread and six (first difference at tick %d)" % first)
	first = _first_difference(one["commands"], six["commands"])
	assert_eq(first, -1, "and the commands (first difference at tick %d)" % first)


# A fight of the battle's first fighters in a space of its own, flown a few ticks so every driver is hosted.
func _small_fight() -> Dictionary:
	Settings.set_value(&"perf_threads", 6)
	Factions.reset()
	Factions.use_table(BenchLayout.faction_table(BenchLayout.BATTLE))
	ContactScan.invalidate()
	await get_tree().physics_frame
	SimClock.reset()
	var space := _space()
	var world := space.get_node("World") as WorldFrame
	var bolts := world.get_node("Projectiles") as Node3D
	var anchor: UniversePos = world.to_universe(Vector3.ZERO)
	var ships: Array[Combatant] = []
	for e: Dictionary in BenchLayout.plan(BenchLayout.BATTLE, 60, SEED):
		if StringName(e["kind"]) != BenchLayout.KIND_FIGHTER:
			continue
		var c: Combatant = ShipAssembly.build(ShipCatalog.spec_for(e["type"]), world, bolts, {
			ShipAssembly.OPT_FACTION: StringName(e["faction"]), ShipAssembly.OPT_DISPLAY_NAME: "SHIP %d" % ships.size(),
			ShipAssembly.OPT_FORCE_ASSIST: true, ShipAssembly.OPT_AI: true, ShipAssembly.OPT_LEAN: true})
		world.spawn(c.ship, anchor.plus_local(e["offset"]), e["basis"])
		c.ship.linear_velocity = e["velocity"]
		c.driver.brain = BrainFactory.from_behaviour(e["behaviour"], anchor, int(e["seed"]))["brain"] as PilotBrain
		ships.append(c)
	var sim: SimCore = SimCore.attach(world)
	for i: int in 8:
		await get_tree().physics_frame
	return {"space": space, "sim": sim, "ships": ships}


func test_a_changed_wing_order_reaches_a_hosted_pilot_and_a_hand_step_takes_the_step_back() -> void:
	if _skipped():
		return
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


func test_the_native_path_switched_off_gives_the_hosted_drivers_their_ticks_back_without_errors() -> void:
	# Fix round 3 (test_contact_registry in a wide run): `perf_native` off mid-fight left the drivers hosted with no host
	# to step them, the batch flushed a hosted tick it could not begin (an error a tick), and no driver gathered a scan.
	if _skipped():
		return
	var fight: Dictionary = await _small_fight()
	var ships: Array[Combatant] = fight["ships"]
	var hosted: int = 0
	for c: Combatant in ships:
		hosted += 1 if c.driver.is_hosted() else 0
	assert_gt(hosted, ships.size() / 2, "most drivers are hosted (%d of %d)" % [hosted, ships.size()])
	Settings.set_value(&"perf_native", false)
	await get_tree().physics_frame
	var still: int = 0
	for c: Combatant in ships:
		if c.driver.is_hosted() or not c.driver.is_physics_processing():
			still += 1
	assert_eq(still, 0, "perf_native off: every driver has its tick back")
	var steps_before: int = ships[0].driver._steps
	var gathers: int = ContactScan.gathers
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(ships[0].driver._steps, steps_before + 2, "and steps itself every tick")
	assert_gt(ContactScan.gathers - gathers, 0, "the GDScript scan is gathered again")
	Settings.set_value(&"perf_native", true)
	(fight["space"] as Node).queue_free()
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
