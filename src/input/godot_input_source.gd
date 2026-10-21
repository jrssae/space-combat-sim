class_name GodotInputSource
extends InputSource
## InputSource over real devices (architecture §6.1). Every action is evaluated here from its InputMap events
## by polling devices, never through Input.is_action_pressed: Input's action state would still report keys
## typed into the debug console, whereas polling lets key and mouse bindings be masked per device class.
## Joypad events with device -1 match every connected pad; the strongest reading wins.

## Emitted when calibration proves a pad's trigger rest value; the owner stores it in Settings.
signal trigger_rest_changed(guid: String, rest: float)

var trigger_deadzone: float = 0.05

var _mouse_delta: Vector2 = Vector2.ZERO
var _wheel_steps: int = 0
var calibration: TriggerCalibration = TriggerCalibration.new()


func _init() -> void:
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


## Seed calibration from saved data ({guid: rest}).
func load_calibration(saved: Dictionary) -> void:
	for guid: String in saved.keys():
		calibration.set_rest(guid, float(saved[guid]))


func poll(dt: float) -> void:
	for pad: int in _pad_ids():
		var guid: String = _pad_guid(pad)
		var changed: bool = calibration.observe(guid, Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_LEFT),
				Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_RIGHT), dt)
		if changed:
			trigger_rest_changed.emit(guid, calibration.get_rest(guid))


func get_vector(neg_x: StringName, pos_x: StringName, neg_y: StringName, pos_y: StringName,
		deadzone: float) -> Vector2:
	var v := Vector2(_strength(pos_x) - _strength(neg_x), _strength(pos_y) - _strength(neg_y))
	return InputSource.radial_deadzone(v, deadzone)


func get_trigger(action: StringName) -> float:
	var best: float = 0.0
	for event: InputEvent in _events(action):
		var motion := event as InputEventJoypadMotion
		if motion != null and _is_trigger_axis(motion.axis):
			for pad: int in _pads_for(motion.device):
				var raw: float = Input.get_joy_axis(pad, motion.axis)
				best = maxf(best, calibration.read(_pad_guid(pad), raw, trigger_deadzone))
		elif _event_active(event, action):
			best = maxf(best, _event_strength(event))
	return best


## Fed from `_input` by Main: relative mouse motion and wheel notches, summed until the next physics tick reads them.
func add_mouse_motion(relative: Vector2) -> void:
	if keyboard_mouse_enabled:
		_mouse_delta += relative


func add_wheel(steps: int) -> void:
	if keyboard_mouse_enabled:
		_wheel_steps += steps


func take_mouse_delta() -> Vector2:
	var out: Vector2 = _mouse_delta
	_mouse_delta = Vector2.ZERO
	return out if keyboard_mouse_enabled else Vector2.ZERO


func take_wheel_steps() -> int:
	var out: int = _wheel_steps
	_wheel_steps = 0
	return out if keyboard_mouse_enabled else 0


func is_pressed(action: StringName) -> bool:
	for event: InputEvent in _events(action):
		if _event_active(event, action):
			return true
	return false


func pad_info() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for pad: int in _pad_ids():
		var guid: String = _pad_guid(pad)
		var axes: Array[float] = []
		for axis: int in 6:
			axes.append(Input.get_joy_axis(pad, axis as JoyAxis))
		out.append({
			"id": pad, "name": _pad_name(pad), "guid": guid, "axes": axes,
			"trigger_rest": calibration.get_rest(guid), "calibrated": calibration.is_calibrated(guid),
		})
	return out


## Connected pads. Virtual (with the two lookups below) so tests can inject pads without hardware.
func _pad_ids() -> Array[int]:
	return Input.get_connected_joypads()


func _pad_guid(pad: int) -> String:
	return Input.get_joy_guid(pad)


func _pad_name(pad: int) -> String:
	return Input.get_joy_name(pad)


func _pads_for(device: int) -> Array[int]:
	if device < 0:
		return _pad_ids()
	var only: Array[int] = [device]
	return only


func _events(action: StringName) -> Array[InputEvent]:
	if not InputMap.has_action(action):
		return []
	return InputMap.action_get_events(action)


func _is_trigger_axis(axis: JoyAxis) -> bool:
	return axis == JOY_AXIS_TRIGGER_LEFT or axis == JOY_AXIS_TRIGGER_RIGHT


## Strongest raw 0..1 reading over every event bound to an action.
func _strength(action: StringName) -> float:
	var best: float = 0.0
	for event: InputEvent in _events(action):
		best = maxf(best, _event_strength(event))
	return best


## Raw 0..1 strength of one bound event (no per-action deadzone; sticks get a radial one in get_vector).
func _event_strength(event: InputEvent) -> float:
	if event is InputEventKey:
		if not keyboard_mouse_enabled:
			return 0.0
		var key := event as InputEventKey
		var pressed: bool = Input.is_physical_key_pressed(key.physical_keycode) if key.physical_keycode != KEY_NONE \
				else Input.is_key_pressed(key.keycode)
		return 1.0 if pressed else 0.0
	if event is InputEventMouseButton:
		if not keyboard_mouse_enabled:
			return 0.0
		return 1.0 if Input.is_mouse_button_pressed((event as InputEventMouseButton).button_index) else 0.0
	if event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		for pad: int in _pads_for(button.device):
			if Input.is_joy_button_pressed(pad, button.button_index):
				return 1.0
		return 0.0
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		var best: float = 0.0
		for pad: int in _pads_for(motion.device):
			var raw: float = Input.get_joy_axis(pad, motion.axis)
			if _is_trigger_axis(motion.axis):
				best = maxf(best, TriggerCalibration.normalize(raw, calibration.get_rest(_pad_guid(pad))))
			else:
				best = maxf(best, maxf(0.0, raw * signf(motion.axis_value)))
		return best
	return 0.0


func _event_active(event: InputEvent, action: StringName) -> bool:
	if event is InputEventJoypadMotion:
		return _event_strength(event) > InputMap.action_get_deadzone(action)
	return _event_strength(event) > 0.5


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		calibration.restart(_pad_guid(device))
