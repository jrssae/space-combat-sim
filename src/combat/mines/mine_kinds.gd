class_name MineKinds
extends RefCounted
## The three mine kinds' numbers (M10-T15, Q20, Q53; `data/capitals/mines.json`) as the native mine rows (`ScsMineRows`) take
## them, and what each kind's blast is (`BlastTable`'s row of the same name). Pure apart from the read; cached.

const PATH: String = "res://data/capitals/mines.json"
## The kinds in the core's order (`mine_kernels::PROX`, `ENERGY`, `GUIDED`).
const NAMES: Array[StringName] = [&"mine_prox", &"mine_energy", &"mine_guided"]
const PROX: int = 0
const ENERGY: int = 1
const GUIDED: int = 2
## Mirrors of `mine_kernels.rs` (`test_native_constants` compares them): a trigger check runs one tick in this many; a laid mine
## ignores its own ship's touch this long, s; a hull this small is touched as a sphere, m.
const CHECK_TICKS: int = 3
const OWN_GRACE_S: float = 6.0
const FIGHTER_RADIUS_MAX_M: float = 50.0
static var _data: Dictionary = {}


## The index of the kind named `name` (`mine_prox`, ...), or -1.
static func index_of(name: StringName) -> int:
	return NAMES.find(name)


## Whether `name` is a mine kind.
static func is_kind(name: StringName) -> bool:
	return NAMES.has(name)


## Kind `kind`'s row of `mines.json`.
static func row(kind: int) -> Dictionary:
	return ((_read().get("kinds", {}) as Dictionary).get(String(NAMES[kind]), {}) as Dictionary)


## The number `key` of kind `kind`'s row (0 when it has none).
static func number(kind: int, key: String) -> float:
	return float(row(kind).get(key, 0.0))


## The blast kind `kind` goes off with, or null (its `BlastTable` row).
static func blast(kind: int) -> BlastSpec:
	return BlastTable.spec(NAMES[kind])


## What kind `kind` takes in `ScsMineRows.set_spec`: trigger, body, arm, dormant, speed, home range, fuse, capitals only, turn
## rate, blast radius, toughness, radar range.
static func numbers(kind: int) -> PackedFloat64Array:
	var r: Dictionary = row(kind)
	var spec: BlastSpec = blast(kind)
	return PackedFloat64Array([float(r.get("trigger_m", 0.0)), float(r.get("body_m", 3.0)), float(r.get("arm_s", 0.0)),
			float(r.get("dormant_s", 0.0)), float(r.get("speed_mps", 0.0)), float(r.get("home_m", 0.0)), float(r.get("fuse_s", 0.0)),
			1.0 if bool(r.get("capitals_only", false)) else 0.0, float(r.get("turn_rad_s", 0.0)),
			spec.radius_m if spec != null else 0.0, float(r.get("toughness", 1)), float(r.get("radar_m", 1000.0))])


## What a mount laying kind `kind` takes in `ScsMineRows.add_layer` (nearest and farthest target, cycle, count, cap, cone, drop
## speed, clearance), or an empty array for a kind that is not laid in battle.
static func laying(kind: int) -> PackedFloat64Array:
	var r: Variant = (_read().get("laying", {}) as Dictionary).get(String(NAMES[kind]))
	if not (r is Dictionary):
		return PackedFloat64Array()
	var d: Dictionary = r
	return PackedFloat64Array([float(d.get("range_min_m", 0.0)), float(d.get("range_m", 0.0)), float(d.get("cycle_s", 20.0)),
			float(d.get("count", 1)), float(d.get("max_in_play", 1)), float(d.get("cone_deg", 60.0)), float(d.get("drop_mps", 0.0)),
			float(d.get("clearance_m", 20.0))])


## Re-reads the file (tests).
static func reload() -> void:
	_data = {}


static func _read() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = parsed if parsed is Dictionary else {"kinds": {}, "laying": {}}
	return _data
