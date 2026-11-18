class_name ControlHintText
extends RefCounted
## The words of a control check's hint (M8 D80): what to press, on the pad and on the keyboard and mouse, then what to do with
## it (`LT + RT / W: FIRE BOTH MAIN PODS`, `HOLD X / SHIFT / MOUSE 4: ...`), as the interaction prompt names its buttons. Read
## from the live `InputMap`, so a rebind shows on the next frame. Pure: tests hand in the events per action.

## What stands for the buttons of a check none of whose actions is bound.
const UNBOUND: String = "NOT BOUND"
const _PRESS_WORDS: Dictionary = {&"hold": "HOLD ", &"tap": "TAP "}


## The whole hint on one line. `events_of` (action -> Array[InputEvent]) replaces the live `InputMap`.
static func line(check: ControlCheck, events_of: Callable = Callable()) -> String:
	var buttons: String = bindings(check, events_of)
	return "%s: %s" % [buttons if not buttons.is_empty() else UNBOUND, check.label]


## What to press for `check`: the pad's side, the keys' and the mouse's, each left out when it has none; "" when nothing is bound.
static func bindings(check: ControlCheck, events_of: Callable = Callable()) -> String:
	var per_action: Array[Array] = []
	for action: StringName in check.actions:
		per_action.append(_events(action, events_of))
	var with_way: bool = check.need_all or check.actions.size() == 1
	var sides := PackedStringArray()
	for side: String in [
			_with_extra(_side(check, per_action, func(e: InputEvent) -> String: return BindingNames.pad_name(e, with_way)), check.pad_extra),
			_with_extra(_side(check, per_action, BindingNames.key_name), check.keys_extra),
			_side(check, per_action, BindingNames.mouse_name)]:
		if not side.is_empty():
			sides.append(side)
	if sides.is_empty():
		return ""
	return String(_PRESS_WORDS.get(check.press, "")) + " / ".join(sides)


## Whether the player can do `check` at all: something is bound to it, or it names an input no action binds.
static func is_bound(check: ControlCheck, events_of: Callable = Callable()) -> bool:
	return not bindings(check, events_of).is_empty()


# One device's side. A check that needs all its actions shows the one control bound to every one of them (W for both main
# pods), else each action's first joined with +; one that needs any shows each action's first.
static func _side(check: ControlCheck, per_action: Array[Array], namer: Callable) -> String:
	var firsts := PackedStringArray()
	var shared: Array = []
	for i: int in per_action.size():
		var names: Array = []
		for event: InputEvent in per_action[i]:
			var name: String = namer.call(event)
			if not name.is_empty() and not names.has(name):
				names.append(name)
		shared = names if i == 0 else shared.filter(func(name: String) -> bool: return names.has(name))
		if names.is_empty():
			if check.need_all:
				return ""  # this device cannot press them all
			continue
		if not firsts.has(names[0]):
			firsts.append(names[0])
	if check.need_all:
		return String(shared[0]) if not shared.is_empty() else " + ".join(firsts)
	return " or ".join(firsts)


static func _with_extra(side: String, extra: String) -> String:
	if side.is_empty() or extra.is_empty():
		return side + extra
	return "%s or %s" % [side, extra]


static func _events(action: StringName, events_of: Callable) -> Array:
	if events_of.is_valid():
		return events_of.call(action)
	return InputMap.action_get_events(action) if InputMap.has_action(action) else []
