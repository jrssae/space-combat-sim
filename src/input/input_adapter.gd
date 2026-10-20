class_name InputAdapter
extends RefCounted
## InputSource -> PilotCommand, once per physics tick (architecture §6.1, §6.2). The only place that knows
## action names. Pure: no Input, no scene tree, so every curve, ramp and edge rule is unit-tested.
##
## Layout (§6.1): the right stick is pitch (Y) and roll (X), analog with a radial deadzone and expo; the D-pad
## Left/Right is yaw, digital with a ramp; D-pad Up is tap = next target, hold = target nearest the nose.

const MAIN_RIGHT := &"main_right"
const MAIN_LEFT := &"main_left"
const RETRO_RIGHT := &"retro_right"
const RETRO_LEFT := &"retro_left"
const PITCH_DOWN := &"pitch_down"
const PITCH_UP := &"pitch_up"
const YAW_LEFT := &"yaw_left"
const YAW_RIGHT := &"yaw_right"
const STRAFE_LEFT := &"strafe_left"
const STRAFE_RIGHT := &"strafe_right"
const STRAFE_DOWN := &"strafe_down"
const STRAFE_UP := &"strafe_up"
const ROLL_LEFT := &"roll_left"
const ROLL_RIGHT := &"roll_right"
const TARGET_NEXT := &"target_next"
const WEAPON_NEXT := &"weapon_next"
const TARGET_AHEAD := &"target_ahead"
const FIRE := &"fire"
const TOGGLE_ASSIST := &"toggle_flight_assist"
const BRAKE := &"brake"
const TOGGLE_CAMERA := &"toggle_camera"
const RESET_SHIP := &"reset_ship"
const PAUSE := &"pause"
const TOGGLE_OVERLAY := &"debug_toggle_overlay"
const TOGGLE_FALLBACK := &"debug_toggle_fallback_mesh"

## Every action the game reads; project.godot must declare each one (tests/unit/test_input_map.gd).
const ACTIONS: Array[StringName] = [
	MAIN_RIGHT, MAIN_LEFT, RETRO_RIGHT, RETRO_LEFT, PITCH_DOWN, PITCH_UP, YAW_LEFT, YAW_RIGHT,
	STRAFE_LEFT, STRAFE_RIGHT, STRAFE_DOWN, STRAFE_UP, ROLL_LEFT, ROLL_RIGHT, TARGET_NEXT, WEAPON_NEXT,
	TARGET_AHEAD, FIRE, TOGGLE_ASSIST, BRAKE, TOGGLE_CAMERA, RESET_SHIP, PAUSE, TOGGLE_OVERLAY, TOGGLE_FALLBACK,
]

## Actions reported as one-tick edges on press rather than held state. `TARGET_NEXT` is not one of them: it is
## the tap-or-hold button (see `target_hold_s`).
const EDGE_ACTIONS: Array[StringName] = [
	TOGGLE_ASSIST, WEAPON_NEXT, TARGET_AHEAD, TOGGLE_CAMERA, RESET_SHIP, PAUSE, TOGGLE_OVERLAY, TOGGLE_FALLBACK,
]

const AIM_EXPO := 1.5
## Default for `target_hold_s` (`Settings.target_hold_s`).
const TARGET_HOLD_S := 0.35
# Slack for comparing accumulated tick times with the hold threshold (21 × 1/60 s must reach 0.35 s).
const _HOLD_EPS := 1e-6

var stick_deadzone: float = 0.15
var invert_y: bool = false
## Seconds for a held D-pad yaw to ramp from 0 to full (`Settings.yaw_ramp_s`).
var yaw_ramp_s: float = 0.25
## `target_next` (D-pad Up, T) is a tap-or-hold button: released sooner than this it gives `target_next` on the
## release; held this long it gives `target_ahead` once, as the threshold is crossed, and its release then gives
## nothing, so a hold never also cycles (`Settings.target_hold_s`).
var target_hold_s: float = TARGET_HOLD_S

## The command produced by the most recent sample (console `input` provider, overlay).
var last: PilotCommand = PilotCommand.new()

var _prev_pressed: Dictionary = {}
var _yaw: float = 0.0
## How long the tap-or-hold button has been down in the current press, s.
var _select_held_s: float = 0.0
## True from the press of the tap-or-hold button until it fires (tap on release, or hold at the threshold).
var _select_armed: bool = false


static func expo_curve(x: float, exponent: float) -> float:
	return signf(x) * pow(absf(x), exponent)


func sample(source: InputSource, dt: float) -> PilotCommand:
	source.poll(dt)
	var cmd := PilotCommand.new()

	var flight: FlightCommand = cmd.flight
	flight.main_right = source.get_trigger(MAIN_RIGHT)
	flight.main_left = source.get_trigger(MAIN_LEFT)
	flight.retro_right = 1.0 if source.is_pressed(RETRO_RIGHT) else 0.0
	flight.retro_left = 1.0 if source.is_pressed(RETRO_LEFT) else 0.0
	flight.strafe = source.get_vector(STRAFE_LEFT, STRAFE_RIGHT, STRAFE_DOWN, STRAFE_UP, stick_deadzone)
	# Right stick: x roll, y pitch, one radial deadzone over the pair, expo on both.
	var aim: Vector2 = source.get_vector(ROLL_LEFT, ROLL_RIGHT, PITCH_DOWN, PITCH_UP, stick_deadzone)
	var pitch: float = expo_curve(aim.y, AIM_EXPO)
	if invert_y:
		pitch = -pitch
	flight.rot = Vector3(pitch, _step_yaw(source, dt), expo_curve(aim.x, AIM_EXPO))
	flight.brake = source.is_pressed(BRAKE)

	var edges: Dictionary = _sample_edges(source)
	flight.toggle_assist = edges[TOGGLE_ASSIST]

	cmd.combat.fire = source.is_pressed(FIRE)
	cmd.combat.weapon_next = edges[WEAPON_NEXT]
	var select: Dictionary = _step_target_select(source, dt)
	cmd.combat.target_next = select[TARGET_NEXT]
	cmd.combat.target_ahead = edges[TARGET_AHEAD] or select[TARGET_AHEAD]

	cmd.ui.toggle_camera = edges[TOGGLE_CAMERA]
	cmd.ui.reset = edges[RESET_SHIP]
	cmd.ui.pause = edges[PAUSE]
	cmd.ui.toggle_overlay = edges[TOGGLE_OVERLAY]
	cmd.ui.toggle_fallback_mesh = edges[TOGGLE_FALLBACK]

	last = cmd
	return cmd


## Re-seed edge state from what is held now, so nothing fires on a transition such as the console opening or
## closing (which masks or unmasks the keyboard while a key may still be down). A tap-or-hold press in progress is
## dropped: neither its release nor its hold fires.
func resync_edges(source: InputSource) -> void:
	for action: StringName in EDGE_ACTIONS:
		_prev_pressed[action] = source.is_pressed(action)
	_prev_pressed[TARGET_NEXT] = source.is_pressed(TARGET_NEXT)
	_disarm_select()


## Forget held state, the yaw ramp and any tap-or-hold press in progress (respawn, scene change).
func reset() -> void:
	_prev_pressed.clear()
	_yaw = 0.0
	_disarm_select()


func _sample_edges(source: InputSource) -> Dictionary:
	var edges: Dictionary = {}
	for action: StringName in EDGE_ACTIONS:
		var pressed: bool = source.is_pressed(action)
		edges[action] = pressed and not bool(_prev_pressed.get(action, false))
		_prev_pressed[action] = pressed
	return edges


# Digital yaw ramps toward ±1 over yaw_ramp_s, snaps to 0 on release, restarts from 0 on reversal, so taps
# give fine corrections from a D-pad.
func _step_yaw(source: InputSource, dt: float) -> float:
	var direction: float = 0.0
	if source.is_pressed(YAW_RIGHT):
		direction += 1.0
	if source.is_pressed(YAW_LEFT):
		direction -= 1.0
	if direction == 0.0:
		_yaw = 0.0
	else:
		if _yaw != 0.0 and signf(_yaw) != direction:
			_yaw = 0.0
		_yaw = move_toward(_yaw, direction, dt / maxf(yaw_ramp_s, 0.001))
	return _yaw


# The tap-or-hold button: {TARGET_NEXT: bool, TARGET_AHEAD: bool}, each true for at most one tick per press.
# The held time counts every tick the button is seen down, the press tick included.
func _step_target_select(source: InputSource, dt: float) -> Dictionary:
	var out: Dictionary = {TARGET_NEXT: false, TARGET_AHEAD: false}
	var pressed: bool = source.is_pressed(TARGET_NEXT)
	var was_pressed: bool = bool(_prev_pressed.get(TARGET_NEXT, false))
	_prev_pressed[TARGET_NEXT] = pressed
	if pressed and not was_pressed:
		_select_armed = true
		_select_held_s = 0.0
	if pressed and _select_armed:
		_select_held_s += dt
		if _select_held_s >= target_hold_s - _HOLD_EPS:
			out[TARGET_AHEAD] = true
			_disarm_select()
	elif not pressed and _select_armed:
		out[TARGET_NEXT] = true
		_disarm_select()
	return out


func _disarm_select() -> void:
	_select_armed = false
	_select_held_s = 0.0
