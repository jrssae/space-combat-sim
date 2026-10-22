class_name InputSource
extends RefCounted
## Device-independent view of the InputMap actions that InputAdapter reads (architecture §6.1).
## GodotInputSource polls real devices; tests use FakeInputSource. Override every method; the base returns
## neutral values so a missing override can never thrust the ship.

## While false, key and mouse bindings read as released (the debug console has the keyboard).
var keyboard_mouse_enabled: bool = true


## Called once per sample before any read (calibration and other per-tick bookkeeping).
func poll(_dt: float) -> void:
	pass


## Stick pair from four actions, radial deadzone with rescaling: x = pos_x - neg_x, y = pos_y - neg_y.
func get_vector(_neg_x: StringName, _pos_x: StringName, _neg_y: StringName, _pos_y: StringName,
		_deadzone: float) -> Vector2:
	return Vector2.ZERO


## Analog 0..1 for a trigger action, after rest calibration and the trigger deadzone.
func get_trigger(_action: StringName) -> float:
	return 0.0


func is_pressed(_action: StringName) -> bool:
	return false


## Mouse travel in pixels since the last call (x right, y down), then cleared. Zero while the keyboard and mouse are masked.
func take_mouse_delta() -> Vector2:
	return Vector2.ZERO


## Mouse wheel notches since the last call, then cleared: positive = rolled toward the user (down), negative = away (up).
func take_wheel_steps() -> int:
	return 0


## Connected pads for the overlay/console: name, guid, raw axes 0-5, trigger_rest.
func pad_info() -> Array[Dictionary]:
	return []


## Radial deadzone with rescaling, shared by every source so fakes and devices agree exactly.
static func radial_deadzone(v: Vector2, deadzone: float) -> Vector2:
	var length: float = v.length()
	if length <= deadzone or length == 0.0:
		return Vector2.ZERO
	var scaled: float = minf(1.0, (length - deadzone) / (1.0 - deadzone))
	return v / length * scaled
