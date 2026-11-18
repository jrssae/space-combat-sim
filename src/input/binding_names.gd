class_name BindingNames
extends RefCounted
## Short names of an action's bindings for a HUD prompt (M7-T27): the pad's glyph, the first key and the first mouse button, so
## a pilot on either reads which button to hold (`HOLD X / SHIFT / MOUSE 4`). Read from the live bindings, so a rebind shows.

const _MOUSE_NAMES: Dictionary = {1: "LMB", 2: "RMB", 3: "MMB", 8: "MOUSE 4", 9: "MOUSE 5"}


## "X / SHIFT / MOUSE 4" for these events: one pad button, one key and one mouse button at most, in that order; "" for none.
static func short(events: Array[InputEvent]) -> String:
	var pad: String = ""
	var key: String = ""
	var mouse: String = ""
	for event: InputEvent in events:
		if event is InputEventJoypadButton and pad.is_empty():
			var widget: StringName = PadLegend.widget_of("pad:button:%d" % (event as InputEventJoypadButton).button_index)
			pad = PadLegend.tag_of(widget).to_upper() if widget != &"" else ""
		elif event is InputEventKey and key.is_empty():
			var k := event as InputEventKey
			key = OS.get_keycode_string(k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode).to_upper()
		elif event is InputEventMouseButton and mouse.is_empty():
			mouse = _MOUSE_NAMES.get((event as InputEventMouseButton).button_index, "")
	var names := PackedStringArray()
	for name: String in [pad, key, mouse]:
		if not name.is_empty():
			names.append(name)
	return " / ".join(names)


## The same for an action as the input map binds it now.
static func of_action(action: StringName) -> String:
	if not InputMap.has_action(action):
		return ""
	return short(InputMap.action_get_events(action))
