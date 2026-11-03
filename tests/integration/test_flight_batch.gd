extends GutTest
## Ships flying in the native flight batch, headless in Jolt (M4-T10, N4; architecture §17.9): every ship but the
## player's takes the batch's path when the library is loaded and `perf_native` is on; a batched ship and its GDScript twin
## fly the same; the damping guard holds for batched ships; an empty tank makes a batched ship coast; a live flip of
## `perf_native` switches the path and carries the assist's state over; a parked ship leaves the step; and the `flight`
## console provider reports the batch. Skips, saying why, when the native library is not built.

const SPEC_PATH: String = "res://assets/ships/starfury_aurora.tres"
const GEN_ASSETS_HINT: String = "run scripts/gen_assets.sh, then scripts/run_tests.sh (it imports first)"

var world: WorldFrame
var spec: ShipSpec
var _native_backup: bool
var _fuel_backup: bool


func before_each() -> void:
	_native_backup = bool(Settings.get_value(&"perf_native"))
	_fuel_backup = bool(Settings.get_value(&"fuel_unlimited"))
	Settings.set_value(&"perf_native", true)
	Settings.set_value(&"fuel_unlimited", true)
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	spec = load(SPEC_PATH) as ShipSpec


func after_each() -> void:
	Settings.set_value(&"perf_native", _native_backup)
	Settings.set_value(&"fuel_unlimited", _fuel_backup)


func _skipped() -> bool:
	if NativeLib.has_class(NativeProbe.NATIVE_CLASS):
		return false
	pending("the native library is not built (scripts/build_native.sh), so there is no native path to compare")
	return true


func _spawn(at: Vector3, player: bool = false, ghost: bool = false) -> Ship:
	var ship: Ship = Ship.create(spec, world)
	ship.console_owner = player
	if ghost:
		# Twins fly through each other at one position: Jolt rounds the torque of a force at a point against the body's
		# world position, so two bodies at different positions can never match bit for bit.
		ship.collision_layer = 0
		ship.collision_mask = 0
	world.spawn(ship, world.to_universe(at))
	assert_true(ship.get_layout().valid, "ship has a valid thruster layout (%s)" % GEN_ASSETS_HINT)
	return ship


func _align() -> void:
	await get_tree().physics_frame


func _step(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _ticks(seconds: float) -> int:
	return roundi(seconds * float(Engine.physics_ticks_per_second))


static func _cmd(main_left: float = 0.0, main_right: float = 0.0, retro_left: float = 0.0, retro_right: float = 0.0,
		rot: Vector3 = Vector3.ZERO, brake: bool = false) -> FlightCommand:
	var cmd := FlightCommand.new()
	cmd.main_left = main_left
	cmd.main_right = main_right
	cmd.retro_left = retro_left
	cmd.retro_right = retro_right
	cmd.rot = rot
	cmd.brake = brake
	return cmd


# A seeded command that changes every tick: triggers, bumpers, sticks and now and then the brake.
static func _random_cmd(rng: RandomNumberGenerator) -> FlightCommand:
	var cmd := _cmd(rng.randf(), rng.randf(), 1.0 if rng.randf() < 0.2 else 0.0, 1.0 if rng.randf() < 0.2 else 0.0,
			Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)), rng.randf() < 0.1)
	cmd.strafe = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
	return cmd


func test_every_ship_but_the_players_flies_in_the_batch() -> void:
	if _skipped():
		return
	var ai: Ship = _spawn(Vector3.ZERO)
	var player: Ship = _spawn(Vector3(0.0, 300.0, 0.0), true)
	var batch: FlightBatch = FlightBatch.attach(world)
	assert_not_null(batch, "the batch lives under World")
	await _align()
	await _step(2)
	assert_eq(ai.flight_path(), &"native", "an AI ship flies in the batch")
	assert_eq(player.flight_path(), &"gdscript", "the player's ship keeps the GDScript path")
	assert_true(ai.batched)
	assert_false(player.batched)
	assert_eq(batch.rows.size(), 1, "one row stepped")
	assert_eq(batch.path(), &"native")


func test_a_batched_ship_and_its_gdscript_twin_fly_the_same() -> void:
	if _skipped():
		return
	var batched: Ship = _spawn(Vector3.ZERO, false, true)
	var twin: Ship = _spawn(Vector3.ZERO, false, true)
	twin.batched = false
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	await _align()
	for i: int in _ticks(3.0):
		var cmd: FlightCommand = _random_cmd(rng)
		batched.set_flight_command(cmd)
		var same := FlightCommand.new()
		same.main_left = cmd.main_left
		same.main_right = cmd.main_right
		same.retro_left = cmd.retro_left
		same.retro_right = cmd.retro_right
		same.rot = cmd.rot
		same.strafe = cmd.strafe
		same.brake = cmd.brake
		twin.set_flight_command(same)
		await _step(1)
		if i == 0:
			assert_eq(batched.flight_path(), &"native")
			assert_eq(twin.flight_path(), &"gdscript")
	assert_eq(batched.flight_path(), &"native")
	assert_eq(twin.flight_path(), &"gdscript")
	assert_gt(batched.linear_velocity.length(), 1.0, "the ships flew")
	assert_eq(batched.linear_velocity, twin.linear_velocity, "the same velocity, bit for bit")
	assert_eq(batched.angular_velocity, twin.angular_velocity, "the same spin, bit for bit")
	assert_eq(batched.position, twin.position, "the same track")
	assert_eq(batched.applied_force(), twin.applied_force(), "the same applied force in the last tick")
	assert_eq(batched.get_flight_output().main_levels, twin.get_flight_output().main_levels, "the same levels for the glow")
	assert_eq(batched.get_flight_output().pod_yaw_cmd, twin.get_flight_output().pod_yaw_cmd, "the same pod-yaw command")


func test_damping_guard_a_batched_ship_coasts_and_spins_on() -> void:
	if _skipped():
		return
	var ship: Ship = _spawn(Vector3.ZERO)
	ship.set_assist(false)
	ship.linear_velocity = Vector3(10.0, 0.0, 0.0)
	ship.angular_velocity = Vector3(0.0, 1.0, 0.0)
	await _align()
	await _step(_ticks(2.0))
	assert_eq(ship.flight_path(), &"native")
	assert_almost_eq(ship.linear_velocity.length(), 10.0, 1e-4, "no linear damping on the batched path")
	assert_almost_eq(ship.angular_velocity.length(), 1.0, 1e-5, "no angular damping with assist off")


func test_a_batched_ship_out_of_reaction_mass_coasts() -> void:
	if _skipped():
		return
	Settings.set_value(&"fuel_unlimited", false)
	var ship: Ship = _spawn(Vector3.ZERO)
	ship.get_fuel_tank().set_kg(spec.fuel_capacity_kg * 0.0005)  # a fraction of a second of full thrust
	ship.set_flight_command(_cmd(1.0, 1.0))
	await _align()
	await _step(_ticks(1.0))
	assert_eq(ship.flight_path(), &"native")
	assert_true(ship.get_fuel_tank().is_empty(), "the tank ran dry")
	assert_true(ship.get_flight_output().propellant_empty, "the output says so")
	var speed: float = ship.linear_velocity.length()
	assert_gt(speed, 0.5, "it got some way before the tank emptied")
	await _step(_ticks(1.0))
	assert_almost_eq(ship.linear_velocity.length(), speed, 1e-4, "and coasts from then on")


func test_a_live_perf_native_flip_switches_the_path_and_keeps_the_assist_state() -> void:
	if _skipped():
		return
	var ship: Ship = _spawn(Vector3.ZERO)
	ship.set_flight_command(_cmd(0.0, 1.0))  # one-sided: the pod-yaw command builds up
	await _align()
	await _step(_ticks(0.1))
	assert_eq(ship.flight_path(), &"native")
	var batch: FlightBatch = FlightBatch.attach(world)
	var native_state: float = batch.assist_state(ship)
	assert_gt(absf(native_state), 0.01, "the smoothed pod-yaw command is under way")
	Settings.set_value(&"perf_native", false)
	await _step(1)
	assert_eq(ship.flight_path(), &"gdscript", "off: the ship's own model flies it")
	assert_eq(batch.rows.size(), 0, "nothing stepped")
	var carried: float = ship.get_flight_output().pod_yaw_cmd / spec.pod_yaw_gain
	assert_true(absf(carried - native_state) < 0.1, "the GDScript assist took the state over (%s vs %s)" % [carried, native_state])
	await _step(_ticks(0.3))
	Settings.set_value(&"perf_native", true)
	await _step(1)
	assert_eq(ship.flight_path(), &"native", "on again: back in the batch")
	assert_true(absf(batch.assist_state(ship) - ship.get_flight_output().pod_yaw_cmd / spec.pod_yaw_gain) < 1e-9,
			"and the native state is the one the GDScript model had")


func test_a_parked_ship_leaves_the_step_and_a_woken_one_returns() -> void:
	if _skipped():
		return
	var ship: Ship = _spawn(Vector3.ZERO)
	var other: Ship = _spawn(Vector3(0.0, 500.0, 0.0))
	var batch: FlightBatch = FlightBatch.attach(world)
	await _align()
	await _step(1)
	assert_eq(batch.rows.size(), 2)
	ship.process_mode = Node.PROCESS_MODE_DISABLED
	await _step(1)
	assert_eq(batch.rows.size(), 1, "the parked ship is not stepped")
	assert_true(batch.rows.has(other))
	ship.process_mode = Node.PROCESS_MODE_INHERIT
	await _step(1)
	assert_eq(batch.rows.size(), 2, "back in play, back in the step")
	ship.queue_free()
	await _step(2)
	assert_eq(batch.rows.size(), 1, "a freed ship is gone")


func test_the_flight_provider_reports_the_batch() -> void:
	if _skipped():
		return
	_spawn(Vector3.ZERO)
	FlightBatch.attach(world)
	await _align()
	await _step(1)
	assert_true(DebugConsole.registry.has_provider(&"flight"), "the batch registers the flight provider")
	var read: Dictionary = DebugConsole.registry.read("flight.path")
	assert_eq(str(read.get("value", "")), "native")
	assert_eq(DebugConsole.registry.read("flight.stepped").get("value"), 1)
