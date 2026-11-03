class_name BindingCapture
extends RefCounted
## Waits for one press to bind (architecture §18, D57; M5-T04). The controls page feeds it every input event while it waits;
## it answers whether the event belongs to the wait, so the page can swallow it and the press neither navigates the menu nor
## reaches the game. A press becomes a descriptor (`ControlProfile` grammar) for `ControlProfiles.bind`.
##
## The wait ends with a press (`CAPTURED`), a held B or Esc (`CANCELLED`) or silence (`TIMED_OUT`). B and Esc are bindable
## too, so they count as a press only when let go in time. Pure: no InputMap, no scene.

enum State { IDLE, WAITING, CAPTURED, CANCELLED, TIMED_OUT }

const TIMEOUT_S: float = 6.0
const CANCEL_HOLD_S: float = 0.8
## How far a stick or trigger travels to count as a press, and how near rest it must have been seen since the wait began.
const AXIS_PRESS: float = 0.6
const AXIS_REST: float = 0.3
const CANCEL_BINDINGS: Array[String] = ["pad:button:1", "key:Escape"]

var state: State = State.IDLE
## The press, once `state` is `CAPTURED`.
var descriptor: String = ""
## Why the last event was ignored (a modifier key, a button the game does not use); empty when nothing was.
var hint: String = ""

var _left_s: float = 0.0
var _holding: String = ""  # the B or Esc that is down and may turn out to be a cancel
var _held_s: float = 0.0
var _rested: Dictionary = {}  # axis -> true once seen near rest


func start(timeout_s: float = TIMEOUT_S) -> void:
	state = State.WAITING
	descriptor = ""
	hint = ""
	_left_s = timeout_s
	_holding = ""
	_held_s = 0.0
	_rested.clear()


func is_waiting() -> bool:
	return state == State.WAITING


## Gives up the wait (the page was left).
func cancel() -> void:
	if is_waiting():
		state = State.CANCELLED


## Time passes: a held B or Esc turns into a cancel, and a wait nobody answers runs out.
func advance(delta: float) -> void:
	if not is_waiting():
		return
	if not _holding.is_empty():
		_held_s += delta
		if _held_s >= CANCEL_HOLD_S:
			state = State.CANCELLED
			return
	_left_s -= delta
	if _left_s <= 0.0:
		state = State.TIMED_OUT


## Takes an event. True when it belongs to the wait and must not go on to the menu or the game; mouse motion and anything
## that arrives when not waiting does not.
func feed(event: InputEvent) -> bool:
	if not is_waiting():
		return false
	if event is InputEventKey:
		_key(event as InputEventKey)
	elif event is InputEventJoypadButton:
		_button(event as InputEventJoypadButton)
	elif event is InputEventJoypadMotion:
		_motion(event as InputEventJoypadMotion)
	elif event is InputEventMouseButton:
		_mouse(event as InputEventMouseButton)
	elif not event is InputEventAction:
		return false
	return true


func _key(event: InputEventKey) -> void:
	if event.echo:
		return
	var text: String = ControlProfile.descriptor_of(event)
	if text.is_empty():
		if event.pressed:
			hint = "Modifier keys (Shift, Ctrl, Alt, Meta) cannot be bound; press one plain key"
		return
	_press_or_release(text, event.pressed)


func _button(event: InputEventJoypadButton) -> void:
	var index: int = event.button_index
	if index < 0 or index > ControlProfile.MAX_PAD_BUTTON or index == ControlProfile.GUIDE_BUTTON:
		if event.pressed:
			hint = "That button is not used by the game"
		return
	_press_or_release("pad:button:%d" % index, event.pressed)


func _mouse(event: InputEventMouseButton) -> void:
	if not ControlProfile.MOUSE_BUTTONS.has(event.button_index):
		return  # the wheel cannot be held
	if event.pressed:
		_capture("mouse:%d" % event.button_index)


# A stick counts once it has been seen at rest and then pushed past AXIS_PRESS, so one that is already held over when the
# wait begins is not taken.
func _motion(event: InputEventJoypadMotion) -> void:
	var axis: int = event.axis
	if axis < 0 or axis > ControlProfile.MAX_PAD_AXIS:
		return
	var value: float = event.axis_value
	if absf(value) <= AXIS_REST:
		_rested[axis] = true
		return
	if absf(value) < AXIS_PRESS or not _rested.get(axis, false):
		return
	if axis >= JOY_AXIS_TRIGGER_LEFT and value < 0.0:
		return
	_capture("pad:axis:%d%s" % [axis, "+" if value > 0.0 else "-"])


# B and Esc wait for their release: held long enough they cancel instead.
func _press_or_release(text: String, pressed: bool) -> void:
	var cancels: bool = CANCEL_BINDINGS.has(text)
	if pressed:
		if cancels:
			_holding = text
			_held_s = 0.0
		else:
			_capture(text)
	elif cancels and _holding == text:
		_capture(text)


func _capture(text: String) -> void:
	state = State.CAPTURED
	descriptor = text
	_holding = ""
