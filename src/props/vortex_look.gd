class_name VortexLook
extends RefCounted
## The jump vortex's timings and colours as data (M7-T23): `data/jump/vortex_look.json`, read once. `VortexTiming`,
## `GateActivation` and `JumpVortex` take their values from here, so the look is tuned without touching code.

const PATH: String = "res://data/jump/vortex_look.json"

static var _data: Dictionary = {}
static var _loaded: bool = false


## The whole file (empty, with an error, when it is missing or broken).
static func data() -> Dictionary:
	if not _loaded:
		_loaded = true
		var file := FileAccess.open(PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
		if parsed is Dictionary:
			_data = parsed
		else:
			push_error("VortexLook: %s is missing or not a JSON object; the vortex falls back to built-in values" % PATH)
	return _data


## One section of the file (`timing`, `gate`, `point`, `colours`, `look`).
static func section(name: String) -> Dictionary:
	var value: Variant = data().get(name)
	return value if value is Dictionary else {}


## A number from `section_name`, or `fallback` when the file does not give one.
static func number(section_name: String, key: String, fallback: float) -> float:
	var value: Variant = section(section_name).get(key)
	return float(value) if value is float or value is int else fallback


## A linear colour from `[r, g, b]`, or `fallback`.
static func colour(raw: Variant, fallback: Color) -> Color:
	if raw is Array and (raw as Array).size() >= 3:
		var a: Array = raw
		return Color(float(a[0]), float(a[1]), float(a[2]))
	return fallback


## The funnel's two colours going `way` (`arrival` or `departure`): the body and its highlight.
static func funnel_colours(way: String, fallback: Array) -> Array:
	var entry: Variant = section("colours").get(way)
	if entry is Dictionary:
		return [colour((entry as Dictionary).get("colour"), fallback[0]), colour((entry as Dictionary).get("highlight"), fallback[1])]
	return fallback


## The funnel's overall brightness going `way`.
static func brightness(way: String, fallback: float) -> float:
	var entry: Variant = section("colours").get(way)
	if entry is Dictionary and (entry as Dictionary).get("brightness") is float:
		return float((entry as Dictionary)["brightness"])
	return fallback
