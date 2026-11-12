extends GutTest
## `ControlLock` (architecture §18 D55, M5-T08, AC8): while a cinematic plays or a mission holds the controls, the player's flight
## and combat commands are zeroed; during a shot A (a fresh press of fire) or Start asks to skip it, and the A that skipped
## does not fire once the controls come back.

var lock: ControlLock


func before_each() -> void:
	lock = ControlLock.new()


# One tick's command with the stick, throttle, fire and a few edges set.
func _busy(fire: bool = false, pause: bool = false) -> PilotCommand:
	var pc := PilotCommand.new()
	pc.flight.main_left = 1.0
	pc.flight.main_right = 0.6
	pc.flight.rot = Vector3(0.5, -0.2, 0.1)
	pc.flight.strafe = Vector2(0.3, 0.0)
	pc.flight.brake = true
	pc.flight.toggle_assist = true
	pc.combat.fire = fire
	pc.combat.target_next = true
	pc.combat.target_nearest = true
	pc.ui.target_menu_open = true
	pc.ui.pause = pause
	pc.ui.toggle_camera = true
	pc.ui.toggle_overlay = true
	pc.ui.comms_open = true
	pc.ui.wing_form = true
	return pc


func _assert_zeroed(pc: PilotCommand) -> void:
	assert_eq_deep(pc.flight.to_dict(), FlightCommand.new().to_dict())
	assert_eq_deep(pc.combat.to_dict(), CombatCommand.new().to_dict())


func test_free_controls_pass_untouched() -> void:
	var pc: PilotCommand = _busy(true, true)
	var before: Dictionary = {"flight": pc.flight.to_dict(), "combat": pc.combat.to_dict(), "ui": pc.ui.to_dict()}
	assert_false(lock.apply(pc, false, false))
	assert_eq_deep({"flight": pc.flight.to_dict(), "combat": pc.combat.to_dict(), "ui": pc.ui.to_dict()}, before)


func test_held_controls_zero_flight_and_combat_but_keep_the_ui() -> void:
	var pc: PilotCommand = _busy(true, true)
	assert_false(lock.apply(pc, true, false), "no shot: nothing to skip")
	_assert_zeroed(pc)
	assert_true(pc.ui.pause, "Start still opens the pause menu under lock_controls alone")
	assert_true(pc.ui.toggle_camera, "and the camera still switches")
	assert_false(pc.ui.comms_open, "the comms menu does not open")
	assert_false(pc.ui.target_menu_open, "nor the target menu (M5-T25)")
	assert_false(pc.combat.target_nearest, "and a tap targets nothing")
	assert_false(pc.ui.wing_form, "and keys 1-4 wait")


func test_a_shot_zeroes_the_commands_even_without_the_lock() -> void:
	var pc: PilotCommand = _busy()
	lock.apply(pc, false, true)
	_assert_zeroed(pc)
	assert_false(pc.ui.toggle_camera, "the shot owns the camera")
	assert_false(pc.ui.comms_open, "no comms menu over a shot")
	assert_true(pc.ui.toggle_overlay, "the debug keys still work")


func test_start_skips_the_shot_instead_of_pausing() -> void:
	lock.apply(_busy(), false, true)
	var pc: PilotCommand = _busy(false, true)
	assert_true(lock.apply(pc, false, true))
	assert_false(pc.ui.pause, "the pause menu does not open")


func test_a_fresh_press_of_a_skips_the_shot() -> void:
	assert_false(lock.apply(_busy(false), false, true))
	assert_false(lock.apply(_busy(false), false, true))
	assert_true(lock.apply(_busy(true), false, true), "A went down during the shot")


func test_a_held_since_before_the_shot_does_not_skip_it_until_pressed_again() -> void:
	assert_false(lock.apply(_busy(true), false, false), "firing before the shot")
	for _i: int in 5:
		assert_false(lock.apply(_busy(true), false, true), "still the same press")
	assert_false(lock.apply(_busy(false), false, true), "released")
	assert_true(lock.apply(_busy(true), false, true), "pressed again")


func test_the_a_that_skipped_does_not_fire_until_released() -> void:
	lock.apply(_busy(false), false, true)
	assert_true(lock.apply(_busy(true), false, true))
	for _i: int in 3:
		var held: PilotCommand = _busy(true)
		assert_false(lock.apply(held, false, false))
		assert_false(held.combat.fire, "still the skip press")
		assert_eq(held.flight.main_left, 1.0, "the rest of the controls are back")
	lock.apply(_busy(false), false, false)
	var pressed: PilotCommand = _busy(true)
	lock.apply(pressed, false, false)
	assert_true(pressed.combat.fire, "a new press fires")


func test_a_shot_ended_by_start_leaves_fire_alone() -> void:
	lock.apply(_busy(false), false, true)
	assert_true(lock.apply(_busy(false, true), false, true))
	var pc: PilotCommand = _busy(true)
	lock.apply(pc, false, false)
	assert_true(pc.combat.fire)


func test_one_held_a_skips_one_shot_even_when_the_next_starts_at_once() -> void:
	lock.apply(_busy(false), false, true)
	assert_true(lock.apply(_busy(true), false, true), "A skips shot a")
	for _i: int in 5:
		assert_false(lock.apply(_busy(true), false, true), "shot b started in the same tick: the held A does not skip it")
	assert_false(lock.apply(_busy(false), false, true), "released")
	assert_true(lock.apply(_busy(true), false, true), "pressed again: b is skipped")


func test_start_skips_one_shot_per_press() -> void:
	lock.apply(_busy(), false, true)
	assert_true(lock.apply(_busy(false, true), false, true), "Start skips shot a")
	assert_false(lock.apply(_busy(false, false), false, true), "shot b plays on: Start is an edge")
	assert_true(lock.apply(_busy(false, true), false, true), "the next press skips b")
