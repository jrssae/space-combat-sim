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
const SETTINGS: Array[StringName] = [&"perf_native", &"perf_native_core", &"perf_native_brains", &"perf_threads"]

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
	assert_gt(int(six["native_thinks"]), TICKS * 20, "the native brains thought (%d thinks)" % int(six["native_thinks"]))
	assert_eq(int(one["native_thinks"]), int(six["native_thinks"]), "the same thinks on both")
	assert_eq(int(six["fallbacks"]), 0, "the host declined no think")
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
	var digests := PackedInt64Array()
	var native_thinks: int = 0
	var fallbacks: int = 0
	var parallel_before: int = int(sim.core.parallel_passes())
	for tick: int in ticks:
		if tick == 1:
			var host: Object = NativeBrains.host(get_tree())
			host.set_fault(1 if fault else 0)
		await get_tree().physics_frame
		digests.append(int(sim.core.rows_digest()))
		native_thinks += AiPilotDriver.thinks_native()
		fallbacks += AiPilotDriver.thinks_fallback()
	var parallel: int = int(sim.core.parallel_passes()) - parallel_before
	NativeBrains.host(get_tree()).set_fault(0)
	space.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	Factions.reset()
	return {"digests": digests, "parallel": parallel, "native_thinks": native_thinks, "fallbacks": fallbacks}


# The first index where the two lists differ (or where one ends early), -1 when they are equal.
func _first_difference(a: PackedInt64Array, b: PackedInt64Array) -> int:
	for i: int in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return i
	return -1 if a.size() == b.size() else mini(a.size(), b.size())
