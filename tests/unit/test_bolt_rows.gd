extends GutTest
## Bolts as core rows (M4-T35a, architecture §17.13): the core owns its bolts, a kernel steps them as a `Projectile` node
## stepped itself, the cannons' gates and spawns run as a kernel over the rows, the hit resolver sweeps and spends the rows,
## and one multimesh draws them. Bit for bit with the bolt node path: the gate, the spawn, the step, and a seeded battle's
## hits and rows; 1 and 6 threads identical; the engine calls do not grow with the bolts. Skips, saying why, when the
## library is not built.

const SHIPS: int = 120
const SEED: int = 1
const TICKS: int = 240
const DELTA: float = 1.0 / 60.0
const NO_NODES: Array[Node] = []
const SETTINGS: Array[StringName] = [&"perf_native", &"perf_native_core", &"perf_native_brains", &"perf_native_flight",
		&"perf_threads", &"perf_native_commands", &"perf_native_bolt_rows"]
const SPEC_PATH: String = "res://assets/ships/starfury_aurora.tres"

var _saved: Dictionary = {}
var _index_of: Dictionary = {}
# A diagnostic: the bolt table of both runs at this tick, printed when they differ.
var _dump_tick: int = -1
var _dumps: Array[String] = []


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


func _skipped() -> bool:
	if NativeLib.has_class(SimCore.NATIVE_CLASS) and NativeLib.has_class(SimCore.CANNONS_CLASS):
		return false
	pending("the native library is not built (scripts/build_native.sh), so there are no bolt rows to test")
	return true


func test_the_setting_exists_and_defaults_on() -> void:
	assert_true(Settings.schema.has_key(&"perf_native_bolt_rows"), "perf_native_bolt_rows is a setting")
	assert_eq(Settings.schema.get_default(&"perf_native_bolt_rows"), true, "on by default")


# --- the bolt kernel against the node ---------------------------------------------------------------------------------


# A bare core that owns its bolts, synced at `tick` with no nodes.
func _core(tick: int = 100) -> Object:
	var core: Object = NativeLib.instantiate(SimCore.NATIVE_CLASS)
	core.set_bolt_rows(true)
	core.sync_in(NO_NODES, tick, DELTA)
	return core


func _random_vec(rng: RandomNumberGenerator, scale: float) -> Vector3:
	return Vector3(rng.randf_range(-scale, scale), rng.randf_range(-scale, scale), rng.randf_range(-scale, scale))


# One tick of a node bolt by hand, as `Projectile._physics_process` does it.
func _fly(bolt: Projectile) -> void:
	bolt.last_step = bolt.velocity * DELTA
	bolt.global_position += bolt.last_step


func test_an_owned_bolt_steps_as_a_node_bolt_does() -> void:
	if _skipped():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 35
	var world := WorldFrame.new()
	add_child_autofree(world)
	var core: Object = _core(100)
	var nodes: Array[Projectile] = []
	for i: int in 60:
		var at: Vector3 = _random_vec(rng, 9000.0)
		var velocity: Vector3 = _random_vec(rng, 1.0).normalized() * rng.randf_range(200.0, 1200.0)
		var bolt := (load(Projectile.SCENE_PATH) as PackedScene).instantiate() as Projectile
		world.add_child(bolt)
		bolt.set_physics_process(false)
		bolt.launch(at, velocity, 0.0)
		nodes.append(bolt)
		core.add_bolt(at, velocity, Factions.RAIDERS, 7, null, 0.25, 10.0, Color.WHITE, 0, 4.0, 0.0)
	assert_eq(int(core.owned_bolts()), 60, "sixty owned rows")
	var now_s: float = 0.0
	for tick: int in range(101, 221):
		now_s += DELTA
		core.sync_in(NO_NODES, tick, DELTA)
		core.step_bolts(now_s, DELTA)
		for bolt: Projectile in nodes:
			_fly(bolt)
		var columns: Array = core.bolt_columns()
		var ends: PackedVector3Array = columns[2]
		var starts: PackedVector3Array = columns[1]
		for i: int in nodes.size():
			if ends[i] != nodes[i].global_position or starts[i] != nodes[i].global_position - nodes[i].last_step:
				fail_test("tick %d bolt %d: row %s from %s, node %s from %s" % [tick, i, ends[i], starts[i],
						nodes[i].global_position, nodes[i].global_position - nodes[i].last_step])
				return
	pass_test("120 ticks of 60 bolts: the rows hold the nodes' positions and steps bit for bit")


func test_a_bolt_waits_out_its_launch_tick_and_expires_in_time() -> void:
	if _skipped():
		return
	var core: Object = _core(5)
	var velocity := Vector3(600.0, 0.0, 0.0)
	var id: int = core.add_bolt(Vector3(1.0, 2.0, 3.0), velocity, Factions.RAIDERS, 7, null, 0.25, 10.0, Color.WHITE, 0, 1.0, 10.0)
	assert_lt(id, 0, "an owned bolt's id is negative, never an instance id")
	assert_eq(int(core.step_bolts(10.0, DELTA)), 0, "nothing expired")
	var ends: PackedVector3Array = core.bolt_columns()[2]
	assert_eq(ends[0], Vector3(1.0, 2.0, 3.0), "a bolt does not move on its launch tick")
	assert_eq((core.bolt_columns()[1] as PackedVector3Array)[0], Vector3(1.0, 2.0, 3.0), "its segment is its muzzle")
	core.sync_in(NO_NODES, 6, DELTA)
	core.step_bolts(10.0 + DELTA, DELTA)
	ends = core.bolt_columns()[2]
	assert_eq(ends[0], Vector3(1.0, 2.0, 3.0) + velocity * DELTA, "the next tick moves it by velocity * delta")
	core.sync_in(NO_NODES, 7, DELTA)
	assert_eq(int(core.step_bolts(10.999, DELTA)), 0, "alive until its lifetime ends")
	core.sync_in(NO_NODES, 8, DELTA)
	assert_eq(int(core.step_bolts(11.0, DELTA)), 1, "expired when now reaches expires_at")
	assert_eq(int(core.owned_bolts()), 0, "and gone")


func test_a_spent_bolt_stays_flagged_until_the_next_sync() -> void:
	if _skipped():
		return
	var core: Object = _core(5)
	var ids: Array[int] = []
	for i: int in 5:
		ids.append(core.add_bolt(Vector3(float(i), 0.0, 0.0), Vector3.ZERO, Factions.RAIDERS, 7, null, 0.25, 10.0, Color.WHITE, 0,
				4.0, 0.0))
	assert_true(core.spend_bolt(ids[1]), "the second bolt is spent")
	assert_true(core.spend_bolt_row(3), "and the fourth, by row")
	assert_false(core.spend_bolt(12345), "no such owned bolt")
	var spent: PackedByteArray = core.bolt_columns()[10]
	assert_eq(Array(spent), [0, 1, 0, 1, 0], "the spent rows are flagged, still listed")
	assert_false(core.bolt_live(1), "a spent row is not live")
	assert_true(core.bolt_live(0), "an unspent one is")
	assert_eq(int(core.bolt_columns()[11]), 5, "five owned rows")
	core.sync_out()
	assert_eq(int(core.bolt_columns()[11]), 5, "still listed at the tick's end (a spent node is, until its frame ends)")
	core.sync_in(NO_NODES, 6, DELTA)
	var left: PackedInt64Array = core.bolt_columns()[0]
	assert_eq(Array(left), [ids[0], ids[2], ids[4]], "the next sync drops the spent rows and keeps the order")


func test_a_rebase_shifts_the_owned_rows() -> void:
	if _skipped():
		return
	var core: Object = _core(5)
	core.add_bolt(Vector3(1.0, 2.0, 3.0), Vector3.ZERO, Factions.RAIDERS, 7, null, 0.25, 10.0, Color.WHITE, 0, 4.0, 0.0)
	core.shift(Vector3(-1000.0, 0.0, 10.0))
	assert_eq((core.bolt_columns()[2] as PackedVector3Array)[0], Vector3(-999.0, 2.0, 13.0), "the row moved with the world")


func test_node_projectiles_follow_the_owned_rows_in_the_table() -> void:
	if _skipped():
		return
	var world := WorldFrame.new()
	add_child_autofree(world)
	var core: Object = _core(5)
	core.add_bolt(Vector3.ZERO, Vector3.ZERO, Factions.RAIDERS, 7, null, 0.25, 10.0, Color.WHITE, 0, 4.0, 0.0)
	var beam := (load(Projectile.SCENE_PATH) as PackedScene).instantiate() as Projectile
	world.add_child(beam)
	beam.set_physics_process(false)
	beam.faction = Factions.EARTH_ALLIANCE
	beam.shooter_id = 99
	beam.damage = 25.0
	beam.fire_beam(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, -100.0), 0.0)
	var group: Array[Node] = [beam]
	core.sync_in(group, 6, DELTA)
	var columns: Array = core.bolt_columns()
	assert_eq(int(columns[11]), 1, "one owned row")
	assert_eq((columns[0] as PackedInt64Array).size(), 2, "the beam follows it")
	assert_eq((columns[0] as PackedInt64Array)[1], beam.get_instance_id(), "the node row keeps its instance id")
	assert_eq((columns[8] as PackedFloat64Array)[1], 25.0, "its damage is a column now")
	assert_eq((columns[6] as PackedInt64Array)[1], 99, "and its shooter")
	core.set_bolt_rows(false)
	assert_eq(int(core.owned_bolts()), 0, "switching the rows off drops the owned bolts")


func test_the_engine_calls_do_not_grow_with_the_owned_bolts() -> void:
	if _skipped():
		return
	var core: Object = _core(5)
	core.sync_bolts(NO_NODES, DELTA)
	core.sync_out()
	var quiet: int = core.engine_calls()[0]
	for i: int in 2000:
		core.add_bolt(Vector3(float(i), 0.0, 0.0), Vector3(1.0, 0.0, 0.0), Factions.RAIDERS, 7, null, 0.25, 10.0, Color.WHITE, 0,
				40.0, 0.0)
	core.sync_in(NO_NODES, 6, DELTA)
	core.step_bolts(DELTA, DELTA)
	core.sync_bolts(NO_NODES, DELTA)
	core.sync_out()
	assert_eq(core.engine_calls()[0], quiet, "2 000 owned bolts cost the sync points no engine call")
	assert_eq(int(core.owned_bolts()), 2000, "all of them in the table")


func test_the_renderer_draws_each_live_bolt_between_its_ticks() -> void:
	if _skipped():
		return
	var core: Object = _core(5)
	var v := Vector3(600.0, 0.0, 0.0)
	for i: int in 3:
		core.add_bolt(Vector3(0.0, float(i), 0.0), v, Factions.RAIDERS, 7, null, 0.25, 10.0, Color.WHITE, 2 if i == 2 else 0, 4.0, 0.0)
	core.sync_in(NO_NODES, 6, DELTA)
	core.step_bolts(DELTA, DELTA)
	core.spend_bolt_row(1)
	assert_eq(int(core.bolt_instances(0)), 2, "two slots of look 0: the spent bolt keeps its slot until the next sync drops it")
	assert_eq(int(core.bolt_instances(2)), 1, "one of look 2")
	var at_end: PackedFloat32Array = core.bolt_transforms(0, 1.0, 1.0, Basis.IDENTITY, 0)
	assert_eq(at_end.size(), 2 * SimCore.BOLT_INSTANCE_FLOATS, "twelve floats an instance")
	assert_eq(at_end.slice(SimCore.BOLT_INSTANCE_FLOATS).count(0.0), SimCore.BOLT_INSTANCE_FLOATS, "the spent bolt's slot is all zero: nothing drawn")
	assert_almost_eq(Vector3(at_end[3], at_end[7], at_end[11]), v * DELTA, Vector3.ONE * 1e-4, "at fraction 1 the bolt is drawn where its tick left it")
	var at_start: PackedFloat32Array = core.bolt_transforms(0, 0.0, 1.0, Basis.IDENTITY, 0)
	var padded: PackedFloat32Array = core.bolt_transforms(0, 0.0, 1.0, Basis.IDENTITY, 8)
	assert_eq(padded.size(), 8 * SimCore.BOLT_INSTANCE_FLOATS, "padded to the multimesh's instance count")
	assert_almost_eq(Vector3(at_start[3], at_start[7], at_start[11]), Vector3.ZERO, Vector3.ONE * 1e-4,
			"at fraction 0 where the last tick left it")


# The y of the bolt drawn in each instance slot of look 0 at fraction 1 (-1.0 for an empty slot: an all-zero transform).
func _slot_ys(core: Object) -> Array[float]:
	var buffer: PackedFloat32Array = core.bolt_transforms(0, 1.0, 1.0, Basis.IDENTITY, 0)
	var out: Array[float] = []
	@warning_ignore("integer_division")
	for k: int in buffer.size() / SimCore.BOLT_INSTANCE_FLOATS:
		var base: int = k * SimCore.BOLT_INSTANCE_FLOATS
		var live: bool = buffer[base] != 0.0 or buffer[base + 1] != 0.0 or buffer[base + 2] != 0.0
		out.append(buffer[base + 7] if live else -1.0)
	return out


func test_a_bolts_draw_slot_stays_its_own_while_others_come_and_go() -> void:
	# Fix round 1 (review minor 1): instance k follows the same bolt tick to tick, for T38's motion vectors.
	if _skipped():
		return
	var core: Object = _core(5)
	var v := Vector3(600.0, 0.0, 0.0)
	for i: int in 3:
		core.add_bolt(Vector3(0.0, float(i + 1), 0.0), v, Factions.RAIDERS, 7, null, 0.25, 10.0, Color.WHITE, 0, 0.5 if i == 0 else 4.0, 0.0)
	core.sync_in(NO_NODES, 6, DELTA)
	core.step_bolts(DELTA, DELTA)
	assert_eq(_slot_ys(core), [1.0, 2.0, 3.0] as Array[float], "three bolts in three slots")
	core.spend_bolt_row(1)
	core.sync_in(NO_NODES, 7, DELTA)  # drops the spent row
	core.step_bolts(2.0 * DELTA, DELTA)
	assert_eq(int(core.bolt_instances(0)), 3, "the spent bolt's slot stays, empty")
	assert_eq(_slot_ys(core), [1.0, -1.0, 3.0] as Array[float], "the other two keep their slots")
	core.add_bolt(Vector3(0.0, 4.0, 0.0), v, Factions.RAIDERS, 7, null, 0.25, 10.0, Color.WHITE, 0, 4.0, 0.0)
	core.sync_in(NO_NODES, 8, DELTA)
	core.step_bolts(3.0 * DELTA, DELTA)
	assert_eq(_slot_ys(core), [1.0, 4.0, 3.0] as Array[float], "a new bolt takes the free slot")
	core.sync_in(NO_NODES, 9, DELTA)
	core.step_bolts(1.0, DELTA)  # the first bolt expires
	assert_eq(_slot_ys(core), [-1.0, 4.0, 3.0] as Array[float], "an expired bolt frees its slot, the others stay put")
	core.sync_in(NO_NODES, 10, DELTA)
	core.step_bolts(10.0, DELTA)
	assert_eq(int(core.bolt_instances(0)), 0, "no instances once every bolt is gone")


# --- the cannon kernel against the GDScript gate and spawn ------------------------------------------------------------


func _weapon() -> WeaponSpec:
	var weapon := WeaponSpec.new()
	weapon.convergence_range_m = 300.0
	return weapon


func _register(cannons: Object, weapon: WeaponSpec, muzzles: PackedVector3Array, body_id: int = 77) -> int:
	return int(cannons.register(body_id, muzzles, weapon.shot_interval_s, weapon.capacitor_capacity, weapon.capacitor_cost_per_shot,
			weapon.capacitor_recharge_per_s, weapon.muzzle_speed_mps, weapon.convergence_range_m, weapon.lifetime_s, weapon.damage,
			weapon.hit_radius_m, weapon.bolt_color, 0, Factions.RAIDERS))


# The muzzles fired by `step_one`'s answer (`[triples, positions]`).
static func _fired_muzzles(answer: Array) -> Array[int]:
	var shots: PackedInt64Array = answer[0]
	var out: Array[int] = []
	for k: int in range(1, shots.size(), 3):
		out.append(int(shots[k]))
	return out


func test_the_cannon_kernel_gates_as_the_gdscript_gate_does() -> void:
	if _skipped():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 3535
	var core: Object = _core(5)
	var cannons: Object = NativeLib.instantiate(SimCore.CANNONS_CLASS)
	var weapon: WeaponSpec = _weapon()
	var muzzles := PackedVector3Array([Vector3(-1.0, 0.0, -2.0), Vector3(1.0, 0.0, -2.0)])
	var slot: int = _register(cannons, weapon, muzzles)
	var gate := PulseCannonGate.new(2, weapon.shot_interval_s)
	gate.capacitor = weapon.make_capacitor()
	var now_s: float = 0.0
	var shots_fired: int = 0
	var cycles: int = 0
	for step: int in 900:
		now_s += DELTA
		if step == 500:
			now_s = 2.0  # a clock reset, as a respawn makes one
		var trigger: bool = rng.randf() < 0.7
		var weapon_next: bool = rng.randf() < 0.03
		if rng.randf() < 0.02:
			var fraction: float = rng.randf()
			gate.capacitor.set_fraction(fraction, now_s)
			cannons.set_charge_fraction(slot, fraction, now_s)
		if weapon_next:
			gate.cycle_mode()
			cycles += 1
		cannons.set_trigger(slot, trigger, weapon_next)
		var expected: Array[int] = gate.update(now_s, trigger)
		var fired: Array[int] = _fired_muzzles(cannons.step_one(core, slot, Basis.IDENTITY, Vector3.ZERO, Vector3.ZERO, now_s))
		if fired != expected:
			fail_test("step %d: the kernel fired %s, the gate %s" % [step, fired, expected])
			return
		shots_fired += fired.size()
		if cannons.cooldown_remaining(slot, now_s) != gate.cooldown_remaining(now_s):
			fail_test("step %d: cooldown %f against %f" % [step, cannons.cooldown_remaining(slot, now_s), gate.cooldown_remaining(now_s)])
			return
		if cannons.charge_fraction(slot, now_s) != gate.capacitor.fraction_at(now_s):
			fail_test("step %d: charge %f against %f" % [step, cannons.charge_fraction(slot, now_s), gate.capacitor.fraction_at(now_s)])
			return
		assert_eq(bool(cannons.linked(slot)), gate.mode == PulseCannonGate.Mode.LINKED, "the same mode at step %d" % step)
	assert_gt(shots_fired, 40, "the sequence fired (%d shots, %d mode cycles)" % [shots_fired, cycles])
	pass_test("900 steps: the same muzzles, cooldowns and charge as the GDScript gate and capacitor")


func test_a_kernel_shot_leaves_the_muzzle_as_the_gdscript_spawn_does() -> void:
	if _skipped():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 36
	var world := WorldFrame.new()
	add_child_autofree(world)
	var body := Node3D.new()
	world.add_child(body)
	var guns := Node3D.new()
	body.add_child(guns)
	var locals := PackedVector3Array([Vector3(-1.3, 0.2, -2.1), Vector3(1.3, 0.2, -2.1), Vector3(0.0, -0.7, -3.0)])
	var markers: Array[Node3D] = []
	for local: Vector3 in locals:
		var marker := Marker3D.new()
		marker.position = local
		guns.add_child(marker)
		markers.append(marker)
	for convergence: float in [0.0, 300.0]:
		var core: Object = _core(5)
		var cannons: Object = NativeLib.instantiate(SimCore.CANNONS_CLASS)
		var weapon: WeaponSpec = _weapon()
		weapon.convergence_range_m = convergence
		var slot: int = _register(cannons, weapon, locals)
		cannons.set_linked(slot, true)
		cannons.set_trigger(slot, true, false)
		var now_s: float = 1.0
		for round: int in 40:
			now_s += 1.0
			cannons.set_charge_fraction(slot, 1.0, now_s)  # the capacitor would hold a volley back every few rounds
			body.global_transform = Transform3D(Basis.from_euler(_random_vec(rng, PI)), _random_vec(rng, 8000.0))
			var velocity: Vector3 = _random_vec(rng, 300.0)
			var answer: Array = cannons.step_one(core, slot, body.global_basis, body.global_position, velocity, now_s)
			var shots: PackedInt64Array = answer[0]
			assert_eq(shots.size(), 9, "every muzzle fired (linked)")
			assert_eq((answer[1] as PackedVector3Array).size(), 3, "a start per shot")
			var columns: Array = core.bolt_columns()
			var ends: PackedVector3Array = columns[2]
			var velocities: PackedVector3Array = columns[12]
			var owned: int = int(columns[11])
			# The GDScript spawn, as `PulseCannon.step` and `_spawn` compute it from the nodes.
			var forward: Vector3 = -body.global_basis.z
			var converge_at: Vector3 = body.global_position + forward * weapon.convergence_range_m
			for m: int in 3:
				var direction: Vector3 = forward
				if weapon.convergence_range_m > 0.0:
					direction = (converge_at - markers[m].global_position).normalized()
				var expected_velocity: Vector3 = velocity + direction * weapon.muzzle_speed_mps
				var row: int = owned - 3 + m
				if ends[row] != markers[m].global_position or velocities[row] != expected_velocity:
					fail_test("convergence %.0f round %d muzzle %d: row at %s with %s, the node spawn at %s with %s" % [convergence,
							round, m, ends[row], velocities[row], markers[m].global_position, expected_velocity])
					return
	pass_test("80 volleys of three: the rows start at the markers' positions with the spawn's velocities, bit for bit")


# --- the seeded battle on both paths ----------------------------------------------------------------------------------


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


## The seeded battle's fighters flown `ticks` ticks with the bolt rows off or on and `threads` threads. Returns per tick a
## digest of the hull rows (positions, velocities, bases), of the bolt table (starts and ends) and of the hits (target and
## shooter by their place in the battle, damage, point), the kills, the shots, and the most bolt nodes and owned rows seen.
func _battle(rows_on: bool, threads: int, ticks: int = TICKS) -> Dictionary:
	Settings.set_value(&"perf_native_bolt_rows", rows_on)
	Settings.set_value(&"perf_threads", threads)
	Settings.set_value(&"perf_native_commands", true)
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
		_index_of[ships[i].ship.get_instance_id()] = i
		_index_of[ships[i].targetable.get_instance_id()] = i
	var sim: SimCore = SimCore.attach(world)
	sim.core.set_parallel_min(2)
	sim.core.set_flight_parallel_min(2)
	var hits: PackedInt64Array = PackedInt64Array()
	var tick_hits: Array = []
	resolver.hit_resolved.connect(func(info: HitInfo) -> void:
		tick_hits.append([_index_of.get(info.target_id, -2), _index_of.get(info.shooter_id, -2), info.damage, info.applied,
				info.point]))
	var deaths: Array = []
	for c: Combatant in ships:
		c.damageable.destroyed.connect(func(_info: HitInfo) -> void: deaths.append(c.display_name))
	var rows := PackedInt64Array()
	var bolt_digests := PackedInt64Array()
	var nodes_max: int = 0
	var owned_max: int = 0
	var shots: int = 0
	for t: int in ticks:
		tick_hits.clear()
		await get_tree().physics_frame
		var hulls: Array = sim.core.hull_columns()
		rows.append(hash([hulls[3], hulls[4], hulls[6]]))
		var columns: Array = sim.core.bolt_columns()
		var shooters: PackedInt64Array = columns[6]
		var by_place := PackedInt64Array()
		for id: int in shooters:
			by_place.append(_index_of.get(id, -2))
		bolt_digests.append(hash([columns[1], columns[2], by_place]))
		if t == _dump_tick:
			var lines := PackedStringArray()
			var ends: PackedVector3Array = columns[2]
			var starts: PackedVector3Array = columns[1]
			for i: int in ends.size():
				lines.append("%d: ship %d at %s from %s" % [i, by_place[i], ends[i], starts[i]])
			_dumps.append("\n".join(lines))
		hits.append(hash(tick_hits))
		nodes_max = maxi(nodes_max, get_tree().get_nodes_in_group(Projectile.GROUP).size())
		owned_max = maxi(owned_max, int(sim.core.owned_bolts()))
	shots = resolver.hits_total
	var out: Dictionary = {"rows": rows, "bolts": bolt_digests, "hits": hits, "kills": deaths.size(), "hits_total": shots,
			"nodes_max": nodes_max, "owned_max": owned_max, "bolt_path": sim.bolt_rows_path()}
	space.queue_free()
	await get_tree().physics_frame
	return out


static func _first_difference(a: PackedInt64Array, b: PackedInt64Array) -> int:
	for i: int in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return i
	return -1 if a.size() == b.size() else mini(a.size(), b.size())


func test_the_seeded_battle_hits_the_same_with_bolts_as_rows() -> void:
	if _skipped():
		return
	var nodes: Dictionary = await _battle(false, 1)
	var rows: Dictionary = await _battle(true, 1)
	assert_eq(nodes["bolt_path"], &"nodes", "the reference flies bolt nodes")
	assert_eq(rows["bolt_path"], &"rows", "the rows path owns its bolts")
	assert_gt(int(nodes["nodes_max"]), 50, "the reference had bolts in flight (%d at most)" % int(nodes["nodes_max"]))
	assert_eq(int(rows["nodes_max"]), 0, "the rows path spawned no bolt node")
	assert_gt(int(rows["owned_max"]), 50, "and owned the bolts (%d at most)" % int(rows["owned_max"]))
	assert_gt(int(nodes["hits_total"]), 10, "hits landed (%d)" % int(nodes["hits_total"]))
	assert_eq(int(rows["hits_total"]), int(nodes["hits_total"]), "the same hits")
	assert_eq(int(rows["kills"]), int(nodes["kills"]), "the same kills (%d)" % int(nodes["kills"]))
	var first: int = _first_difference(nodes["bolts"], rows["bolts"])
	if first >= 0 and _dump_tick < 0:
		_dump_tick = first
		_dumps.clear()
		await _battle(false, 1, first + 1)
		await _battle(true, 1, first + 1)
		gut.p("bolt tables at tick %d\n-- nodes --\n%s\n-- rows --\n%s" % [first, _dumps[0], _dumps[1]])
	assert_eq(first, -1, "the bolt table is the same bits every tick (first difference at tick %d)" % first)
	first = _first_difference(nodes["hits"], rows["hits"])
	assert_eq(first, -1, "every hit lands the same (first difference at tick %d)" % first)
	first = _first_difference(nodes["rows"], rows["rows"])
	assert_eq(first, -1, "the hull rows are the same bits every tick (first difference at tick %d)" % first)
	gut.p("battle %d seed %d, %d ticks: %d hits, %d kills, %d bolt nodes at most against %d owned rows" % [SHIPS, SEED, TICKS,
			int(nodes["hits_total"]), int(nodes["kills"]), int(nodes["nodes_max"]), int(rows["owned_max"])])


func test_one_thread_and_six_give_the_same_bolts() -> void:
	if _skipped():
		return
	var one: Dictionary = await _battle(true, 1)
	var six: Dictionary = await _battle(true, 6)
	var first: int = _first_difference(one["bolts"], six["bolts"])
	assert_eq(first, -1, "the bolt table is the same bits with one thread and six (first difference at tick %d)" % first)
	first = _first_difference(one["hits"], six["hits"])
	assert_eq(first, -1, "and the hits (first difference at tick %d)" % first)
	first = _first_difference(one["rows"], six["rows"])
	assert_eq(first, -1, "and the rows (first difference at tick %d)" % first)


# --- the cannon in play -----------------------------------------------------------------------------------------------


# A node bolt the way a cannon spawns one (the player's path on the rows setting).
func _node_bolt(bolts: Node3D, at: Vector3, v: Vector3, shooter: int, damage: float) -> Projectile:
	var p := PulseCannon.PROJECTILE_SCENE.instantiate() as Projectile
	bolts.add_child(p)
	p.configure(_weapon())
	p.shooter_id = shooter
	p.faction = Factions.RAIDERS
	p.damage = damage
	p.launch(at, v, SimClock.now())
	return p


# A hull with a node bolt and an owned row reaching it in the same tick, two ticks apart in launch, the row first when
# `row_first`. Returns the id of the shooter whose bolt landed first (the kill).
func _same_tick_tie(row_first: bool) -> Dictionary:
	Settings.set_value(&"perf_native_bolt_rows", true)
	var space := _space()
	var world := space.get_node("World") as WorldFrame
	var bolts := world.get_node("Projectiles") as Node3D
	var resolver := HitResolver.new()
	resolver.name = "HitResolver"
	space.add_child(resolver)
	var target: Combatant = ShipAssembly.build(load(SPEC_PATH) as ShipSpec, world, bolts, {
		ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE, ShipAssembly.OPT_DISPLAY_NAME: "TARGET", ShipAssembly.OPT_LEAN: true})
	world.spawn(target.ship, world.to_universe(Vector3.ZERO))
	var shooters: Array[Combatant] = []
	for i: int in 2:
		var c: Combatant = ShipAssembly.build(load(SPEC_PATH) as ShipSpec, world, bolts, {
			ShipAssembly.OPT_FACTION: Factions.RAIDERS, ShipAssembly.OPT_DISPLAY_NAME: "SHOOTER %d" % i, ShipAssembly.OPT_LEAN: true})
		world.spawn(c.ship, world.to_universe(Vector3(0.0, 0.0, 5000.0 + 200.0 * float(i))))
		shooters.append(c)
	var sim: SimCore = SimCore.attach(world)
	var killer: Array[int] = [0]
	target.damageable.destroyed.connect(func(info: HitInfo) -> void: killer[0] = info.shooter_id)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var v := Vector3(0.0, 0.0, 600.0)  # 10 m a tick toward the hull from -Z
	var damage: float = target.damageable.hull.max_hp * 10.0
	var node_shooter: int = shooters[0].ship.get_instance_id()
	var row_shooter: int = shooters[1].ship.get_instance_id()
	var first_at := Vector3(0.0, 0.0, -200.0)
	var node_bolt: Projectile = null
	if row_first:
		sim.core.add_bolt(first_at, v, Factions.RAIDERS, row_shooter, null, 0.25, damage, Color.WHITE, 0, 4.0, SimClock.now())
	else:
		node_bolt = _node_bolt(bolts, first_at, v, node_shooter, damage)
	await get_tree().physics_frame
	await get_tree().physics_frame
	# The second leaves two ticks later from where the first is now, so both reach the hull in the same tick.
	var columns: Array = sim.core.bolt_columns()
	var ends: PackedVector3Array = columns[2]
	var second_at: Vector3 = node_bolt.global_position if node_bolt != null else ends[0]
	if row_first:
		_node_bolt(bolts, second_at, v, node_shooter, damage)
	else:
		sim.core.add_bolt(second_at, v, Factions.RAIDERS, row_shooter, null, 0.25, damage, Color.WHITE, 0, 4.0, SimClock.now())
	var ticks: int = 0
	while killer[0] == 0 and ticks < 60:
		await get_tree().physics_frame
		ticks += 1
	var out: Dictionary = {"killer": killer[0], "node": node_shooter, "row": row_shooter, "hits": resolver.hits_total,
			"path": sim.bolt_rows_path()}
	space.queue_free()
	await get_tree().physics_frame
	return out


func test_the_bolt_launched_first_lands_first_whether_a_node_or_a_row() -> void:
	# Fix round 1 (review minor 6): the resolver sweeps the bolts in launch order, not owned rows first.
	if _skipped():
		return
	var node_first: Dictionary = await _same_tick_tie(false)
	assert_eq(node_first["path"], &"rows")
	assert_eq(node_first["hits"], 1, "one hit kills; the second bolt finds the hull gone (%s)" % node_first)
	assert_eq(node_first["killer"], node_first["node"], "the node bolt launched first takes the kill (%s)" % node_first)
	var row_first: Dictionary = await _same_tick_tie(true)
	assert_eq(row_first["hits"], 1, "one hit kills (%s)" % row_first)
	assert_eq(row_first["killer"], row_first["row"], "the row launched first takes the kill (%s)" % row_first)


func test_a_cannon_on_the_kernel_fires_rows_and_signals_each_shot() -> void:
	if _skipped():
		return
	Settings.set_value(&"perf_native_bolt_rows", true)
	Settings.set_value(&"perf_native_commands", false)
	var space := _space()
	var world := space.get_node("World") as WorldFrame
	var bolts := world.get_node("Projectiles") as Node3D
	var c: Combatant = ShipAssembly.build(load(SPEC_PATH) as ShipSpec, world, bolts, {
		ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE, ShipAssembly.OPT_DISPLAY_NAME: "GUNNER", ShipAssembly.OPT_LEAN: true})
	world.spawn(c.ship, world.to_universe(Vector3.ZERO))
	var sim: SimCore = SimCore.attach(world)
	await get_tree().physics_frame
	var shots: Array = []
	c.cannon.shot_fired.connect(func(muzzle_index: int, at: Vector3) -> void: shots.append([muzzle_index, at]))
	var cmd := CombatCommand.new()
	cmd.fire = true
	for i: int in 40:
		c.cannon.set_combat_command(cmd)
		await get_tree().physics_frame
	assert_eq(sim.bolt_rows_path(), &"rows", "the cannon fires through the kernel")
	assert_true(c.cannon.on_kernel(), "the cannon is registered with the kernel")
	assert_gt(shots.size(), 1, "shots were signalled (%d)" % shots.size())
	assert_gt(int(sim.core.owned_bolts()), 1, "the bolts are owned rows")
	assert_eq(get_tree().get_nodes_in_group(Projectile.GROUP).size(), 0, "no bolt node was spawned")
	var muzzles: Array[Transform3D] = c.ship.get_muzzle_transforms()  # a lean ship's muzzles are data (finding 12)
	var first: Array = shots[0]
	var at: Vector3 = first[1]
	var near: bool = false
	for muzzle: Transform3D in muzzles:
		near = near or at.distance_to(c.ship.global_transform * muzzle.origin) < c.ship.linear_velocity.length() * DELTA * 2.0 + 1.0
	assert_true(near, "a shot is signalled at a muzzle")
	assert_false(c.cannon.is_physics_processing(), "the cannon's own tick is off on the kernel")
	Settings.set_value(&"perf_native_bolt_rows", false)
	assert_true(c.cannon.is_physics_processing(), "and back on when the rows are switched off")
	assert_false(c.cannon.on_kernel(), "off the kernel")
	space.queue_free()
	await get_tree().physics_frame


func test_a_cannon_on_a_body_the_core_has_no_row_for_still_fires() -> void:
	if _skipped():
		return
	Settings.set_value(&"perf_native_bolt_rows", true)
	var space := _space()
	var world := space.get_node("World") as WorldFrame
	var bolts := world.get_node("Projectiles") as Node3D
	var body := RigidBody3D.new()
	body.gravity_scale = 0.0
	world.add_child(body)
	var muzzle := Marker3D.new()
	muzzle.position = Vector3(0.0, 0.0, -2.0)
	body.add_child(muzzle)
	var cannon := PulseCannon.new()
	body.add_child(cannon)
	var typed: Array[Node3D] = [muzzle]
	cannon.setup(body, typed, bolts)
	var sim: SimCore = SimCore.attach(world)
	assert_not_null(sim, "a core under the world")
	var cmd := CombatCommand.new()
	cmd.fire = true
	var shots: Array = []
	cannon.shot_fired.connect(func(_i: int, at: Vector3) -> void: shots.append(at))
	for i: int in 30:
		cannon.set_combat_command(cmd)
		await get_tree().physics_frame
	assert_true(cannon.on_kernel(), "the cannon is on the kernel")
	assert_gt(shots.size(), 0, "a body with no row (no marker, no hull) still fires, from the node's pose (%d shots)" % shots.size())
	assert_gt(int(sim.core.owned_bolts()), 0, "its bolts are rows")
	space.queue_free()
	await get_tree().physics_frame
