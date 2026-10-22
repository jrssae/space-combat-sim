extends GutTest
## WeaponCapacitor (architecture §6.3, M2-T14) with a fake clock: starts full, each projectile costs energy, the store
## recharges linearly up to capacity, a payment is all or nothing, and a clock that jumps back neither adds nor loses.

const DT: float = 1.0 / 60.0
const CAP: float = WeaponCapacitor.DEFAULT_CAPACITY
const COST: float = WeaponCapacitor.DEFAULT_COST_PER_SHOT
const RATE: float = WeaponCapacitor.DEFAULT_RECHARGE_PER_S

var cap: WeaponCapacitor


func before_each() -> void:
	cap = WeaponCapacitor.new()


func test_defaults_give_about_three_seconds_of_alternating_fire_and_a_four_second_recharge() -> void:
	assert_eq(cap.capacity, CAP)
	assert_eq(cap.cost_per_shot, COST)
	assert_eq(cap.recharge_per_s, RATE)
	assert_almost_eq(CAP / RATE, 4.0, 1e-9, "empty to full in 4 s")
	# Alternating fire is one projectile every 0.25 s; count how long the full store keeps paying for them.
	var shots: int = 0
	var now: float = 0.0
	while cap.spend(1, now):
		shots += 1
		now += 0.25
	assert_eq(shots, 12, "the full store plus the recharge during the burst pays for 12 shots")
	assert_almost_eq(now, 3.0, 1e-9, "the 13th, at 3 s, is the first refused")


func test_starts_full() -> void:
	assert_eq(cap.charge_at(0.0), CAP)
	assert_eq(cap.fraction_at(0.0), 1.0)
	assert_true(cap.can_afford(1, 0.0))


func test_spend_takes_the_cost_and_reports_success() -> void:
	assert_true(cap.spend(1, 0.0))
	assert_almost_eq(cap.charge_at(0.0), CAP - COST, 1e-9)
	assert_true(cap.spend(2, 0.0))
	assert_almost_eq(cap.charge_at(0.0), CAP - 3.0 * COST, 1e-9)


func test_recharge_is_linear_and_capped_at_capacity() -> void:
	cap.set_fraction(0.0, 10.0)
	assert_eq(cap.charge_at(10.0), 0.0)
	assert_almost_eq(cap.charge_at(11.0), RATE, 1e-9)
	assert_almost_eq(cap.charge_at(12.0), 2.0 * RATE, 1e-9)
	assert_almost_eq(cap.fraction_at(12.0), 2.0 * RATE / CAP, 1e-9)
	assert_eq(cap.charge_at(14.0), CAP, "full after capacity / rate")
	assert_eq(cap.charge_at(1000.0), CAP, "and never above")


func test_charge_at_reads_without_changing_anything() -> void:
	cap.set_fraction(0.0, 0.0)
	assert_almost_eq(cap.charge_at(1.0), RATE, 1e-9)
	assert_almost_eq(cap.charge_at(1.0), RATE, 1e-9, "same answer twice")
	assert_almost_eq(cap.charge_at(0.5), 0.5 * RATE, 1e-9, "and an earlier time still works")


func test_an_empty_store_cannot_pay_and_keeps_what_it_has() -> void:
	cap.set_fraction(0.0, 0.0)
	assert_false(cap.can_afford(1, 0.0))
	assert_false(cap.spend(1, 0.0))
	assert_eq(cap.charge_at(0.0), 0.0)
	var wait: float = COST / RATE
	assert_false(cap.spend(1, wait - 0.01), "a little too early")
	assert_true(cap.spend(1, wait), "pays the moment it has enough")
	assert_almost_eq(cap.charge_at(wait), 0.0, 1e-6)


func test_payment_is_all_or_nothing() -> void:
	cap.set_fraction(1.5 * COST / CAP, 0.0)  # one and a half shots
	assert_false(cap.spend(2, 0.0), "two projectiles need two shots' worth")
	assert_almost_eq(cap.charge_at(0.0), 1.5 * COST, 1e-9, "nothing was taken")
	assert_true(cap.spend(1, 0.0))
	assert_almost_eq(cap.charge_at(0.0), 0.5 * COST, 1e-9)


func test_summed_ticks_do_not_lose_a_shot_to_rounding() -> void:
	# Empty store, polled every 1/60 s tick: the first tick whose time reaches cost / rate must pay.
	cap.set_fraction(0.0, 0.0)
	var now: float = 0.0
	var paid_at: float = -1.0
	for i: int in 200:
		if cap.spend(1, now):
			paid_at = now
			break
		now += DT
	assert_gte(paid_at, 0.0, "it paid")
	assert_almost_eq(paid_at, COST / RATE, DT, "within a tick of cost / rate")


func test_a_clock_reset_adds_nothing_and_loses_nothing() -> void:
	cap.set_fraction(0.5, 1000.0)
	cap.advance(1000.0)
	cap.advance(0.0)  # SimClock.reset(0)
	assert_almost_eq(cap.charge_at(0.0), 0.5 * CAP, 1e-9, "kept")
	assert_almost_eq(cap.charge_at(1.0), 0.5 * CAP + RATE, 1e-9, "and recharging from the new time")


func test_refill_and_set_fraction() -> void:
	cap.set_fraction(0.25, 0.0)
	assert_almost_eq(cap.fraction_at(0.0), 0.25, 1e-12)
	cap.set_fraction(7.0, 0.0)
	assert_eq(cap.fraction_at(0.0), 1.0, "clamped")
	cap.set_fraction(-1.0, 0.0)
	assert_eq(cap.fraction_at(0.0), 0.0, "clamped")
	cap.set_fraction(NAN, 0.0)
	assert_eq(cap.fraction_at(0.0), 0.0, "NaN ignored")
	cap.refill()
	assert_eq(cap.fraction_at(0.0), 1.0)


func test_custom_numbers_and_degenerate_values() -> void:
	var small := WeaponCapacitor.new(10.0, 4.0, 2.0)
	assert_true(small.spend(2, 0.0))
	assert_almost_eq(small.charge_at(0.0), 2.0, 1e-9)
	assert_false(small.spend(1, 0.0), "2 left, 4 needed")
	assert_true(small.spend(1, 1.0), "one second of recharge brings it to 4")
	var broken := WeaponCapacitor.new(-1.0, -1.0, -1.0)
	assert_eq(broken.capacity, 0.0)
	assert_eq(broken.cost_per_shot, 0.0)
	assert_eq(broken.recharge_per_s, 0.0)
	assert_eq(broken.fraction_at(5.0), 0.0, "no capacity: no fraction")
	assert_true(broken.spend(3, 0.0), "free shots from a zero-cost store")
