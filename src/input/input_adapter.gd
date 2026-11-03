class_name InputAdapter
extends RefCounted
## InputSource -> PilotCommand, once per physics tick (architecture §6.1, §6.2). The only place that knows
## action names. Pure: no Input, no scene tree, so every curve, ramp and edge rule is unit-tested.
##
## Layout (§6.1, M3-T15): the right stick flies three axes by direction, read as one vector with a radial deadzone and
## expo: straight up or down pitches, straight left or right yaws, the four diagonals roll toward the side the stick leans
## (`split_stick`). The roll keys (Caps Lock, G) add to its roll. B on the pad is tap = next target, hold = previous target
## (`target_cycle`, as the mouse wheel); B on the keyboard and Mouse 2 are tap = next target, hold = target nearest the
## nose (`target_next`). D-pad Up toggles flight assist. The mouse is pitch (Y) and yaw (X): its speed, smoothed over a few
## ticks, is the rate command. Holding
## `camera_look` (L3, the middle mouse button) sends the right stick and the mouse to the camera instead
## (`UiCommand.look_*`); the ship ignores them.
##
## The keyboard (layout B) is all under the left hand because the right hand flies the mouse: this class sees only action
## names, so which key drives which action is project.godot's and the control profile's business. Two keys drive a pair
## of actions at once (W = both main pods, S = both retro pods), which needs nothing here: each pod reads its own action.
## The mouse side buttons are bound like any other (Mouse 4 `autotrack`, Mouse 5 `weapon_next`). Keys 1-4 are the wing orders
## (attack my target, form on me, engage at will, cover me; M3-T07), press edges in `UiCommand` for `Main` to pass on. D-pad Left
## and key 5 switch the running lights (M3-T27).

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
## The pad's tap-or-hold target button (B): tap = next, hold = previous.
const TARGET_CYCLE := &"target_cycle"
const AUTOTRACK := &"autotrack"
const CAMERA_LOOK := &"camera_look"
const SCREENSHOT := &"screenshot"
const WING_ATTACK := &"wing_attack"
const WING_FORM := &"wing_form"
const WING_ENGAGE := &"wing_engage"
const WING_COVER := &"wing_cover"
const TOGGLE_RUNNING_LIGHTS := &"toggle_running_lights"

## Every action the game reads; project.godot must declare each one (tests/unit/test_input_map.gd).
const ACTIONS: Array[StringName] = [
	MAIN_RIGHT, MAIN_LEFT, RETRO_RIGHT, RETRO_LEFT, PITCH_DOWN, PITCH_UP, YAW_LEFT, YAW_RIGHT,
	STRAFE_LEFT, STRAFE_RIGHT, STRAFE_DOWN, STRAFE_UP, ROLL_LEFT, ROLL_RIGHT, TARGET_NEXT, WEAPON_NEXT,
	TARGET_AHEAD, FIRE, TOGGLE_ASSIST, BRAKE, TOGGLE_CAMERA, RESET_SHIP, PAUSE, TOGGLE_OVERLAY, TOGGLE_FALLBACK,
	TARGET_PREV, AUTOTRACK, CAMERA_LOOK, SCREENSHOT, WING_ATTACK, WING_FORM, WING_ENGAGE, WING_COVER, TARGET_CYCLE,
	TOGGLE_RUNNING_LIGHTS,
]

## Actions reported as one-tick edges on press rather than held state. `TARGET_NEXT` and `TARGET_CYCLE` are not among
## them: they are the tap-or-hold buttons (see `target_hold_s`).
const EDGE_ACTIONS: Array[StringName] = [
	TOGGLE_ASSIST, WEAPON_NEXT, TARGET_AHEAD, TOGGLE_CAMERA, RESET_SHIP, PAUSE, TOGGLE_OVERLAY, TOGGLE_FALLBACK,
	TARGET_PREV, SCREENSHOT, AUTOTRACK, WING_ATTACK, WING_FORM, WING_ENGAGE, WING_COVER, TOGGLE_RUNNING_LIGHTS,
]

const AIM_EXPO := 1.5
## Default for `mouse_full_rate_px_s` (`Settings.mouse_full_rate_px_s`).
const MOUSE_FULL_RATE_PX_S := 1200.0
## Share of the gap to the mouse's current speed that the smoothed rate closes each tick.
const MOUSE_SMOOTHING := 0.4
## Half-width of the right stick's pitch and yaw sectors, degrees from straight up/down and left/right; the diagonals
## between them roll (`split_stick`).
const STICK_SECTOR_HALF_DEG := 22.5
## The tap-or-hold buttons and what their tap and hold give.
const TAP_HOLD: Dictionary = {TARGET_NEXT: [TARGET_NEXT, TARGET_AHEAD], TARGET_CYCLE: [TARGET_NEXT, TARGET_PREV]}
## Default for `target_hold_s` (`Settings.target_hold_s`).
const TARGET_HOLD_S := 0.35
# Slack for comparing accumulated tick times with the hold threshold (21 × 1/60 s must reach 0.35 s).
const _HOLD_EPS := 1e-6

var stick_deadzone: float = 0.15
var invert_y: bool = false
## `target_next` (keyboard B, Mouse 2) and `target_cycle` (pad B) are tap-or-hold buttons, on separate timers: released
## sooner than this they give `target_next` on the release; held this long they give their hold action once, as the
## threshold is crossed (`target_ahead` and `target_prev`), and the release then gives nothing, so a hold never also
## cycles and never repeats (`Settings.target_hold_s`).
var target_hold_s: float = TARGET_HOLD_S
## Mouse speed, pixels per second, that commands the full turn rate (`Settings.mouse_full_rate_px_s`).
var mouse_full_rate_px_s: float = MOUSE_FULL_RATE_PX_S

## The command produced by the most recent sample (console `input` provider, overlay).
var last: PilotCommand = PilotCommand.new()

## Auto-track is switched on (toggled by the `autotrack` action). Main clears it when the target is gone.
var autotrack_on: bool = false

var _prev_pressed: Dictionary = {}
## The mouse's turn command, -1..1 per axis (x yaw right, y pitch up), after smoothing.
var _mouse_rate: Vector2 = Vector2.ZERO
## Per tap-or-hold button: how long it has been down in the current press (s), and whether the press is armed (from the
## press until it fires: tap on release, or hold at the threshold).
var _held_s: Dictionary = {TARGET_NEXT: 0.0, TARGET_CYCLE: 0.0}
var _armed: Dictionary = {TARGET_NEXT: false, TARGET_CYCLE: false}


static func expo_curve(x: float, exponent: float) -> float:
	return signf(x) * pow(absf(x), exponent)


## The right stick (`v`, after the radial deadzone, length 0..1) as `(pitch, yaw, roll)`: one axis at a time, at the stick's
## deflection after expo, chosen by direction. Within `STICK_SECTOR_HALF_DEG` of straight up or down it pitches (+ up),
## within it of straight left or right it yaws (+ right), and on the diagonals between it rolls toward the side the stick
## leans (+ right).
static func split_stick(v: Vector2) -> Vector3:
	var length: float = v.length()
	if length <= 0.0:
		return Vector3.ZERO
	var m: float = expo_curve(minf(length, 1.0), AIM_EXPO)
	var from_vertical_deg: float = rad_to_deg(atan2(absf(v.x), absf(v.y)))
	if from_vertical_deg <= STICK_SECTOR_HALF_DEG:
		return Vector3(signf(v.y) * m, 0.0, 0.0)
	if from_vertical_deg >= 90.0 - STICK_SECTOR_HALF_DEG:
		return Vector3(0.0, signf(v.x) * m, 0.0)
	return Vector3(0.0, 0.0, signf(v.x) * m)


func sample(source: InputSource, dt: float) -> PilotCommand:
	source.poll(dt)
	var cmd := PilotCommand.new()

	var flight: FlightCommand = cmd.flight
	flight.main_right = source.get_trigger(MAIN_RIGHT)
	flight.main_left = source.get_trigger(MAIN_LEFT)
	flight.retro_right = 1.0 if source.is_pressed(RETRO_RIGHT) else 0.0
	flight.retro_left = 1.0 if source.is_pressed(RETRO_LEFT) else 0.0
	flight.strafe = source.get_vector(STRAFE_LEFT, STRAFE_RIGHT, STRAFE_DOWN, STRAFE_UP, stick_deadzone)
	# Right stick: x yaw, y pitch, one radial deadzone over the pair, then split by direction (pitch, yaw or roll).
	var aim: Vector2 = source.get_vector(YAW_LEFT, YAW_RIGHT, PITCH_DOWN, PITCH_UP, stick_deadzone)
	var mouse_px: Vector2 = source.take_mouse_delta()
	var looking: bool = source.is_pressed(CAMERA_LOOK)
	var mouse_turn: Vector2 = _step_mouse(mouse_px, dt, looking)
	var stick: Vector3 = split_stick(aim)
	if looking:
		# The right stick and the mouse belong to the camera; the ship keeps flying as it was.
		stick = Vector3.ZERO
	var pitch: float = -stick.x if invert_y else stick.x
	var mouse_pitch: float = -mouse_turn.y if invert_y else mouse_turn.y
	var key_roll: float = (1.0 if source.is_pressed(ROLL_RIGHT) else 0.0) - (1.0 if source.is_pressed(ROLL_LEFT) else 0.0)
	flight.rot = Vector3(clampf(pitch + mouse_pitch, -1.0, 1.0), clampf(stick.y + mouse_turn.x, -1.0, 1.0),
			clampf(stick.z + key_roll, -1.0, 1.0))
	flight.brake = source.is_pressed(BRAKE)

	var edges: Dictionary = _sample_edges(source)
	flight.toggle_assist = edges[TOGGLE_ASSIST]
	# Auto-track is a toggle: one press switches it on, the next switches it off.
	if edges[AUTOTRACK]:
		autotrack_on = not autotrack_on
	flight.autotrack = autotrack_on

	cmd.combat.fire = source.is_pressed(FIRE)
	cmd.combat.weapon_next = edges[WEAPON_NEXT]
	var select: Dictionary = _step_tap_hold(source, TARGET_NEXT, dt)
	var cycle: Dictionary = _step_tap_hold(source, TARGET_CYCLE, dt)
	var wheel: int = source.take_wheel_steps()
	cmd.combat.target_next = select[TARGET_NEXT] or cycle[TARGET_NEXT] or wheel > 0
	cmd.combat.target_prev = edges[TARGET_PREV] or cycle[TARGET_PREV] or wheel < 0
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
	cmd.ui.toggle_running_lights = edges[TOGGLE_RUNNING_LIGHTS]
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
	for button: StringName in TAP_HOLD:
		_prev_pressed[button] = source.is_pressed(button)
		_disarm(button)


## One tick while a menu has the pad (the pause menu): only the pause edge is read, so Start or Esc can close the menu. Every other
## button is re-seeded from what is held, so none that moves the menu acts behind it, or fires when it closes. The mouse and the wheel
## are drained like any tick.
func sample_menu(source: InputSource, dt: float) -> UiCommand:
	source.poll(dt)
	var cmd := PilotCommand.new()
	cmd.ui.pause = source.is_pressed(PAUSE) and not bool(_prev_pressed.get(PAUSE, false))
	source.take_mouse_delta()
	source.take_wheel_steps()
	_mouse_rate = Vector2.ZERO
	resync_edges(source)
	last = cmd
	return cmd.ui


## Forget held state and any tap-or-hold press in progress (respawn, scene change).
func reset() -> void:
	_prev_pressed.clear()
	_mouse_rate = Vector2.ZERO
	autotrack_on = false
	for button: StringName in TAP_HOLD:
		_disarm(button)


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


# A tap-or-hold button (`TAP_HOLD`): {its tap action: bool, its hold action: bool}, each true for at most one tick per
# press. The held time counts every tick the button is seen down, the press tick included.
func _step_tap_hold(source: InputSource, button: StringName, dt: float) -> Dictionary:
	var tap: StringName = TAP_HOLD[button][0]
	var hold: StringName = TAP_HOLD[button][1]
	var out: Dictionary = {tap: false, hold: false}
	var pressed: bool = source.is_pressed(button)
	var was_pressed: bool = bool(_prev_pressed.get(button, false))
	_prev_pressed[button] = pressed
	if pressed and not was_pressed:
		_armed[button] = true
		_held_s[button] = 0.0
	if pressed and bool(_armed[button]):
		_held_s[button] = float(_held_s[button]) + dt
		if float(_held_s[button]) >= target_hold_s - _HOLD_EPS:
			out[hold] = true
			_disarm(button)
	elif not pressed and bool(_armed[button]):
		out[tap] = true
		_disarm(button)
	return out


func _disarm(button: StringName) -> void:
	_armed[button] = false
	_held_s[button] = 0.0
