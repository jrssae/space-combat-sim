class_name SettingsSchema
extends RefCounted
## Pure description of every user setting: type, default, range or choices (architecture §6.4).
## Parses console text and validates values; knows nothing about files or the scene tree.
## A new setting is one entry in ENTRIES, so the console can list, check and save it automatically.

const TYPE_ENUM := -1  # pseudo type for string settings restricted to `choices`

const ENTRIES: Dictionary = {
	&"control_profile": {"type": TYPE_STRING, "default": "default", "pattern": "^[a-z0-9_]{1,32}$",
		"doc": "Control profile applied at start-up and on change (console: controls list)"},
	&"invert_y": {"type": TYPE_BOOL, "default": false,
		"doc": "Invert pitch: stick back = nose down"},
	&"stick_deadzone": {"type": TYPE_FLOAT, "default": 0.15, "min": 0.0, "max": 0.30,
		"doc": "Radial stick deadzone, rescaled so full deflection still reaches 1"},
	&"trigger_deadzone": {"type": TYPE_FLOAT, "default": 0.05, "min": 0.0, "max": 0.20,
		"doc": "Trigger deadzone applied after rest calibration"},
	&"yaw_ramp_s": {"type": TYPE_FLOAT, "default": 0.25, "min": 0.05, "max": 1.0,
		"doc": "Seconds for D-pad yaw to ramp from 0 to full"},
	&"target_hold_s": {"type": TYPE_FLOAT, "default": 0.35, "min": 0.15, "max": 1.0,
		"doc": "Hold D-pad Up this long to target the nearest to the nose; a shorter tap selects the next target"},
	&"assist_default": {"type": TYPE_BOOL, "default": true,
		"doc": "Flight assist state at spawn"},
	&"fuel_unlimited": {"type": TYPE_BOOL, "default": true,
		"doc": "Reaction mass is never drawn down (the fuel gauge stays full); off = a finite tank that can run dry"},
	&"camera_default": {"type": TYPE_ENUM, "default": &"chase", "choices": [&"chase", &"cockpit"],
		"doc": "Camera mode at spawn"},
	&"camera_chase_smoothing_s": {"type": TYPE_FLOAT, "default": 0.0, "min": 0.0, "max": 0.5,
		"doc": "Chase camera orientation lag, s; 0 = rigid mount locked to the ship"},
	&"chase_bolt_scale": {"type": TYPE_FLOAT, "default": 3.0, "min": 1.0, "max": 10.0,
		"doc": "How much larger bolts are drawn in the chase view (the cockpit view always draws them true size)"},
	&"debug_text_size": {"type": TYPE_FLOAT, "default": 22.0, "min": 8.0, "max": 64.0,
		"doc": "Font size in pixels of the debug overlay text (1080p; it does not scale with the window)"},
	&"mouse_full_rate_px_s": {"type": TYPE_FLOAT, "default": 1200.0, "min": 100.0, "max": 10000.0,
		"doc": "Mouse speed in pixels per second that commands the full turn rate; lower = more sensitive"},
	&"mouse_look_deg_per_px": {"type": TYPE_FLOAT, "default": 0.12, "min": 0.01, "max": 1.0,
		"doc": "Degrees the camera turns per pixel of mouse travel while free look is held"},
	&"show_overlay": {"type": TYPE_BOOL, "default": true,
		"doc": "Show the debug overlay"},
	&"scenario": {"type": TYPE_ENUM, "default": &"combat_sandbox", "choices": [&"combat_sandbox", &"free_flight"],
		"doc": "The scenario the game loads: the wave sandbox, or free flight with the nav buoys"},
	&"sfx_volume": {"type": TYPE_FLOAT, "default": 0.8, "min": 0.0, "max": 1.0,
		"doc": "Gain of the SFX audio bus, 0 (silent) to 1 (full)"},
	&"show_hud": {"type": TYPE_BOOL, "default": true,
		"doc": "Show the combat HUD (target box, lead reticle, radar, gauges)"},
	&"hud_targeting_grid": {"type": TYPE_BOOL, "default": false,
		"doc": "Show the targeting grid in the chase view too (it is always shown in the cockpit view)"},
	&"hud_chase_opacity": {"type": TYPE_FLOAT, "default": 0.7, "min": 0.1, "max": 1.0,
		"doc": "How opaque the HUD is in the chase view (the cockpit view always draws it fully)"},
	&"cockpit_light_energy": {"type": TYPE_FLOAT, "default": 1.6, "min": 0.0, "max": 8.0,
		"doc": "Brightness of the cabin lamp that lights the cockpit frame in the first-person view (applies on the next spawn)"},
	&"hud_velocity_marker": {"type": TYPE_BOOL, "default": false,
		"doc": "Also draw the prograde / retrograde marker in the world (it is only on screen when you fly near your nose); the drift sphere is always drawn"},
	&"hull_splat_sync": {"type": TYPE_BOOL, "default": true,
		"doc": "Debug switch: draw the hull splats at the script-interpolated pose (on). Off lets the engine interpolate the splat node, which GDGS reads as the last physics tick's pose"},
	&"hull_depth_proxy": {"type": TYPE_BOOL, "default": true,
		"doc": "Debug switch: the black depth proxy that hides things behind the splat hull. Off draws no proxy (plumes may then show through the hull)"},
	&"physics_jitter_fix": {"type": TYPE_FLOAT, "default": 0.5, "min": 0.0, "max": 2.0,
		"doc": "Debug switch: Godot's physics jitter fix (Engine.physics_jitter_fix); 0 turns the frame-time smoothing off"},
	&"show_fps": {"type": TYPE_BOOL, "default": false,
		"doc": "Show the console FPS counter"},
	&"console_enabled": {"type": TYPE_BOOL, "default": true,
		"doc": "Allow the ` key to open the debug console"},
	&"console_pause_on_open": {"type": TYPE_BOOL, "default": false,
		"doc": "Pause the game while the console is open"},
}

## Keys that were renamed: old name -> current name. `Settings.revert` reads a saved file's old key when the current
## one is absent, and the next `save` writes only the current name.
const RENAMED: Dictionary = {
	&"roll_ramp_s": &"yaw_ramp_s",  # the D-pad ramp moved from roll to yaw when the two were swapped
}

const _TRUE_WORDS: PackedStringArray = ["true", "on", "1", "yes"]
const _FALSE_WORDS: PackedStringArray = ["false", "off", "0", "no"]


func keys() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: StringName in ENTRIES.keys():
		out.append(key)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


func has_key(key: StringName) -> bool:
	return ENTRIES.has(key)


## Former names of `key` (see `RENAMED`).
func old_names(key: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for old: StringName in RENAMED.keys():
		if RENAMED[old] == key:
			out.append(old)
	return out


func get_entry(key: StringName) -> Dictionary:
	return ENTRIES.get(key, {})


func get_type(key: StringName) -> int:
	return int(get_entry(key).get("type", TYPE_NIL))


func get_default(key: StringName) -> Variant:
	return get_entry(key).get("default")


func get_choices(key: StringName) -> Array:
	return get_entry(key).get("choices", [])


## Human-readable type/range, e.g. "float 0.0..0.3" or "enum chase|cockpit".
func describe(key: StringName) -> String:
	var entry: Dictionary = get_entry(key)
	if entry.is_empty():
		return "unknown"
	match int(entry["type"]):
		TYPE_BOOL:
			return "bool"
		TYPE_FLOAT:
			return "float %s..%s" % [entry["min"], entry["max"]]
		TYPE_ENUM:
			return "enum " + "|".join(PackedStringArray(entry["choices"]))
		TYPE_STRING:
			return "string " + String(entry["pattern"])
	return type_string(int(entry["type"]))


## Validates (and coerces where lossless, e.g. int -> float) a typed value.
## Returns {"ok": bool, "value": Variant, "error": String}.
func validate(key: StringName, value: Variant) -> Dictionary:
	var entry: Dictionary = get_entry(key)
	if entry.is_empty():
		return _fail("unknown setting '%s'" % key)
	match int(entry["type"]):
		TYPE_BOOL:
			if typeof(value) != TYPE_BOOL:
				return _fail("%s expects a bool, got %s" % [key, type_string(typeof(value))])
			return _ok(value)
		TYPE_FLOAT:
			if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
				return _fail("%s expects a float, got %s" % [key, type_string(typeof(value))])
			var f: float = float(value)
			if is_nan(f) or f < float(entry["min"]) or f > float(entry["max"]):
				return _fail("%s must be in %s..%s, got %s" % [key, entry["min"], entry["max"], f])
			return _ok(f)
		TYPE_ENUM:
			if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
				return _fail("%s expects one of %s" % [key, describe(key).trim_prefix("enum ")])
			var name := StringName(value)
			if not (entry["choices"] as Array).has(name):
				return _fail("%s expects one of %s, got '%s'" % [key, describe(key).trim_prefix("enum "), name])
			return _ok(name)
		TYPE_STRING:
			if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
				return _fail("%s expects text, got %s" % [key, type_string(typeof(value))])
			var text := String(value)
			var pattern := RegEx.create_from_string(String(entry["pattern"]))
			if pattern.search(text) == null:
				return _fail("%s must match %s, got '%s'" % [key, entry["pattern"], text])
			return _ok(text)
	return _fail("%s has an unsupported schema type" % key)


## Parses console/config text into a typed value, then validates it.
func parse(key: StringName, text: String) -> Dictionary:
	var entry: Dictionary = get_entry(key)
	if entry.is_empty():
		return _fail("unknown setting '%s'" % key)
	var t := text.strip_edges()
	match int(entry["type"]):
		TYPE_BOOL:
			var lower := t.to_lower()
			if _TRUE_WORDS.has(lower):
				return _ok(true)
			if _FALSE_WORDS.has(lower):
				return _ok(false)
			return _fail("%s expects true/false/on/off/1/0, got '%s'" % [key, t])
		TYPE_FLOAT:
			if not t.is_valid_float():
				return _fail("%s expects a number, got '%s'" % [key, t])
			return validate(key, t.to_float())
		TYPE_ENUM:
			return validate(key, StringName(t.to_lower()))
		TYPE_STRING:
			return validate(key, t)
	return _fail("%s has an unsupported schema type" % key)


func _ok(value: Variant) -> Dictionary:
	return {"ok": true, "value": value, "error": ""}


func _fail(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}
