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
	&"target_hold_s": {"type": TYPE_FLOAT, "default": 0.35, "min": 0.15, "max": 1.0,
		"doc": "Hold a target button this long for its second function (pad B: previous target; keyboard B, Mouse 2: nearest the nose); a shorter tap selects the next target"},
	&"assist_default": {"type": TYPE_BOOL, "default": true,
		"doc": "Flight assist state at spawn"},
	&"fuel_unlimited": {"type": TYPE_BOOL, "default": true,
		"doc": "Reaction mass is never drawn down (the fuel gauge stays full); off = a finite tank that can run dry"},
	&"friendly_fire": {"type": TYPE_BOOL, "default": false,
		"doc": "Bolts hurt any ship but their shooter, allies and the player included; off = only hostile ships (and buoys) take hits"},
	&"ram_damage": {"type": TYPE_BOOL, "default": true,
		"doc": "Collisions hurt by the velocity change they cause (rams); off = ships still bounce but take no damage"},
	&"camera_default": {"type": TYPE_ENUM, "default": &"chase", "choices": [&"chase", &"cockpit"],
		"doc": "Camera mode at spawn"},
	&"particle_density": {"type": TYPE_FLOAT, "default": 1.0, "min": 0.0, "max": 1.0,
		"doc": "How much of each spark and debris burst is thrown, 0 (none) to 1 (full); 0 costs nothing per frame (M3-T23)"},
	&"lens_flare": {"type": TYPE_BOOL, "default": true,
		"doc": "Lens flare and glare from the star, hidden behind hulls (M3-T25)"},
	&"motion_blur": {"type": TYPE_BOOL, "default": false,
		"doc": "Smear the stars and hulls on fast turns; off asks the renderer for nothing (M3-T25)"},
	&"motion_blur_strength": {"type": TYPE_FLOAT, "default": 0.5, "min": 0.0, "max": 1.0,
		"doc": "How much of each frame's motion the blur smears, 0 (none) to 1 (the whole frame) (M3-T25)"},
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
	&"scenario": {"type": TYPE_ENUM, "default": &"combat_sandbox", "choices": [&"combat_sandbox", &"free_flight", &"instructor_route", &"dogfight"],
		"doc": "The scenario the game loads: the wave sandbox, free flight with the nav buoys, or the instructor's route"},
	&"sfx_volume": {"type": TYPE_FLOAT, "default": 0.8, "min": 0.0, "max": 1.0,
		"doc": "Gain of the SFX audio bus, 0 (silent) to 1 (full)"},
	&"show_hud": {"type": TYPE_BOOL, "default": true,
		"doc": "Show the combat HUD (target box, lead reticle, radar, gauges)"},
	&"hud_targeting_grid": {"type": TYPE_BOOL, "default": false,
		"doc": "Show the targeting grid in the chase view too (in the cockpit view it is on the console's octagon)"},
	&"hud_chase_opacity": {"type": TYPE_FLOAT, "default": 0.7, "min": 0.1, "max": 1.0,
		"doc": "How opaque the HUD is in the chase view (the cockpit view always draws it fully)"},
	&"cockpit_light_energy": {"type": TYPE_FLOAT, "default": 1.0, "min": 0.0, "max": 8.0,  # M4-T30b (Q37): a subtler red cabin
		"doc": "Brightness of the cabin lamp that lights the cockpit frame in the first-person view (applies on the next spawn)"},
	&"cabin_glow_level": {"type": TYPE_FLOAT, "default": 0.3, "min": 0.0, "max": 2.0,
		"doc": "How much red the cockpit glow adds in the canopy, seen from outside"},
	&"cabin_glow_view_m": {"type": TYPE_FLOAT, "default": 150.0, "min": 1.0, "max": 2000.0,
		"doc": "How far off the cockpit glow can be seen, m (it fades over the last fifth)"},
	&"running_light_min_px": {"type": TYPE_FLOAT, "default": 1.0, "min": 0.5, "max": 12.0,
		"doc": "A running light is never smaller than this on screen, radius in pixels; past that it dims by the inverse square instead"},
	&"hud_velocity_marker": {"type": TYPE_BOOL, "default": false,
		"doc": "Also draw the prograde / retrograde marker in the world (it is only on screen when you fly near your nose); the drift sphere is always drawn"},
	&"physics_jitter_fix": {"type": TYPE_FLOAT, "default": 0.5, "min": 0.0, "max": 2.0,
		"doc": "Debug switch: Godot's physics jitter fix (Engine.physics_jitter_fix); 0 turns the frame-time smoothing off"},
	&"show_fps": {"type": TYPE_BOOL, "default": false,
		"doc": "Show the console FPS counter"},
	&"console_enabled": {"type": TYPE_BOOL, "default": true,
		"doc": "Allow the ` key to open the debug console"},
	&"console_pause_on_open": {"type": TYPE_BOOL, "default": false,
		"doc": "Pause the game while the console is open"},
	&"ai_think_rate": {"type": TYPE_BOOL, "default": true,
		"doc": "AI ships far from the player think at ai_think_far_hz and hold their last command between (M4-T04); off = every AI ship thinks every tick"},
	&"ai_think_near_m": {"type": TYPE_FLOAT, "default": 2000.0, "min": 0.0, "max": 100000.0,
		"doc": "AI ships within this distance of the player think every tick; farther ones (and every one with no player alive) think at ai_think_far_hz"},
	&"ai_think_far_hz": {"type": TYPE_FLOAT, "default": 20.0, "min": 1.0, "max": 60.0,
		"doc": "How often a far AI ship thinks, Hz, on staggered physics ticks (20 = every third tick at 60 Hz)"},
	&"ai_nearest_k": {"type": TYPE_INT, "default": 12, "min": 0, "max": 64,
		"doc": "An AI ship scores, avoids and checks its fire lane against its nearest this many contacts (M4-T04); when that cuts any, the nearest hostile ship, its target, wing, objective and latest attacker are kept too; 0 = every contact"},
	&"perf_native": {"type": TYPE_BOOL, "default": true,
		"doc": "Run the hot paths in the native library when it is built (M4-T05); off = the GDScript code, for pairing the two in one process"},
	# M4-T10
	&"perf_native_flight": {"type": TYPE_BOOL, "default": true,
		"doc": "Fly every AI ship's flight model in the native batch (M4-T10) when perf_native is on and the library is built; off = each ship's own GDScript model, for pairing the two in one process"},
	# M4-T09
	&"ai_nearest_static_k": {"type": TYPE_INT, "default": 4, "min": 0, "max": 32,
		"doc": "An AI ship avoids its nearest this many rocks and mines within 5 km (M4-T09); they are never among its contacts; 0 = none"},
	# M4-T11
	&"far_ship_dot_m": {"type": TYPE_FLOAT, "default": 3000.0, "min": 500.0, "max": 50000.0,
		"doc": "Past this distance from the camera an AI ship is drawn as a dot: no hull, plumes or markers (M4-T11); it shows its detail again a tenth inside"},
	# M4-T14
	&"collision_layers": {"type": TYPE_BOOL, "default": true,
		"doc": "Jolt layers by kind (M4-T14): fighters, the player, capitals and rocks each pair only with what can hit them (fighters with fighters too, Q33); off puts every body on the one default layer. Ships follow it at once, capitals and rocks as they are built"},
	&"far_ship_interpolation_off": {"type": TYPE_BOOL, "default": true,
		"doc": "A far-dot AI ship's body is not interpolated, so a rebase leaves its nodes out of the interpolation reset (M4-T14)"},
	# M4-T15
	&"perf_native_core": {"type": TYPE_BOOL, "default": true,
		"doc": "The native simulation core feeds the contact scan, the hit sweep, the flight step and the ram broad phase from one sync a tick (M4-T15) when perf_native is on and the library is built; off = each class loads its own copy, for pairing the two in one process"},
	# M4-T20
	&"perf_native_weapons": {"type": TYPE_BOOL, "default": true,
		"doc": "The stand-ins' turrets, interceptors, beams, missiles and mines step as native kernels over the core's rows (M4-T20) when the core is on; off = the GDScript stand-ins, the reference, for pairing the two in one process"},
	# M4-T17
	&"perf_native_brains": {"type": TYPE_BOOL, "default": true,
		"doc": "Every AiPilot thinks in the native brains over the core's rows (M4-T17) when perf_native and perf_native_core are on and the library is built; off = the GDScript brains, for pairing the two in one process"},
	# M4-T18
	&"perf_threads": {"type": TYPE_INT, "default": 0, "min": 0, "max": 64,
		"doc": "Worker threads for the native core's per-ship passes, the brains and the flight step (M4-T18): 0 = as many threads as the machine has performance cores, 1 = the main thread alone; outputs are the same bits whatever the count; live"},
	# M4-T30a
	&"ambient_level": {"type": TYPE_FLOAT, "default": 0.3, "min": 0.0, "max": 2.0,
		"doc": "The environment's ambient light, white at this energy: what the textured meshes and every other lit surface get on every side (M4-T30a, live)"},
	# M4-T34
	&"perf_native_bolt_sync": {"type": TYPE_BOOL, "default": true,
		"doc": "The core's two bolt reads a tick go through the cheaper native reader (M4-T34) when the core is on; off = the core's own read, the reference, for pairing the two in one process"},
	&"perf_ram_contact_columns": {"type": TYPE_BOOL, "default": true,
		"doc": "The ram resolver hands its contact tracker columns and builds contact lists only for the hulls Jolt reports touching (M4-T34); off = a sample per hull every tick, the reference, for pairing the two in one process"},
	&"perf_ram_sweep_cull": {"type": TYPE_BOOL, "default": true,
		"doc": "The ram resolver's swept test first checks a hull's bounding sphere, then each volume's, against the other hull's box and places only the volumes that can reach it (M4-T34; the same answers); off = every volume placed, the reference"},
	&"perf_targeting_on_read": {"type": TYPE_BOOL, "default": true,
		"doc": "The player's targeting computer checks its selection every tick and builds its list of every target only when it is read, the HUD's and the radar's once a frame (M4-T34; the same selection); off = the list built every tick, the reference"},
	&"perf_native_sweep_cells": {"type": TYPE_BOOL, "default": true,
		"doc": "The native hit broad phase keeps its grid's cells in hash maps (M4-T34; the same pairs and work); off = the sorted cells, the reference"},
}

## Keys that were renamed: old name -> current name. `Settings.revert` reads a saved file's old key when the current
## one is absent, and the next `save` writes only the current name.
## (The D-pad yaw ramp, `yaw_ramp_s` and before it `roll_ramp_s`, went with M3-T15: the stick yaws now. `revert` reads
## only schema keys, so a saved file's old line is ignored and dropped on the next `save`.)
const RENAMED: Dictionary = {}

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
		TYPE_INT:
			return "int %s..%s" % [entry["min"], entry["max"]]
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
		TYPE_INT:
			if typeof(value) != TYPE_INT and not (typeof(value) == TYPE_FLOAT and float(value) == floorf(float(value))):
				return _fail("%s expects a whole number, got %s" % [key, str(value)])
			var i: int = int(value)
			if i < int(entry["min"]) or i > int(entry["max"]):
				return _fail("%s must be in %s..%s, got %s" % [key, entry["min"], entry["max"], i])
			return _ok(i)
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
		TYPE_INT:
			if not t.is_valid_int():
				return _fail("%s expects a whole number, got '%s'" % [key, t])
			return validate(key, t.to_int())
		TYPE_ENUM:
			return validate(key, StringName(t.to_lower()))
		TYPE_STRING:
			return validate(key, t)
	return _fail("%s has an unsupported schema type" % key)


func _ok(value: Variant) -> Dictionary:
	return {"ok": true, "value": value, "error": ""}


func _fail(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}
