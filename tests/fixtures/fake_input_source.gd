class_name FakeInputSource
extends InputSource
## Scripted InputSource for tests: set action strengths directly; optionally mark them as keyboard-sourced so
## keyboard_mouse_enabled = false masks them, like GodotInputSource does for the console.

var polled_dt: float = 0.0
var _strengths: Dictionary = {}  # action -> 0..1
var _from_keyboard: Dictionary = {}  # action -> true when the value comes from a key


func hold(action: StringName, strength: float = 1.0, from_keyboard: bool = false) -> void:
	_strengths[action] = strength
	if from_keyboard:
		_from_keyboard[action] = true
	else:
		_from_keyboard.erase(action)


func release(action: StringName) -> void:
	_strengths.erase(action)
	_from_keyboard.erase(action)


func release_all() -> void:
	_strengths.clear()
	_from_keyboard.clear()


func poll(dt: float) -> void:
	polled_dt = dt


func get_vector(neg_x: StringName, pos_x: StringName, neg_y: StringName, pos_y: StringName,
		deadzone: float) -> Vector2:
	var v := Vector2(_value(pos_x) - _value(neg_x), _value(pos_y) - _value(neg_y))
	return InputSource.radial_deadzone(v, deadzone)


func get_trigger(action: StringName) -> float:
	return _value(action)


func is_pressed(action: StringName) -> bool:
	return _value(action) > 0.5


func _value(action: StringName) -> float:
	if _from_keyboard.has(action) and not keyboard_mouse_enabled:
		return 0.0
	return float(_strengths.get(action, 0.0))
