extends GutTest
## The AI step on a worker thread, one tick behind (M4-T24, Q53, architecture §15.3 and §17.13; setting `sim_step`): the
## brains' batch runs as a job over a snapshot of the core's rows, launched at -9 and joined at the next tick's -9, so the
## frame and the player's input never wait on it. `threaded` must equal `delayed` (the same one-tick handover on the main
## thread) tick for tick; `inline` is today's step and differs from them by the one-tick shift; a job that misses its
## deadline is counted and waited for, never skipped; the schedule flips live; a reader asking while the brains are away
## answers from the launch. Skips, saying why, when the library is not built.

const SHIPS: int = 120
const SEED: int = 1
const TICKS: int = 240
const SETTINGS: Array[StringName] = [&"perf_native", &"perf_native_core", &"perf_native_brains", &"perf_native_flight",
		&"perf_threads", &"perf_native_commands", &"perf_native_driver_step", &"perf_native_bolt_rows", &"ai_think_rate",
		&"sim_step"]

var _saved: Dictionary = {}


func before_each() -> void:
	for key: StringName in SETTINGS:
		_saved[key] = Settings.get_value(key)
	Settings.set_value(&"perf_native", true)
	Settings.set_value(&"perf_native_core", true)
	Settings.set_value(&"perf_native_brains", true)
	Settings.set_value(&"perf_native_flight", true)
	Settings.set_value(&"perf_native_commands", true)
	Settings.set_value(&"perf_native_driver_step", true)
	Settings.set_value(&"ai_think_rate", true)
	Factions.reset()
	ContactScan.invalidate()


func after_each() -> void:
	for key: StringName in SETTINGS:
		if _saved[key] != null:
			Settings.set_value(key, _saved[key])
	var host: Object = NativeBrains.host(get_tree())
	if host != null:
		host.set_fault(0)
	Factions.reset()
	ContactScan.invalidate()


func _skipped() -> bool:
	if NativeLib.has_class(NativeProbe.NATIVE_CLASS):
		return false
	pending("the native library is not built (scripts/build_native.sh), so there is no step to thread")
	return true


func test_the_setting_exists_and_defaults_to_threaded() -> void:
	assert_true(Settings.schema.has_key(&"sim_step"), "sim_step is a setting")
	assert_eq(Settings.schema.get_default(&"sim_step"), &"threaded", "the worker thread by default (Q53)")
	assert_eq(BrainBatch.step_mode_of(&"inline"), BrainBatch.STEP_INLINE)
	assert_eq(BrainBatch.step_mode_of(&"delayed"), BrainBatch.STEP_DELAYED)
	assert_eq(BrainBatch.step_mode_of(&"threaded"), BrainBatch.STEP_THREADED)


func test_the_threaded_step_equals_the_delayed_step_tick_for_tick() -> void:
	if _skipped():
		return
	var delayed: Dictionary = await _battle(&"delayed", 6)
	var threaded: Dictionary = await _battle(&"threaded", 6)
	assert_gt(int(delayed["hits_total"]), 10, "hits landed (%d)" % int(delayed["hits_total"]))
	assert_gt(int(threaded["native_thinks"]), TICKS * 20, "the brains thought on the thread (%d thinks)" % int(threaded["native_thinks"]))
	var first_thinks: int = _first_difference(delayed["thinks"], threaded["thinks"])
	assert_eq(first_thinks, -1, "the same thinks every tick (first difference at tick %d: %s against %s)" % [first_thinks,
			str((delayed["thinks"] as PackedInt64Array).slice(maxi(first_thinks - 1, 0), first_thinks + 3)),
			str((threaded["thinks"] as PackedInt64Array).slice(maxi(first_thinks - 1, 0), first_thinks + 3))])
	assert_eq(int(threaded["native_thinks"]), int(delayed["native_thinks"]), "the same number of thinks")
	assert_eq(int(threaded["held"]), int(delayed["held"]), "the same number of held ticks")
	assert_true(bool(threaded["off_main"]), "the threaded job ran off the main thread")
	assert_false(bool(delayed["off_main"]), "the delayed job ran on the main thread")
	assert_eq(int(threaded["misses"]), 0, "no deadline missed on an idle machine (%d)" % int(threaded["misses"]))
	var first: int = _first_difference(delayed["rows"], threaded["rows"])
	assert_eq(first, -1, "the rows are the same bits every tick (first difference at tick %d)" % first)
	first = _first_difference(delayed["commands"], threaded["commands"])
	assert_eq(first, -1, "the commands are the same bits every tick (first difference at tick %d)" % first)
	first = _first_difference(delayed["hits"], threaded["hits"])
	assert_eq(first, -1, "the same hits every tick (first difference at tick %d)" % first)
	gut.p("threaded against delayed, %d ships, %d ticks: %d thinks, %d hits; the job ran %d us a tick at most" % [SHIPS, TICKS,
			int(threaded["native_thinks"]), int(threaded["hits_total"]), int(threaded["step_us_max"])])


func test_one_thread_and_six_give_the_same_threaded_battle() -> void:
	if _skipped():
		return
	var one: Dictionary = await _battle(&"threaded", 1)
	var six: Dictionary = await _battle(&"threaded", 6)
	assert_eq(int(one["native_thinks"]), int(six["native_thinks"]), "the same number of thinks")
	var first: int = _first_difference(one["rows"], six["rows"])
	assert_eq(first, -1, "the rows are the same bits with one thread and six (first difference at tick %d)" % first)
	first = _first_difference(one["commands"], six["commands"])
	assert_eq(first, -1, "and the commands (first difference at tick %d)" % first)


func test_the_inline_step_flies_the_same_commands_one_tick_earlier() -> void:
	if _skipped():
		return
	var inline: Dictionary = await _battle(&"inline", 6, 20)
	var delayed: Dictionary = await _battle(&"delayed", 6, 20)
	var first_inline: int = _first_command_tick(inline["live"])
	var first_delayed: int = _first_command_tick(delayed["live"])
	assert_gte(first_inline, 0, "the inline step wrote commands")
	assert_eq(first_delayed, first_inline + 1, "the delayed step's first commands land one tick later (tick %d against %d)" % [
			first_delayed, first_inline])
	assert_eq((delayed["commands"] as PackedInt64Array)[first_delayed], (inline["commands"] as PackedInt64Array)[first_inline],
			"and they are the same commands: the first thinks read the same rows")
	assert_ne(_first_difference(inline["rows"], delayed["rows"]), -1, "the one-tick shift changes the outcome against today (Q53)")


func test_a_missed_deadline_is_counted_and_waited_for_never_skipped() -> void:
	if _skipped():
		return
	var delayed: Dictionary = await _battle(&"delayed", 6, 60)
	var slow: Dictionary = await _battle(&"threaded", 6, 60, true)
	assert_gt(int(slow["misses"]), 40, "a job slower than the tick misses its deadline every tick (%d of 60)" % int(slow["misses"]))
	assert_gt(int(slow["wait_us_max"]), 10_000, "and the main thread waited for it (%d us at most)" % int(slow["wait_us_max"]))
	assert_eq(int(slow["native_thinks"]), int(delayed["native_thinks"]), "no think was skipped")
	var first: int = _first_difference(delayed["rows"], slow["rows"])
	assert_eq(first, -1, "the late results land as the on-time ones would (first difference at tick %d)" % first)


func test_the_schedule_flips_live_and_a_reader_while_the_brains_are_away_answers_from_the_launch() -> void:
	if _skipped():
		return
	var fight: Dictionary = await _start(&"threaded", 6)
	var sim: SimCore = fight["sim"]
	var host: Object = NativeBrains.host(get_tree())
	var ships: Array = fight["ships"]
	for i: int in 6:
		await get_tree().physics_frame
	assert_true(bool(host.step_pending()), "between ticks a job is out on the threaded step")
	var pilot := (ships[3] as Combatant).driver.brain as AiPilot
	assert_true(pilot.has_native_slot(), "the pilot has a slot")
	var slot: int = pilot.native_slot_index()
	var early: int = int(host.early_joins())
	var d: Dictionary = host.describe(slot)
	assert_true(d.has("behaviour"), "describe answers while the brains are away")
	assert_eq(int(host.early_joins()), early + 1, "the first ask of a slot joins the job early")
	await get_tree().physics_frame
	assert_true(bool(host.step_pending()), "the next tick launched again")
	var out: PackedFloat64Array = host.slot_output(slot)
	assert_true(out.size() == 0 or out.size() == AiPilot.NATIVE_OUT_LEN, "a hosted reader answers from the launch's view")
	d = host.describe(slot)
	assert_true(d.has("behaviour"), "describe answers again")
	assert_eq(int(host.early_joins()), early + 1, "from the cache this time: no early join")
	Settings.set_value(&"sim_step", &"inline")
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_false(bool(host.step_pending()), "inline: no job is out between ticks")
	assert_eq(int(host.deadline_misses()), 0, "the flip joined the last job without a miss")
	var thinks: int = 0
	for i: int in 3:
		await get_tree().physics_frame
		thinks += AiPilotDriver.thinks_native()
	assert_gt(thinks, 0, "the brains think on inline")
	Settings.set_value(&"sim_step", &"threaded")
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_true(bool(host.step_pending()), "and again on the thread")
	assert_gt(int(sim.core.row_count()), 0, "the core still holds the rows")
	fight["space"].queue_free()
	await get_tree().physics_frame
	Factions.reset()


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


## The seeded battle's fighters (four sides, the bench's session table) built in a space of their own with the step `mode`
## and `threads` threads: the space, the core and the ships.
func _start(mode: StringName, threads: int) -> Dictionary:
	Settings.set_value(&"sim_step", mode)
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
	var sim: SimCore = SimCore.attach(world)
	sim.core.set_parallel_min(2)
	sim.core.set_flight_parallel_min(2)
	return {"space": space, "sim": sim, "ships": ships, "resolver": resolver}


## The seeded battle flown `ticks` ticks with the step `mode` and `threads` threads (`slow`: the job sleeps 40 ms, so every
## deadline is missed). Returns per tick the rows' digest, the commands' digest and a digest of the hits; the counts and
## the step's readouts.
func _battle(mode: StringName, threads: int, ticks: int = TICKS, slow: bool = false) -> Dictionary:
	var fight: Dictionary = await _start(mode, threads)
	var sim: SimCore = fight["sim"]
	var resolver: HitResolver = fight["resolver"]
	var host: Object = NativeBrains.host(get_tree())
	var misses_before: int = int(host.deadline_misses())
	var tick_hits: Array = []
	resolver.hit_resolved.connect(func(info: HitInfo) -> void:
		tick_hits.append([info.target_id != 0, info.shooter_id != 0, info.damage, info.applied, info.point]))
	var rows := PackedInt64Array()
	var commands := PackedInt64Array()
	var live := PackedInt64Array()
	var hits := PackedInt64Array()
	var thinks := PackedInt64Array()
	var native_thinks: int = 0
	var held: int = 0
	var step_us_max: int = 0
	var wait_us_max: int = 0
	var off_main: bool = false
	for t: int in ticks:
		if t == 1 and slow:
			host.set_fault(3)
		tick_hits.clear()
		await get_tree().physics_frame
		rows.append(int(sim.core.rows_digest()))
		commands.append(int(sim.core.commands_digest()))
		live.append(int(sim.core.live_commands()))
		hits.append(hash(tick_hits))
		if t > 0:  # tick 0 has no join yet on a delayed step: the counts it reads are the last run's
			thinks.append(AiPilotDriver.thinks_native())
			native_thinks += AiPilotDriver.thinks_native()
			held += AiPilotDriver.held()
		step_us_max = maxi(step_us_max, int(host.step_us()))
		wait_us_max = maxi(wait_us_max, int(host.step_wait_us()))
		off_main = off_main or bool(host.step_off_main())
	host.set_fault(0)
	var out: Dictionary = {"rows": rows, "commands": commands, "live": live, "hits": hits, "thinks": thinks, "hits_total": resolver.hits_total,
			"native_thinks": native_thinks, "held": held, "step_us_max": step_us_max, "wait_us_max": wait_us_max,
			"off_main": off_main, "misses": int(host.deadline_misses()) - misses_before}
	fight["space"].queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	Factions.reset()
	return out


# The first tick any ship flew a command from its row.
func _first_command_tick(live: PackedInt64Array) -> int:
	for i: int in live.size():
		if live[i] > 0:
			return i
	return -1


static func _first_difference(a: PackedInt64Array, b: PackedInt64Array) -> int:
	for i: int in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return i
	return -1 if a.size() == b.size() else mini(a.size(), b.size())
