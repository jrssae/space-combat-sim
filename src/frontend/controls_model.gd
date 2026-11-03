class_name ControlsModel
extends RefCounted
## The words of the controls page (architecture §18, D57; M5-T04): what an action and a binding are called, the rows, the
## suggested name for a new profile and what the right panel says. Pure: it reads profiles and names, no InputMap.

const SUGGESTED_NAME: String = "my_controls"
const _STICK_SIDES: Dictionary = {"0-": "left", "0+": "right", "1-": "up", "1+": "down",
		"2-": "left", "2+": "right", "3-": "up", "3+": "down"}
const _MOUSE_NAMES: Dictionary = {1: "left", 2: "right", 3: "middle", 8: "side 1", 9: "side 2"}


## The menu's name for an action, told apart from the others that share a wording ("Pitch" up and down) by the direction.
static func action_title(action: StringName) -> String:
	var label: String = PadLegend.label_of_action(action)
	for other: StringName in InputAdapter.ACTIONS:
		if other != action and PadLegend.label_of_action(other) == label:
			return "%s %s" % [label, String(action).get_slice("_", String(action).count("_"))]
	return label


## A binding as the player reads it ("A", "L stick left", "Key Space"); one it cannot name is shown as it is.
static func binding_text(descriptor: String) -> String:
	var parts: PackedStringArray = descriptor.split(":", true, 2)
	if parts.size() < 2:
		return descriptor
	match parts[0]:
		"pad":
			var widget: StringName = PadLegend.widget_of(descriptor)
			if widget == &"":
				return descriptor
			if parts[1] == "axis" and (widget == &"ls" or widget == &"rs"):
				return "%s %s" % [PadLegend.tag_of(widget), _STICK_SIDES[parts[2]]]
			return PadLegend.tag_of(widget)
		"key":
			return "Key %s" % parts[1]
		"mouse":
			var button: int = parts[1].to_int()
			return "Mouse %s" % _MOUSE_NAMES[button] if _MOUSE_NAMES.has(button) else descriptor
	return descriptor


## One line of the list: the action and all its bindings.
static func row_text(profile: ControlProfile, action: StringName) -> String:
	var names := PackedStringArray()
	for descriptor: String in profile.descriptors_for(action):
		names.append(binding_text(descriptor))
	return "%s: %s" % [action_title(action), ", ".join(names) if not names.is_empty() else "(unbound)"]


static func profile_row_text(profile_name: String, unsaved: bool) -> String:
	return "Profile: %s%s" % [profile_name, " (unsaved changes)" if unsaved else ""]


## The name offered for "save as": the user's own profile in use (saving over it keeps it up to date), else a free one.
static func suggested_name(active: String, builtin: PackedStringArray, all: PackedStringArray) -> String:
	if not builtin.has(active):
		return active
	var candidate: String = SUGGESTED_NAME
	var number: int = 2
	while all.has(candidate):
		candidate = "%s_%d" % [SUGGESTED_NAME, number]
		number += 1
	return candidate


## Typed text made into a profile name as far as is certain (case, spaces); anything else invalid is left for the store to refuse.
static func clean_name(text: String) -> String:
	return text.strip_edges().to_lower().replace(" ", "_")


## Why a change was refused, for the status line.
static func refusal_text(errors: PackedStringArray) -> String:
	if errors.size() == 1:
		return "Not changed: %s" % errors[0]
	return "Not changed:\n" + "\n".join(errors)


## A right-panel content (`ObjectivesModel` shape) of plain lines.
static func panel(title: String, lines: Array[String]) -> Dictionary:
	var shown: Array[Dictionary] = []
	for text: String in lines:
		shown.append({"text": text, "mark": "", "state": &"", "primary": true, "optional": false})
	return {"title": title, "lines": shown}


## The right panel for an action: its exact bindings (what the console's `controls show` prints) and each in words.
static func action_panel(profile: ControlProfile, action: StringName) -> Dictionary:
	var lines: Array[String] = [profile.describe_action(action)]
	for descriptor: String in profile.descriptors_for(action):
		lines.append("%s  (%s)" % [binding_text(descriptor), descriptor])
	return panel(action_title(action).to_upper(), lines)
