extends GutTest
## Threads inside the native core (M4-T18, architecture §17.13): the per-ship passes (the brains with their perception
## queries and avoidance, the flight step) run across worker threads, and the outputs do not depend on how many. A seeded
## battle stepped 600 ticks with one thread and with six gives the same rows byte for byte, a think that reads what the
## worker's previous think left (another row's output) is caught by that comparison, and the thread count follows
## `perf_threads` at once. Each fight runs in a space of its own with the clock reset, as `test_brain_tolerance` flies
## them. Skips, saying why, when the library is not built.

const SHIPS: int = 120
const SEED: int = 1
const TICKS: int = 600
const FAULT_TICKS: int = 120
const SETTINGS: Array[StringName] = [&"perf_native", &"perf_native_core", &"perf_native_brains", &"perf_threads",
		&"perf_native_commands", &"perf_native_driver_step", &"sim_step", &"perf_step_threads"]

var _saved: Dictionary = {}


func before_each() -> void:
	for key: StringName in SETTINGS:
		_saved[key] = Settings.get_value(key)
	Settings.set_value(&"perf_native", true)
	Settings.set_value(&"perf_native_core", true)
	Settings.set_value(&"perf_native_brains", true)
	Factions.reset()
	ContactScan.invalidate()


func after_each() -> void:
	for key: StringName in SETTINGS:
		Settings.set_value(key, _saved[key])
	var host: Object = NativeBrains.host(get_tree())
	if host != null:
		host.set_fault(0)
	Factions.reset()
	ContactScan.invalidate()


func _skipped() -> bool:
	if NativeLib.has_class(NativeProbe.NATIVE_CLASS):
		return false
	pending("the native library is not built (scripts/build_native.sh), so there are no native threads to test")
	return true


func test_the_thread_count_follows_the_setting_at_once() -> void:
	if _skipped():
		return
	var space := _space()
	var world := space.get_node("World") as WorldFrame
	var sim: SimCore = SimCore.attach(world)
	await get_tree().physics_frame
	assert_not_null(sim, "a core under the world")
	var cores: int = int(sim.core.performance_cores())
	assert_gte(cores, 1, "the machine has at least one performance core")
	Settings.set_value(&"perf_threads", 3)
	assert_eq(int(sim.core.threads()), 3, "three threads as soon as the setting says three")
	Settings.set_value(&"perf_threads", 1)
	assert_eq(int(sim.core.threads()), 1, "one thread at once")
	Settings.set_value(&"perf_threads", 0)
	assert_eq(int(sim.core.threads()), cores, "0 means the performance cores (%d)" % cores)
	Settings.set_value(&"perf_threads", 6)
	assert_eq(int(sim.core.threads()), 6, "six at once")
	space.queue_free()
	await get_tree().physics_frame


func test_a_seeded_battle_gives_the_same_rows_byte_for_byte_with_one_thread_and_six() -> void:
	if _skipped():
		return
	var one: Dictionary = await _battle(1, TICKS, false)
	var six: Dictionary = await _battle(6, TICKS, false)
	var a: PackedInt64Array = one["digests"]
	var b: PackedInt64Array = six["digests"]
	assert_eq(a.size(), TICKS, "a digest of the rows every tick with one thread")
	assert_eq(b.size(), TICKS, "and with six")
	assert_eq(int(one["parallel"]), 0, "one thread never ran a pass in parallel")
	assert_gt(int(six["parallel"]), TICKS, "six threads ran the passes in parallel (%d passes)" % int(six["parallel"]))
	assert_gte(int(six["brains_parallel"]), TICKS - 2, "the brains' pass itself ran in parallel every tick (%d)" % int(six["brains_parallel"]))
	assert_gt(int(six["native_thinks"]), TICKS * 20, "the native brains thought (%d thinks)" % int(six["native_thinks"]))
	assert_eq(int(one["native_thinks"]), int(six["native_thinks"]), "the same thinks on both")
	assert_eq(int(six["fallbacks"]), 0, "the host declined no think")
	gut.p("battle %d seed %d, %d ticks: %d native thinks, %d passes in parallel with six threads" % [SHIPS, SEED, TICKS,
			int(six["native_thinks"]), int(six["parallel"])])
	var first: int = _first_difference(a, b)
	assert_eq(first, -1, "the rows are the same bits every tick with one thread and six (first difference at tick %d)" % first)


func test_a_think_that_reads_another_rows_output_is_caught() -> void:
	if _skipped():
		return
	var one: Dictionary = await _battle(1, FAULT_TICKS, true)
	var six: Dictionary = await _battle(6, FAULT_TICKS, true)
	var first: int = _first_difference(one["digests"], six["digests"])
	gut.p("the injected read of the worker's previous think: first difference at tick %d of %d" % [first, FAULT_TICKS])
	assert_gt(int(six["parallel"]), 0, "the faulty pass ran in parallel")
	assert_ne(first, -1, "a think that reads another row's output makes one thread and six differ")


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


## The seeded battle's fighters (four sides, the bench's session table) flown `ticks` ticks with `threads` threads and the
## injected fault on or off. Returns the rows' digest every tick, the passes that ran in parallel, the native thinks and
## the declined ones.
func _battle(threads: int, ticks: int, fault: bool) -> Dictionary:
	Settings.set_value(&"perf_threads", threads)
	Settings.set_value(&"perf_step_threads", 0)  # the brains' pass on the core's pool, whatever the step's schedule (M4-T24)
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
	var sim: SimCore = SimCore.attach(world)
	assert_eq(int(sim.core.threads()), threads, "%d threads asked for" % threads)
	# Every pass in parallel whatever its size, so the comparison covers the brains and the flight step.
	sim.core.set_parallel_min(2)
	sim.core.set_flight_parallel_min(2)
	var digests := PackedInt64Array()
	var native_thinks: int = 0
	var fallbacks: int = 0
	var parallel_before: int = int(sim.core.parallel_passes())
	var brains_before: int = int(sim.core.parallel_passes_of(0))
	for tick: int in ticks:
		if tick == 1:
			var host: Object = NativeBrains.host(get_tree())
			host.set_fault(1 if fault else 0)
		await get_tree().physics_frame
		digests.append(int(sim.core.rows_digest()))
		native_thinks += AiPilotDriver.thinks_native()
		fallbacks += AiPilotDriver.thinks_fallback()
	var parallel: int = int(sim.core.parallel_passes()) - parallel_before
	var brains_parallel: int = int(sim.core.parallel_passes_of(0)) - brains_before
	NativeBrains.host(get_tree()).set_fault(0)
	space.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	Factions.reset()
	return {"digests": digests, "parallel": parallel, "brains_parallel": brains_parallel, "native_thinks": native_thinks,
			"fallbacks": fallbacks}


# The first index where the two lists differ (or where one ends early), -1 when they are equal.
func _first_difference(a: PackedInt64Array, b: PackedInt64Array) -> int:
	for i: int in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return i
	return -1 if a.size() == b.size() else mini(a.size(), b.size())


# --- fix round 1 ---------------------------------------------------------------------------------------------------------


func test_the_pool_is_joined_when_the_thread_count_changes() -> void:
	if _skipped():
		return
	var space := _space()
	var sim: SimCore = SimCore.attach(space.get_node("World"))
	await get_tree().physics_frame
	sim.core.set_threads(6)
	sim.core.set_threads(3)
	assert_lte(int(sim.core.live_workers()), 3, "the six old workers are gone before the three new ones start")
	sim.core.set_threads(1)
	assert_eq(int(sim.core.live_workers()), 0, "one thread: every worker has exited, none is left running")
	space.queue_free()
	await get_tree().physics_frame


func test_a_panic_in_the_pool_keeps_the_brains_and_holds_the_tick() -> void:
	if _skipped():
		return
	var fight: Dictionary = await _small_fight()
	var host: Object = NativeBrains.host(get_tree())
	var batch: BrainBatch = BrainBatch.for_tree(get_tree())
	var slots: int = int(host.count())
	var queued: int = _queue_thinks(fight["ships"])
	assert_gt(queued, 0, "some ships queued a native think")
	var before: Array = _commands(fight["ships"])
	var held_before: int = AiPilotDriver.thinks_fallback()
	host.set_fault(2)
	batch.flush()
	batch.flush()  # the delayed step: this flush joins the job the first launched
	host.set_fault(0)
	assert_eq(int(host.pass_failures()), 1, "the failed pass is counted")
	assert_engine_error("panicked", "and said once")
	assert_eq(AiPilotDriver.thinks_fallback() - held_before, queued, "every think of that batch held and was counted")
	assert_eq(_commands(fight["ships"]), before, "every ship keeps its last command")
	assert_eq(int(host.count()), slots, "no brain was lost")
	await _thinks_resume(fight)


func test_a_slot_listed_twice_in_one_flight_step_flies_as_two_steps_in_a_row() -> void:
	if _skipped():
		return
	var spec: ShipSpec = load("res://assets/ships/starfury_aurora.tres") as ShipSpec
	var layout: ThrusterLayout = ThrusterLayout.load_file("res://tests/fixtures/hardpoints_nominal.json")
	var step: Object = NativeLib.instantiate(FlightBatch.NATIVE_CLASS)
	var twice: int = FlightBatch.register_slot(step, RID(), spec, layout)
	var once: int = FlightBatch.register_slot(step, RID(), spec, layout)
	step.set_assist_state(twice, 0.3)
	step.set_assist_state(once, 0.3)
	var scalars := PackedFloat64Array([0.6, 0.6, 0.0, 0.0])
	var vectors := PackedVector3Array([Vector3(0.2, 0.0, 0.0), Vector3(0.0, -0.9, 0.3), Vector3.ZERO, Vector3.ZERO,
			Vector3.ZERO, Vector3.ZERO])
	var flags := PackedByteArray([0, 0, 1, 1])
	var states := PackedVector3Array([Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(5.0, 0.0, -40.0),
			Vector3(0.0, 0.2, 0.0)])
	var pair_scalars := scalars.duplicate()
	pair_scalars.append_array(scalars)
	var pair_vectors := vectors.duplicate()
	pair_vectors.append_array(vectors)
	var pair_flags := flags.duplicate()
	pair_flags.append_array(flags)
	var pair_states := states.duplicate()
	pair_states.append_array(states)
	assert_true(step.step(PackedInt32Array([twice, twice]), pair_scalars, pair_vectors, pair_flags, pair_states, 1.0 / 60.0))
	var pair_out: PackedFloat64Array = step.out_scalars()
	var in_a_row := PackedFloat64Array()
	for i: int in 2:
		assert_true(step.step(PackedInt32Array([once]), scalars, vectors, flags, states, 1.0 / 60.0))
		in_a_row.append_array(step.out_scalars())
	assert_ne(in_a_row.slice(0, FlightBatch.OUT_SCALARS), in_a_row.slice(FlightBatch.OUT_SCALARS), "the assist state moved between the two steps")
	assert_eq(pair_out, in_a_row, "the second entry reads the assist state the first left, as on the base")
	assert_eq(float(step.assist_state(twice)), float(step.assist_state(once)), "and leaves the same assist state")


# A fight of the battle's first fighters in a space of its own, flown a few ticks so every pilot has its native slot.
func _small_fight() -> Dictionary:
	Settings.set_value(&"perf_threads", 6)
	Settings.set_value(&"perf_native_driver_step", false)  # these fights queue thinks by hand (T18's seam; the host's step: test_driver_step)
	Settings.set_value(&"sim_step", &"delayed")  # and join the flush's job by hand on the main thread (test_core_snapshot)
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
	autofree(space)
	return {"space": space, "sim": sim, "ships": ships}


# Steps every driver by hand into this frame's batch (as `_physics_process` does) and returns how many queued.
func _queue_thinks(ships: Array) -> int:
	var batch: BrainBatch = BrainBatch.for_tree(get_tree())
	var queued: int = 0
	for c: Combatant in ships:
		var before: int = batch.queued()
		c.driver.step(1.0 / 60.0, true)
		queued += batch.queued() - before
	return queued


# Every ship's current flight command, as bytes.
func _commands(ships: Array) -> Array:
	var out: Array = []
	for c: Combatant in ships:
		out.append(var_to_bytes((c.ship._flight as FlightCommand).to_dict()))
	return out


# The next ticks think natively again, with nothing declined (a tick's counts are read after the next tick starts, so the
# first read still shows the held tick).
func _thinks_resume(fight: Dictionary) -> void:
	var native: int = 0
	var held: int = 0
	await get_tree().physics_frame
	for i: int in 4:
		await get_tree().physics_frame
		native += AiPilotDriver.thinks_native()
		held += AiPilotDriver.thinks_fallback()
	assert_gt(native, 0, "native thinks resume")
	assert_eq(held, 0, "and none is declined")
	Factions.reset()
