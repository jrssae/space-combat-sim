class_name PadPresses
extends RefCounted
## Which parts of the pad are held or moved right now (M8-T22), so the menus' controller diagram can light them and a
## player sees which button is which. Pure: the menu frame feeds it the joypad events its menus receive; it never reads
## `Input`.

## How far a stick must be off centre, and a trigger pulled, to count.
const STICK_THRESHOLD: float = 0.35
const TRIGGER_THRESHOLD: float = 0.3
const _STICKS: Array[StringName] = [&"ls", &"rs"]

var _buttons: Dictionary = {}  # "device:index" -> widget, for the buttons held
var _axes: Dictionary = {}  # "device:axis" -> value, for the axes off rest


## Takes one input event. Returns true when what is lit changed; keys, the mouse and unknown buttons change nothing.
func feed(event: InputEvent) -> bool:
	var button := event as InputEventJoypadButton
	if button != null:
		return feed_button(button.device, button.button_index, button.pressed)
	var motion := event as InputEventJoypadMotion
	if motion != null:
		return feed_axis(motion.device, motion.axis, motion.axis_value)
	return false


func feed_button(device: int, index: int, pressed: bool) -> bool:
	var widget: StringName = PadLegend.widget_of_button(index)
	if widget == &"":
		return false
	var before: Array[StringName] = widgets()
	var key: String = "%d:%d" % [device, index]
	if pressed:
		_buttons[key] = widget
	else:
		_buttons.erase(key)
	return widgets() != before


func feed_axis(device: int, axis: int, value: float) -> bool:
	if PadLegend.widget_of_axis(axis) == &"":
		return false
	var before: Array[StringName] = widgets()
	_axes["%d:%d" % [device, axis]] = value
	return widgets() != before


## Forgets everything held (the menu closed, or a pad went away with a button down).
func clear() -> void:
	_buttons.clear()
	_axes.clear()


## The pad parts to light, in the diagram's order.
func widgets() -> Array[StringName]:
	var held: Dictionary = {}
	for widget: StringName in _buttons.values():
		held[widget] = true
	var sticks: Dictionary = {}  # "device:stick" -> the stick's deflection
	for key: String in _axes:
		var parts: PackedStringArray = key.split(":")
		var widget: StringName = PadLegend.widget_of_axis(parts[1].to_int())
		var value: float = _axes[key]
		if _STICKS.has(widget):
			var stick: String = "%s:%s" % [parts[0], widget]
			sticks[stick] = (sticks.get(stick, Vector2.ZERO) as Vector2) + (Vector2(value, 0.0) if parts[1].to_int() % 2 == 0 else Vector2(0.0, value))
		elif value > TRIGGER_THRESHOLD:
			held[widget] = true
	for stick: String in sticks:
		if (sticks[stick] as Vector2).length() > STICK_THRESHOLD:
			held[StringName(stick.get_slice(":", 1))] = true
	var out: Array[StringName] = []
	for widget: StringName in PadLegend.WIDGETS:
		if held.has(widget):
			out.append(widget)
	return out
