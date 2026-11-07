extends GutTest
## The native pilots' commands as core rows (M4-T33, architecture §17.13): the brains' batch writes each native pilot's
## flight and combat command into the core, the flight batch applies it the same tick, and the drivers touch only the ships
## whose trigger, selection or command source changed. Seeded battles fly the same bits with the rows path on and off, with
## one thread and six; a command set from GDScript takes over from the row. Each fight runs in a space of its own with the clock reset, as
## `test_core_threads` flies them. Skips, saying why, when the library is not built.

const SHIPS: int = 120
const SEED: int = 1
const TICKS: int = 240
const SETTINGS: Array[StringName] = [&"perf_native", &"perf_native_core", &"perf_native_brains", &"perf_native_flight",
		&"perf_threads", &"perf_native_commands", &"perf_native_driver_step", &"sim_step"]

var _saved: Dictionary = {}
# The battle's ships by their `Targetable` id, so selections compare across runs (each run has its own instance ids).
var _index_of: Dictionary = {}


func before_each() -> void:
	for key: StringName in SETTINGS:
		_saved[key] = Settings.get_value(key)
	Settings.set_value(&"perf_native", true)
	Settings.set_value(&"perf_native_core", true)
	Settings.set_value(&"perf_native_brains", true)
	Settings.set_value(&"perf_native_flight", true)
	Factions.reset()
	ContactScan.invalidate()


func after_each() -> void:
	for key: StringName in SETTINGS:
		if _saved[key] != null:
			Settings.set_value(key, _saved[key])
	Factions.reset()
	ContactScan.invalidate()


const FIXTURE: String = "row_commands"


func _skipped() -> bool:
	if NativeLib.has_class(NativeProbe.NATIVE_CLASS):
		return false
	pending("the native library is not built (scripts/build_native.sh), so there are no native commands to test")
	return true


func test_commands_from_rows_fly_the_same_battle_as_today() -> void:
	if _skipped():
		return
	# The drivers handing each ship its command (T18's path), recorded before M4-T37 removed it.
	var recorded: Variant = ParityFixture.stored(FIXTURE, "battle_with_commands_from_the_drivers")
	var rows: Dictionary = await _battle(1, true)
	assert_eq((rows["rows"] as PackedInt64Array).size(), TICKS, "a digest every tick on the rows path")
	assert_gt(int(rows["native_thinks"]), TICKS * 20, "the native brains thought (%d thinks)" % int(rows["native_thinks"]))
	assert_eq(int(rows["fallbacks"]), 0, "nothing declined on the rows path")
	assert_eq(int(rows["finished"]), 0, "on the rows path no driver finishes a think ship by ship")
	assert_gt(int(rows["live_max"]), SHIPS / 2, "most ships fly a command from the rows (%d at most)" % int(rows["live_max"]))
	assert_lt(int(rows["events"]), int(rows["native_thinks"]) / 4,
			"the drivers handle a few events, not every think (%d events for %d thinks)" % [int(rows["events"]),
			int(rows["native_thinks"])])
	gut.p("battle %d seed %d, %d ticks: %d native thinks, %d events on the rows path, %d ships on row commands at most" % [
			SHIPS, SEED, TICKS, int(rows["native_thinks"]), int(rows["events"]), int(rows["live_max"])])
	assert_eq(ParityFixture.encode(_digest_of(rows)), recorded,
			"every ship flies the drivers' command, trigger and selection every tick, the same rows and the same pilots (recorded)")


# What the battle is held to: the thinks, and digests of every tick's commands and rows and of the pilots at the end.
static func _digest_of(battle: Dictionary) -> Dictionary:
	return {"native_thinks": battle["native_thinks"], "commands": ParityFixture.digest(battle["commands"]),
			"rows": ParityFixture.digest(battle["rows"]), "pilots": ParityFixture.digest(battle["pilots"])}


func test_one_thread_and_six_give_the_same_commands_from_rows() -> void:
	if _skipped():
		return
	var one: Dictionary = await _battle(1, true)
	var six: Dictionary = await _battle(6, true)
	var first: int = _first_difference(one["row_commands"], six["row_commands"])
	assert_eq(first, -1, "the core's commands are the same bits every tick with one thread and six (first difference at tick %d)" % first)
	first = _first_difference(one["rows"], six["rows"])
	assert_eq(first, -1, "and the rows (first difference at tick %d)" % first)
	assert_eq(int(one["events"]), int(six["events"]), "the same events")


func test_a_command_set_from_gdscript_takes_over_from_the_row() -> void:
	if _skipped():
		return
	Settings.set_value(&"perf_native_commands", true)
	var fight: Dictionary = await _small_fight()
	var sim: SimCore = fight["sim"]
	var c: Combatant = null
	for ship: Combatant in fight["ships"]:
		if ship.ship.is_row_commanded() and sim.core.row_command(ship.ship.get_instance_id())[10] == 0.0:
			c = ship
			break
	assert_not_null(c, "a ship flies a command from the rows, without the brake")
	if c == null:
		return
	c.driver.unhost()  # the host steps it no more
	c.driver.set_physics_process(false)  # its pilot stays, but thinks no more: only the command below releases the row
	var cmd := FlightCommand.new()
	cmd.brake = true
	c.apply_commands(cmd, CombatCommand.new())
	assert_false(c.ship.is_row_commanded(), "the ship flies the command set from GDScript")
	var row: PackedFloat64Array = sim.core.row_command(c.ship.get_instance_id())
	assert_true(row.is_empty() or row[0] == 0.0, "the row's command is no longer live")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var batch: FlightBatch = c.ship.get_parent().get_node("FlightBatch") as FlightBatch
	assert_true(batch.stepped(c.ship), "the batch flew it")
	assert_true(c.ship.get_flight_output().braking, "with the GDScript command's brake")


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


## The seeded battle's fighters (four sides, the bench's session table) flown `ticks` ticks on the rows path with
## `threads` threads, every pass in parallel when `parallel`. Returns per tick the rows' digest, the effective commands'
## digest (every ship's flight command, trigger and selection) and the core's commands' digest; the pilots' digest at the
## end; the native thinks, declined thinks, driver finishes and events; the most ships on row commands in a tick.
func _battle(threads: int, parallel: bool, ticks: int = TICKS) -> Dictionary:
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
	_index_of.clear()
	for i: int in ships.size():
		_index_of[ships[i].targetable.get_instance_id()] = i
	var sim: SimCore = SimCore.attach(world)
	if parallel:
		sim.core.set_parallel_min(2)
		sim.core.set_flight_parallel_min(2)
	var digests := PackedInt64Array()
	var commands := PackedInt64Array()
	var row_commands := PackedInt64Array()
	var native_thinks: int = 0
	var fallbacks: int = 0
	var finished: int = 0
	var events: int = 0
	var live_max: int = 0
	for tick: int in ticks:
		await get_tree().physics_frame
		digests.append(int(sim.core.rows_digest()))
		commands.append(_commands_digest(sim, ships))
		var batch: BrainBatch = BrainBatch.for_tree(get_tree())
		row_commands.append(int(sim.core.commands_digest()))
		live_max = maxi(live_max, int(sim.core.live_commands()))
		if batch != null:
			finished += batch.finishes
			events += batch.events
		native_thinks += AiPilotDriver.thinks_native()
		fallbacks += AiPilotDriver.thinks_fallback()
	var pilots := PackedInt64Array()
	for c: Combatant in ships:
		pilots.append(_pilot_digest(c))
	space.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	Factions.reset()
	return {"rows": digests, "commands": commands, "row_commands": row_commands, "pilots": pilots,
			"native_thinks": native_thinks, "fallbacks": fallbacks, "finished": finished, "events": events, "live_max": live_max}


# What every ship flies this tick: the flight command (from its row when it flies one), its cannon's trigger, its selection.
func _commands_digest(sim: SimCore, ships: Array[Combatant]) -> int:
	var all := PackedFloat64Array()
	for c: Combatant in ships:
		if not is_instance_valid(c.ship) or not c.ship.can_process():
			all.append(-1.0)
			continue
		var f: FlightCommand = c.ship._flight
		var row := PackedFloat64Array()
		if c.ship.has_method(&"is_row_commanded") and c.ship.is_row_commanded():
			row = sim.core.row_command(c.ship.get_instance_id())
		if row.size() > 0 and row[0] != 0.0:
			all.append_array(row.slice(1, 11))
		else:
			all.append_array([f.main_left, f.main_right, f.retro_left, f.retro_right, f.strafe.x, f.strafe.y, f.rot.x, f.rot.y,
					f.rot.z, 1.0 if f.brake else 0.0])
		var combat: CombatCommand = c.cannon._command
		all.append(1.0 if combat != null and combat.fire else 0.0)
		all.append(float(_stable(c.ship.targeting.selected_id())))
	return hash(all)


# A target id as the ship's place in the battle (-1 none, -2 not one of the battle's ships).
func _stable(id: int) -> int:
	return int(_index_of.get(id, -2)) if id > 0 else -1


# What the game reads of a pilot: the behaviour in control, the wanted target, the dodge, dwell, switches and the scores.
func _pilot_digest(c: Combatant) -> int:
	var pilot := c.driver.brain as AiPilot
	if pilot == null:
		return 0
	var d: Dictionary = pilot.describe()
	var scores := PackedFloat64Array()
	for id: StringName in AiPilot.TIE_ORDER:
		scores.append(pilot.score_of(id))
		scores.append(pilot.raw_score_of(id))
	return hash([String(pilot.current.id) if pilot.current != null else "none", _stable(pilot.wanted_target_id),
			pilot.dwell_s, pilot.switches, c.driver.avoiding, c.driver.avoiding_urgent, scores, var_to_str(d),
			pilot.desired_velocity, pilot.has_desired_velocity, _stable(pilot.context.attack_target_id),
			_stable(pilot.context.current_target_id)])


# Every ship's command in the core (live flag first, then the numbers), in ship order.
func _row_commands(sim: SimCore, ships: Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for c: Combatant in ships:
		var row: PackedFloat64Array = sim.core.row_command(c.ship.get_instance_id())
		out.append(float(row.size()))
		out.append_array(row)
	return out


# The first index where the two lists differ (or where one ends early), -1 when they are equal.
func _first_difference(a: PackedInt64Array, b: PackedInt64Array) -> int:
	for i: int in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return i
	return -1 if a.size() == b.size() else mini(a.size(), b.size())


# A fight of the battle's first fighters in a space of its own, flown a few ticks so every pilot has its native slot. The
# drivers stepped by hand here take their step back from the host (M4-T35), so these fights queue thinks by hand.
func _small_fight() -> Dictionary:
	Settings.set_value(&"perf_threads", 6)
	Settings.set_value(&"sim_step", &"delayed")  # these fights flush by hand and join the job on the main thread (test_core_snapshot)
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


# --- fix round 1 ---------------------------------------------------------------------------------------------------------


func test_a_ship_whose_row_the_core_lost_is_handed_its_command_once_and_flies_from_the_row_again() -> void:
	if _skipped():
		return
	Settings.set_value(&"perf_native_commands", true)
	var fight: Dictionary = await _small_fight()
	var sim: SimCore = fight["sim"]
	var lost: Array[Combatant] = []
	for c: Combatant in fight["ships"]:
		if c.ship.is_row_commanded():
			sim.core.release_command(c.ship.get_instance_id())  # as a core made again under the ships would hold nothing
			lost.append(c)
	assert_gt(lost.size(), 0, "ships flew from their rows")
	for i: int in 8:  # every ship thinks at least once at the far rate
		await get_tree().physics_frame
	var back: int = 0
	for c: Combatant in lost:
		if c.ship.is_row_commanded() and not sim.core.row_command(c.ship.get_instance_id()).is_empty():
			back += 1
	assert_eq(back, lost.size(), "every ship is handed its command once and flies from its row again (%d of %d)" % [back, lost.size()])
	var events: int = 0
	for i: int in 6:
		await get_tree().physics_frame
		events += AiPilotDriver.rows_events()
	var thinks: int = 0
	for i: int in 6:
		await get_tree().physics_frame
		thinks += AiPilotDriver.thinks_native()
	assert_lt(events, thinks, "the drivers are no longer handed every think (%d events, %d thinks)" % [events, thinks])


func test_a_native_pilot_that_wants_the_nearest_hostile_has_it_selected_as_today() -> void:
	if _skipped():
		return
	Settings.set_value(&"perf_native_commands", true)
	var fight: Dictionary = await _small_fight()
	var c: Combatant = fight["ships"][0]
	c.driver.set_physics_process(false)
	c.ship.targeting.clear_selection()
	c.driver._retarget_in_s = 0.0
	var out := PackedFloat64Array()
	out.resize(BrainBatch.STRIDE)
	out[0] = 1.0  # thought; the wanted target's two halves stay 0: TARGET_NEAREST_HOSTILE
	c.driver.rows_event(BrainBatch.EVENT_SELECT, out, 1)
	assert_true(c.ship.targeting.system.has_selection(), "the driver selected the nearest hostile, as T18's path's retarget does")
