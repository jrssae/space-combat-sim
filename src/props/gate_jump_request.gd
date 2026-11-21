class_name GateJumpRequest
extends RefCounted
## Whether a gate takes the player's request for a jump (M7-T28, maintainer 2026-11-14): only from within 2 km of its mouth, farther
## for a ship closing fast (M8-T18, D84), so a request made at speed still leaves the autopilot room to slow to its run-in.
## Farther out the request is refused with an answer the HUD can show. The range and the answer are data
## (`data/jump/gate_request.json`), read once. Pure.

const PATH: String = "res://data/jump/gate_request.json"
const DEFAULT_RANGE_M: float = 2000.0
const DEFAULT_OUT_OF_RANGE: String = "out of range"
const DEFAULT_HOLD_S: float = 2.0
const DEFAULT_DECEL_MPS2: float = 30.0
const DEFAULT_CAP_M: float = 10000.0

static var _data: Dictionary = {}
static var _loaded: bool = false


## How far from the gate's mouth a request is still taken, m, for a ship closing at `closing_mps` that brakes at `decel_mps2`
## (0: the data's): the base range, plus the hold flown at that speed, plus the autopilot's slowdown to its run-in, capped.
static func range_m(closing_mps: float = 0.0, decel_mps2: float = 0.0) -> float:
	var base: float = _number("range_m", DEFAULT_RANGE_M)
	var speed: float = maxf(closing_mps, 0.0)
	if speed <= 0.0:
		return base
	var decel: float = decel_mps2 if decel_mps2 > 0.0 else _number("decel_mps2", DEFAULT_DECEL_MPS2)
	var run_in: float = GateAutopilot.RUN_IN_MPS
	# Planned as the autopilot flies: at `PLAN_MARGIN` of the ideal braking speed, so the margin squared on the braking.
	var margin: float = StoppingDistance.PLAN_MARGIN
	var slowdown: float = maxf(speed * speed - run_in * run_in, 0.0) / (2.0 * decel * margin * margin)
	var reach: float = base + speed * _number("hold_s", DEFAULT_HOLD_S) + slowdown
	return minf(reach, maxf(_number("range_cap_m", DEFAULT_CAP_M), base))


## The answer to a request from too far out.
static func out_of_range_text() -> String:
	var value: Variant = _read().get("out_of_range")
	return value if value is String and not (value as String).is_empty() else DEFAULT_OUT_OF_RANGE


## Why a request from `distance_m` out is refused, or "" when the gate takes it; `reach_m` is the live range (`range_m(speed)`).
static func refusal(distance_m: float, reach_m: float = -1.0) -> String:
	return "" if distance_m <= (reach_m if reach_m > 0.0 else range_m()) else out_of_range_text()


static func _number(key: String, fallback: float) -> float:
	var value: Variant = _read().get(key)
	return float(value) if (value is float or value is int) and float(value) > 0.0 else fallback


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
