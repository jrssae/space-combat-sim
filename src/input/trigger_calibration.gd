class_name TriggerCalibration
extends RefCounted
## Pure trigger rest detection and normalisation (architecture §6.1, generic-pad quirks).
##
## SDL3 normally reports triggers as 0..1, but some generic pads report -1..1 (rest = -1). A pad starts at
## rest 0 (the safe guess: a -1 pad then reads 0 thrust at idle, whereas guessing -1 on a 0..1 pad would read
## half thrust at idle). Any raw sample below -0.5 proves a -1..1 trigger and switches that pad to rest -1
## for good. A pad is reported calibrated after SAMPLE_WINDOW_S of samples. Continuous detection also covers a
## pilot squeezing a trigger during start-up, which a one-shot idle window would get wrong.

const SAMPLE_WINDOW_S := 0.5
const NEGATIVE_REST_THRESHOLD := -0.5

var _rest: Dictionary = {}  # guid -> 0.0 or -1.0
var _sampled_s: Dictionary = {}  # guid -> seconds observed


static func normalize(raw: float, rest: float) -> float:
	return clampf((raw - rest) / (1.0 - rest), 0.0, 1.0)


static func apply_deadzone(value: float, deadzone: float) -> float:
	if value <= deadzone:
		return 0.0
	return minf(1.0, (value - deadzone) / (1.0 - deadzone))


## Seed a pad from saved calibration (Settings `[pads]`).
func set_rest(guid: String, rest: float) -> void:
	_rest[guid] = -1.0 if rest < NEGATIVE_REST_THRESHOLD else 0.0


func get_rest(guid: String) -> float:
	return float(_rest.get(guid, 0.0))


func has_pad(guid: String) -> bool:
	return _rest.has(guid)


## Feed both raw trigger axes of one pad for one tick. Returns true when this sample changed the rest value.
func observe(guid: String, raw_left: float, raw_right: float, dt: float) -> bool:
	var before: float = get_rest(guid)
	if not _rest.has(guid):
		_rest[guid] = 0.0
	if minf(raw_left, raw_right) < NEGATIVE_REST_THRESHOLD:
		_rest[guid] = -1.0
	_sampled_s[guid] = float(_sampled_s.get(guid, 0.0)) + dt
	return get_rest(guid) != before


func is_calibrated(guid: String) -> bool:
	return float(_sampled_s.get(guid, 0.0)) >= SAMPLE_WINDOW_S


## Hot-plug: sample the pad again (a stored -1 stays -1; the hardware cannot have changed range).
func restart(guid: String) -> void:
	_sampled_s[guid] = 0.0


## Trigger value 0..1 for a raw axis on a pad, rest-normalised then deadzoned.
func read(guid: String, raw: float, deadzone: float) -> float:
	return apply_deadzone(normalize(raw, get_rest(guid)), deadzone)
