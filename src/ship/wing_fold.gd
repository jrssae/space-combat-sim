class_name WingFold
extends RefCounted
## How an atmospheric shuttle folds its wings for a bay (M10-T17, Q73, Q93: the Kestrel's fold up 90 degrees at their root
## joints, the Centauri shuttle's 110, Q99): the fold's numbers (`data/ships/wing_folds.json`) and the pose of each wing at a
## share of the fold. Pure; `WingFoldNode` draws it from the hull's break-up chunks, the wings already being their own meshes.
##
## A wing turns about its root joint (its chunk's `joint`) round the hull's length (+Z), its tip going up: the starboard wing
## (+X) by +angle, the port wing by -angle.

const DATA_PATH: String = "res://data/ships/wing_folds.json"
## The chunks that are wings.
const WINGS: PackedStringArray = ["wing_l", "wing_r"]

static var _data: Dictionary = {}
static var _loaded: bool = false


## The fold of craft `asset` (`{fold_deg, fold_s, station_bay}`), empty when it does not fold.
static func of_asset(asset: String) -> Dictionary:
	if not _loaded:
		_loaded = true
		var text: String = FileAccess.get_file_as_string(DATA_PATH)
		var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
		_data = parsed if parsed is Dictionary else {}
	var found: Variant = _data.get(asset)
	return (found as Dictionary).duplicate() if found is Dictionary else {}


## Whether craft `asset` flies into the station's docking bay with its wings folded (`station_bay`): it does not fit it spread.
static func folds_for_station(asset: String) -> bool:
	return bool(of_asset(asset).get("station_bay", false))


## Whether a hull's `chunks` (`hardpoints.json`) have both wings as their own pieces, with joints.
static func has_wings(chunks: Array) -> bool:
	var found: int = 0
	for raw: Variant in chunks:
		if raw is Dictionary and WINGS.has(str((raw as Dictionary).get("name", ""))) and (raw as Dictionary).has("joint"):
			found += 1
	return found == WINGS.size()


## Where chunk `chunk` is drawn in the hull's frame with the fold `amount` done (0 spread, 1 folded) of `fold_deg`: its own
## place, a wing turned up about its joint.
static func chunk_transform(chunk: Dictionary, amount: float, fold_deg: float) -> Transform3D:
	var at := Transform3D(Basis.IDENTITY, _vec(chunk.get("offset")))
	var chunk_name: String = str(chunk.get("name", ""))
	if not WINGS.has(chunk_name):
		return at
	return wing_turn(chunk, amount, fold_deg) * at


## How a wing chunk and everything on it (its hit volumes) is turned about its joint with the fold `amount` done.
static func wing_turn(chunk: Dictionary, amount: float, fold_deg: float) -> Transform3D:
	var joint: Vector3 = _vec(chunk.get("joint"))
	var side: float = 1.0 if joint.x >= 0.0 else -1.0
	var turn := Basis(Vector3.BACK, side * deg_to_rad(fold_deg) * clampf(amount, 0.0, 1.0))
	return Transform3D(turn, joint - turn * joint)


## `amount` moved toward `target` by `delta` seconds of a fold that takes `fold_s`, eased at both ends by the caller's draw.
static func advance(amount: float, target: float, delta: float, fold_s: float) -> float:
	return move_toward(amount, target, delta / maxf(fold_s, 0.01))


## The fold's share drawn for `amount` of its time: easing in and out.
static func eased(amount: float) -> float:
	var t: float = clampf(amount, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _vec(v: Variant) -> Vector3:
	return Vector3(float(v[0]), float(v[1]), float(v[2])) if v is Array and (v as Array).size() == 3 else Vector3.ZERO
