class_name GateJumpRequest
extends RefCounted
## Whether a gate takes the player's request for a jump (M7-T28, maintainer 2026-11-14): only from within 2 km of its mouth.
## Farther out the request is refused with an answer the HUD can show. The range and the answer are data
## (`data/jump/gate_request.json`), read once. Pure.

const PATH: String = "res://data/jump/gate_request.json"
const DEFAULT_RANGE_M: float = 2000.0
const DEFAULT_OUT_OF_RANGE: String = "out of range"

static var _data: Dictionary = {}
static var _loaded: bool = false


## How far from the gate's mouth a request is still taken, m.
static func range_m() -> float:
	var value: Variant = _read().get("range_m")
	return float(value) if (value is float or value is int) and float(value) > 0.0 else DEFAULT_RANGE_M


## The answer to a request from too far out.
static func out_of_range_text() -> String:
	var value: Variant = _read().get("out_of_range")
	return value if value is String and not (value as String).is_empty() else DEFAULT_OUT_OF_RANGE


## Why a request from `distance_m` out is refused, or "" when the gate takes it.
static func refusal(distance_m: float) -> String:
	return "" if distance_m <= range_m() else out_of_range_text()


static func _read() -> Dictionary:
	if not _loaded:
		_loaded = true
		var file := FileAccess.open(PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
		if parsed is Dictionary:
			_data = parsed
		else:
			push_error("GateJumpRequest: %s is missing or not a JSON object; the built-in range applies" % PATH)
	return _data
