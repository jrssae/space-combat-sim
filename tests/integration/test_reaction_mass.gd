extends GutTest
## The Ship's reaction-mass tank in Jolt, headless (architecture §5.1, M2-T14): with `settings.fuel_unlimited` on (the
## default) the tank is never drawn down; with it off the flow is drawn every tick, and an empty tank means the ship
## cannot thrust (and just coasts, the damping guard still holds). Also the `ship.fuel_kg` / `ship.fuel_fraction`
## console keys and the `refuel` command.
##
## Timing as in test_ship_physics.gd: `physics_frame` fires at the start of a tick, so a command set after `_align()` is
## used in that same tick and each further `await physics_frame` observes one more completed step. Expected numbers
## come from the ShipSpec, never literals.

const SPEC_PATH: String = "res://assets/ships/starfury_aurora.tres"
const GEN_ASSETS_HINT: String = "run scripts/gen_assets.sh, then scripts/run_tests.sh (it imports first)"

var world: WorldFrame
var spec: ShipSpec
var ship: Ship
var _unlimited_backup: Variant
var _assist_backup: Variant


func before_each() -> void:
	_unlimited_backup = Settings.get_value(&"fuel_unlimited")
	_assist_backup = Settings.get_value(&"assist_default")
	Settings.set_value(&"assist_default", true)
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	spec = load(SPEC_PATH) as ShipSpec
	ship = Ship.create(spec, world)
	world.spawn(ship, world.to_universe(Vector3.ZERO))
	assert_true(ship.get_layout().valid, "ship has a valid thruster layout (%s)" % GEN_ASSETS_HINT)


func after_each() -> void:
	Settings.set_value(&"fuel_unlimited", _unlimited_backup)
	Settings.set_value(&"assist_default", _assist_backup)


func _dt() -> float:
	return 1.0 / float(Engine.physics_ticks_per_second)


func _ticks(seconds: float) -> int:
	return roundi(seconds * float(Engine.physics_ticks_per_second))


func _step(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


## Both triggers at full (and nothing else): straight-line thrust along the nose.
func _thrust_cmd() -> FlightCommand:
	var cmd := FlightCommand.new()
	cmd.main_left = 1.0
	cmd.main_right = 1.0
	return cmd


## Reaction mass flow of `_thrust_cmd()`, kg/s: four main nozzles at full.
func _thrust_flow() -> float:
	return 4.0 * spec.pod_main_thrust / spec.exhaust_velocity


func _console(line: String) -> ConsoleResult:
	var results: Array[ConsoleResult] = DebugConsole.registry.execute(line)
	assert_eq(results.size(), 1, "one statement: " + line)
	return results[0]


## Thrust for `seconds` from a tick boundary, then the tick's results are in.
func _burn(seconds: float) -> void:
	await get_tree().physics_frame
	ship.set_flight_command(_thrust_cmd())
	await _step(_ticks(seconds))


# --- the tank ------------------------------------------------------------------------------------------------


func test_the_tank_is_built_from_the_ship_spec_and_starts_full() -> void:
	Settings.set_value(&"fuel_unlimited", false)
	var tank: FuelTank = ship.get_fuel_tank()
	assert_eq(tank.capacity_kg, spec.fuel_capacity_kg)
	assert_eq(tank.mass_kg(), spec.fuel_capacity_kg)
	assert_eq(tank.fraction(), 1.0)
	assert_false(tank.is_empty())


func test_fuel_unlimited_defaults_to_true() -> void:
	assert_true(Settings.schema.get_default(&"fuel_unlimited"))
	assert_true(ship.get_fuel_tank().unlimited)


func test_unlimited_fuel_is_never_drawn_down() -> void:
	Settings.set_value(&"fuel_unlimited", true)
	await _burn(1.0)
	assert_gt(ship.linear_velocity.length(), 20.0, "it flew (30 m/s² for 1 s)")
	assert_gt(ship.get_flight_output().mass_flow_kg_s, 0.0, "flow is reported")
	assert_eq(ship.get_fuel_tank().mass_kg(), spec.fuel_capacity_kg, "gauge stays full")
	assert_eq(ship.get_fuel_tank().fraction(), 1.0)


func test_a_finite_tank_is_drawn_down_by_the_mass_flow() -> void:
	Settings.set_value(&"fuel_unlimited", false)
	await _burn(1.0)
	var drawn: float = spec.fuel_capacity_kg - ship.get_fuel_tank().mass_kg()
	assert_almost_eq(ship.get_flight_output().mass_flow_kg_s, _thrust_flow(), 1e-6, "flow from the spec")
	assert_almost_eq(drawn, _thrust_flow() * 1.0, _thrust_flow() * _dt() * 2.0, "one second of flow, give or take a tick")
	assert_almost_eq(ship.get_fuel_tank().fraction(), 1.0 - drawn / spec.fuel_capacity_kg, 1e-9)


func test_an_idle_ship_burns_nothing() -> void:
	Settings.set_value(&"fuel_unlimited", false)
	await _step(_ticks(0.5))
	assert_eq(ship.get_fuel_tank().mass_kg(), spec.fuel_capacity_kg)


# --- an empty tank: the ship cannot thrust ------------------------------------------------------------------


func test_with_an_empty_tank_the_ship_cannot_thrust() -> void:
	Settings.set_value(&"fuel_unlimited", false)
	ship.get_fuel_tank().set_kg(0.0)
	var cmd: FlightCommand = _thrust_cmd()
	cmd.retro_left = 1.0
	cmd.retro_right = 1.0
	cmd.strafe = Vector2(1.0, 1.0)
	await get_tree().physics_frame
	ship.set_flight_command(cmd)
	await _step(_ticks(1.0))
	var out: FlightOutput = ship.get_flight_output()
	assert_true(out.propellant_empty, "the model was told the tank is empty")
	assert_eq(out.force_b, Vector3.ZERO, "no force asked of the engine")
	assert_eq(out.mass_flow_kg_s, 0.0)
	assert_almost_eq(ship.linear_velocity.length(), 0.0, 1e-6, "and the ship did not move")
	assert_almost_eq(ship.position.length(), 0.0, 1e-6)
	assert_eq(ship.get_fuel_tank().mass_kg(), 0.0, "still empty")


func test_the_same_ship_thrusts_again_once_refuelled() -> void:
	Settings.set_value(&"fuel_unlimited", false)
	ship.get_fuel_tank().set_kg(0.0)
	await _burn(0.5)
	assert_almost_eq(ship.linear_velocity.length(), 0.0, 1e-6, "dry: nothing")
	var result: ConsoleResult = _console("refuel")
	assert_true(result.ok, result.text())
	await _step(_ticks(0.5))
	assert_gt(ship.linear_velocity.length(), 10.0, "refuelled: 30 m/s² for 0.5 s")
	assert_false(ship.get_flight_output().propellant_empty)


func test_the_ship_runs_dry_mid_burn_and_coasts_at_the_speed_it_had() -> void:
	Settings.set_value(&"fuel_unlimited", false)
	ship.get_fuel_tank().set_kg(_thrust_flow() * 1.0)  # one second of full thrust
	await _burn(2.0)
	assert_true(ship.get_fuel_tank().is_empty())
	var accel: float = 4.0 * spec.pod_main_thrust / spec.mass
	# One second of thrust, plus at most the single tick that spends the last grams.
	assert_between(ship.linear_velocity.length(), accel * 1.0 - 0.5, accel * 1.0 + accel * _dt() * 2.0 + 0.1, "about one second's delta-v")
	var coasting: float = ship.linear_velocity.length()
	await _step(_ticks(1.0))
	assert_almost_eq(ship.linear_velocity.length(), coasting, 1e-4, "a dry ship coasts: zero damping, zero thrust")
	assert_true(ship.get_flight_output().propellant_empty)


func test_unlimited_fuel_ignores_an_empty_store() -> void:
	Settings.set_value(&"fuel_unlimited", false)
	ship.get_fuel_tank().set_kg(0.0)
	Settings.set_value(&"fuel_unlimited", true)
	await _burn(0.5)
	assert_gt(ship.linear_velocity.length(), 10.0, "the setting means it never runs dry")
	assert_eq(ship.get_fuel_tank().fraction(), 1.0)


func test_the_setting_applies_live() -> void:
	Settings.set_value(&"fuel_unlimited", true)
	await get_tree().physics_frame
	ship.set_flight_command(_thrust_cmd())
	await _step(_ticks(0.5))
	assert_eq(ship.get_fuel_tank().mass_kg(), spec.fuel_capacity_kg, "nothing drawn while unlimited")
	assert_true(_console("set settings.fuel_unlimited false").ok)
	await _step(_ticks(0.5))
	var drawn: float = spec.fuel_capacity_kg - ship.get_fuel_tank().mass_kg()
	assert_almost_eq(drawn, _thrust_flow() * 0.5, _thrust_flow() * _dt() * 3.0, "drawing from the moment the setting changed")


func test_respawn_refuels() -> void:
	Settings.set_value(&"fuel_unlimited", false)
	ship.get_fuel_tank().set_kg(12.0)
	ship.reset_to(Transform3D.IDENTITY)
	assert_eq(ship.get_fuel_tank().mass_kg(), spec.fuel_capacity_kg)


func test_setup_with_another_spec_resizes_the_tank() -> void:
	Settings.set_value(&"fuel_unlimited", false)
	var small: ShipSpec = spec.duplicate() as ShipSpec
	small.fuel_capacity_kg = 1234.0
	ship.setup(small, world)
	assert_eq(ship.get_fuel_tank().capacity_kg, 1234.0)
	assert_eq(ship.get_fuel_tank().mass_kg(), 1234.0)


# --- console ---------------------------------------------------------------------------------------------------


func test_console_fuel_keys_read_the_tank() -> void:
	var provider: ConsoleStateProvider = DebugConsole.registry.get_provider(&"ship")
	assert_true(provider.has_key(&"fuel_kg"))
	assert_true(provider.has_key(&"fuel_fraction"))
	assert_true(provider.is_writable(&"fuel_kg"))
	assert_false(provider.is_writable(&"fuel_fraction"))
	assert_eq(DebugConsole.registry.read("ship.fuel_kg")["value"], spec.fuel_capacity_kg)
	assert_eq(DebugConsole.registry.read("ship.fuel_fraction")["value"], 1.0)
	assert_eq(DebugConsole.registry.format_path("ship.fuel_fraction"), "ship.fuel_fraction = 1.00")
	assert_string_contains(DebugConsole.registry.format_path("ship.fuel_kg"), "ship.fuel_kg = ")
	assert_string_contains(DebugConsole.registry.format_path("ship.fuel_kg"), "kg")
	var text: String = _console("state ship").text()
	assert_string_contains(text, "ship.fuel_kg = ")
	assert_string_contains(text, "ship.fuel_fraction = ")


func test_console_fuel_kg_is_writable_within_the_capacity() -> void:
	Settings.set_value(&"fuel_unlimited", false)
	var result: ConsoleResult = _console("set ship.fuel_kg 7200")
	assert_true(result.ok, result.text())
	assert_eq(ship.get_fuel_tank().mass_kg(), 7200.0)
	assert_almost_eq(float(DebugConsole.registry.read("ship.fuel_fraction")["value"]), 7200.0 / spec.fuel_capacity_kg, 1e-9)
	assert_false(_console("set ship.fuel_kg %d" % int(spec.fuel_capacity_kg * 2.0)).ok, "more than the tank holds")
	assert_false(_console("set ship.fuel_kg -1").ok, "negative")
	assert_eq(ship.get_fuel_tank().mass_kg(), 7200.0, "unchanged by the rejected writes")
	assert_true(_console("set ship.fuel_kg 0").ok)
	assert_true(ship.get_fuel_tank().is_empty())


func test_console_fuel_fraction_is_read_only() -> void:
	var result: ConsoleResult = _console("set ship.fuel_fraction 0.5")
	assert_false(result.ok)
	assert_string_contains(result.error, "read-only")


func test_console_fuel_gauge_reads_full_while_unlimited_even_after_a_write() -> void:
	Settings.set_value(&"fuel_unlimited", true)
	assert_true(_console("set ship.fuel_kg 100").ok)
	assert_eq(DebugConsole.registry.read("ship.fuel_fraction")["value"], 1.0, "gauge stays full")
	Settings.set_value(&"fuel_unlimited", false)
	assert_almost_eq(float(DebugConsole.registry.read("ship.fuel_kg")["value"]), 100.0, 1e-9, "the store was kept")


func test_console_refuel_fills_or_adds() -> void:
	Settings.set_value(&"fuel_unlimited", false)
	ship.get_fuel_tank().set_kg(100.0)
	var result: ConsoleResult = _console("refuel 500")
	assert_true(result.ok, result.text())
	assert_eq(ship.get_fuel_tank().mass_kg(), 600.0)
	assert_string_contains(result.text(), "added 500 kg")
	result = _console("refuel")
	assert_true(result.ok, result.text())
	assert_eq(ship.get_fuel_tank().mass_kg(), spec.fuel_capacity_kg)
	assert_string_contains(result.text(), "added %.0f kg" % (spec.fuel_capacity_kg - 600.0))
	assert_false(_console("refuel -5").ok, "negative amounts are rejected")
	assert_true(DebugConsole.registry.has_command(&"refuel"))


func test_console_entries_leave_with_the_ship() -> void:
	assert_true(DebugConsole.registry.has_command(&"refuel"))
	world.remove_child(ship)
	assert_false(DebugConsole.registry.has_command(&"refuel"), "command unregistered on exit")
	ship.free()
	ship = null
