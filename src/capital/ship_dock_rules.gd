class_name ShipDockRules
extends RefCounted
## The numbers and small decisions of docking at a ship (M10-T53, Q84): a hull's options from `data/capitals/ship_docks.json`,
## the way round its keep-out boxes, when a craft turns onto a collar's lane, how fast it backs down it and when it is taken.
## Pure: `ShipDock` flies by it.

const DATA_PATH: String = "res://data/capitals/ship_docks.json"
const DEFAULTS: Dictionary = {
	"join_out_m": 220.0, "join_m": 12.0, "join_max_mps": 6.0, "nose_tol_deg": 6.0, "lane_mps": 14.0, "final_mps": 1.5,
	"final_m": 25.0, "gap_m": 0.3, "capture_m": 0.6, "capture_mps": 2.5, "release_m": 90.0, "approach_mps": 80.0,
	"via_mps": 40.0, "clear_m": 30.0, "via_m": 55.0, "hold_max_mps": 2.0, "range_m": 3000.0, "timeout_s": 300.0, "brake_share": 0.5,
	"keep_out": [],
}

static var _file: Dictionary = {}
static var _loaded: bool = false


## A hull's options: its own entry over the file's defaults over `DEFAULTS`.
static func options(hull_type: StringName) -> Dictionary:
	var file: Dictionary = _read()
	var out: Dictionary = DEFAULTS.duplicate(true)
	var hulls: Dictionary = file.get("hulls", {}) if file.get("hulls") is Dictionary else {}
	for layer: Variant in [file.get("defaults", {}), hulls.get(String(hull_type), {})]:
		for key: Variant in layer if layer is Dictionary else {}:
			if not str(key).begins_with("_"):
				out[key] = (layer as Dictionary)[key]
	return out


## Reads the file again on the next call (tests).
static func reload() -> void:
	_loaded = false


## The way round the hull to `goal` (its frame): its boxes from the options, as the station's (`DockKeepOut`).
static func keep_out(opts: Dictionary, goal: Vector3) -> DockKeepOut:
	return DockKeepOut.build(DockKeepOut.boxes_from(opts.get("keep_out", [])), goal, float(opts["clear_m"]), float(opts["via_m"]))


## The craft's capability as its approach plans with it: `brake_share` of its mains, since a heavy shuttle spends seconds
## turning its engines forward before it brakes, and the lane's start lies between it and the hull.
static func cautious(capability: ShipCapability, opts: Dictionary) -> ShipCapability:
	capability.a_main *= clampf(float(opts["brake_share"]), 0.05, 1.0)
	return capability


## Whether the hull moves too fast against the place's rest for anyone to dock (Q84: it holds station).
static func under_way(speed_mps: float, opts: Dictionary) -> bool:
	return speed_mps > float(opts["hold_max_mps"])


## Whether a craft `distance_m` from the lane's start and moving at `speed_mps` against the hull turns onto the lane.
static func joins(distance_m: float, speed_mps: float, opts: Dictionary) -> bool:
	return distance_m <= float(opts["join_m"]) and speed_mps <= float(opts["join_max_mps"])


## Whether the craft points as it will lie mated: its nose within the tolerance of `nose` and its top of `up` (World, unit).
static func aligned(basis: Basis, nose: Vector3, up: Vector3, opts: Dictionary) -> bool:
	var tol: float = deg_to_rad(float(opts["nose_tol_deg"]))
	return (-basis.z).angle_to(nose) <= tol and basis.y.angle_to(up) <= 2.0 * tol


## What the craft can shed along the lane, m/s2: it backs in when its nose points out (`nose_into` < 0), so its mains brake it.
static func brake_mps2(nose_into: float, capability: ShipCapability) -> float:
	return capability.a_retro if nose_into >= 0.0 else capability.a_main


## Its gain over the last metres, 1/s, and the least it closes at, m/s.
const EASE_PER_S: float = 0.5
const CREEP_MPS: float = 0.2


## The speed down the lane with `to_go_m` left to the mated place: none until it points right, never more than it can still
## shed, a walk over the last metres easing onto the lock, and back out again when it went past (negative).
static func lane_speed(to_go_m: float, is_aligned: bool, brake: float, opts: Dictionary) -> float:
	if not is_aligned:
		return 0.0
	var final_mps: float = float(opts["final_mps"])
	if to_go_m <= float(opts["final_m"]):
		return clampf(to_go_m * EASE_PER_S, -final_mps, final_mps) if to_go_m < 0.0 \
				else minf(final_mps, maxf(to_go_m * EASE_PER_S, CREEP_MPS))
	var slowing: float = StoppingDistance.speed_for_mps(to_go_m - float(opts["final_m"]), brake)
	return minf(float(opts["lane_mps"]), maxf(slowing, final_mps))


## Whether a craft `offset` from its mated place (any frame) at `speed_mps` against the hull is taken and held.
static func captured(offset: Vector3, speed_mps: float, opts: Dictionary) -> bool:
	return offset.length() <= float(opts["capture_m"]) and speed_mps <= float(opts["capture_mps"])


static func _read() -> Dictionary:
	if _loaded:
		return _file
	_loaded = true
	_file = {}
	if FileAccess.file_exists(DATA_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary:
			_file = parsed
		else:
			push_warning("ShipDockRules: %s is not a JSON object" % DATA_PATH)
	return _file
