extends GutTest
## The free-falling frame (M6-T04, D64): the World's anchor falls on its orbit in 64-bit, sampled first in the tick and
## stepped last; a ship at rest in the frame feels only the residual, on the batch's path and on its own model alike; with no
## star system, or on the station's rail far outside Epsilon III's zone, nothing pulls. AC1's whole low orbit runs through the
## core's binding (under a second), and in the Rust tests (`native/src/frame/tests.rs`).

const SPEC_PATH: String = "res://assets/ships/starfury_aurora.tres"
const GM_TERRA: float = 3.986e14
const RADIUS_TERRA_M: float = 6.371e6
const ALTITUDE_M: float = 4.0e5
## D64's budget for an empty frame against the analytic orbit.
const BUDGET_M: float = 0.05
const CHECK_EVERY: int = 500

var world: WorldFrame
var system: StarSystem
var _fuel_backup: bool


## A star far off, an Earth-sized planet, and a place on a 400 km circular orbit round it: D64's test orbit.
static func fixture_system() -> StarSystem:
	var made := StarSystem.new()
	made.build(&"fixture", {
		"name": "Fixture", "a_min": 0.5,
		"bodies": [
			{"id": "sun", "kind": "star", "gm": 1.327e20, "radius_m": 6.96e8},
			{"id": "terra", "kind": "planet", "parent": "sun", "gm": GM_TERRA, "radius_m": RADIUS_TERRA_M,
				"atmosphere_top_m": 1.0e5,
				"orbit": {"a_m": 1.496e11, "e": 0.0, "i_deg": 0.0, "node_deg": 0.0, "peri_deg": 0.0, "m0_deg": 0.0, "epoch_s": 0.0}},
		],
		"places": [
			{"id": "post", "parent": "terra",
				"orbit": {"a_m": RADIUS_TERRA_M + ALTITUDE_M, "e": 0.0, "i_deg": 0.0, "node_deg": 0.0, "peri_deg": 0.0,
					"m0_deg": 0.0, "epoch_s": 0.0}},
		],
	})
	return made


## The circular orbit's state at `radius_m` now, in the game's axes: out along +X, moving along -Z.
static func circular_state(radius_m: float, gm: float) -> PackedFloat64Array:
	return PackedFloat64Array([radius_m, 0.0, 0.0, 0.0, 0.0, -sqrt(gm / radius_m)])


func before_each() -> void:
	_fuel_backup = bool(Settings.get_value(&"fuel_unlimited"))
	Settings.set_value(&"fuel_unlimited", true)
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	system = fixture_system()
	assert_true(system.is_valid(), "the fixture system loads: %s" % [system.errors])


func after_each() -> void:
	Settings.set_value(&"fuel_unlimited", _fuel_backup)


func _ship(at: Vector3, player: bool) -> Ship:
	var ship: Ship = Ship.create(load(SPEC_PATH) as ShipSpec, world)
	ship.console_owner = player
	world.spawn(ship, world.to_universe(at))
	ship.assist_on = false
	ship.set_flight_command(FlightCommand.new())
	return ship


func _step(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func test_an_empty_frame_follows_its_orbit_over_a_short_arc() -> void:
	var radius: float = RADIUS_TERRA_M + ALTITUDE_M
	assert_true(world.anchor_in_orbit(system, &"terra", circular_state(radius, GM_TERRA)))
	assert_eq(world.anchor_text(), "orbit terra")
	var start_s: float = SimClock.now()
	await _step(120)
	# The anchor steps once at the end of every tick the clock advances in.
	var ticks: int = roundi((SimClock.now() - start_s) * float(Engine.physics_ticks_per_second))
	var angle: float = sqrt(GM_TERRA / (radius * radius * radius)) * float(ticks) / float(Engine.physics_ticks_per_second)
	var state: PackedFloat64Array = world.anchor_state()
	assert_eq(state.size(), 6)
	# In 64-bit floats, not a Vector3: 6 771 km in 32 bits steps in half metres.
	var dx: float = state[0] - radius * cos(angle)
	var dz: float = state[2] + radius * sin(angle)
	var off: float = sqrt(dx * dx + state[1] * state[1] + dz * dz)
	assert_lt(off, BUDGET_M, "within D64's budget after %d ticks (off by %s m)" % [ticks, off])
	assert_almost_eq(Vector3(state[3], state[4], state[5]).length(), sqrt(GM_TERRA / radius), 1e-3, "orbital speed held")


func test_an_empty_frame_keeps_one_low_orbit_within_the_budget() -> void:
	var radius: float = RADIUS_TERRA_M + ALTITUDE_M
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	world.process_mode = Node.PROCESS_MODE_DISABLED  # the loop below is the frame's only tick
	assert_true(world.anchor_in_orbit(system, &"terra", circular_state(radius, GM_TERRA)))
	var core: Object = SimCore.for_tree(get_tree()).core
	var rate: float = sqrt(GM_TERRA / (radius * radius * radius))
	var ticks: int = ceili(TAU / rate / dt)
	var t0: float = SimClock.now()
	var worst: float = 0.0
	for tick: int in ticks:
		core.frame_sample(t0 + float(tick) * dt)
		core.frame_step(dt)
		if (tick + 1) % CHECK_EVERY == 0 or tick + 1 == ticks:
			var state: PackedFloat64Array = world.anchor_state()
			var angle: float = rate * float(tick + 1) * dt
			var dx: float = state[0] - radius * cos(angle)
			var dz: float = state[2] + radius * sin(angle)
			worst = maxf(worst, sqrt(dx * dx + state[1] * state[1] + dz * dz))
	assert_lt(worst, BUDGET_M, "worst %s m over %d ticks" % [worst, ticks])


func test_a_ship_at_rest_in_the_frame_feels_only_the_residual() -> void:
	assert_true(world.anchor_on_rail(system, &"post"))
	assert_true(world.gravity_active(), "a low orbit lies inside the planet's zone")
	var batch: FlightBatch = FlightBatch.attach(world)
	# 1 km out from the planet (the rail starts on +X) and 1 km along the track, on the batch's path and on the ship's own.
	var outward: Ship = _ship(Vector3(1000.0, 0.0, 0.0), false)
	var along: Ship = _ship(Vector3(0.0, 0.0, -1000.0), false)
	var own_model: Ship = _ship(Vector3(1000.0, 200.0, 0.0), true)
	var at_anchor: Ship = _ship(Vector3.ZERO, false)
	await _step(3)
	assert_eq(outward.flight_path(), &"native")
	assert_eq(own_model.flight_path(), &"gdscript")
	var ticks: int = 60
	var expected_out: Vector3 = world.gravity_residual(outward.position) * float(ticks) / 60.0
	var expected_along: Vector3 = world.gravity_residual(along.position) * float(ticks) / 60.0
	var v_out: Vector3 = outward.linear_velocity
	var v_along: Vector3 = along.linear_velocity
	var v_own: Vector3 = own_model.linear_velocity
	await _step(ticks)
	var radius: float = RADIUS_TERRA_M + ALTITUDE_M
	var tidal: float = GM_TERRA / (radius * radius * radius) * 1000.0
	assert_almost_eq(expected_out.x, 2.0 * tidal, 0.01 * tidal, "outward the planet's pull weakens: twice the gradient")
	assert_almost_eq(expected_along.z, tidal, 0.01 * tidal, "along the track the pull leans back toward the anchor")
	assert_almost_eq(outward.linear_velocity - v_out, expected_out, Vector3.ONE * 0.02 * tidal, "batched ship: the residual alone")
	assert_almost_eq(along.linear_velocity - v_along, expected_along, Vector3.ONE * 0.02 * tidal, "along the track")
	assert_almost_eq(own_model.linear_velocity - v_own, world.gravity_residual(own_model.position) * float(ticks) / 60.0,
			Vector3.ONE * 0.02 * tidal, "the ship's own model feels the same residual")
	assert_eq(at_anchor.linear_velocity, Vector3.ZERO, "at the anchor itself the residual is exactly zero")
	assert_eq(batch.path(), &"native")


func test_with_no_star_system_nothing_pulls() -> void:
	FlightBatch.attach(world)
	var ship: Ship = _ship(Vector3(1000.0, 0.0, 0.0), false)
	await _step(30)
	assert_false(world.gravity_active())
	assert_eq(world.anchor_text(), "none")
	assert_eq(ship.linear_velocity, Vector3.ZERO, "bit for bit at rest, as in M5")
	assert_eq(world.environment_accel(Vector3(5000.0, 0.0, 0.0)), Vector3.ZERO)


func test_the_station_rail_lies_outside_every_zone_so_nothing_pulls() -> void:
	var local: StarSystem = StarSystem.load_system(StarSystemHost.DEFAULT_SYSTEM)
	assert_true(world.anchor_on_rail(local, StarSystemHost.DEFAULT_ANCHOR))
	await _step(2)
	assert_false(world.gravity_active(), "27 500 km is outside Epsilon III's 18 300 km zone (D66)")
	assert_eq(world.gravity_residual(Vector3(20000.0, 0.0, 0.0)), Vector3.ZERO)
	var state: PackedFloat64Array = world.anchor_state()
	assert_almost_eq(Vector3(state[0], state[1], state[2]).length(), 2.75e7, 1.0, "the anchor rides the station's rail")


func test_a_rebase_keeps_the_residual_at_a_universe_point() -> void:
	assert_true(world.anchor_on_rail(system, &"post"))
	var point := Vector3(3000.0, -400.0, 1500.0)
	var before: Vector3 = world.gravity_residual(point)
	world.rebase(Vector3(2000.0, 0.0, -1000.0))
	world.sample_gravity(SimClock.now())
	var after: Vector3 = world.gravity_residual(point - Vector3(2000.0, 0.0, -1000.0))
	assert_almost_eq(after, before, Vector3.ONE * 1e-9, "the same universe point, the same pull")
	assert_ne(before, Vector3.ZERO)


func test_the_frame_console_command_anchors_and_lets_go() -> void:
	var result: ConsoleResult = _run("frame orbit 400")
	assert_true(result.ok, result.error)
	assert_eq(world.anchor_text(), "orbit epsilon_iii")
	assert_true(world.gravity_active(), "400 km above Epsilon III is deep in its zone")
	assert_true(_run("frame rail babylon5").ok)
	assert_false(world.gravity_active())
	assert_false(_run("frame orbit -3").ok, "a negative altitude is refused")
	assert_true(_run("frame off").ok)
	assert_eq(world.anchor_text(), "none")
	var read: Dictionary = DebugConsole.registry.read("world.anchor")
	assert_eq(read["value"], "none")


func _run(line: String) -> ConsoleResult:
	var results: Array[ConsoleResult] = DebugConsole.registry.execute(line)
	return results[0]
