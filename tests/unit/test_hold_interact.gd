extends GutTest
## The auto-track button's tap and hold (M7-T27): a tap toggles, a 2 s hold fires the interaction once, a release cancels, and the
## bar's progress.

const DT: float = 1.0 / 60.0


func _ticks(h: HoldInteract, n: int, pressed: bool, offered: bool = true) -> Dictionary:
	var taps: int = 0
	var fires: int = 0
	for i: int in n:
		h.step(pressed, offered, DT)
		taps += int(h.tapped)
		fires += int(h.fired)
	return {"taps": taps, "fires": fires}


func test_a_press_taps_at_once_when_nothing_is_offered() -> void:
	var h := HoldInteract.new()
	h.step(true, false, DT)
	assert_true(h.tapped, "auto-track switches on the press, as before")
	var rest: Dictionary = _ticks(h, 200, true, false)
	assert_eq(rest["taps"], 0, "a held press taps once")
	assert_eq(rest["fires"], 0, "and never fires")
	assert_eq(h.progress(), 0.0, "no bar")


func test_a_short_press_on_an_offer_taps_on_the_release() -> void:
	var h := HoldInteract.new()
	var held: Dictionary = _ticks(h, 10, true)
	assert_eq(held["taps"], 0, "nothing on the press: it may become a hold")
	h.step(false, true, DT)
	assert_true(h.tapped)
	assert_false(h.fired)


func test_a_two_second_hold_fires_once() -> void:
	var h := HoldInteract.new()
	var held: Dictionary = _ticks(h, 119, true)
	assert_eq(held["fires"], 0, "not before 2 s")
	h.step(true, true, DT)
	assert_true(h.fired, "120 ticks of 1/60 s")
	var after: Dictionary = _ticks(h, 120, true)
	assert_eq(after["fires"], 0, "held on, it does not repeat")
	h.step(false, true, DT)
	assert_false(h.tapped, "the release after a hold gives nothing")
	assert_false(h.fired)


func test_releasing_mid_hold_cancels() -> void:
	var h := HoldInteract.new()
	_ticks(h, 60, true)
	assert_gt(h.progress(), 0.0)
	h.step(false, true, DT)
	assert_false(h.tapped, "past the tap window a release is no tap")
	assert_false(h.fired)
	assert_eq(h.progress(), 0.0, "the bar empties")
	var next: Dictionary = _ticks(h, 100, true)
	assert_eq(next["fires"], 0, "a new hold starts from zero")


func test_progress_fills_after_the_tap_window() -> void:
	var h := HoldInteract.new()
	_ticks(h, 10, true)
	assert_eq(h.progress(), 0.0, "inside the tap window the bar stays hidden")
	_ticks(h, 50, true)
	assert_almost_eq(h.progress(), 0.5, 1e-6, "1 s of 2 s")
	_ticks(h, 30, true)
	assert_almost_eq(h.progress(), 0.75, 1e-6)
	_ticks(h, 30, true)
	assert_eq(h.progress(), 0.0, "fired: the bar is gone")


func test_the_offer_going_away_cancels_the_hold() -> void:
	var h := HoldInteract.new()
	_ticks(h, 60, true)
	var gone: Dictionary = _ticks(h, 200, true, false)
	assert_eq(gone["fires"], 0)
	assert_eq(h.progress(), 0.0)
	h.step(false, false, DT)
	assert_false(h.tapped)


func test_hold_time_is_a_setting() -> void:
	var h := HoldInteract.new()
	h.hold_s = 1.0
	assert_eq(_ticks(h, 60, true)["fires"], 1)
	assert_eq(float(SettingsSchema.ENTRIES[&"interact_hold_s"]["default"]), HoldInteract.HOLD_S)


func test_resync_drops_a_press() -> void:
	var h := HoldInteract.new()
	_ticks(h, 60, true)
	h.resync(true)
	assert_eq(_ticks(h, 200, true)["fires"], 0, "the held button does not fire after a resync")
	h.step(false, true, DT)
	assert_false(h.tapped)


# --- The subsystem hold (M10-T18): a long press of X steps a capital's subsystems --------------------------------------------


func _cycle_ticks(h: HoldInteract, n: int, pressed: bool, offered: bool = false, cycle_ok: bool = true) -> Dictionary:
	var taps: int = 0
	var steps: int = 0
	var fires: int = 0
	for i: int in n:
		h.step(pressed, offered, DT, cycle_ok)
		taps += int(h.tapped)
		steps += int(h.cycled)
		fires += int(h.fired)
	return {"taps": taps, "steps": steps, "fires": fires}


func test_a_tap_with_subsystems_on_offer_taps_on_the_release() -> void:
	var h := HoldInteract.new()
	var held: Dictionary = _cycle_ticks(h, 10, true)
	assert_eq(held["taps"], 0, "auto-track waits for the release")
	var up: Dictionary = _cycle_ticks(h, 1, false)
	assert_eq(up["taps"], 1)
	assert_eq(up["steps"], 0, "and no step")


func test_a_hold_steps_at_half_a_second_and_the_release_gives_nothing() -> void:
	var h := HoldInteract.new()
	var held: Dictionary = _cycle_ticks(h, 31, true)
	assert_eq(held["steps"], 1, "one step at 0.5 s")
	assert_eq(held["taps"], 0)
	var up: Dictionary = _cycle_ticks(h, 1, false)
	assert_eq(up["taps"], 0, "a long hold never toggles auto-track")
	assert_eq(h.progress(), 0.0, "no interaction bar for a subsystem step")


func test_a_press_just_under_the_threshold_is_a_tap() -> void:
	var h := HoldInteract.new()
	_cycle_ticks(h, 29, true)
	assert_eq(_cycle_ticks(h, 1, false)["taps"], 1)


func test_keeping_it_down_repeats_every_half_second() -> void:
	var h := HoldInteract.new()
	assert_eq(_cycle_ticks(h, 91, true)["steps"], 3, "0.5, 1.0 and 1.5 s")
	assert_eq(_cycle_ticks(h, 1, false)["taps"], 0)


func test_without_a_capital_the_press_is_the_old_tap_on_the_press() -> void:
	var h := HoldInteract.new()
	h.step(true, false, DT, false)
	assert_true(h.tapped, "no capital: auto-track on the press, as before")
	var rest: Dictionary = _cycle_ticks(h, 120, true, false, false)
	assert_eq(rest["steps"], 0, "a hold steps nothing")
	assert_eq(rest["taps"], 0)


func test_an_offered_interaction_wins_over_the_subsystems() -> void:
	var h := HoldInteract.new()
	var held: Dictionary = _cycle_ticks(h, 125, true, true)
	assert_eq(held["steps"], 0, "an abort or a jump is the hold's meaning")
	assert_eq(held["fires"], 1)


func test_losing_the_capital_mid_hold_stops_the_steps_but_the_release_still_gives_nothing() -> void:
	var h := HoldInteract.new()
	_cycle_ticks(h, 20, true)
	assert_eq(_cycle_ticks(h, 20, true, false, false)["steps"], 0)
	assert_eq(_cycle_ticks(h, 1, false)["taps"], 0)
