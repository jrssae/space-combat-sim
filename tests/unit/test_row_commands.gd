extends GutTest
## The native pilots' commands as core rows (M4-T33, architecture §17.13): the brains' batch writes each native pilot's
## flight and combat command into the core, the flight batch applies it the same tick, and the drivers touch only the ships
## whose trigger, selection or command source changed. The seeded battle (`SeededBattle`) flies the same bits as the drivers'
## commands did, and as the drivers' own step did at the far rate (`driver_step.json`); a command set from GDScript takes
## over from the row. One thread against six is `test_core_threads`' (M6-T18).

const TICKS: int = 240
const SETTINGS: Array[StringName] = [&"perf_threads", &"sim_step", &"ai_think_rate"]

var _saved: Dictionary = {}
# The battle's ships by their `Targetable` id, so selections compare across runs (each run has its own instance ids).
var _index_of: Dictionary = {}


func before_each() -> void:
	for key: StringName in SETTINGS:
		_saved[key] = Settings.get_value(key)
	Factions.reset()
	ContactScan.invalidate()


func after_each() -> void:
	for key: StringName in SETTINGS:
		if _saved[key] != null:
			Settings.set_value(key, _saved[key])
	Factions.reset()
	ContactScan.invalidate()


const FIXTURE: String = "row_commands"
const DRIVER_STEP_FIXTURE: String = "driver_step"


func test_commands_from_rows_fly_the_same_battle_as_today() -> void:
	# The drivers handing each ship its command (T18's path), recorded before M4-T37 removed it.
	var rows: Dictionary = await _battle(1, true)
	var recorded: Variant = ParityFixture.rerecorded(FIXTURE, "battle_with_commands_from_the_drivers", _digest_of(rows))
	assert_eq((rows["rows"] as PackedInt64Array).size(), TICKS, "a digest every tick on the rows path")
	assert_gt(int(rows["native_thinks"]), TICKS * 20, "the native brains thought (%d thinks)" % int(rows["native_thinks"]))
	assert_eq(int(rows["fallbacks"]), 0, "nothing declined on the rows path")
	assert_eq(int(rows["finished"]), 0, "on the rows path no driver finishes a think ship by ship")
	assert_gt(int(rows["live_max"]), SeededBattle.SHIPS / 2, "most ships fly a command from the rows (%d at most)" % int(rows["live_max"]))
	assert_lt(int(rows["events"]), int(rows["native_thinks"]) / 4,
			"the drivers handle a few events, not every think (%d events for %d thinks)" % [int(rows["events"]),
			int(rows["native_thinks"])])
	gut.p("battle %d seed %d, %d ticks: %d native thinks, %d events on the rows path, %d ships on row commands at most" % [
			SeededBattle.SHIPS, SeededBattle.SEED, TICKS, int(rows["native_thinks"]), int(rows["events"]), int(rows["live_max"])])
	assert_eq(ParityFixture.encode(_digest_of(rows)), recorded,
			"every ship flies the drivers' command, trigger and selection every tick, the same rows and the same pilots (recorded)")
	# The same battle is the driver step's far-rate case (no player, every ship far): the hosted step against the drivers'
	# own step, recorded in `driver_step.json` (M6-T18 folded that test of `test_driver_step` in here).
	var far: Variant = ParityFixture.rerecorded(DRIVER_STEP_FIXTURE, "battle_far_rate", SeededBattle.hosted_digest(rows["hosted"], 1))
	assert_not_null(far, "the drivers' own step was recorded")
	if far == null:
		return
	assert_gt(int(far["hits_total"]), 10, "far rate: hits landed (%d)" % int(far["hits_total"]))
	assert_gt(int(rows["hosted_max"]), SeededBattle.SHIPS / 2, "far rate: most drivers were hosted (%d)" % int(rows["hosted_max"]))
	assert_lt(int(rows["processing_min"]), SeededBattle.SHIPS / 10,
			"far rate: hosted drivers do not tick (%d still processing at the fewest)" % int(rows["processing_min"]))
	assert_eq(ParityFixture.encode(SeededBattle.hosted_digest(rows["hosted"], 1)), far,
			"far rate: the same thinks, held ticks, rows, commands, hits and pilots as the drivers' own step (recorded); ship 0: %s" % [
			rows["first"]])


# What the battle is held to: the thinks, and digests of every tick's commands and rows and of the pilots at the end.
static func _digest_of(battle: Dictionary) -> Dictionary:
	return {"native_thinks": battle["native_thinks"], "commands": ParityFixture.digest(battle["commands"]),
			"rows": ParityFixture.digest(battle["rows"]), "pilots": ParityFixture.digest(battle["pilots"])}


func test_a_declined_think_holds_the_command_the_row_has() -> void:
	var fight: Dictionary = await _small_fight()
	var sim: SimCore = fight["sim"]
	var batch: BrainBatch = BrainBatch.for_tree(get_tree())
	var queued: int = _queue_thinks(fight["ships"])
	assert_gt(queued, 0, "some ships queued a native think")
	sim.touch((fight["ships"][0] as Combatant).ship)
	sim.core.resync_touched_now()  # the rows move between the drivers' scan and the launch
	batch.flush()  # lands the previous tick's job and launches this one (the delayed step runs it at the next join)
	var before: PackedFloat64Array = _row_commands(sim, fight["ships"])
	var live_before: int = int(sim.core.live_commands())
	assert_gt(live_before, 0, "ships fly commands from the rows")
	var held_before: int = AiPilotDriver.thinks_fallback()
	batch.flush()  # joins the job the first flush launched
	assert_eq(AiPilotDriver.thinks_fallback() - held_before, queued, "every queued think was held and counted")
	assert_eq(_row_commands(sim, fight["ships"]), before, "every row keeps its command")
	assert_eq(int(sim.core.live_commands()), live_before, "and every ship still flies it")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var native: int = 0
	for i: int in 4:
		await get_tree().physics_frame
		native += AiPilotDriver.thinks_native()
	assert_gt(native, 0, "native thinks resume")


func test_a_command_set_from_gdscript_takes_over_from_the_row() -> void:
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


func test_ships_flying_from_their_rows_are_not_gathered() -> void:
	var fight: Dictionary = await _small_fight()
	var sim: SimCore = fight["sim"]
	var row_ships: Array[Combatant] = []
	for ship: Combatant in fight["ships"]:
		if ship.ship.is_row_commanded() and not sim.core.row_command(ship.ship.get_instance_id()).is_empty():
			row_ships.append(ship)
	assert_gt(row_ships.size(), SeededBattle.SHIPS / 4, "many ships fly from their rows")
	await get_tree().physics_frame
	var batch: FlightBatch = row_ships[0].ship.get_parent().get_node("FlightBatch") as FlightBatch
	assert_lte(batch.gathered_count, batch.stepped_count() - row_ships.size() / 2,
			"the row ships fly without a GDScript gather (M5-T31; a few take fresh commands through one)")
	for c: Combatant in row_ships:
		assert_true(batch.stepped(c.ship), "%s flown" % c.display_name)
		assert_eq(c.ship.flight_path(), &"native")


## The seeded battle's fighters (`SeededBattle`) flown `ticks` ticks on the rows path with `threads` threads, every pass
## in parallel when `parallel`. Returns per tick the rows' digest, the effective commands' digest (every ship's flight
## command, trigger and selection) and the core's commands' digest; the pilots' digest at the end; the native thinks,
## declined thinks, driver finishes and events; the most ships on row commands in a tick. Under `hosted`, what the driver
## step's recording holds (`SeededBattle.hosted_digest`), with the most drivers hosted and the fewest processing.
func _battle(threads: int, parallel: bool, ticks: int = TICKS) -> Dictionary:
	Settings.set_value(&"perf_threads", threads)
	Settings.set_value(&"ai_think_rate", true)
	var fight: Dictionary = await SeededBattle.start(self, {SeededBattle.OPT_PARALLEL: parallel})
	var sim: SimCore = fight["sim"]
	var ships: Array[Combatant] = fight["ships"]
	_index_of = fight["targetable_index"]
	var tick_hits: Array = []
	SeededBattle.log_hits(fight, tick_hits)
	var digests := PackedInt64Array()
	var commands := PackedInt64Array()
	var row_commands := PackedInt64Array()
	var hits := PackedInt64Array()
	var held_ticks := PackedInt64Array()
	var native_thinks: int = 0
	var fallbacks: int = 0
	var finished: int = 0
	var events: int = 0
	var live_max: int = 0
	var hosted_max: int = 0
	var processing_min: int = ships.size()
	for tick: int in ticks:
		tick_hits.clear()
		await get_tree().physics_frame
		digests.append(int(sim.core.rows_digest()))
		commands.append(_commands_digest(sim, ships))
		var batch: BrainBatch = BrainBatch.for_tree(get_tree())
		row_commands.append(int(sim.core.commands_digest()))
		hits.append(hash(tick_hits))
		live_max = maxi(live_max, int(sim.core.live_commands()))
		if batch != null:
			finished += batch.finishes
			events += batch.events
		native_thinks += AiPilotDriver.thinks_native()
		fallbacks += AiPilotDriver.thinks_fallback()
		held_ticks.append(AiPilotDriver.held())
		hosted_max = maxi(hosted_max, AiPilotDriver.hosted())
		if tick % 40 == 39:
			var processing: int = 0
			for c: Combatant in ships:
				if c.driver.is_physics_processing():
					processing += 1
			processing_min = mini(processing_min, processing)
	var pilots := PackedInt64Array()
	var hosted_pilots := PackedInt64Array()
	for c: Combatant in ships:
		pilots.append(_pilot_digest(c))
		hosted_pilots.append(SeededBattle.pilot_digest(c, fight["index_of"]))
	var hosted: Dictionary = {"rows": digests, "commands": row_commands, "hits": hits,
			"hits_total": (fight["resolver"] as HitResolver).hits_total, "pilots": hosted_pilots, "native_thinks": native_thinks,
			"held_ticks": held_ticks}
	var first: Array = SeededBattle.pilot_parts(ships[0], fight["index_of"])
	await SeededBattle.finish(fight)
	return {"rows": digests, "commands": commands, "row_commands": row_commands, "pilots": pilots,
			"native_thinks": native_thinks, "fallbacks": fallbacks, "finished": finished, "events": events, "live_max": live_max,
			"hosted": hosted, "hosted_max": hosted_max, "processing_min": processing_min, "first": first}


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


# A fight of the battle's first fighters, flown a few ticks so every pilot has its native slot, on the delayed step: these
# fights flush by hand and join the job on the main thread (test_core_snapshot). The drivers stepped by hand here take their
# step back from the host (M4-T35), so these fights queue thinks by hand.
func _small_fight() -> Dictionary:
	Settings.set_value(&"perf_threads", 6)
	Settings.set_value(&"sim_step", &"delayed")
	var fight: Dictionary = await SeededBattle.small_fight(self)
	autofree(fight["space"])
	return fight


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
