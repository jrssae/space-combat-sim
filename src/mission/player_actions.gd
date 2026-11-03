class_name PlayerActions
extends RefCounted
## What the player did in one physics tick, as action names (architecture §18 D52): read from the `PilotCommand` that `Main`
## already samples each tick, never from `Input`. Edges (assist, next target, wing orders...) count on their tick; held controls
## (a pod, a stick past half way, fire, brake) count on every tick they are held. The `input_performed` trigger and M8's
## per-control tutorial checks read this set.

## A stick or trigger counts as used past this deflection.
const ANALOG_THRESHOLD: float = 0.5

## Every name `from_command` can report (the `InputAdapter` action names).
const NAMES: Array[StringName] = [
	InputAdapter.MAIN_LEFT, InputAdapter.MAIN_RIGHT, InputAdapter.RETRO_LEFT, InputAdapter.RETRO_RIGHT,
	InputAdapter.PITCH_UP, InputAdapter.PITCH_DOWN, InputAdapter.YAW_LEFT, InputAdapter.YAW_RIGHT,
	InputAdapter.ROLL_LEFT, InputAdapter.ROLL_RIGHT, InputAdapter.STRAFE_LEFT, InputAdapter.STRAFE_RIGHT,
	InputAdapter.STRAFE_UP, InputAdapter.STRAFE_DOWN, InputAdapter.BRAKE, InputAdapter.FIRE, InputAdapter.TOGGLE_ASSIST,
	InputAdapter.AUTOTRACK, InputAdapter.WEAPON_NEXT, InputAdapter.TARGET_NEXT, InputAdapter.TARGET_PREV,
	InputAdapter.TARGET_AHEAD, InputAdapter.TOGGLE_CAMERA, InputAdapter.CAMERA_LOOK, InputAdapter.RESET_SHIP,
	InputAdapter.PAUSE, InputAdapter.WING_ATTACK, InputAdapter.WING_FORM, InputAdapter.WING_ENGAGE, InputAdapter.WING_COVER,
	InputAdapter.TOGGLE_RUNNING_LIGHTS,
]


## The actions in `pc`, as a set (name -> true).
static func from_command(pc: PilotCommand) -> Dictionary:
	var out: Dictionary = {}
	if pc == null:
		return out
	var f: FlightCommand = pc.flight
	_analog(out, f.main_left, InputAdapter.MAIN_LEFT, &"")
	_analog(out, f.main_right, InputAdapter.MAIN_RIGHT, &"")
	_analog(out, f.retro_left, InputAdapter.RETRO_LEFT, &"")
	_analog(out, f.retro_right, InputAdapter.RETRO_RIGHT, &"")
	_analog(out, f.rot.x, InputAdapter.PITCH_UP, InputAdapter.PITCH_DOWN)
	_analog(out, f.rot.y, InputAdapter.YAW_RIGHT, InputAdapter.YAW_LEFT)
	_analog(out, f.rot.z, InputAdapter.ROLL_RIGHT, InputAdapter.ROLL_LEFT)
	_analog(out, f.strafe.x, InputAdapter.STRAFE_RIGHT, InputAdapter.STRAFE_LEFT)
	_analog(out, f.strafe.y, InputAdapter.STRAFE_UP, InputAdapter.STRAFE_DOWN)
	_flag(out, f.brake, InputAdapter.BRAKE)
	_flag(out, f.toggle_assist, InputAdapter.TOGGLE_ASSIST)
	_flag(out, f.autotrack, InputAdapter.AUTOTRACK)
	var c: CombatCommand = pc.combat
	_flag(out, c.fire, InputAdapter.FIRE)
	_flag(out, c.weapon_next, InputAdapter.WEAPON_NEXT)
	_flag(out, c.target_next, InputAdapter.TARGET_NEXT)
	_flag(out, c.target_prev, InputAdapter.TARGET_PREV)
	_flag(out, c.target_ahead, InputAdapter.TARGET_AHEAD)
	var u: UiCommand = pc.ui
	_flag(out, u.toggle_camera, InputAdapter.TOGGLE_CAMERA)
	_flag(out, u.look_active, InputAdapter.CAMERA_LOOK)
	_flag(out, u.reset, InputAdapter.RESET_SHIP)
	_flag(out, u.pause, InputAdapter.PAUSE)
	_flag(out, u.wing_attack, InputAdapter.WING_ATTACK)
	_flag(out, u.wing_form, InputAdapter.WING_FORM)
	_flag(out, u.wing_engage, InputAdapter.WING_ENGAGE)
	_flag(out, u.wing_cover, InputAdapter.WING_COVER)
	_flag(out, u.toggle_running_lights, InputAdapter.TOGGLE_RUNNING_LIGHTS)
	return out


# One axis: past the threshold one way is `positive`, the other way `negative` (&"" for a one-way control).
static func _analog(out: Dictionary, value: float, positive: StringName, negative: StringName) -> void:
	if value > ANALOG_THRESHOLD:
		out[positive] = true
	elif value < -ANALOG_THRESHOLD and negative != &"":
		out[negative] = true


static func _flag(out: Dictionary, on: bool, action: StringName) -> void:
	if on:
		out[action] = true
