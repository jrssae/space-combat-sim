class_name ControlCheckSample
extends RefCounted
## What a control check reads in one physics tick (M8 D80): the player's ship as measured, and what the pilot's commands asked
## for. Plain data: `ControlCheckProbe` fills it from the game, tests fill it by hand. Never from `Input`.

## A flight axis counts as in use past this deflection: lower than `PlayerActions.ANALOG_THRESHOLD`, so a gentle mouse or a
## half-pulled trigger still counts and the measured motion decides the pass.
const ANALOG_MIN: float = 0.1
## Command events beyond `PlayerActions.NAMES`: X's completed hold, and the target button's.
const INTERACT: StringName = &"interact"
const TARGET_MENU: StringName = &"target_menu"
const EXTRA_EVENTS: Array[StringName] = [INTERACT, TARGET_MENU]

## The measured state by name (`state`), and what each holds.
const ASSIST: StringName = &"assist"  ## bool: flight assist is on
const CAMERA: StringName = &"camera"  ## String: cockpit, chase or cinematic
const LOOK_DEG: StringName = &"look_deg"  ## float: how far free look has turned the view off the nose
const LIGHTS: StringName = &"lights"  ## bool: the running lights are on
const TRACKING: StringName = &"tracking"  ## bool: auto-track holds the nose on the target
const TARGET: StringName = &"target"  ## int: the selected target's id, 0 for none
const FIRE_MODE: StringName = &"fire_mode"  ## String: alternating or linked
const INTERACTIONS: StringName = &"interactions"  ## int: interactions run so far
const WING_ORDER: StringName = &"wing_order"  ## String: the wing's order word (`AiContext.ORDER_WORDS`)
const WING_ORDERS: StringName = &"wing_orders"  ## int: orders given so far
const TARGET_MENUS: StringName = &"target_menus"  ## int: times the target menu opened
const FIELDS: Array[StringName] = [ASSIST, CAMERA, LOOK_DEG, LIGHTS, TRACKING, TARGET, FIRE_MODE, INTERACTIONS, WING_ORDER,
		WING_ORDERS, TARGET_MENUS]

## The ship's velocity against its rest reference, World frame, m/s.
var velocity: Vector3 = Vector3.ZERO
## The ship's attitude, and its turn rate (World frame, rad/s).
var basis: Basis = Basis.IDENTITY
var angular_velocity: Vector3 = Vector3.ZERO
## `FIELDS` -> value.
var state: Dictionary = {}
## The command events of this tick, as a set (name -> true): `PlayerActions.NAMES` and `EXTRA_EVENTS`.
var events: Dictionary = {}


## Every event name a check may watch.
static func event_names() -> Array[StringName]:
	var out: Array[StringName] = PlayerActions.NAMES.duplicate()
	out.append_array(EXTRA_EVENTS)
	return out


## The events in `pc`: `PlayerActions`' set, the flight axes from `ANALOG_MIN` up, and the two holds.
static func events_of(pc: PilotCommand) -> Dictionary:
	var out: Dictionary = PlayerActions.from_command(pc)
	if pc == null:
		return out
	var f: FlightCommand = pc.flight
	_axis(out, f.main_left, InputAdapter.MAIN_LEFT, &"")
	_axis(out, f.main_right, InputAdapter.MAIN_RIGHT, &"")
	_axis(out, f.retro_left, InputAdapter.RETRO_LEFT, &"")
	_axis(out, f.retro_right, InputAdapter.RETRO_RIGHT, &"")
	_axis(out, f.rot.x, InputAdapter.PITCH_UP, InputAdapter.PITCH_DOWN)
	_axis(out, f.rot.y, InputAdapter.YAW_RIGHT, InputAdapter.YAW_LEFT)
	_axis(out, f.rot.z, InputAdapter.ROLL_RIGHT, InputAdapter.ROLL_LEFT)
	_axis(out, f.strafe.x, InputAdapter.STRAFE_RIGHT, InputAdapter.STRAFE_LEFT)
	_axis(out, f.strafe.y, InputAdapter.STRAFE_UP, InputAdapter.STRAFE_DOWN)
	if pc.ui.interact:
		out[INTERACT] = true
	if pc.ui.target_menu_open:
		out[TARGET_MENU] = true
	return out


## The ship's speed against its reference, m/s.
func speed_mps() -> float:
	return velocity.length()


static func _axis(out: Dictionary, value: float, positive: StringName, negative: StringName) -> void:
	if value >= ANALOG_MIN:
		out[positive] = true
	elif value <= -ANALOG_MIN and negative != &"":
		out[negative] = true
