extends GutTest
## The core owns the simulated state (M4-T35b, architecture §17.13): activity, hull points and the selection as columns
## updated from events, the ram stage's contact read in one native call with `contact_monitor` off, the AI targeting
## controllers' selection check as a row column, and the batched ships' own tick off. Seeded fights give the rows, commands
## and hits the old paths gave (recorded in `tests/fixtures/parity/core_state.json` before M4-T37 removed them and their
## switches).

const SHIPS: int = 120
const SEED: int = 1
const TICKS: int = 240
const DELTA: float = 1.0 / 60.0
const SPEC_PATH: String = "res://assets/ships/starfury_aurora.tres"
const FIXTURE: String = "core_state"
const SETTINGS: Array[StringName] = [&"perf_native", &"perf_native_core", &"perf_native_brains", &"perf_native_flight",
		&"perf_threads", &"perf_native_commands", &"perf_native_bolt_rows", &"ram_damage"]

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
	Factions.reset()
	ContactScan.invalidate()


func after_each() -> void:
	for key: StringName in SETTINGS:
		if _saved[key] != null:
			Settings.set_value(key, _saved[key])
	Factions.reset()
	ContactScan.invalidate()


func _skipped() -> bool:
	if NativeLib.has_class(SimCore.NATIVE_CLASS):
		return false
	pending("the native library is not built (scripts/build_native.sh), so there is no core to test")
	return true


# --- a small world: two lean ships and the core ---------------------------------------------------------------------


# A world with its projectiles in a space of its own; `[space, world, projectiles]`.
func _space() -> Array:
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
	return [space, world, bolts]


func _ship(world: WorldFrame, bolts: Node3D, name: String, faction: StringName, at: Vector3, ai: bool = false) -> Combatant:
	var c: Combatant = ShipAssembly.build(load(SPEC_PATH) as ShipSpec, world, bolts, {
		ShipAssembly.OPT_FACTION: faction, ShipAssembly.OPT_DISPLAY_NAME: name, ShipAssembly.OPT_LEAN: true,
		ShipAssembly.OPT_AI: ai})
	world.spawn(c.ship, world.to_universe(at))
	return c


func _hull_row(sim: SimCore, c: Combatant) -> float:
	return float(sim.core.row_hull_fraction(sim.core.row_of_id(c.ship.get_instance_id())))


func _target_row(sim: SimCore, c: Combatant) -> int:
	return int(sim.core.row_target_id(sim.core.row_of_id(c.ship.get_instance_id())))


func test_the_hull_and_selection_columns_follow_the_events_at_the_next_sync() -> void:
	if _skipped():
		return
	var made: Array = _space()
	var world: WorldFrame = made[1]
	var a: Combatant = _ship(world, made[2], "A", Factions.EARTH_ALLIANCE, Vector3.ZERO)
	var b: Combatant = _ship(world, made[2], "B", Factions.RAIDERS, Vector3(0.0, 0.0, -500.0))
	var sim: SimCore = SimCore.attach(world)
	await get_tree().physics_frame
	sim.sync_now()
	assert_eq(_hull_row(sim, a), 1.0, "a full hull reads 1")
	assert_eq(_target_row(sim, a), -1, "no selection reads -1")
	var hit := HitInfo.new(a.ship.get_instance_id(), b.ship.get_instance_id(), Factions.RAIDERS, 25.0)
	a.damageable.apply_hit(hit)
	var expected: float = a.damageable.hull.fraction()
	assert_lt(expected, 1.0, "the hit took hull points")
	assert_eq(_hull_row(sim, a), 1.0, "the row keeps the sync's value until the next sync (as a read at the sync would)")
	a.ship.targeting.select_id(b.targetable.get_instance_id())
	assert_eq(a.ship.targeting.selected_id(), b.targetable.get_instance_id(), "A selected B")
	assert_eq(_target_row(sim, a), -1, "the selection column too")
	sim.sync_now()
	assert_eq(_hull_row(sim, a), expected, "the next sync carries the hull the event gave, bit for bit")
	assert_eq(_target_row(sim, a), b.targetable.get_instance_id(), "and the selection")
	a.ship.targeting.clear_selection()
	a.damageable.restore()
	sim.sync_now()
	assert_eq(_hull_row(sim, a), 1.0, "a heal is an event too")
	assert_eq(_target_row(sim, a), -1, "and a cleared selection")
	# Activity: a parked ship loses its row at the next sync, a shown one gets a new one; a touch covers a body that only
	# stopped processing (no visibility event).
	b.ship.visible = false
	b.ship.process_mode = Node.PROCESS_MODE_DISABLED
	sim.sync_now()
	assert_eq(sim.core.row_of_id(b.ship.get_instance_id()), -1, "a hidden, parked ship has no row")
	b.ship.visible = true
	b.ship.process_mode = Node.PROCESS_MODE_INHERIT
	sim.sync_now()
	assert_gte(int(sim.core.row_of_id(b.ship.get_instance_id())), 0, "shown again, it has a row")
	b.ship.process_mode = Node.PROCESS_MODE_DISABLED
	sim.sync_now()
	assert_gte(int(sim.core.row_of_id(b.ship.get_instance_id())), 0,
			"a body that only stopped processing keeps its row until something touches it (no visibility event)")
	sim.touch(b.ship)
	sim.sync_now()
	assert_eq(sim.core.row_of_id(b.ship.get_instance_id()), -1, "touched, it is read again and has none")
	(made[0] as SubViewport).queue_free()
	await get_tree().physics_frame


func test_a_ship_reports_jolt_contacts_with_contact_monitor_off() -> void:
	if _skipped():
		return
	var made: Array = _space()
	var world: WorldFrame = made[1]
	var a: Combatant = _ship(world, made[2], "A", Factions.EARTH_ALLIANCE, Vector3.ZERO)
	var b: Combatant = _ship(world, made[2], "B", Factions.RAIDERS, Vector3(0.0, 0.0, -40.0))
	assert_false(a.ship.contact_monitor, "contact_monitor is off (nothing connects body_entered)")
	assert_eq(a.ship.max_contacts_reported, Ship.CONTACTS_REPORTED, "max_contacts_reported stays")
	b.ship.linear_velocity = Vector3(0.0, 0.0, 60.0)
	var seen: int = 0
	for i: int in 120:
		await get_tree().physics_frame
		var state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(a.ship.get_rid())
		if state != null:
			seen += state.get_contact_count()
	assert_gt(seen, 0, "the direct state still reports contacts (%d points over the melee)" % seen)
	(made[0] as SubViewport).queue_free()
	await get_tree().physics_frame


# --- the AI targeting controllers' selection check ----------------------------------------------------------------------


func test_the_native_selection_check_clears_as_the_controllers_did() -> void:
	if _skipped():
		return
	var recorded: Variant = ParityFixture.stored(FIXTURE, "selection_check_signals")
	var native: Array = await _selection_signals()
	assert_eq(ParityFixture.encode(native), recorded,
			"the same target_changed signals on the same ticks as the controllers' own check (recorded): %s" % [native])
	assert_gte(native.size(), 4, "selections and clears happened")


# A selection in reach, one that leaves reach and one parked, on the native check: each target_changed signal as
# `[ticks since the first, to B, to C, cleared]`.
func _selection_signals() -> Array:
	var made: Array = _space()
	var world: WorldFrame = made[1]
	var a: Combatant = _ship(world, made[2], "A", Factions.EARTH_ALLIANCE, Vector3.ZERO, true)
	var b: Combatant = _ship(world, made[2], "B", Factions.RAIDERS, Vector3(0.0, 0.0, -500.0), true)
	var c: Combatant = _ship(world, made[2], "C", Factions.RAIDERS, Vector3(0.0, 0.0, 500.0), true)
	SimCore.attach(world)
	a.ship.targeting.set_sensor_range_m(1000.0)  # the core's check took the range when the controller bound
	var changes: Array = []
	a.ship.targeting.target_changed.connect(func(id: int) -> void: changes.append([Engine.get_physics_frames(), id]))
	await get_tree().physics_frame
	assert_eq(a.ship.targeting.is_physics_processing(), false, "the AI controller hands its check to the core")
	var frame0: int = Engine.get_physics_frames()
	a.ship.targeting.select_id(b.targetable.get_instance_id())
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(a.ship.targeting.selected_id(), b.targetable.get_instance_id(), "B in reach stays selected")
	b.ship.global_position = Vector3(0.0, 0.0, -2000.0)  # out of A's reach
	await get_tree().physics_frame
	assert_eq(a.ship.targeting.selected_id(), 0, "a selection that left reach is cleared by the next tick")
	a.ship.targeting.select_id(c.targetable.get_instance_id())
	await get_tree().physics_frame
	c.ship.visible = false
	c.ship.process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().physics_frame
	assert_eq(a.ship.targeting.selected_id(), 0, "a parked selection is cleared")
	var stamped: Array = []
	for change: Array in changes:
		stamped.append([int(change[0]) - frame0, change[1] == b.targetable.get_instance_id(),
				change[1] == c.targetable.get_instance_id(), change[1] == 0])
	(made[0] as SubViewport).queue_free()
	await get_tree().physics_frame
	return stamped


# --- the batch owns its ships' ticks ------------------------------------------------------------------------------------


## Reads a row's position at `priority`, each tick (a probe for the late systems' view of the rows).
class RowProbe extends Node:
	var sim: SimCore
	var body: Node3D
	var row_position: Vector3 = Vector3.INF
	var body_position: Vector3 = Vector3.INF

	func _init(p_sim: SimCore, p_body: Node3D, priority: int) -> void:
		sim = p_sim
		body = p_body
		process_physics_priority = priority

	func _physics_process(_delta: float) -> void:
		var hulls: Array = sim.core.hull_columns()
		var i: int = (hulls[0] as PackedInt64Array).find(body.get_instance_id())
		row_position = (hulls[3] as PackedVector3Array)[i] if i >= 0 else Vector3.INF
		body_position = body.global_position


func test_a_drifting_buoy_is_read_where_this_ticks_move_put_it() -> void:
	# Fix rounds 1 and 2: a script-moved target (a nav buoy's drift at the default priority, after the core's first sync)
	# touches its row, which the core reads again before the native selection check (100) and the hit sweep (200), so
	# they see this tick's place as the tree reads did. The buoy keeps the default priority: the World's rebase at 0
	# runs before every prop (test_rebase_in_play).
	if _skipped():
		return
	var parts: Array = _space()
	var space: SubViewport = parts[0]
	var world: WorldFrame = parts[1]
	var buoy: NavBuoy = NavBuoy.create("BUOY", Vector3(600.0, 0.0, 0.0))
	world.spawn(buoy, world.to_universe(Vector3(0.0, 0.0, -500.0)))
	var sim: SimCore = SimCore.attach(world)
	var resolver := HitResolver.new()  # the resolvers' sync at 200 reads the touched rows again
	resolver.name = "HitResolver"
	space.add_child(resolver)
	var at_check := RowProbe.new(sim, buoy, TargetingController.LATE_PRIORITY + 1)
	var at_sweep := RowProbe.new(sim, buoy, HitResolver.LATE_PRIORITY + 1)
	space.add_child(at_check)
	space.add_child(at_sweep)
	for i: int in 3:
		await get_tree().physics_frame
	assert_eq(buoy.process_physics_priority, 0, "the buoy moves at the default priority, after the World's rebase")
	assert_ne(at_check.row_position, Vector3.INF, "the buoy's hull is a row")
	assert_eq(at_check.row_position, at_check.body_position, "after the selection check: the row is where this tick's drift put the buoy, bit for bit")
	assert_eq(at_sweep.row_position, at_sweep.body_position, "after the hit sweep: the same")
	space.queue_free()
	await get_tree().physics_frame


func test_the_batch_switches_its_ships_own_tick_off_and_back() -> void:
	if _skipped():
		return
	var made: Array = _space()
	var world: WorldFrame = made[1]
	var a: Combatant = _ship(world, made[2], "A", Factions.EARTH_ALLIANCE, Vector3.ZERO, true)
	var b: Combatant = _ship(world, made[2], "B", Factions.RAIDERS, Vector3(0.0, 0.0, -500.0), true)
	SimCore.attach(world)
	var batch: FlightBatch = FlightBatch.attach(world)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_true(batch.stepped(a.ship), "the batch flies A")
	assert_false(a.ship.is_physics_processing(), "a ship the batch flies does not tick itself")
	assert_false(b.ship.is_physics_processing(), "nor B")
	a.ship.batched = false
	await get_tree().physics_frame
	assert_true(a.ship.is_physics_processing(), "a ship off the batch ticks itself again")
	assert_false(batch.stepped(a.ship), "and the batch no longer flies it")
	# The combat edges a batch-owned ship is handed still reach its targeting.
	var cmd := CombatCommand.new()
	cmd.target_next = true
	b.ship.set_combat_command(cmd)
	await get_tree().physics_frame
	assert_eq(b.ship.targeting.selected_id(), a.targetable.get_instance_id(), "target_next selected the other ship through the batch's gather")
	(made[0] as SubViewport).queue_free()
	await get_tree().physics_frame


# --- the seeded battle, each path against its reference -----------------------------------------------------------------


## The seeded battle's fighters flown `ticks` ticks with `overrides` set and `threads` threads: per tick the rows' digest
## (positions, velocities, bases, spins, flags, hulls, selections), the commands' digest and a digest of the hits.
func _battle(overrides: Dictionary, threads: int, ticks: int = TICKS) -> Dictionary:
	for key: StringName in overrides:
		Settings.set_value(key, overrides[key])
	Settings.set_value(&"perf_threads", threads)
	Factions.reset()
	Factions.use_table(BenchLayout.faction_table(BenchLayout.BATTLE))
	ContactScan.invalidate()
	await get_tree().process_frame
	await get_tree().physics_frame
	SimClock.reset()
	var made: Array = _space()
	var space: SubViewport = made[0]
	var world: WorldFrame = made[1]
	var bolts: Node3D = made[2]
	var resolver := HitResolver.new()
	resolver.name = "HitResolver"
	space.add_child(resolver)
	var rams := RamResolver.new()
	rams.name = "RamResolver"
	rams.world = world
	space.add_child(rams)
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
		var made_brain: Dictionary = BrainFactory.from_behaviour(e["behaviour"], anchor, int(e["seed"]))
		c.driver.brain = made_brain["brain"] as PilotBrain
		ships.append(c)
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
	rams.ram_resolved.connect(func(info: HitInfo) -> void:
		tick_hits.append(["ram", _index_of.get(info.target_id, -2), _index_of.get(info.shooter_id, -2), info.damage, info.point]))
	var rows := PackedInt64Array()
	var commands := PackedInt64Array()
	var hits := PackedInt64Array()
	var ram_count: int = 0
	for t: int in ticks:
		tick_hits.clear()
		await get_tree().physics_frame
		rows.append(int(sim.core.rows_digest()))
		commands.append(int(sim.core.commands_digest()))
		hits.append(hash(tick_hits))
	ram_count = rams.rams_total if "rams_total" in rams else 0
	var out: Dictionary = {"rows": rows, "commands": commands, "hits": hits, "hits_total": resolver.hits_total, "rams": ram_count,
			"sync_calls": sim.engine_calls()[0]}
	space.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	return out


static func _first_difference(a: PackedInt64Array, b: PackedInt64Array) -> int:
	for i: int in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return i
	return -1 if a.size() == b.size() else mini(a.size(), b.size())


# What a battle is held to: digests of its rows, commands and hits every tick, and its totals.
static func _digest_of(battle: Dictionary) -> Dictionary:
	return {"rows": ParityFixture.digest(battle["rows"]), "commands": ParityFixture.digest(battle["commands"]),
			"hits": ParityFixture.digest(battle["hits"]), "hits_total": battle["hits_total"], "rams": battle["rams"],
			"ticks": (battle["rows"] as PackedInt64Array).size()}


# The cases recorded with one old path each (M4-T37: the event columns, the native selection check and the batch owning
# its ships off), before those paths were removed.
const OLD_PATH_CASES: Array[String] = ["battle_without_perf_core_event_columns", "battle_without_perf_native_selection_check",
		"battle_without_perf_batch_owns_ships"]


func test_the_battle_flies_as_each_old_path_did() -> void:
	if _skipped():
		return
	var candidate: Dictionary = await _battle({}, 1)
	for case: String in OLD_PATH_CASES:
		var recorded: Variant = ParityFixture.stored(FIXTURE, case)
		assert_not_null(recorded, "%s was recorded" % case)
		if recorded == null:
			continue
		assert_gt(int(recorded["hits_total"]), 10, "%s: hits landed (%d)" % [case, int(recorded["hits_total"])])
		assert_eq(ParityFixture.encode(_digest_of(candidate)), recorded,
				"%s: the same rows, commands and hits every tick as the recording" % case)
	gut.p("%d hits; %d sync calls a tick" % [int(candidate["hits_total"]), int(candidate["sync_calls"])])


func test_one_thread_and_six_give_the_same_battle_with_everything_on() -> void:
	if _skipped():
		return
	var one: Dictionary = await _battle({}, 1)
	var six: Dictionary = await _battle({}, 6)
	var first: int = _first_difference(one["rows"], six["rows"])
	assert_eq(first, -1, "the rows are the same bits with one thread and six (first difference at tick %d)" % first)
	first = _first_difference(one["hits"], six["hits"])
	assert_eq(first, -1, "and the hits (first difference at tick %d)" % first)


# --- the ram stage's contact read ---------------------------------------------------------------------------------------


# The melee of `test_fighter_melee`, in a fresh physics space: [digest, ram lines, the resolver's contact path].
func _melee() -> Array:
	var made: Array = _space()
	var space: SubViewport = made[0]
	var world: WorldFrame = made[1]
	var rams := RamResolver.new()
	rams.world = world
	space.add_child(rams)
	var ram_lines := PackedStringArray()
	rams.ram_resolved.connect(func(info: HitInfo) -> void: ram_lines.append("ram %s<-%s dmg %.6f applied %.6f v %.6f at %s" % [
			HitResolver.name_of(info.target_id), HitResolver.name_of(info.shooter_id), info.damage, info.applied,
			info.relative_speed_mps, var_to_str(info.point)]))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ships: Array[Combatant] = []
	for i: int in 8:
		var c: Combatant = ShipAssembly.build(load(SPEC_PATH) as ShipSpec, world, made[2], {
			ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE if i % 2 == 0 or i == 5 else Factions.RAIDERS,
			ShipAssembly.OPT_DISPLAY_NAME: "F%d" % i, ShipAssembly.OPT_LEAN: true})
		world.spawn(c.ship, world.to_universe(Vector3(0.0, 0.0, 5000.0 * i)))
		ships.append(c)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for c: Combatant in ships:
		var at := Vector3(rng.randf_range(-60.0, 60.0), rng.randf_range(-30.0, 30.0), rng.randf_range(-60.0, 60.0))
		c.ship.reset_to(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)), at))
		c.ship.linear_velocity = -at.normalized() * rng.randf_range(15.0, 70.0)
	var lines := PackedStringArray()
	for tick: int in 240:
		await get_tree().physics_frame
		if tick % 20 == 19:
			for c: Combatant in ships:
				var s: Ship = c.ship
				lines.append("t%d %s %s %s %s %.6f" % [tick, c.display_name, var_to_str(s.global_position),
						var_to_str(s.linear_velocity), var_to_str(s.angular_velocity), c.damageable.hull.hp])
	var path: StringName = rams.contact_path()
	space.queue_free()
	await get_tree().physics_frame
	return ["\n".join(lines), ram_lines.duplicate(), path]


func test_the_melee_rams_the_same_with_the_contacts_read_natively() -> void:
	if _skipped():
		return
	Settings.set_value(&"ram_damage", true)
	var recorded: Variant = ParityFixture.stored(FIXTURE, "melee_rams")
	var native: Array = await _melee()
	assert_eq(native[2], &"native", "the contacts are read in one native call")
	assert_not_null(recorded, "the GDScript read's melee was recorded")
	if recorded == null:
		return
	assert_gt((recorded["rams"] as Array).size(), 5, "the melee rams")
	assert_eq(ParityFixture.encode(_melee_summary(native)), recorded,
			"the same rams in the same order, and the same poses, spins and hulls every 20 ticks, as the recording")


# What the melee is held to: its ram lines whole and a digest of its pose lines.
static func _melee_summary(melee: Array) -> Dictionary:
	return {"rams": melee[1], "poses": ParityFixture.digest(melee[0])}
