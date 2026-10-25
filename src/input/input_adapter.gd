class_name InputAdapter
extends RefCounted
## InputSource -> PilotCommand, once per physics tick (architecture §6.1, §6.2). The only place that knows
## action names. Pure: no Input, no scene tree, so every curve, ramp and edge rule is unit-tested.
##
## Layout (§6.1): the right stick is pitch (Y) and roll (X), analog with a radial deadzone and expo; the D-pad
## Left/Right is yaw, digital with a ramp; D-pad Up (on the keyboard B, and Mouse 2) is tap = next target, hold = target
## nearest the nose. The mouse is pitch (Y) and yaw (X): its speed, smoothed over a few ticks, is the rate command. Holding
## `camera_look` (L3, the middle mouse button) sends the right stick and the mouse to the camera instead
## (`UiCommand.look_*`); the ship ignores them.
##
## The keyboard (layout B) is all under the left hand because the right hand flies the mouse: this class sees only action
## names, so which key drives which action is project.godot's and the control profile's business. Two keys drive a pair
## of actions at once (W = both main pods, S = both retro pods), which needs nothing here: each pod reads its own action.
## The mouse side buttons are bound like any other (Mouse 4 `autotrack`, Mouse 5 `weapon_next`). Keys 1-4 are the wing orders
## (attack my target, form on me, engage at will, cover me; M3-T07), press edges in `UiCommand` for `Main` to pass on.

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
const TARGET_PREV := &"target_prev"
const AUTOTRACK := &"autotrack"
const CAMERA_LOOK := &"camera_look"
const SCREENSHOT := &"screenshot"
const WING_ATTACK := &"wing_attack"
const WING_FORM := &"wing_form"
const WING_ENGAGE := &"wing_engage"
const WING_COVER := &"wing_cover"

## Every action the game reads; project.godot must declare each one (tests/unit/test_input_map.gd).
const ACTIONS: Array[StringName] = [
	MAIN_RIGHT, MAIN_LEFT, RETRO_RIGHT, RETRO_LEFT, PITCH_DOWN, PITCH_UP, YAW_LEFT, YAW_RIGHT,
	STRAFE_LEFT, STRAFE_RIGHT, STRAFE_DOWN, STRAFE_UP, ROLL_LEFT, ROLL_RIGHT, TARGET_NEXT, WEAPON_NEXT,
	TARGET_AHEAD, FIRE, TOGGLE_ASSIST, BRAKE, TOGGLE_CAMERA, RESET_SHIP, PAUSE, TOGGLE_OVERLAY, TOGGLE_FALLBACK,
	TARGET_PREV, AUTOTRACK, CAMERA_LOOK, SCREENSHOT, WING_ATTACK, WING_FORM, WING_ENGAGE, WING_COVER,
]

## Actions reported as one-tick edges on press rather than held state. `TARGET_NEXT` is not one of them: it is
## the tap-or-hold button (see `target_hold_s`).
const EDGE_ACTIONS: Array[StringName] = [
	TOGGLE_ASSIST, WEAPON_NEXT, TARGET_AHEAD, TOGGLE_CAMERA, RESET_SHIP, PAUSE, TOGGLE_OVERLAY, TOGGLE_FALLBACK,
	TARGET_PREV, SCREENSHOT, AUTOTRACK, WING_ATTACK, WING_FORM, WING_ENGAGE, WING_COVER,
]

const AIM_EXPO := 1.5
## Default for `mouse_full_rate_px_s` (`Settings.mouse_full_rate_px_s`).
const MOUSE_FULL_RATE_PX_S := 1200.0
## Share of the gap to the mouse's current speed that the smoothed rate closes each tick.
const MOUSE_SMOOTHING := 0.4
## Default for `target_hold_s` (`Settings.target_hold_s`).
const TARGET_HOLD_S := 0.35
# Slack for comparing accumulated tick times with the hold threshold (21 × 1/60 s must reach 0.35 s).
const _HOLD_EPS := 1e-6

var stick_deadzone: float = 0.15
var invert_y: bool = false
## Seconds for a held D-pad yaw to ramp from 0 to full (`Settings.yaw_ramp_s`).
var yaw_ramp_s: float = 0.25
## `target_next` (D-pad Up, B, Mouse 2) is a tap-or-hold button: released sooner than this it gives `target_next` on the
## release; held this long it gives `target_ahead` once, as the threshold is crossed, and its release then gives
## nothing, so a hold never also cycles (`Settings.target_hold_s`).
var target_hold_s: float = TARGET_HOLD_S
## Mouse speed, pixels per second, that commands the full turn rate (`Settings.mouse_full_rate_px_s`).
var mouse_full_rate_px_s: float = MOUSE_FULL_RATE_PX_S

## The command produced by the most recent sample (console `input` provider, overlay).
var last: PilotCommand = PilotCommand.new()

## Auto-track is switched on (toggled by the `autotrack` action). Main clears it when the target is gone.
var autotrack_on: bool = false

var _prev_pressed: Dictionary = {}
var _yaw: float = 0.0
## The mouse's turn command, -1..1 per axis (x yaw right, y pitch up), after smoothing.
var _mouse_rate: Vector2 = Vector2.ZERO
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
	var mouse_px: Vector2 = source.take_mouse_delta()
	var looking: bool = source.is_pressed(CAMERA_LOOK)
	var mouse_turn: Vector2 = _step_mouse(mouse_px, dt, looking)
	var pitch: float = expo_curve(aim.y, AIM_EXPO)
	var roll: float = expo_curve(aim.x, AIM_EXPO)
	if looking:
		# The right stick and the mouse belong to the camera; the ship keeps flying as it was.
		pitch = 0.0
		roll = 0.0
	if invert_y:
		pitch = -pitch
	var mouse_pitch: float = -mouse_turn.y if invert_y else mouse_turn.y
	flight.rot = Vector3(clampf(pitch + mouse_pitch, -1.0, 1.0), clampf(_step_yaw(source, dt) + mouse_turn.x, -1.0, 1.0), roll)
	flight.brake = source.is_pressed(BRAKE)

	var edges: Dictionary = _sample_edges(source)
	flight.toggle_assist = edges[TOGGLE_ASSIST]
	# Auto-track is a toggle: one press switches it on, the next switches it off.
	if edges[AUTOTRACK]:
		autotrack_on = not autotrack_on
	flight.autotrack = autotrack_on

	cmd.combat.fire = source.is_pressed(FIRE)
	cmd.combat.weapon_next = edges[WEAPON_NEXT]
	var select: Dictionary = _step_target_select(source, dt)
	var wheel: int = source.take_wheel_steps()
	cmd.combat.target_next = select[TARGET_NEXT] or wheel > 0
	cmd.combat.target_prev = edges[TARGET_PREV] or wheel < 0
	cmd.combat.target_ahead = edges[TARGET_AHEAD] or select[TARGET_AHEAD]

	cmd.ui.toggle_camera = edges[TOGGLE_CAMERA]
	cmd.ui.reset = edges[RESET_SHIP]
	cmd.ui.pause = edges[PAUSE]
	cmd.ui.toggle_overlay = edges[TOGGLE_OVERLAY]
	cmd.ui.toggle_fallback_mesh = edges[TOGGLE_FALLBACK]
	cmd.ui.screenshot = edges[SCREENSHOT]
	cmd.ui.wing_attack = edges[WING_ATTACK]
	cmd.ui.wing_form = edges[WING_FORM]
	cmd.ui.wing_engage = edges[WING_ENGAGE]
	cmd.ui.wing_cover = edges[WING_COVER]
	cmd.ui.look_active = looking
	if looking:
		var look_y: float = -aim.y if not invert_y else aim.y
		cmd.ui.look_stick = Vector2(aim.x, look_y)
		cmd.ui.look_mouse_px = Vector2(mouse_px.x, -mouse_px.y if not invert_y else mouse_px.y)

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
	_mouse_rate = Vector2.ZERO
	autotrack_on = false
	_disarm_select()


func _sample_edges(source: InputSource) -> Dictionary:
	var edges: Dictionary = {}
	for action: StringName in EDGE_ACTIONS:
		var pressed: bool = source.is_pressed(action)
		edges[action] = pressed and not bool(_prev_pressed.get(action, false))
		_prev_pressed[action] = pressed
	return edges


# The mouse as a turn command: its speed (pixels this tick over the tick length) against `mouse_full_rate_px_s`, smoothed
# over a few ticks because mouse events arrive per rendered frame and not per physics tick. x is yaw right; y is pitch up
# (the mouse pulled toward the user = nose up, like a stick pulled back). While the camera has the mouse, the turn
# command eases back to zero.
func _step_mouse(px: Vector2, dt: float, looking: bool) -> Vector2:
	var target := Vector2.ZERO
	if not looking and dt > 0.0:
		target = (px / dt / maxf(mouse_full_rate_px_s, 1.0)).limit_length(1.0)
	_mouse_rate = _mouse_rate.lerp(target, MOUSE_SMOOTHING)
	if _mouse_rate.length_squared() < 1e-6:
		_mouse_rate = Vector2.ZERO
	return _mouse_rate


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
