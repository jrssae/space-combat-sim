extends GutTest
## FuelTank (architecture §5.1, M2-T14): starts full, `draw` integrates flow over time and clamps at zero,
## `unlimited` reads as a permanently full tank that is never drawn down, `refuel` and `set_kg` clamp to the capacity.
## The Starfury's tank size is derived from its ShipSpec, never hard-coded.

const SPEC_PATH: String = "res://assets/ships/starfury_aurora.tres"
const DT: float = 1.0 / 60.0
const CAPACITY: float = 1000.0

var tank: FuelTank


func before_each() -> void:
	tank = FuelTank.new(CAPACITY)


func test_starts_full() -> void:
	assert_eq(tank.capacity_kg, CAPACITY)
	assert_eq(tank.mass_kg(), CAPACITY)
	assert_eq(tank.fraction(), 1.0)
	assert_false(tank.is_empty())
	assert_false(tank.unlimited)


func test_draw_integrates_flow_over_time() -> void:
	var taken: float = tank.draw(50.0, 2.0)
	assert_almost_eq(taken, 100.0, 1e-9)
	assert_almost_eq(tank.mass_kg(), 900.0, 1e-9)
	assert_almost_eq(tank.fraction(), 0.9, 1e-12)
	for i: int in 60:
		tank.draw(60.0, DT)  # 60 kg/s for one second in 1/60 s ticks
	assert_almost_eq(tank.mass_kg(), 840.0, 1e-6)


func test_draw_clamps_at_empty_and_reports_what_it_took() -> void:
	tank.draw(990.0, 1.0)
	assert_false(tank.is_empty(), "10 kg left")
	var taken: float = tank.draw(100.0, 1.0)
	assert_almost_eq(taken, 10.0, 1e-9, "only what was left")
	assert_eq(tank.mass_kg(), 0.0)
	assert_eq(tank.fraction(), 0.0)
	assert_true(tank.is_empty())
	assert_eq(tank.draw(100.0, 1.0), 0.0, "nothing more to take")
	assert_eq(tank.mass_kg(), 0.0, "never negative")


func test_draw_ignores_negative_zero_and_non_finite_input() -> void:
	tank.draw(100.0, 1.0)
	var before: float = tank.mass_kg()
	assert_eq(tank.draw(-10.0, 1.0), 0.0, "a negative flow does not refuel")
	assert_eq(tank.draw(10.0, -1.0), 0.0, "time does not run backwards")
	assert_eq(tank.draw(0.0, 1.0), 0.0)
	assert_eq(tank.draw(10.0, 0.0), 0.0)
	assert_eq(tank.draw(NAN, 1.0), 0.0)
	assert_eq(tank.draw(INF, 1.0), 0.0)
	assert_eq(tank.mass_kg(), before)


func test_unlimited_is_never_drawn_down_and_reads_full() -> void:
	tank.unlimited = true
	assert_eq(tank.draw(1.0e6, 10.0), 0.0, "nothing is taken")
	assert_eq(tank.mass_kg(), CAPACITY)
	assert_eq(tank.fraction(), 1.0)
	assert_false(tank.is_empty())


func test_unlimited_reads_full_even_with_an_empty_store_and_the_store_is_kept() -> void:
	tank.draw(1.0e6, 1.0)
	assert_true(tank.is_empty())
	tank.unlimited = true
	assert_false(tank.is_empty(), "unlimited fuel cannot run out")
	assert_eq(tank.fraction(), 1.0)
	assert_eq(tank.mass_kg(), CAPACITY)
	tank.unlimited = false
	assert_true(tank.is_empty(), "switching back resumes from the real store")
	assert_eq(tank.mass_kg(), 0.0)


func test_unlimited_with_no_capacity_still_reads_full() -> void:
	var none := FuelTank.new(0.0, true)
	assert_eq(none.fraction(), 1.0)
	assert_false(none.is_empty())


func test_a_finite_tank_without_capacity_is_empty() -> void:
	var none := FuelTank.new(0.0)
	assert_true(none.is_empty())
	assert_eq(none.fraction(), 0.0)
	assert_eq(FuelTank.new(-5.0).capacity_kg, 0.0, "a negative capacity is no capacity")


func test_refuel_fills_by_default_and_clamps_to_capacity() -> void:
	tank.draw(400.0, 1.0)
	assert_almost_eq(tank.refuel(100.0), 100.0, 1e-9)
	assert_almost_eq(tank.mass_kg(), 700.0, 1e-9)
	assert_almost_eq(tank.refuel(), 300.0, 1e-9, "returns what it added")
	assert_eq(tank.mass_kg(), CAPACITY)
	assert_eq(tank.refuel(50.0), 0.0, "already full")
	assert_eq(tank.mass_kg(), CAPACITY)


func test_refuel_ignores_negative_and_nan_amounts() -> void:
	tank.draw(400.0, 1.0)
	assert_eq(tank.refuel(-100.0), 0.0)
	assert_eq(tank.refuel(NAN), 0.0)
	assert_almost_eq(tank.mass_kg(), 600.0, 1e-9)


func test_refuel_lifts_an_empty_tank() -> void:
	tank.draw(1.0e6, 1.0)
	assert_true(tank.is_empty())
	tank.refuel(1.0)
	assert_false(tank.is_empty())


func test_set_kg_clamps_and_ignores_nan() -> void:
	tank.set_kg(250.0)
	assert_eq(tank.mass_kg(), 250.0)
	tank.set_kg(5000.0)
	assert_eq(tank.mass_kg(), CAPACITY)
	tank.set_kg(-5.0)
	assert_eq(tank.mass_kg(), 0.0)
	assert_true(tank.is_empty())
	tank.set_kg(100.0)
	tank.set_kg(NAN)
	assert_eq(tank.mass_kg(), 100.0)


func test_starfury_tank_holds_ten_minutes_of_both_pods_at_full_main_thrust() -> void:
	var spec := load(SPEC_PATH) as ShipSpec
	assert_not_null(spec, "ShipSpec resource loads")
	var flow: float = 4.0 * spec.pod_main_thrust / spec.exhaust_velocity  # four main nozzles, kg/s
	assert_almost_eq(spec.fuel_capacity_kg / flow, 600.0, 1.0, "about ten minutes")
	var full := FuelTank.new(spec.fuel_capacity_kg)
	full.draw(flow, 599.0)
	assert_false(full.is_empty(), "still burning after 599 s")
	full.draw(flow, 2.0)
	assert_true(full.is_empty(), "dry after 601 s")
