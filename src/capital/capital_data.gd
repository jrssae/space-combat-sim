class_name CapitalData
extends RefCounted
## The capital ships' tuning (M8-T08, D83), read once from `data/capitals/capitals.json`: how long each class's jump drive
## needs after a jump before it can open another point, each faction's carrier doctrine (when its fighters go home and
## when the carrier flees; `CarrierTactics.DEFAULTS` lists the keys), and how far each class is heard (M10-T07, Q51). Pure
## apart from the read.

const PATH: String = "res://data/capitals/capitals.json"
## A class the file does not name recharges this long, s.
const DEFAULT_RECHARGE_S: float = 60.0

static var _data: Dictionary = {}
static var _loaded: bool = false


## How long `cls`'s drive needs after a jump, s.
static func jump_recharge_s(cls: StringName) -> float:
	var table: Variant = _read().get("jump_recharge_s")
	var value: Variant = (table as Dictionary).get(String(cls)) if table is Dictionary else null
	return maxf(float(value), 0.0) if value is float or value is int else DEFAULT_RECHARGE_S


## How far a capital of `cls` is heard, by every side, m (M10-T07, Q51): the file's `broadcast_range_m` for the class, or its
## `capital` value for a class it does not name (destroyers, carriers).
static func broadcast_range_m(cls: StringName) -> float:
	var table: Variant = _read().get("broadcast_range_m")
	if not (table is Dictionary):
		return 0.0
	var value: Variant = (table as Dictionary).get(String(cls), (table as Dictionary).get("capital"))
	return maxf(float(value), 0.0) if value is float or value is int else 0.0


## The carrier doctrine of `faction`: the options its raids start from (empty: `CarrierTactics.DEFAULTS` alone).
static func doctrine(faction: StringName) -> Dictionary:
	var table: Variant = _read().get("carrier_doctrine")
	var found: Variant = (table as Dictionary).get(String(faction)) if table is Dictionary else null
	return (found as Dictionary).duplicate() if found is Dictionary else {}


## Reads the file again on the next call (tests).
static func reload() -> void:
	_loaded = false


static func _read() -> Dictionary:
	if not _loaded:
		_loaded = true
		_data = {}
		var file := FileAccess.open(PATH, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
		if parsed is Dictionary:
			_data = parsed
		else:
			push_warning("CapitalData: cannot read %s; defaults are used" % PATH)
	return _data
