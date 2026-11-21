class_name BindingNames
extends RefCounted
## Short names of an action's bindings for a HUD prompt (M7-T27): the pad's glyph, the first key and the first mouse button, so
## a pilot on either reads which button to hold (`HOLD X / SHIFT / MOUSE 4`). Read from the live bindings, so a rebind shows.
## The control checks' hints (M8-T04) name triggers and sticks too (`LT`, `L STICK LEFT`).

const _MOUSE_NAMES: Dictionary = {1: "LMB", 2: "RMB", 3: "MMB", 8: "MOUSE 4", 9: "MOUSE 5"}
const _STICKS: Array[StringName] = [&"ls", &"rs"]
# The way a stick is pushed, by axis parity (even: sideways, odd: fore and aft) and sign (negative first).
const _WAYS: Array = [["LEFT", "RIGHT"], ["UP", "DOWN"]]


## "X / SHIFT / MOUSE 4" for these events: one pad control, one key and one mouse button at most, in that order; "" for none.
static func short(events: Array[InputEvent]) -> String:
	var names := PackedStringArray()
	for name: String in [first(events, pad_name), first(events, key_name), first(events, mouse_name)]:
		if not name.is_empty():
			names.append(name)
	return " / ".join(names)


## The first name `namer` (`pad_name`, `key_name` or `mouse_name`) gives for one of `events`; "" for none.
static func first(events: Array[InputEvent], namer: Callable) -> String:
	for event: InputEvent in events:
		var name: String = namer.call(event)
		if not name.is_empty():
			return name
	return ""


## The pad's name for an event: a button's glyph (`X`), a trigger (`LT`) or a stick with the way it is pushed
## (`L STICK LEFT`; the stick alone without `with_way`); "" for anything off the pad.
static func pad_name(event: InputEvent, with_way: bool = true) -> String:
	if event is InputEventJoypadButton:
		var widget: StringName = PadLegend.widget_of("pad:button:%d" % (event as InputEventJoypadButton).button_index)
		return PadLegend.tag_of(widget).to_upper() if widget != &"" else ""
	if not (event is InputEventJoypadMotion):
		return ""
	var motion := event as InputEventJoypadMotion
	var part: StringName = PadLegend.widget_of("pad:axis:%d%s" % [motion.axis, "+" if motion.axis_value > 0.0 else "-"])
	if part == &"":
		return ""
	var tag: String = PadLegend.tag_of(part).to_upper()
	if not with_way or not _STICKS.has(part):
		return tag
	var ways: Array = _WAYS[motion.axis % 2]
	return "%s %s" % [tag, ways[1 if motion.axis_value > 0.0 else 0]]


## The key's name (`SHIFT`); "" for anything but a key.
static func key_name(event: InputEvent) -> String:
	if not (event is InputEventKey):
		return ""
	var k := event as InputEventKey
	return OS.get_keycode_string(k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode).to_upper()


## The mouse button's name (`MOUSE 4`); "" for anything else.
static func mouse_name(event: InputEvent) -> String:
	if not (event is InputEventMouseButton):
		return ""
	return _MOUSE_NAMES.get((event as InputEventMouseButton).button_index, "")


## The same for an action as the input map binds it now.
static func of_action(action: StringName) -> String:
	if not InputMap.has_action(action):
		return ""
	return short(InputMap.action_get_events(action))
