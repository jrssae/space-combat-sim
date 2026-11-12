extends GutTest
## Gravity on every kind of mover (M6-T07, D66), inside a body's zone only: the core's bolts take the frame's pull before they
## move; a debris chunk, a held wreck, an explosion and a projectile node fall with a pull read once a second (`HeldPull`),
## within a centimetre of a per-tick read over a chunk's life; the brake holds a ship on a point under the pull, on the
## batch's path and on its own model; and on the station's rail, outside Epsilon III's zone, nothing pulls and every mover
## keeps its bits. The tier's rows are in `test_tier.gd`, the long runs (one orbit, the curved bolt) in
## `test_gravity_orbit.gd`.

const FreeFall: GDScript = preload("res://tests/integration/test_free_fall.gd")
const SPEC_PATH: String = "res://assets/ships/starfury_aurora.tres"
const DT: float = 1.0 / 60.0
## Real ticks run this many times faster than the clock, each still 1/60 s of sim time.
const SPEED_UP: float = 20.0

var world: WorldFrame
var system: StarSystem
var _fuel_backup: bool
var _rate_backup: int
var _scale_backup: float
var _steps_backup: int


func before_each() -> void:
	_fuel_backup = bool(Settings.get_value(&"fuel_unlimited"))
	Settings.set_value(&"fuel_unlimited", true)
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	_steps_backup = Engine.max_physics_steps_per_frame
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	system = FreeFall.fixture_system()


func after_each() -> void:
	Settings.set_value(&"fuel_unlimited", _fuel_backup)
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup


# A bare core on the fixture's low orbit (`post`, 400 km up), or on the data's station rail, sampled at sim time 0.
func _bare_core(on_station: bool) -> Object:
	var core: Object = NativeLib.instantiate(SimCore.NATIVE_CLASS)
	var at: StarSystem = StarSystem.load_system(StarSystemHost.DEFAULT_SYSTEM) if on_station else system
	core.frame_set_system(at.ephemeris(), at.a_min)
	assert_true(core.frame_anchor_on_rail(at.index_of(StarSystemHost.DEFAULT_ANCHOR if on_station else &"post")))
	core.frame_sample(0.0)
	core.sync_in(100, DT)
	return core


func _bolt_velocity(core: Object) -> Vector3:
	return (core.bolt_columns()[12] as PackedVector3Array)[0]


func test_a_core_bolt_takes_the_pull_before_it_moves() -> void:
	var core: Object = _bare_core(false)
	var at := Vector3(3000.0, 0.0, -500.0)
	var v := Vector3(0.0, 0.0, -1200.0)
	core.add_bolt(at, v, Factions.RAIDERS, 7, null, 0.25, 10.0, Color.WHITE, 0, 4.0, 0.0)
	core.sync_in(101, DT)
	var pull: Vector3 = core.frame_residual(at)
	assert_gt(pull.length(), 5e-3, "the tide 3 km out")
	core.step_bolts(0.0, DT)
	var v1: Vector3 = v + pull * DT
	assert_eq(_bolt_velocity(core), v1, "the kick first, in the kernel's 32 bits")
	assert_eq((core.bolt_positions() as PackedVector3Array)[0], at + v1 * DT, "then the move with the new velocity")
	assert_eq(int(core.gravity_readouts()[2]), 1, "one bolt took the pull")


func test_on_the_stations_rail_a_bolt_keeps_its_bits() -> void:
	var core: Object = _bare_core(true)
	assert_false(core.frame_active(), "Babylon 5's orbit lies outside Epsilon III's zone: no gravity there (D66)")
	var at := Vector3(3000.0, 0.0, -500.0)
	var v := Vector3(0.0, 0.0, -1200.0)
	core.add_bolt(at, v, Factions.RAIDERS, 7, null, 0.25, 10.0, Color.WHITE, 0, 4.0, 0.0)
	core.sync_in(101, DT)
	core.step_bolts(0.0, DT)
	assert_eq(_bolt_velocity(core), v, "no pull: the velocity keeps every bit")
	assert_eq((core.bolt_positions() as PackedVector3Array)[0], at + v * DT)
	assert_eq(core.gravity_readouts(), PackedInt64Array([0, 0, 0, 0, 0]), "nothing read a pull")


# A chunk's life against the pull read every tick: the held pull's error, and its cost.
func test_a_debris_chunk_falls_within_a_centimetre_of_a_per_tick_pull() -> void:
	assert_true(world.anchor_on_rail(system, &"post"))
	world.process_mode = Node.PROCESS_MODE_DISABLED  # the loop below is the only tick
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var chunk: DebrisChunk = DebrisChunk.create_shard(rng)
	world.add_child(chunk)
	var at := Vector3(3000.0, 0.0, 0.0)  # 3 km out from the anchor: the tide pulls it farther out
	var v := Vector3(12.0, -4.0, 9.0)
	chunk.launch(Transform3D(Basis.IDENTITY, at), v, Vector3.ZERO)
	var ticks: int = roundi(DebrisChunk.LIFETIME_S / DT) - 1
	var p_ref: Array[float] = [at.x, at.y, at.z]
	var v_ref: Array[float] = [v.x, v.y, v.z]
	var held_us: int = 0
	var read_us: int = 0
	for i: int in ticks:
		var t0: int = Time.get_ticks_usec()
		var g: Vector3 = world.gravity_residual(Vector3(p_ref[0], p_ref[1], p_ref[2]))
		var t1: int = Time.get_ticks_usec()
		chunk.advance(DT)
		held_us += Time.get_ticks_usec() - t1
		read_us += t1 - t0
		for k: int in 3:
			v_ref[k] += g[k] * DT
			p_ref[k] += v_ref[k] * DT
	var straight: Vector3 = at + v * float(ticks) * DT
	var ref := Vector3(p_ref[0], p_ref[1], p_ref[2])
	assert_gt(ref.distance_to(straight), 0.2, "the pull bends the path (%.3f m)" % ref.distance_to(straight))
	var off: float = chunk.global_position.distance_to(ref)
	assert_lt(off, 0.01, "within a centimetre of a per-tick read after %.1f s (%.4f m)" % [float(ticks) * DT, off])
	gut.p("debris: held pull off by %.4f m over %d ticks; %d us for the chunk's ticks, %d us for one read a tick" % [
			off, ticks, held_us, read_us])


func test_a_held_wreck_an_explosion_and_a_projectile_node_fall_too() -> void:
	assert_true(world.anchor_on_rail(system, &"post"))
	world.process_mode = Node.PROCESS_MODE_DISABLED
	var at := Vector3(3000.0, 0.0, 0.0)
	var pull: Vector3 = world.gravity_residual(at)
	var offsets: Array[Vector3] = [Vector3.ZERO]
	var wreck := StagedWreck.new(BreakupPlan.make(1, 0, 1), offsets, offsets, Transform3D(Basis.IDENTITY, at), Vector3.ZERO,
			Vector3.ZERO)
	var blast: Explosion = Explosion.create(20.0, Vector3.ZERO)
	world.add_child(blast)
	blast.global_position = at
	var bolt := (load(Projectile.SCENE_PATH) as PackedScene).instantiate() as Projectile
	world.add_child(bolt)
	bolt.configure(WeaponSpec.new())
	bolt.launch(at, Vector3.ZERO, SimClock.now())
	for i: int in 60:
		wreck.advance(DT, world)
		blast._physics_process(DT)
		bolt._physics_process(DT)
	for moved: Array in [["wreck", wreck.velocity], ["explosion", blast.velocity], ["projectile", bolt.velocity]]:
		assert_almost_eq(moved[1] as Vector3, pull, Vector3.ONE * 1e-5, "%s: one second of the pull in one second" % moved[0])
	assert_gt(pull.x, 0.0, "outward, as the tide pulls 3 km out")


# A ship told to brake at a point under the pull, on the batch's path and on its own model.
func test_the_brake_holds_a_ship_on_a_point_under_the_pull() -> void:
	assert_true(world.anchor_on_rail(system, &"post"))
	FlightBatch.attach(world)
	var held: Array[Ship] = []
	var points: Array[Vector3] = [Vector3(3000.0, 0.0, 0.0), Vector3(3000.0, 300.0, -1500.0)]
	for k: int in points.size():
		var ship: Ship = Ship.create(load(SPEC_PATH) as ShipSpec, world)
		ship.console_owner = k == 1  # the second one on its own model
		world.spawn(ship, world.to_universe(points[k]))
		ship.assist_on = false
		var brake := FlightCommand.new()
		brake.brake = true
		ship.set_flight_command(brake)
		held.append(ship)
	var drifting: Ship = Ship.create(load(SPEC_PATH) as ShipSpec, world)
	world.spawn(drifting, world.to_universe(Vector3(3000.0, -300.0, 0.0)))
	drifting.assist_on = false
	drifting.set_flight_command(FlightCommand.new())
	Engine.max_physics_steps_per_frame = roundi(SPEED_UP)
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < 10.0:
		await get_tree().physics_frame
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	assert_eq(held[0].flight_path(), &"native")
	assert_eq(held[1].flight_path(), &"gdscript")
	var fell: float = drifting.global_position.distance_to(Vector3(3000.0, -300.0, 0.0))
	assert_gt(fell, 0.3, "with no brake the pull carries a ship off (%.2f m in 10 s)" % fell)
	for k: int in held.size():
		var off: float = held[k].global_position.distance_to(points[k])
		assert_lt(off, 0.05, "%s held its point within 5 cm (%.4f m)" % [held[k].flight_path(), off])
		assert_lt(held[k].linear_velocity.length(), 1e-3, "and at rest")
