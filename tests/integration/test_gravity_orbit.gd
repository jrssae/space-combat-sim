extends GutTest
## Gravity over long runs (M6-T07, D64's AC4 budget, D66): a ship coasting along the track beside the station's stand-in on
## a low fixture orbit stays within 0.5 m (at up to 3 km) of a 64-bit run of the same start: parked as a tier row over one
## whole orbit, and flown in Jolt by the flight batch (the whole orbit with the slow files on); and a bolt fired near the planet curves as the
## analytic path says.

const FreeFall: GDScript = preload("res://tests/integration/test_free_fall.gd")
const SPEC_PATH: String = "res://assets/ships/starfury_aurora.tres"
const DT: float = 1.0 / 60.0
## D64's AC4 budget at up to 3 km.
const BUDGET_M: float = 0.5
const CHECK_EVERY: int = 500
## The Jolt run's length in a focused run: a tenth of the orbit. With the slow files on (`GUT_SLOW=1`: the standard tier and
## CI) it flies the whole orbit, about a minute at Jolt's pace here (6 000 ticks a second).
const JOLT_TICKS: int = 30000
## How much faster than the clock the Jolt run's ticks go, each still 1/60 s of sim time, and the most ticks one frame takes
## (more overflow Jolt's job queue).
const JOLT_SPEED_UP: float = 100.0
const JOLT_STEPS_PER_FRAME: int = 32

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


# The station's orbit: radius, speed and mean motion.
static func _orbit() -> Array[float]:
	var r: float = FreeFall.RADIUS_TERRA_M + FreeFall.ALTITUDE_M
	return [r, sqrt(FreeFall.GM_TERRA / r), sqrt(FreeFall.GM_TERRA / (r * r * r))]


# A point `ahead_m` along the station's own orbit, against the station: position then velocity in the local frame, from
# the station's state (`radial` out from the planet, `along` its motion). The frame does not turn, so it moves.
static func _along_track(ahead_m: float, radial: Vector3, along: Vector3) -> Array[Vector3]:
	var o: Array[float] = _orbit()
	var theta: float = ahead_m / o[0]
	var c: float = cos(theta)
	var s: float = sin(theta)
	return [radial * (o[0] * (c - 1.0)) + along * (o[0] * s), along * (o[1] * (c - 1.0)) - radial * (o[1] * s)]


# --- one orbit, parked in the tier (the core stepped by hand) ----------------------------------------------------------


func test_a_parked_ship_stays_beside_the_station_over_one_orbit() -> void:
	world.process_mode = Node.PROCESS_MODE_DISABLED  # the loop below is the frame's only tick
	assert_true(world.anchor_on_rail(system, &"post"))
	var sim: SimCore = SimCore.for_tree(get_tree())
	var core: Object = sim.core
	var spec: ShipSpec = load(SPEC_PATH) as ShipSpec
	var layout: ThrusterLayout = ThrusterLayout.load_file("res://tests/fixtures/hardpoints_nominal.json")
	var a: Array = FlightBatch.type_arrays(spec, layout)
	var type_ix: int = int(core.tier_register_type(a[0], a[1], a[2], a[3], a[4], a[5], layout.center_of_mass))
	# At sim time 0 the station is out along +X, moving along -Z (the fixture's rail).
	var separations: Array[float] = [1000.0, 3000.0]
	var refs: Array = []
	for k: int in separations.size():
		var start: Array[Vector3] = _along_track(separations[k], Vector3.RIGHT, Vector3.FORWARD)
		var id: int = 900 + k
		core.tier_add(SimCore.KIND_SHIP, id, 0, type_ix, start[0], start[1], Basis.IDENTITY, Vector3.ZERO)
		core.tier_set_control(id, Vector3.ZERO, PackedFloat64Array(), 0.0, false)
		refs.append([[start[0].x, start[0].y, start[0].z], [start[1].x, start[1].y, start[1].z]])
	var o: Array[float] = _orbit()
	var ticks: int = ceili(TAU / o[2] / DT)
	var worst: Array[float] = [0.0, 0.0]
	var gap: Array[float] = [0.0, 0.0]
	for tick: int in ticks:
		core.frame_sample(float(tick) * DT)
		# The 64-bit run of the same start: kick with the frame's residual at its own place, then drift.
		for k: int in refs.size():
			var p: Array = refs[k][0]
			var v: Array = refs[k][1]
			var g: Vector3 = core.frame_residual(Vector3(p[0], p[1], p[2]))
			for i: int in 3:
				v[i] += g[i] * DT
				p[i] += v[i] * DT
		core.sync_in(1000 + tick, DT)
		if (tick + 1) % CHECK_EVERY == 0 or tick + 1 == ticks:
			for k: int in refs.size():
				var row: Vector3 = core.tier_state(900 + k)["position"]
				var p: Array = refs[k][0]
				worst[k] = maxf(worst[k], row.distance_to(Vector3(p[0], p[1], p[2])))
				gap[k] = Vector3(p[0], p[1], p[2]).length()
	for k: int in separations.size():
		assert_lt(worst[k], BUDGET_M, "%.0f m along the track: worst %.4f m off the 64-bit run over %d ticks" % [
				separations[k], worst[k], ticks])
		assert_almost_eq(gap[k], separations[k], separations[k] * 0.01, "and still beside the station (%.1f m)" % gap[k])
	gut.p("tier, one orbit (%d ticks): worst %.4f m at 1 km, %.4f m at 3 km" % [ticks, worst[0], worst[1]])


# --- the same start flown in Jolt by the flight batch, the real tick sped up -----------------------------------------


## Steps the 64-bit reference once a tick, after the frame's sample and before the flight step reads the ship.
class Reference extends Node:
	var world: WorldFrame = null
	var p: Array[float] = []
	var v: Array[float] = []
	var ticks: int = 0

	func _init() -> void:
		process_physics_priority = WorldFrame.SAMPLE_PRIORITY + 1

	func _physics_process(delta: float) -> void:
		var g: Vector3 = world.gravity_residual(Vector3(p[0], p[1], p[2]))
		for i: int in 3:
			v[i] += g[i] * delta
			p[i] += v[i] * delta
		ticks += 1

	func position() -> Vector3:
		return Vector3(p[0], p[1], p[2])


func test_a_ship_in_jolt_coasts_beside_the_station_as_the_64_bit_run_does() -> void:
	assert_true(world.anchor_on_rail(system, &"post"))
	FlightBatch.attach(world)
	var state: PackedFloat64Array = world.anchor_state()
	var radial := Vector3(state[0], state[1], state[2]).normalized()
	var along := Vector3(state[3], state[4], state[5]).normalized()
	var start: Array[Vector3] = _along_track(3000.0, radial, along)
	var ship: Ship = Ship.create(load(SPEC_PATH) as ShipSpec, world)
	world.spawn(ship, world.to_universe(start[0]))
	ship.assist_on = false
	ship.set_flight_command(FlightCommand.new())
	ship.linear_velocity = start[1]
	var ref := Reference.new()
	ref.world = world
	ref.p = [start[0].x, start[0].y, start[0].z]
	ref.v = [start[1].x, start[1].y, start[1].z]
	world.add_child(ref)
	var ticks: int = ceili(TAU / _orbit()[2] / DT) if SlowTests.enabled() else JOLT_TICKS
	Engine.max_physics_steps_per_frame = JOLT_STEPS_PER_FRAME
	Engine.physics_ticks_per_second = roundi(60.0 * JOLT_SPEED_UP)
	Engine.time_scale = JOLT_SPEED_UP
	var wall_start: int = Time.get_ticks_msec()
	var worst: float = 0.0
	while ref.ticks < ticks:
		await get_tree().physics_frame
		worst = maxf(worst, ship.global_position.distance_to(ref.position()))
	var wall_ms: int = Time.get_ticks_msec() - wall_start
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	assert_eq(ship.flight_path(), &"native")
	assert_lt(worst, BUDGET_M, "worst %.4f m off the 64-bit run over %d ticks" % [worst, ref.ticks])
	gut.p("jolt: %d ticks in %d ms, worst %.4f m" % [ref.ticks, wall_ms, worst])


# --- a bolt near the planet ----------------------------------------------------------------------------------------------


func test_a_bolt_fired_near_the_planet_curves_as_the_analytic_path_says() -> void:
	var core: Object = NativeLib.instantiate(SimCore.NATIVE_CLASS)
	core.frame_set_system(system.ephemeris(), system.a_min)
	assert_true(core.frame_anchor_on_rail(system.index_of(&"post")))
	core.frame_set_origin(20000.0, 0.0, 0.0)  # the local space 20 km out from the station, where the tide is strong
	core.frame_sample(0.0)
	core.sync_in(100, DT)
	var v0 := Vector3(0.0, 300.0, -900.0)
	core.add_bolt(Vector3.ZERO, v0, Factions.RAIDERS, 7, null, 0.25, 10.0, Color.WHITE, 0, 4.0, 0.0)
	# The analytic path from the launch: x0 + v0 t + a0 t^2 / 2 + j t^3 / 6, the pull and its rate along the flight from the
	# frame's own residual (the tide is linear across a few km, so the difference is exact); t (t + dt) for the kick-then-drift
	# step's half tick.
	var a0: Vector3 = core.frame_residual(Vector3.ZERO)
	var jerk: Vector3 = (core.frame_residual(v0) - core.frame_residual(-v0)) / 2.0
	var p_ref: Array[float] = [0.0, 0.0, 0.0]
	var v_ref: Array[float] = [v0.x, v0.y, v0.z]
	var moves: int = 0
	for tick: int in range(1, 240):
		core.frame_sample(float(tick) * DT)
		core.sync_in(100 + tick, DT)
		core.step_bolts(float(tick) * DT, DT)
		var g: Vector3 = core.frame_residual(Vector3(p_ref[0], p_ref[1], p_ref[2]))
		for i: int in 3:
			v_ref[i] += g[i] * DT
			p_ref[i] += v_ref[i] * DT
		moves += 1
	var t: float = float(moves) * DT
	var analytic: Vector3 = v0 * t + a0 * (0.5 * t * (t + DT)) + jerk * (t * t * t / 6.0)
	var bolt: Vector3 = (core.bolt_positions() as PackedVector3Array)[0]
	var bend: float = analytic.distance_to(v0 * t)
	assert_gt(bend, 0.3, "the pull bends the bolt off its line (%.3f m in %.1f s)" % [bend, t])
	var integrated := Vector3(p_ref[0], p_ref[1], p_ref[2])
	assert_lt(integrated.distance_to(analytic), 0.005, "the analytic path and a 64-bit run agree (%.4f m)" % integrated.distance_to(analytic))
	assert_lt(bolt.distance_to(analytic), 0.02, "the bolt flies the analytic path, within its 32 bits (%.4f m off, %.3f m bend)" % [
			bolt.distance_to(analytic), bend])
	gut.p("bolt: %.3f m bend over %.2f s, %.4f m off the analytic path" % [bend, t, bolt.distance_to(analytic)])
