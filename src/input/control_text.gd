class_name ControlText
extends RefCounted
## Names controls in spoken text as they are bound now (M8-T33, the maintainer: always the control it is mapped to, never the
## default). A line writes `{action:<name>}` where it means a control (`Tap {action:autotrack}.`), or `{action:a,b}` when
## the pad and the keyboard reach the same thing through different actions (`{action:target_cycle,target_next}`); the comms
## panel resolves it as the line is shown, for the device the pilot used last: the pad's glyph (`X`), or the key and the mouse
## button (`SHIFT / MOUSE 4`). Read from the live `InputMap`, so a rebind shows at once. Pure: tests hand in the events.
##
## Mission text never writes a control's name itself: `tests/unit/test_text_names_no_control.gd` fails on one.

const OPEN: String = "{action:"
const CLOSE: String = "}"
## What stands for a control nothing is bound to.
const UNBOUND: String = "NOT BOUND"


## `text` with every placeholder replaced by its control's name on `device`. `events_of` (action -> Array[InputEvent]) replaces
## the live `InputMap`.
static func resolve(text: String, device: InputSource.Device, events_of: Callable = Callable()) -> String:
	if not text.contains(OPEN):
		return text
	var out: String = ""
	var at: int = 0
	while true:
		var open: int = text.find(OPEN, at)
		var close: int = text.find(CLOSE, open) if open >= 0 else -1
		if open < 0 or close < 0:
			break
		out += text.substr(at, open - at) + name_of(_actions(text.substr(open + OPEN.length(), close - open - OPEN.length())),
				device, events_of)
		at = close + CLOSE.length()
	return out + text.substr(at)


## The control for `actions` on `device`: the first of them that device binds. With none, the other device's; with none at
## all, `UNBOUND`.
static func name_of(actions: PackedStringArray, device: InputSource.Device, events_of: Callable = Callable()) -> String:
	var other: InputSource.Device = InputSource.Device.KEYS if device == InputSource.Device.PAD else InputSource.Device.PAD
	for wanted: InputSource.Device in [device, other]:
		for action: String in actions:
			var found: String = _on_device(_events(StringName(action), events_of), wanted)
			if not found.is_empty():
				return found
	return UNBOUND


## The actions every placeholder of `text` names, one list per placeholder, in order.
static func placeholders(text: String) -> Array[PackedStringArray]:
	var out: Array[PackedStringArray] = []
	var at: int = 0
	while true:
		var open: int = text.find(OPEN, at)
		var close: int = text.find(CLOSE, open) if open >= 0 else -1
		if open < 0 or close < 0:
			break
		out.append(_actions(text.substr(open + OPEN.length(), close - open - OPEN.length())))
		at = close + CLOSE.length()
	return out


## `text` with its placeholders cut out: what is left is prose, where no control may be named.
static func prose(text: String) -> String:
	var out: String = ""
	var at: int = 0
	while true:
		var open: int = text.find(OPEN, at)
		var close: int = text.find(CLOSE, open) if open >= 0 else -1
		if open < 0 or close < 0:
			break
		out += text.substr(at, open - at)
		at = close + CLOSE.length()
	return out + text.substr(at)


static func _actions(inner: String) -> PackedStringArray:
	var out := PackedStringArray()
	for part: String in inner.split(",", false):
		out.append(part.strip_edges())
	return out


# The pad's control among `events`, or the key and the mouse button as the prompts join them.
static func _on_device(events: Array, device: InputSource.Device) -> String:
	var typed: Array[InputEvent] = []
	typed.assign(events)
	if device == InputSource.Device.PAD:
		return BindingNames.first(typed, BindingNames.pad_name)
	var names := PackedStringArray()
	for found: String in [BindingNames.first(typed, BindingNames.key_name), BindingNames.first(typed, BindingNames.mouse_name)]:
		if not found.is_empty():
			names.append(found)
	return " / ".join(names)


static func _events(action: StringName, events_of: Callable) -> Array:
	if events_of.is_valid():
		return events_of.call(action)
	return InputMap.action_get_events(action) if InputMap.has_action(action) else []
