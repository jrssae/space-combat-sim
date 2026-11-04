class_name ControlLock
extends RefCounted
## Takes the ship out of the player's hands (architecture §18 D55, M5-T08): while a cinematic plays or a mission holds the controls
## (`MissionApi.lock_controls`), `Main` passes each tick's command through `apply`, which zeroes its flight and combat parts. The
## ship keeps flying on its own momentum and its assist stays as it was. No wing order goes out (keys 1-4, the comms menu of D54);
## the rest of the UI part is left alone, so the overlay, a screenshot or (with no shot) the pause menu still work.
##
## During a shot, Start or a fresh press of A (fire) asks to skip it. A held since before the shot does not count until it has been
## let go, and the A that skipped does not fire when the controls come back until it is released.

# A has been up since the shot began, so pressing it now is meant as a skip.
var _skip_armed: bool = false
# The A that skipped is still held: it must not fire.
var _hold_fire: bool = false


## Filters `pc` in place for this tick. `held`: the mission holds the controls; `shot_playing`: a cinematic is on screen. Returns
## true when the player asked to skip the shot.
func apply(pc: PilotCommand, held: bool, shot_playing: bool) -> bool:
	var fire_down: bool = pc.combat.fire
	var skip: bool = false
	if shot_playing:
		skip = pc.ui.pause or (fire_down and _skip_armed)
		if not fire_down:
			_skip_armed = true
		if skip:
			_skip_armed = false  # the next shot may start this tick: the same press must not skip it too
			_hold_fire = fire_down
		pc.ui.pause = false  # Start skips the shot rather than opening the pause menu
		pc.ui.toggle_camera = false
	else:
		_skip_armed = false
	if _hold_fire:
		if fire_down:
			pc.combat.fire = false
		else:
			_hold_fire = false
	if held or shot_playing:
		pc.flight = FlightCommand.new()
		pc.combat = CombatCommand.new()
		# The wing orders wait too (keys 1-4 and the comms menu, which `Main` closes).
		pc.ui.comms_open = false
		pc.ui.comms_pick = -1
		pc.ui.wing_attack = false
		pc.ui.wing_form = false
		pc.ui.wing_engage = false
		pc.ui.wing_cover = false
	return skip
