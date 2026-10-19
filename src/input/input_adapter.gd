class_name InputAdapter
extends RefCounted
## InputSource -> PilotCommand, once per physics tick (architecture §6.1, §6.2). The only place that knows
## action names. Pure: no Input, no scene tree, so every curve, ramp and edge rule is unit-tested.

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

## Actions reported as one-tick edges rather than held state.
const EDGE_ACTIONS: Array[StringName] = [
	TOGGLE_ASSIST, WEAPON_NEXT, TARGET_NEXT, TARGET_AHEAD, TOGGLE_CAMERA, RESET_SHIP, PAUSE, TOGGLE_OVERLAY,
	TOGGLE_FALLBACK,
]

const AIM_EXPO := 1.5

var stick_deadzone: float = 0.15
var invert_y: bool = false
var roll_ramp_s: float = 0.25

## The command produced by the most recent sample (console `input` provider, overlay).
var last: PilotCommand = PilotCommand.new()

var _prev_pressed: Dictionary = {}
var _roll: float = 0.0


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
	var aim: Vector2 = source.get_vector(YAW_LEFT, YAW_RIGHT, PITCH_DOWN, PITCH_UP, stick_deadzone)
	var pitch: float = expo_curve(aim.y, AIM_EXPO)
	if invert_y:
		pitch = -pitch
	flight.rot = Vector3(pitch, expo_curve(aim.x, AIM_EXPO), _step_roll(source, dt))
	flight.brake = source.is_pressed(BRAKE)

	var edges: Dictionary = _sample_edges(source)
	flight.toggle_assist = edges[TOGGLE_ASSIST]

	cmd.combat.fire = source.is_pressed(FIRE)
	cmd.combat.weapon_next = edges[WEAPON_NEXT]
	cmd.combat.target_next = edges[TARGET_NEXT]
	cmd.combat.target_ahead = edges[TARGET_AHEAD]

	cmd.ui.toggle_camera = edges[TOGGLE_CAMERA]
	cmd.ui.reset = edges[RESET_SHIP]
	cmd.ui.pause = edges[PAUSE]
	cmd.ui.toggle_overlay = edges[TOGGLE_OVERLAY]
	cmd.ui.toggle_fallback_mesh = edges[TOGGLE_FALLBACK]

	last = cmd
	return cmd


## Re-seed edge state from what is held now, so nothing fires on a transition such as the console opening or
## closing (which masks or unmasks the keyboard while a key may still be down).
func resync_edges(source: InputSource) -> void:
	for action: StringName in EDGE_ACTIONS:
		_prev_pressed[action] = source.is_pressed(action)


## Forget held state and the roll ramp (respawn, scene change).
func reset() -> void:
	_prev_pressed.clear()
	_roll = 0.0


func _sample_edges(source: InputSource) -> Dictionary:
	var edges: Dictionary = {}
	for action: StringName in EDGE_ACTIONS:
		var pressed: bool = source.is_pressed(action)
		edges[action] = pressed and not bool(_prev_pressed.get(action, false))
		_prev_pressed[action] = pressed
	return edges


# Digital roll ramps toward ±1 over roll_ramp_s, snaps to 0 on release, restarts from 0 on reversal, so taps
# give fine corrections from a D-pad.
func _step_roll(source: InputSource, dt: float) -> float:
	var direction: float = 0.0
	if source.is_pressed(ROLL_RIGHT):
		direction += 1.0
	if source.is_pressed(ROLL_LEFT):
		direction -= 1.0
	if direction == 0.0:
		_roll = 0.0
	else:
		if _roll != 0.0 and signf(_roll) != direction:
			_roll = 0.0
		_roll = move_toward(_roll, direction, dt / maxf(roll_ramp_s, 0.001))
	return _roll
