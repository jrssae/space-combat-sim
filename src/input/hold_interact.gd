class_name HoldInteract
extends RefCounted
## The auto-track button's two jobs (M7-T27): a tap toggles auto-track, a long hold runs the targeted object's interaction (the
## gate's jump; later docking and cargo). Pure: `InputAdapter` steps it once a tick with the button's state.
##
## A press that starts while nothing is offered taps at once, on the press, as auto-track always has. A press that starts while
## an interaction is offered is a tap-or-hold: let go within `tap_s` it taps (on the release), held `hold_s` it fires the
## interaction once (the release then gives nothing), and let go in between it is cancelled. The interaction going away
## mid-hold cancels the hold; a release still within `tap_s` taps.
##
## A press that starts while no interaction is offered but a capital's subsystems can be cycled (`cycle_ok`, M10-T18) is a
## tap-or-hold too, split at `cycle_s`: the tap comes on the release (auto-track waits that long), a hold steps to the next
## subsystem at `cycle_s` and again every `cycle_s` while it stays down, and the release after a step gives nothing.

## Default for `hold_s` (`Settings.interact_hold_s`): the maintainer's "hold X for 2 seconds".
const HOLD_S: float = 2.0
## Default for `cycle_s`: the maintainer's long press of X that picks the next subsystem.
const CYCLE_S: float = 0.5
# Slack for comparing accumulated tick times with a threshold (120 x 1/60 s must reach 2 s).
const _EPS: float = 1e-6

## How long a hold runs before the interaction fires, s.
var hold_s: float = HOLD_S
## Releases sooner than this are taps, s (`InputAdapter.target_hold_s`, so both tap-or-hold buttons split at the same time).
var tap_s: float = InputAdapter.TARGET_HOLD_S

## How long X is held before it steps to the next subsystem, and between repeats, s.
var cycle_s: float = CYCLE_S

## This tick: the button tapped (toggle auto-track), and the hold completed (run the interaction). Each true for one tick.
var tapped: bool = false
var fired: bool = false
## This tick: the hold stepped to the next subsystem (true for one tick per step).
var cycled: bool = false

var _cycling: bool = false
var _steps: int = 0
var _was_pressed: bool = false
var _armed: bool = false
var _held: float = 0.0


## One tick of the button: `pressed` its state now, `offered` whether the selected target offers an interaction now, `cycle_ok`
## whether a long press may step through a capital's subsystems (read at the press, and again at each step).
func step(pressed: bool, offered: bool, dt: float, cycle_ok: bool = false) -> void:
	tapped = false
	fired = false
	cycled = false
	var press_edge: bool = pressed and not _was_pressed
	var release_edge: bool = not pressed and _was_pressed
	_was_pressed = pressed
	if press_edge:
		_held = 0.0
		_steps = 0
		_cycling = cycle_ok and not offered
		_armed = offered or _cycling
		tapped = not _armed
		if not _armed:
			return
	if not _armed:
		return
	if pressed:
		_held += dt
		if _cycling:
			_step_cycle(cycle_ok)
		elif not offered and _held >= tap_s - _EPS:
			_disarm()  # the target stopped offering mid-hold
		elif offered and _held >= hold_s - _EPS:
			fired = true
			_disarm()
	elif release_edge:
		var window: float = cycle_s if _cycling else tap_s
		tapped = _steps == 0 and _held < window - _EPS
		_disarm()


# A subsystem hold: a step each `cycle_s` held, one per tick at most. Losing the capital stops the steps but the press stays
# spent, so its release never toggles auto-track.
func _step_cycle(cycle_ok: bool) -> void:
	if _held < float(_steps + 1) * cycle_s - _EPS:
		return
	_steps += 1
	cycled = cycle_ok


## How far the hold has run, 0..1, once it is past the tap window (0 before, so a tap never flashes the bar).
func progress() -> float:
	if not _armed or _cycling or _held < tap_s - _EPS or hold_s <= 0.0:
		return 0.0
	return clampf(_held / hold_s, 0.0, 1.0)


## Takes the button's state as it is without acting on it, and drops a press in progress (the console opening, a menu closing).
func resync(pressed: bool) -> void:
	_was_pressed = pressed
	_disarm()


## Forgets everything (respawn, scene change).
func reset() -> void:
	_was_pressed = false
	_disarm()
	tapped = false
	fired = false
	cycled = false


func _disarm() -> void:
	_armed = false
	_cycling = false
	_steps = 0
	_held = 0.0
