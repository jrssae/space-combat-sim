extends GutTest
## PulseCannonGate (architecture §6.3, AC7) with a fake clock: ALTERNATING is 4 Hz with the muzzles taking turns,
## LINKED is 2 Hz with both together, the first shot comes out on the press, the cooldown carries across mode
## switches, and cycling modes can never raise the rate of fire.

const DT: float = 1.0 / 60.0
const ALT_S: float = PulseCannonGate.ALTERNATING_INTERVAL_S
const LINKED_S: float = PulseCannonGate.LINKED_INTERVAL_S

var gate: PulseCannonGate


func before_each() -> void:
	gate = PulseCannonGate.new()


## Holds the trigger for `seconds` of 1/60 s ticks starting at `start_s` (the clock is summed tick by tick, like
## SimClock). Returns one entry per shot: {"t": time, "muzzles": Array[int]}.
func _hold(seconds: float, start_s: float = 0.0) -> Array[Dictionary]:
	var shots: Array[Dictionary] = []
	var ticks: int = roundi(seconds / DT)
	var now: float = start_s
	for i: int in ticks:
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


# --- modes ---------------------------------------------------------------------------------------------------


func test_starts_in_alternating_mode() -> void:
	assert_eq(gate.mode, PulseCannonGate.Mode.ALTERNATING)


func test_cycle_mode_wraps() -> void:
	gate.cycle_mode()
	assert_eq(gate.mode, PulseCannonGate.Mode.LINKED)
	gate.cycle_mode()
	assert_eq(gate.mode, PulseCannonGate.Mode.ALTERNATING)
	gate.cycle_mode()
	assert_eq(gate.mode, PulseCannonGate.Mode.LINKED)


func test_mode_names_round_trip() -> void:
	assert_eq(PulseCannonGate.mode_name(PulseCannonGate.Mode.ALTERNATING), &"alternating")
	assert_eq(PulseCannonGate.mode_name(PulseCannonGate.Mode.LINKED), &"linked")
	assert_eq(PulseCannonGate.mode_from_name(&"linked"), PulseCannonGate.Mode.LINKED)
	assert_eq(PulseCannonGate.mode_from_name(&"alternating"), PulseCannonGate.Mode.ALTERNATING)
	assert_eq(PulseCannonGate.mode_from_name(&"nonsense"), PulseCannonGate.Mode.ALTERNATING)


# --- alternating ---------------------------------------------------------------------------------------------


func test_first_shot_is_immediate_on_press() -> void:
	assert_eq(gate.update(0.0, true), [0])


func test_first_shot_is_immediate_after_a_long_quiet_spell() -> void:
	gate.update(0.0, true)
	assert_eq(gate.update(100.0, false), [], "trigger up: nothing")
	assert_eq(gate.update(100.0, true), [1], "pressed after a long wait: fires on that tick")


func test_no_shots_while_the_trigger_is_up() -> void:
	for i: int in 120:
		assert_true(gate.update(i * DT, false).is_empty())


func test_alternating_is_four_hertz_with_alternating_muzzles() -> void:
	var shots: Array[Dictionary] = _hold(2.0)
	assert_eq(shots.size(), 8, "8 shots in 2 s")
	for i: int in shots.size():
		assert_eq(shots[i]["muzzles"], [i % 2], "shot %d uses muzzle %d" % [i, i % 2])
		assert_almost_eq(float(shots[i]["t"]), i * ALT_S, 1e-6, "shot %d at %.2f s" % [i, i * ALT_S])


func test_alternating_fires_nothing_inside_the_interval() -> void:
	assert_eq(gate.update(0.0, true), [0])
	assert_true(gate.update(0.1, true).is_empty())
	assert_true(gate.update(0.249, true).is_empty())
	assert_eq(gate.update(0.25, true), [1])


func test_tapping_the_trigger_cannot_beat_the_cooldown() -> void:
	assert_eq(gate.update(0.0, true), [0])
	assert_true(gate.update(0.05, false).is_empty())
	assert_true(gate.update(0.10, true).is_empty(), "re-press inside the cooldown does nothing")
	assert_true(gate.update(0.15, false).is_empty())
	assert_true(gate.update(0.20, true).is_empty())
	assert_eq(gate.update(0.26, true), [1])


func test_alternation_continues_after_a_pause() -> void:
	assert_eq(gate.update(0.0, true), [0])
	assert_eq(gate.update(5.0, true), [1])
	assert_eq(gate.update(9.0, true), [0])


# --- linked --------------------------------------------------------------------------------------------------


func test_linked_is_two_hertz_with_both_muzzles() -> void:
	gate.cycle_mode()
	var shots: Array[Dictionary] = _hold(2.0)
	assert_eq(shots.size(), 4, "4 volleys in 2 s")
	for i: int in shots.size():
		assert_eq(shots[i]["muzzles"], [0, 1], "volley %d fires both" % i)
		assert_almost_eq(float(shots[i]["t"]), i * LINKED_S, 1e-6)


func test_linked_first_volley_is_immediate_and_then_waits_half_a_second() -> void:
	gate.cycle_mode()
	assert_eq(gate.update(3.0, true), [0, 1])
	assert_true(gate.update(3.25, true).is_empty())
	assert_true(gate.update(3.49, true).is_empty())
	assert_eq(gate.update(3.5, true), [0, 1])


func test_linked_volleys_do_not_disturb_the_alternating_turn() -> void:
	assert_eq(gate.update(0.0, true), [0])
	gate.cycle_mode()
	assert_eq(gate.update(1.0, true), [0, 1])
	gate.cycle_mode()
	assert_eq(gate.update(2.0, true), [1], "the turn passed to muzzle 1 after muzzle 0 fired")


# --- cooldown carries across switches ------------------------------------------------------------------------


func test_cooldown_carries_from_alternating_to_linked() -> void:
	assert_eq(gate.update(0.0, true), [0])
	gate.cycle_mode()
	assert_true(gate.update(0.1, true).is_empty())
	assert_true(gate.update(0.24, true).is_empty())
	assert_eq(gate.update(0.25, true), [0, 1], "only the remaining alternating cooldown applies")
	assert_true(gate.update(0.5, true).is_empty(), "then the linked interval")
	assert_eq(gate.update(0.75, true), [0, 1])


func test_cooldown_carries_from_linked_to_alternating() -> void:
	gate.cycle_mode()
	assert_eq(gate.update(0.0, true), [0, 1])
	gate.cycle_mode()
	assert_true(gate.update(0.25, true).is_empty(), "switching does not shorten the linked cooldown")
	assert_true(gate.update(0.49, true).is_empty())
	assert_eq(gate.update(0.5, true), [0])


func test_cooldown_remaining_counts_down_to_zero() -> void:
	assert_eq(gate.cooldown_remaining(0.0), 0.0, "ready before the first shot")
	gate.update(10.0, true)
	assert_almost_eq(gate.cooldown_remaining(10.0), ALT_S, 1e-9)
	assert_almost_eq(gate.cooldown_remaining(10.1), ALT_S - 0.1, 1e-9)
	assert_eq(gate.cooldown_remaining(10.3), 0.0)
	gate.cycle_mode()
	gate.update(11.0, true)
	assert_almost_eq(gate.cooldown_remaining(11.0), LINKED_S, 1e-9)


func test_cycling_modes_every_tick_never_raises_the_rate_of_fire() -> void:
	# Worst case for the rate: hold the trigger and flip the mode on every tick, for each phase pattern.
	var seconds: float = 10.0
	var ceiling: int = ceili(seconds / ALT_S) + 2  # 4 projectiles per second, plus the immediate first shot
	for period: int in [1, 2, 3, 5, 7, 11]:
		gate.reset()
		if gate.mode != PulseCannonGate.Mode.ALTERNATING:
			gate.cycle_mode()
		var count: int = 0
		var now: float = 0.0
		for tick: int in roundi(seconds / DT):
			if tick % period == 0:
				gate.cycle_mode()
			count += gate.update(now, true).size()
			now += DT
		assert_true(count <= ceiling, "cycling every %d ticks fired %d projectiles in %.0f s (limit %d)" % [period, count, seconds, ceiling])
		assert_true(count >= ceiling - 8, "and it still fires (%d projectiles)" % count)


func test_cycling_with_random_presses_never_raises_the_rate_of_fire() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260704
	var seconds: float = 30.0
	var count: int = 0
	var now: float = 0.0
	for tick: int in roundi(seconds / DT):
		if rng.randf() < 0.3:
			gate.cycle_mode()
		count += gate.update(now, rng.randf() < 0.8).size()
		now += DT
	assert_true(count <= ceili(seconds / ALT_S) + 2, "fired %d projectiles in %.0f s" % [count, seconds])


func test_both_modes_deliver_the_same_projectile_rate() -> void:
	var alternating: int = _projectile_count(_hold(4.0))
	gate.reset()
	gate.cycle_mode()
	var linked: int = _projectile_count(_hold(4.0))
	assert_eq(alternating, 16)
	assert_eq(linked, 16)


# --- reset and clock oddities --------------------------------------------------------------------------------


func test_reset_makes_the_cannon_ready_and_restarts_at_muzzle_zero() -> void:
	gate.update(0.0, true)
	gate.reset()
	assert_eq(gate.update(0.01, true), [0])


func test_a_clock_reset_to_an_earlier_time_does_not_stick_the_cannon() -> void:
	gate.update(1000.0, true)
	assert_eq(gate.update(0.0, true).size(), 0, "still cooling, but for at most one linked interval")
	assert_true(gate.cooldown_remaining(0.0) <= LINKED_S)
	assert_eq(gate.update(0.25, true).size(), 0)
	assert_eq(gate.update(LINKED_S, true).size(), 1, "and it fires again once that interval has passed")


# --- any number of muzzles, interval from the spec (M2-T02) --------------------------------------------------


func test_defaults_are_the_starfury_two_muzzles_at_a_quarter_second() -> void:
	assert_eq(gate.muzzle_count, 2)
	assert_eq(gate.interval_s, ALT_S)
	assert_eq(gate.linked_interval_s(), LINKED_S)


func test_four_muzzles_alternating_cycle_zero_to_three_at_the_spec_interval() -> void:
	gate = PulseCannonGate.new(4, 0.2)
	var shots: Array[Dictionary] = _hold(2.0)
	assert_eq(shots.size(), 10, "one shot per 0.2 s")
	for i: int in shots.size():
		assert_eq(shots[i]["muzzles"], [i % 4], "turn %d" % i)
		if i > 0:
			assert_almost_eq(float(shots[i]["t"]) - float(shots[i - 1]["t"]), 0.2, DT, "interval")


func test_four_muzzles_linked_fire_all_every_interval_times_four() -> void:
	gate = PulseCannonGate.new(4, 0.2)
	gate.cycle_mode()
	var shots: Array[Dictionary] = _hold(3.0)
	assert_eq(shots.size(), 4, "a volley every 0.8 s: at 0, 0.8, 1.6 and 2.4 s")
	for shot: Dictionary in shots:
		assert_eq(shot["muzzles"], [0, 1, 2, 3])
	assert_almost_eq(float(shots[1]["t"]) - float(shots[0]["t"]), 0.8, DT)


func test_projectile_rate_is_the_same_in_both_modes_for_any_muzzle_count() -> void:
	for count: int in [1, 2, 3, 4, 6]:
		gate = PulseCannonGate.new(count, 0.25)
		var alternating: int = _projectile_count(_hold(4.0))
		gate.reset()
		gate.cycle_mode()
		var linked: int = _projectile_count(_hold(4.0))
		assert_eq(alternating, 16, "%d muzzles alternating" % count)
		# A volley is all or nothing, so the last one can overshoot the window by up to count - 1 projectiles.
		assert_true(linked >= 16 and linked < 16 + count, "%d muzzles linked: %d projectiles" % [count, linked])


func test_a_single_muzzle_fires_muzzle_zero_in_both_modes() -> void:
	gate = PulseCannonGate.new(1, 0.25)
	assert_eq(gate.update(0.0, true), [0])
	assert_eq(gate.update(0.25, true), [0])
	gate.cycle_mode()
	assert_eq(gate.update(10.0, true), [0])


func test_configure_clamps_nonsense_and_keeps_the_mode() -> void:
	gate.cycle_mode()
	gate.configure(0, -1.0)
	assert_eq(gate.muzzle_count, 1)
	assert_eq(gate.interval_s, ALT_S, "a non-positive interval falls back to the default")
	assert_eq(gate.mode, PulseCannonGate.Mode.LINKED)


func test_a_clock_reset_never_waits_longer_than_the_linked_interval_of_four_muzzles() -> void:
	gate = PulseCannonGate.new(4, 0.25)
	gate.cycle_mode()
	gate.update(1000.0, true)
	assert_true(gate.cooldown_remaining(0.0) <= 1.0 + 1e-9)
