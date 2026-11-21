class_name PadUiBindings
extends RefCounted
## Keeps the menus' own pad actions (`ui_accept`, `ui_cancel`...) positional too (M10-T63). Godot binds them to the raw A/B/X/Y
## indices, which a pad that reports by label (see `PadLayout`) puts on the wrong face buttons; the swap is its own inverse, so
## it is applied whenever the layout's swapping changes.


## Retargets the built-in `ui_*` actions from `before` to `after`; nothing happens when both read buttons the same way.
static func retarget(before: StringName, after: StringName) -> void:
	if PadLayout.swaps_face_buttons(before) == PadLayout.swaps_face_buttons(after):
		return
	for action: StringName in InputMap.get_actions():
		if not String(action).begins_with("ui_"):
			continue
		for event: InputEvent in InputMap.action_get_events(action):
			var button := event as InputEventJoypadButton
			if button != null:
				button.button_index = PadLayout.button_index(PadLayout.SWITCH, button.button_index) as JoyButton
