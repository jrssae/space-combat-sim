class_name ControlProfile
extends RefCounted
## A named set of input bindings (architecture §15.12): for every `InputAdapter.ACTIONS` entry, the events bound
## to it as text descriptors, plus its InputMap deadzone. Converts to and from the InputMap and ConfigFile text,
## and validates against the M1 input rules before anything touches the InputMap, so a bad profile can never
## leave the map half-changed. No scene tree and no devices, so all of it is unit-tested.
##
## Descriptors (every event is device -1, i.e. any pad):
##   pad:button:<0-14>      standard SDL button index, Guide (5) excluded
##   pad:axis:<0-5><+|->    standard SDL axis and the direction that counts (triggers, axes 4 and 5, only +)
##   key:<Godot key name>   a physical key: E, Space, Left, F3, "Kp 0" (key:Kp_0 also works); no modifiers
##   mouse:<1|2|3|8|9>      left, right, middle, side buttons (the wheel cannot be held)
## The ` key (KEY_QUOTELEFT) belongs to the console and is rejected everywhere.
##
## ConfigFile text:
##   [profile]    format=1, description="..."
##   [bindings]   fire=["pad:button:0", "key:Space", "mouse:1"]   one list per action, in event order
##   [deadzones]  fire=0.5                                         one number per action

const FORMAT_VERSION: int = 1
const DEFAULT_NAME: String = "default"
## Profile names double as file names (`user://controls/<name>.cfg`) and as `settings.control_profile` values.
const NAME_PATTERN: String = "^[a-z0-9_]{1,32}$"
## Actions that need no pad binding: no pad button is free for them, or the pad reaches the function another way (target_ahead
## is the D-pad Up hold, target_prev the mouse wheel's twin).
const KEYBOARD_ONLY: Array[StringName] = [
	InputAdapter.TOGGLE_FALLBACK, InputAdapter.TOGGLE_OVERLAY, InputAdapter.TARGET_AHEAD, InputAdapter.TARGET_PREV,
	InputAdapter.SCREENSHOT,
]
const MAX_PAD_BUTTON: int = 14  # D-pad Right; 15 and up are SDL extras (paddles, touchpad, misc)
const GUIDE_BUTTON: int = 5
const MAX_PAD_AXIS: int = 5  # right trigger
const MOUSE_BUTTONS: Array[int] = [1, 2, 3, 8, 9]
const MAX_DEADZONE: float = 0.9
const DESCRIPTOR_HELP: String = "pad:button:<0-14>, pad:axis:<0-5><+|->, key:<name>, mouse:<1|2|3|8|9>"

const SECTION_PROFILE: String = "profile"
const SECTION_BINDINGS: String = "bindings"
const SECTION_DEADZONES: String = "deadzones"

# A binding the descriptor grammar cannot express (modifier keys, logical keys, a specific device, other event
# kinds) is kept as this prefix plus the event's text, so validation can name it instead of silently dropping it.
const _UNREPRESENTABLE: String = "?"

var name: String = ""
var description: String = ""
## StringName action -> Array of descriptor Strings, in the order the events are bound.
var bindings: Dictionary = {}
## StringName action -> float, the InputMap deadzone.
var deadzones: Dictionary = {}


static func is_valid_name(profile_name: String) -> bool:
	return RegEx.create_from_string(NAME_PATTERN).search(profile_name) != null


static func action_names() -> PackedStringArray:
	var out := PackedStringArray()
	for action: StringName in InputAdapter.ACTIONS:
		out.append(String(action))
	return out


# --- Descriptors -------------------------------------------------------------------------------------------------


## Reads a descriptor. Returns {"ok", "descriptor" (canonical spelling), "event" (a fresh InputEvent), "error"}.
static func parse_descriptor(text: String) -> Dictionary:
	var raw: String = text.strip_edges()
	var parts: PackedStringArray = raw.split(":", true, 2)
	match parts[0].to_lower():
		"pad":
			if parts.size() < 3:
				return _bad_descriptor("expected pad:button:<0-14> or pad:axis:<0-5><+|->, got '%s'" % raw)
			match parts[1].to_lower():
				"button":
					return _parse_pad_button(parts[2])
				"axis":
					return _parse_pad_axis(parts[2])
			return _bad_descriptor("unknown pad input '%s' (expected pad:button:<n> or pad:axis:<n><+|->)" % raw)
		"key":
			if parts.size() < 2:
				return _bad_descriptor("expected key:<name>, got '%s'" % raw)
			return _parse_key(parts[1])
		"mouse":
			if parts.size() < 2:
				return _bad_descriptor("expected mouse:<button>, got '%s'" % raw)
			return _parse_mouse(parts[1])
	return _bad_descriptor("unknown binding '%s' (expected %s)" % [raw, DESCRIPTOR_HELP])


## The InputEvent for a descriptor, or null if it is not valid.
static func event_from(descriptor: String) -> InputEvent:
	var parsed: Dictionary = parse_descriptor(descriptor)
	return parsed["event"] if parsed["ok"] else null


## The descriptor for an InputMap event, or "" when the grammar cannot express it exactly.
static func descriptor_of(event: InputEvent) -> String:
	if event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		return "pad:button:%d" % button.button_index if button.device == -1 else ""
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if motion.device != -1 or absf(motion.axis_value) != 1.0:
			return ""
		return "pad:axis:%d%s" % [motion.axis, "+" if motion.axis_value > 0.0 else "-"]
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.alt_pressed or key.shift_pressed or key.ctrl_pressed or key.meta_pressed:
			return ""
		if key.physical_keycode != KEY_NONE:
			return "key:" + OS.get_keycode_string(key.physical_keycode)
		if key.keycode == KEY_QUOTELEFT:
			return "key:" + OS.get_keycode_string(key.keycode)  # not expressible, but validation names the console key
		return ""
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.alt_pressed or mouse.shift_pressed or mouse.ctrl_pressed or mouse.meta_pressed:
			return ""
		return "mouse:%d" % mouse.button_index
	return ""


# --- InputMap ----------------------------------------------------------------------------------------------------


## Snapshot of the InputMap's game actions (missing actions are left out, which validation reports).
static func from_input_map(p_name: String = "") -> ControlProfile:
	var profile := ControlProfile.new()
	profile.name = p_name
	for action: StringName in InputAdapter.ACTIONS:
		if not InputMap.has_action(action):
			continue
		var list: Array = []
		for event: InputEvent in InputMap.action_get_events(action):
			var descriptor: String = descriptor_of(event)
			list.append(descriptor if not descriptor.is_empty() else _UNREPRESENTABLE + event.as_text())
		profile.bindings[action] = list
		profile.deadzones[action] = InputMap.action_get_deadzone(action)
	return profile


## Validates, then replaces the events and deadzone of every game action in the InputMap. Returns the validation
## errors; when there are any, the InputMap has not been touched.
func apply_to_input_map() -> PackedStringArray:
	var errors: PackedStringArray = validate()
	if not errors.is_empty():
		return errors
	# Build every event first; only then touch the map, so it changes all at once or not at all.
	var staged: Dictionary = {}
	for action: StringName in InputAdapter.ACTIONS:
		var events: Array[InputEvent] = []
		for descriptor: Variant in bindings[action]:
			events.append(event_from(String(descriptor)))
		staged[action] = events
	for action: StringName in InputAdapter.ACTIONS:
		var deadzone: float = float(deadzones[action])
		if not InputMap.has_action(action):
			InputMap.add_action(action, deadzone)
		InputMap.action_erase_events(action)
		var events: Array[InputEvent] = staged[action]
		for event: InputEvent in events:
			InputMap.action_add_event(action, event)
		InputMap.action_set_deadzone(action, deadzone)
	return errors


# --- Validation --------------------------------------------------------------------------------------------------


## Every problem, one line each, phrased with the config path (`bindings.fire[1]: ...`). Empty = valid.
## Rules (M1 input): every action present with a deadzone, a pad binding on every action but the keyboard-only
## debug one, standard SDL indices only, no duplicate bindings, never the console key.
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	for action: StringName in InputAdapter.ACTIONS:
		_validate_bindings(action, errors)
		_validate_deadzone(action, errors)
	var known: PackedStringArray = action_names()
	for section: Array in [[SECTION_BINDINGS, bindings], [SECTION_DEADZONES, deadzones]]:
		var table: Dictionary = section[1]
		for key: Variant in table.keys():
			if not InputAdapter.ACTIONS.has(StringName(key)):
				errors.append("%s.%s: unknown action%s" % [section[0], key,
						ConsoleFormat.did_you_mean(String(key), known)])
	return errors


func _validate_bindings(action: StringName, errors: PackedStringArray) -> void:
	var path: String = "%s.%s" % [SECTION_BINDINGS, action]
	if not bindings.has(action):
		errors.append(path + ": missing")
		return
	var list: Array = bindings[action]
	var seen: Dictionary = {}
	var has_pad: bool = false
	for i: int in list.size():
		var parsed: Dictionary = parse_descriptor(String(list[i]))
		if not parsed["ok"]:
			errors.append("%s[%d]: %s" % [path, i, parsed["error"]])
			continue
		var descriptor: String = parsed["descriptor"]
		if seen.has(descriptor):
			errors.append("%s[%d]: %s is listed twice" % [path, i, descriptor])
		seen[descriptor] = true
		has_pad = has_pad or descriptor.begins_with("pad:")
	if not has_pad and not KEYBOARD_ONLY.has(action):
		errors.append("%s: needs a pad binding (pad:button:<n> or pad:axis:<n><+|->); the pad must reach every action" % path)


func _validate_deadzone(action: StringName, errors: PackedStringArray) -> void:
	var path: String = "%s.%s" % [SECTION_DEADZONES, action]
	if not deadzones.has(action):
		errors.append(path + ": missing")
		return
	var value: Variant = deadzones[action]
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		errors.append("%s: expected a number, got %s" % [path, type_string(typeof(value))])
		return
	var f: float = float(value)
	if is_nan(f) or f < 0.0 or f > MAX_DEADZONE:
		errors.append("%s: must be in 0.0..%s, got %s" % [path, MAX_DEADZONE, f])


# --- Editing (bind / unbind) ------------------------------------------------------------------------------------


func duplicate_profile() -> ControlProfile:
	var copy := ControlProfile.new()
	copy.name = name
	copy.description = description
	for action: Variant in bindings.keys():
		copy.bindings[action] = (bindings[action] as Array).duplicate()
	copy.deadzones = deadzones.duplicate()
	return copy


## The descriptors bound to an action (empty for an unknown one), canonical spelling where they parse.
func descriptors_for(action: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	if bindings.has(action):
		for descriptor: Variant in bindings[action]:
			out.append(String(descriptor))
	return out


## `fire: pad:button:0 key:Space mouse:1 (deadzone 0.50)`
func describe_action(action: StringName) -> String:
	var shown: String = " ".join(descriptors_for(action)) if bindings.has(action) else ""
	var text: String = "%s: %s" % [action, shown if not shown.is_empty() else "(unbound)"]
	if deadzones.has(action):
		text += " (deadzone %.2f)" % float(deadzones[action])
	return text


## A copy with `descriptor` added to `action`'s events. Returns {"ok", "profile", "changed", "descriptor", "errors"};
## `changed` is false when it was already bound. Nothing is applied: the caller validates and applies the copy.
func with_bound(action: StringName, descriptor: String) -> Dictionary:
	var checked: Dictionary = _check_edit(action, descriptor)
	if not checked["ok"]:
		return checked
	var canonical: String = checked["descriptor"]
	var list: Array = (bindings[action] as Array).duplicate()
	for existing: Variant in list:
		var parsed: Dictionary = parse_descriptor(String(existing))
		if parsed["ok"] and parsed["descriptor"] == canonical:
			checked["changed"] = false
			checked["profile"] = duplicate_profile()
			return checked
	list.append(canonical)
	var copy: ControlProfile = duplicate_profile()
	copy.bindings[action] = list
	return _finish_edit(checked, copy)


## A copy with `descriptor` removed from `action`'s events. Same result shape as `with_bound`; fails when the action
## does not have it, and when removing it would leave the copy invalid (the last pad binding of an action).
func with_unbound(action: StringName, descriptor: String) -> Dictionary:
	var checked: Dictionary = _check_edit(action, descriptor)
	if not checked["ok"]:
		return checked
	var canonical: String = checked["descriptor"]
	var kept: Array = []
	var found: bool = false
	for existing: Variant in bindings[action]:
		var parsed: Dictionary = parse_descriptor(String(existing))
		if parsed["ok"] and parsed["descriptor"] == canonical:
			found = true
		else:
			kept.append(existing)
	if not found:
		return _edit_failed("%s has no %s binding (it has: %s)" % [action, canonical,
				" ".join(descriptors_for(action))])
	var copy: ControlProfile = duplicate_profile()
	copy.bindings[action] = kept
	return _finish_edit(checked, copy)


func _check_edit(action: StringName, descriptor: String) -> Dictionary:
	if not InputAdapter.ACTIONS.has(action):
		return _edit_failed("unknown action '%s'%s" % [action, ConsoleFormat.did_you_mean(String(action),
				action_names())])
	if not bindings.has(action):
		return _edit_failed("this profile has no bindings for %s" % action)
	var parsed: Dictionary = parse_descriptor(descriptor)
	if not parsed["ok"]:
		return _edit_failed(parsed["error"])
	return {"ok": true, "profile": null, "changed": true, "descriptor": parsed["descriptor"], "errors": PackedStringArray()}


func _finish_edit(result: Dictionary, copy: ControlProfile) -> Dictionary:
	var errors: PackedStringArray = copy.validate()
	if not errors.is_empty():
		return {"ok": false, "profile": null, "changed": false, "descriptor": result["descriptor"], "errors": errors}
	result["profile"] = copy
	return result


static func _edit_failed(message: String) -> Dictionary:
	return {"ok": false, "profile": null, "changed": false, "descriptor": "", "errors": PackedStringArray([message])}


## True when both profiles bind the same events (compared as canonical descriptors) with the same deadzones.
## Name and description are ignored.
func same_bindings(other: ControlProfile) -> bool:
	if bindings.size() != other.bindings.size() or deadzones.size() != other.deadzones.size():
		return false
	for action: Variant in bindings.keys():
		if not other.bindings.has(action) or not other.deadzones.has(action):
			return false
		if descriptors_for(StringName(action)) != other.descriptors_for(StringName(action)):
			return false
	for action: Variant in deadzones.keys():
		if not other.deadzones.has(action) or not is_equal_approx(float(deadzones[action]), float(other.deadzones[action])):
			return false
	return true


# --- ConfigFile text ---------------------------------------------------------------------------------------------


func to_config() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION_PROFILE, "format", FORMAT_VERSION)
	if not description.is_empty():
		cfg.set_value(SECTION_PROFILE, "description", description)
	for action: StringName in _ordered_actions(bindings):
		cfg.set_value(SECTION_BINDINGS, String(action), (bindings[action] as Array).duplicate())
	for action: StringName in _ordered_actions(deadzones):
		cfg.set_value(SECTION_DEADZONES, String(action), float(deadzones[action]))
	return cfg


func to_config_text() -> String:
	return to_config().encode_to_text()


## Reads profile text. Returns {"ok", "profile", "errors"}; `profile` is set whenever the text parsed, even if it
## then failed validation (so a caller can show what is in it). Syntax errors also print an engine error.
static func from_config_text(text: String, p_name: String = "") -> Dictionary:
	var cfg := ConfigFile.new()
	var err: Error = cfg.parse(text)
	if err != OK:
		return {"ok": false, "profile": null,
				"errors": PackedStringArray(["not valid config text (%s)" % error_string(err)])}
	return from_config(cfg, p_name)


static func from_config(cfg: ConfigFile, p_name: String = "") -> Dictionary:
	var profile := ControlProfile.new()
	profile.name = p_name
	var errors := PackedStringArray()
	for section: String in cfg.get_sections():
		if not [SECTION_PROFILE, SECTION_BINDINGS, SECTION_DEADZONES].has(section):
			errors.append("[%s]: unknown section (expected [%s], [%s], [%s])" % [section, SECTION_PROFILE,
					SECTION_BINDINGS, SECTION_DEADZONES])
	if cfg.has_section(SECTION_PROFILE):
		var format: Variant = cfg.get_value(SECTION_PROFILE, "format", FORMAT_VERSION)
		if typeof(format) != TYPE_INT or int(format) != FORMAT_VERSION:
			errors.append("profile.format: this build reads format %d, got %s" % [FORMAT_VERSION, format])
		profile.description = str(cfg.get_value(SECTION_PROFILE, "description", ""))
		for key: String in cfg.get_section_keys(SECTION_PROFILE):
			if key != "format" and key != "description":
				errors.append("profile.%s: unknown key" % key)
	if cfg.has_section(SECTION_BINDINGS):
		for key: String in cfg.get_section_keys(SECTION_BINDINGS):
			var value: Variant = cfg.get_value(SECTION_BINDINGS, key)
			var list: Array = []
			if typeof(value) == TYPE_STRING:
				list.append(value)
			elif value is Array or value is PackedStringArray:
				for item: Variant in value:
					list.append(item)
			else:
				errors.append("%s.%s: expected a list of text descriptors" % [SECTION_BINDINGS, key])
				continue
			for i: int in list.size():
				if typeof(list[i]) != TYPE_STRING:
					errors.append("%s.%s[%d]: expected text, got %s" % [SECTION_BINDINGS, key, i,
							type_string(typeof(list[i]))])
					list[i] = _UNREPRESENTABLE + str(list[i])
			profile.bindings[StringName(key)] = list
	if cfg.has_section(SECTION_DEADZONES):
		for key: String in cfg.get_section_keys(SECTION_DEADZONES):
			profile.deadzones[StringName(key)] = cfg.get_value(SECTION_DEADZONES, key)
	errors.append_array(profile.validate())
	return {"ok": errors.is_empty(), "profile": profile, "errors": errors}


# --- Private -----------------------------------------------------------------------------------------------------


# ACTIONS order first (the layout of §6.1), then anything else alphabetically.
static func _ordered_actions(table: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	for action: StringName in InputAdapter.ACTIONS:
		if table.has(action):
			out.append(action)
	var extra: Array[String] = []
	for key: Variant in table.keys():
		if not InputAdapter.ACTIONS.has(StringName(key)):
			extra.append(String(key))
	extra.sort()
	for key: String in extra:
		out.append(StringName(key))
	return out


static func _bad_descriptor(message: String) -> Dictionary:
	return {"ok": false, "descriptor": "", "event": null, "error": message}


static func _good_descriptor(descriptor: String, event: InputEvent) -> Dictionary:
	return {"ok": true, "descriptor": descriptor, "event": event, "error": ""}


static func _parse_pad_button(text: String) -> Dictionary:
	if not text.is_valid_int():
		return _bad_descriptor("pad button index must be a number 0-%d, got '%s'" % [MAX_PAD_BUTTON, text])
	var index: int = text.to_int()
	if index == GUIDE_BUTTON:
		return _bad_descriptor("pad button 5 is Guide, which is not used (standard buttons are 0-%d)" % MAX_PAD_BUTTON)
	if index < 0 or index > MAX_PAD_BUTTON:
		return _bad_descriptor("pad button %d is outside the standard layout (0-%d)" % [index, MAX_PAD_BUTTON])
	var event := InputEventJoypadButton.new()
	event.device = -1
	event.button_index = index as JoyButton
	return _good_descriptor("pad:button:%d" % index, event)


static func _parse_pad_axis(text: String) -> Dictionary:
	var sign_char: String = text.right(1)
	var digits: String = text.left(text.length() - 1)
	if (sign_char != "+" and sign_char != "-") or not digits.is_valid_int():
		return _bad_descriptor("pad axis must be <0-%d>+ or <0-%d>-, got '%s'" % [MAX_PAD_AXIS, MAX_PAD_AXIS, text])
	var index: int = digits.to_int()
	if index < 0 or index > MAX_PAD_AXIS:
		return _bad_descriptor("pad axis %d is outside the standard layout (0-%d)" % [index, MAX_PAD_AXIS])
	if index >= JOY_AXIS_TRIGGER_LEFT and sign_char == "-":
		return _bad_descriptor("pad axis %d is a trigger and only reads in the + direction" % index)
	var event := InputEventJoypadMotion.new()
	event.device = -1
	event.axis = index as JoyAxis
	event.axis_value = 1.0 if sign_char == "+" else -1.0
	return _good_descriptor("pad:axis:%d%s" % [index, sign_char], event)


static func _parse_key(text: String) -> Dictionary:
	var key_name: String = text.strip_edges()
	var code: int = OS.find_keycode_from_string(key_name)
	if code == KEY_NONE:
		code = OS.find_keycode_from_string(key_name.replace("_", " "))
	if code == KEY_NONE:
		return _bad_descriptor("unknown key name '%s' (Godot's names: E, Space, Left, F3, Kp 0 ...)" % key_name)
	if (code & KEY_MODIFIER_MASK) != 0:
		return _bad_descriptor("'%s' uses a modifier; bind one plain key" % key_name)
	if code == KEY_QUOTELEFT:
		return _bad_descriptor("key:QuoteLeft is the console key and cannot be bound to an action")
	var event := InputEventKey.new()
	event.device = -1
	event.physical_keycode = code as Key
	return _good_descriptor("key:" + OS.get_keycode_string(code as Key), event)


static func _parse_mouse(text: String) -> Dictionary:
	if not text.is_valid_int() or not MOUSE_BUTTONS.has(text.to_int()):
		return _bad_descriptor("mouse button must be 1 (left), 2 (right), 3 (middle), 8 or 9 (side), got '%s'" % text)
	var event := InputEventMouseButton.new()
	event.device = -1
	event.button_index = text.to_int() as MouseButton
	return _good_descriptor("mouse:%d" % text.to_int(), event)
