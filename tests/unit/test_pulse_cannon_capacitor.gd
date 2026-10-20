extends GutTest
## PulseCannonGate with a WeaponCapacitor (architecture §6.3, M2-T14) and a fake clock: the M1 fire rates hold for
## short bursts (AC0, AC7), an empty capacitor blocks the gate without disturbing its cooldown or muzzle turn, sustained
## fire is held to the recharge rate, and no mode or mode switch can draw more energy than the store provides.
## Expected values come from the capacitor's own numbers, never literals.

const DT: float = 1.0 / 60.0
const ALT_S: float = PulseCannonGate.ALTERNATING_INTERVAL_S
const LINKED_S: float = PulseCannonGate.LINKED_INTERVAL_S
const CAP: float = WeaponCapacitor.DEFAULT_CAPACITY
const COST: float = WeaponCapacitor.DEFAULT_COST_PER_SHOT
const RATE: float = WeaponCapacitor.DEFAULT_RECHARGE_PER_S

var gate: PulseCannonGate
var cap: WeaponCapacitor


func before_each() -> void:
	gate = PulseCannonGate.new()
	cap = WeaponCapacitor.new()
	gate.capacitor = cap


## Holds the trigger for `seconds` of 1/60 s ticks from `start_s`, the clock summed tick by tick like SimClock.
## One entry per shot: {"t": time, "muzzles": Array[int]}.
func _hold(seconds: float, start_s: float = 0.0) -> Array[Dictionary]:
	var shots: Array[Dictionary] = []
	var now: float = start_s
	for i: int in roundi(seconds / DT):
		var fired: Array[int] = gate.update(now, true)
		if not fired.is_empty():
			shots.append({"t": now, "muzzles": fired})
		now += DT
	return shots


func _projectile_count(shots: Array[Dictionary]) -> int:
	var count: int = 0
	for shot: Dictionary in shots:
		count += (shot["muzzles"] as Array).size()
	return count


# --- M1 rates still hold for short bursts (AC0, AC7) -------------------------------------------------------------


func test_no_capacitor_means_unlimited_fire_as_in_m1() -> void:
	var plain := PulseCannonGate.new()
	assert_null(plain.capacitor, "a bare gate has none")
	var count: int = 0
	var now: float = 0.0
	for i: int in 60 * 20:
		count += plain.update(now, true).size()
		now += DT
	assert_eq(count, 80, "4 projectiles a second for 20 s, however long")


func test_alternating_burst_of_two_seconds_is_the_m1_rate() -> void:
	var shots: Array[Dictionary] = _hold(2.0)
	assert_eq(shots.size(), 8, "8 shots in 2 s")
	for i: int in shots.size():
		assert_eq(shots[i]["muzzles"], [i % 2] as Array[int], "muzzles take turns")
		assert_almost_eq(float(shots[i]["t"]), i * ALT_S, DT, "4 Hz")


func test_alternating_burst_lasts_twelve_shots_then_is_held_back() -> void:
	var shots: Array[Dictionary] = _hold(4.0)
	assert_lt(shots.size(), 16, "fewer than the unlimited 16 in 4 s")
	for i: int in 12:
		assert_almost_eq(float(shots[i]["t"]), i * ALT_S, DT, "shot %d on the M1 schedule" % i)
	assert_gt(float(shots[12]["t"]), 12.0 * ALT_S + 0.2, "the 13th waits for the recharge (about 3.28 s)")


func test_linked_burst_is_the_m1_rate() -> void:
	gate.cycle_mode()
	var shots: Array[Dictionary] = _hold(2.0)
	assert_eq(shots.size(), 4, "4 volleys in 2 s")
	for i: int in shots.size():
		assert_eq(shots[i]["muzzles"], [0, 1] as Array[int])
		assert_almost_eq(float(shots[i]["t"]), i * LINKED_S, DT, "2 Hz")


func test_the_first_shot_still_comes_out_on_the_press() -> void:
	assert_eq(gate.update(5.0, true), [0] as Array[int])


# --- sustained fire is limited -------------------------------------------------------------------------------------


func test_sustained_fire_settles_at_the_recharge_rate() -> void:
	var shots: Array[Dictionary] = _hold(20.0)
	var total: int = _projectile_count(shots)
	var ceiling: int = floori((CAP + RATE * 20.0) / COST) + 1
	assert_lte(total, ceiling, "cannot spend more than the store plus 20 s of recharge")
	assert_gt(total, int(0.8 * (CAP + RATE * 20.0) / COST), "and it does use most of it")
	assert_lt(total, 80, "well under the unlimited 80")
	# After the first charge, shots are spaced by cost / rate, not by the cooldown.
	var late: Array = shots.filter(func(s: Dictionary) -> bool: return float(s["t"]) > 10.0)
	for i: int in range(1, late.size()):
		assert_almost_eq(float(late[i]["t"]) - float(late[i - 1]["t"]), COST / RATE, 2.0 * DT, "paced by the recharge")


func test_linked_sustained_fire_is_held_to_the_same_energy_rate() -> void:
	gate.cycle_mode()
	var total: int = _projectile_count(_hold(20.0))
	assert_lte(total, floori((CAP + RATE * 20.0) / COST) + 1)
	assert_lt(total, 80)
	assert_gt(total, 36)


func test_releasing_the_trigger_recharges_in_capacity_over_rate_seconds() -> void:
	_hold(3.0)
	assert_lt(cap.fraction_at(3.0), 0.2, "nearly empty after the burst")
	var wait: float = CAP / RATE
	assert_lt(cap.fraction_at(3.0 + 0.75 * wait), 1.0, "not yet full after three quarters of the time")
	gate.update(3.0 + wait, false)  # the trigger is up; the gate still brings the store up to date
	assert_almost_eq(cap.fraction_at(3.0 + wait), 1.0, 1e-9, "full again after capacity / rate")
	var again: Array[Dictionary] = _hold(2.0, 3.0 + wait + 1.0)
	assert_eq(again.size(), 8, "and the next burst is a full-rate one")


func test_never_pays_more_than_the_store_holds_over_any_window() -> void:
	# Mash both the trigger and the mode over 30 s: total energy spent can never exceed store + recharge.
	var now: float = 0.0
	var projectiles: int = 0
	for i: int in 60 * 30:
		if i % 37 == 0:
			gate.cycle_mode()
		projectiles += gate.update(now, i % 200 < 150).size()
		now += DT
	assert_lte(float(projectiles) * COST, CAP + RATE * now + 1e-6)


# --- an empty capacitor blocks the gate -------------------------------------------------------------------------


func test_an_empty_capacitor_blocks_the_gate() -> void:
	cap.set_fraction(0.0, 0.0)
	assert_eq(gate.update(0.0, true), [] as Array[int], "no energy, no shot")
	assert_eq(gate.update(0.1, true), [] as Array[int])


func test_the_first_shot_comes_the_moment_the_capacitor_can_pay() -> void:
	cap.set_fraction(0.0, 0.0)
	var shots: Array[Dictionary] = _hold(1.0)
	assert_gt(shots.size(), 0, "fires once recharged")
	assert_almost_eq(float(shots[0]["t"]), COST / RATE, 2.0 * DT, "after cost / rate seconds")


func test_a_blocked_shot_leaves_the_cooldown_alone() -> void:
	cap.set_fraction(0.0, 0.0)
	gate.update(0.0, true)
	assert_eq(gate.cooldown_remaining(0.0), 0.0, "nothing was fired, so nothing is cooling down")


func test_a_blocked_shot_does_not_skip_a_muzzle() -> void:
	var seen: Array[int] = []
	for shot: Dictionary in _hold(3.0):  # drain it, 12 shots: 0, 1, 0, 1, ...
		seen.append((shot["muzzles"] as Array)[0])
	assert_eq(seen.size(), 12)
	cap.set_fraction(0.0, 3.0)  # the store is empty for a while
	assert_eq(gate.update(3.0, true), [] as Array[int])
	var resumed: Array[Dictionary] = _hold(1.0, 3.0)
	assert_gt(resumed.size(), 0)
	assert_eq(resumed[0]["muzzles"], [0] as Array[int], "12 shots were fired, so the turn is muzzle 0 again")


func test_a_linked_volley_needs_two_shots_of_energy() -> void:
	gate.cycle_mode()
	cap.set_fraction(1.5 * COST / CAP, 0.0)
	assert_eq(gate.update(0.0, true), [] as Array[int], "1.5 shots' worth cannot pay for two projectiles")
	assert_eq(gate.cooldown_remaining(0.0), 0.0)
	var wait: float = 0.5 * COST / RATE
	assert_eq(gate.update(wait + 1e-4, true), [0, 1] as Array[int], "fires as soon as it can pay for both")
	gate.cycle_mode()
	cap.set_fraction(1.5 * COST / CAP, 10.0)
	assert_eq(gate.update(10.0, true), [0] as Array[int], "alternating can pay for one")


func test_switching_mode_cannot_get_around_the_energy_limit() -> void:
	cap.set_fraction(COST / CAP, 0.0)  # exactly one shot
	assert_eq(gate.update(0.0, true), [0] as Array[int])
	gate.cycle_mode()
	assert_eq(gate.update(0.0, true), [] as Array[int], "still cooling down and out of energy")
	gate.cycle_mode()
	assert_eq(gate.update(ALT_S, true), [] as Array[int], "0.25 s of recharge is not enough for another")


func test_reset_refills_the_capacitor_and_forgets_the_cooldown() -> void:
	assert_eq(_hold(2.7).size(), 11, "eleven shots: the next muzzle is 1")
	assert_lt(cap.fraction_at(2.7), 0.2)
	gate.reset()
	assert_eq(cap.fraction_at(2.7), 1.0, "respawn comes with a full capacitor")
	assert_eq(gate.update(2.7, true), [0] as Array[int], "no cooldown, and the muzzle turn is forgotten too")


func test_reset_without_a_capacitor_is_fine() -> void:
	var plain := PulseCannonGate.new()
	plain.reset()
	assert_eq(plain.update(0.0, true), [0] as Array[int])


func test_a_clock_reset_keeps_charge_and_recharges_from_the_new_time() -> void:
	_hold(3.0, 1000.0)
	gate.update(1003.0, false)
	var charge: float = cap.charge_at(1003.0)
	gate.update(0.0, false)  # SimClock.reset(0): the gate must not stall or refill
	assert_almost_eq(cap.charge_at(0.0), charge, 1e-6, "the charge survived the jump back")
	assert_almost_eq(cap.charge_at(2.0), minf(CAP, charge + 2.0 * RATE), 1e-6, "and recharges from the new time")
