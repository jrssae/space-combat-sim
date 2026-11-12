class_name PadLegend
extends RefCounted
## What each pad button does, read from a control profile (architecture §18, D57, Q15). The menu frame's controller diagram
## draws this, so a rebind shows at once. Pure: it only reads the profile's descriptors (the list `ControlProfile.describe_action`
## prints), and knows the standard XInput layout and the menu's wording for each action.

## The drawn parts of the pad, in the order the diagram lists them.
const WIDGETS: Array[StringName] = [
	&"lt", &"rt", &"lb", &"rb", &"ls", &"rs", &"l3", &"r3", &"dpad_up", &"dpad_down", &"dpad_left", &"dpad_right",
	&"a", &"b", &"x", &"y", &"back", &"start",
]
const _TAGS: Dictionary = {
	&"lt": "LT", &"rt": "RT", &"lb": "LB", &"rb": "RB", &"ls": "L stick", &"rs": "R stick", &"l3": "L3", &"r3": "R3",
	&"dpad_up": "D-pad up", &"dpad_down": "D-pad down", &"dpad_left": "D-pad left", &"dpad_right": "D-pad right",
	&"a": "A", &"b": "B", &"x": "X", &"y": "Y", &"back": "Back", &"start": "Start",
}
# SDL button indices (Guide, 5, is not used by the game).
const _BUTTONS: Dictionary = {
	0: &"a", 1: &"b", 2: &"x", 3: &"y", 4: &"back", 6: &"start", 7: &"l3", 8: &"r3", 9: &"lb", 10: &"rb",
	11: &"dpad_up", 12: &"dpad_down", 13: &"dpad_left", 14: &"dpad_right",
}
const _AXES: Dictionary = {0: &"ls", 1: &"ls", 2: &"rs", 3: &"rs", 4: &"lt", 5: &"rt"}

## What the menu calls each game action. The four directions of a stick axis share one name, so a stick shows it once.
const ACTION_LABELS: Dictionary = {
	&"main_right": "Right main pod", &"main_left": "Left main pod", &"retro_right": "Right retro", &"retro_left": "Left retro",
	&"pitch_down": "Pitch", &"pitch_up": "Pitch", &"yaw_left": "Yaw", &"yaw_right": "Yaw",
	&"strafe_left": "Strafe", &"strafe_right": "Strafe", &"strafe_down": "Strafe", &"strafe_up": "Strafe",
	&"roll_left": "Roll", &"roll_right": "Roll",
	&"target_next": "Target / target menu", &"target_prev": "Previous target", &"target_ahead": "Target ahead",
	&"target_cycle": "Target / target menu", &"weapon_next": "Next weapon", &"fire": "Fire",
	&"toggle_flight_assist": "Flight assist", &"brake": "Brake", &"toggle_camera": "Camera", &"reset_ship": "Reset ship",
	&"pause": "Pause", &"debug_toggle_overlay": "Debug overlay", &"debug_toggle_fallback_mesh": "Debug mesh",
	&"autotrack": "Auto-track", &"camera_look": "Free look", &"screenshot": "Screenshot",
	&"wing_attack": "Wing: attack", &"wing_form": "Wing: form on me", &"wing_engage": "Wing: engage", &"wing_cover": "Wing: cover me",
	&"toggle_running_lights": "Running lights", &"comms_menu": "Comms menu",
}

var _actions: Dictionary = {}  # widget -> Array[StringName], in the order of InputAdapter.ACTIONS
var _widgets: Dictionary = {}  # action -> Array[StringName], in the order of the action's descriptors


## The legend of `profile`'s pad bindings. Keys and the mouse are not on the pad and are left out.
static func from_profile(profile: ControlProfile) -> PadLegend:
	var legend := PadLegend.new()
	for action: StringName in InputAdapter.ACTIONS:
		for descriptor: String in profile.descriptors_for(action):
			var widget: StringName = widget_of(descriptor)
			if widget == &"":
				continue
			legend._add(widget, action)
	return legend


## The pad part a descriptor (`pad:button:0`, `pad:axis:3-`) is, or `&""` for a key, the mouse or anything off the pad.
static func widget_of(descriptor: String) -> StringName:
	var parts: PackedStringArray = descriptor.split(":")
	if parts.size() != 3 or parts[0] != "pad":
		return &""
	if parts[1] == "button" and parts[2].is_valid_int():
		return _BUTTONS.get(parts[2].to_int(), &"")
	if parts[1] == "axis" and parts[2].length() == 2 and (parts[2].ends_with("+") or parts[2].ends_with("-")):
		var index: String = parts[2].substr(0, 1)
		return _AXES.get(index.to_int(), &"") if index.is_valid_int() else &""
	return &""


## The menu's name for an action; an action it has no wording for is shown readable rather than as its identifier.
static func label_of_action(action: StringName) -> String:
	if ACTION_LABELS.has(action):
		return ACTION_LABELS[action]
	return String(action).replace("_", " ").capitalize()


## The short name of a pad part as printed on the pad ("A", "LT", "D-pad up").
static func tag_of(widget: StringName) -> String:
	return _TAGS.get(widget, String(widget))


## The pad parts that have something bound, in diagram order.
func widgets() -> Array[StringName]:
	var out: Array[StringName] = []
	for widget: StringName in WIDGETS:
		if _actions.has(widget):
			out.append(widget)
	return out


## What a pad part does, as the menu words it ("Pitch / Yaw"); empty when nothing is bound to it.
func label_for(widget: StringName) -> String:
	var names: PackedStringArray = []
	for action: StringName in actions_for(widget):
		var name: String = label_of_action(action)
		if not names.has(name):
			names.append(name)
	return " / ".join(names)


func actions_for(widget: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(_actions.get(widget, []))
	return out


## Where an action sits on the pad (for highlighting it); empty for an action with no pad binding.
func widgets_for(action: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(_widgets.get(action, []))
	return out


func _add(widget: StringName, action: StringName) -> void:
	var on_widget: Array = _actions.get(widget, [])
	if not on_widget.has(action):
		on_widget.append(action)
	_actions[widget] = on_widget
	var of_action: Array = _widgets.get(action, [])
	if not of_action.has(widget):
		of_action.append(widget)
	_widgets[action] = of_action
