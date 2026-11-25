class_name CapitalPart
extends RefCounted
## An engine or a launch bay of a capital ship as a part of its own (M10-T65, Q72): its own points, where it sits and how close a
## hit must land to strike it, so a shot on it hurts the part (and half as much the hull) and a lost part stops thrusting or
## launching. It is lost at 0 or with its section. Pure.

const ENGINE: String = "engine"
const BAY: String = "bay"

var name: String = ""
## `ENGINE` or `BAY`.
var kind: String = ""
var section: String = ""
## Body frame with the rotating pieces at rest, m: an engine's nozzle, a bay's mouth.
var position: Vector3 = Vector3.ZERO
## A hit this close lands on it, m; below 0 for a part the hardpoints place nowhere (lost only with its section).
var reach_m: float = 10.0
var max_hp: float = 1500.0
var hp: float = 1500.0
var alive: bool = true


## The engine `entry` of the hardpoints' `engines[]`: its nozzle, reached within its radius plus `min_reach_m`.
static func engine(entry: Dictionary, hit_points: float, min_reach_m: float) -> CapitalPart:
	var p := CapitalPart.new()
	p.kind = ENGINE
	p._read(entry, hit_points)
	p.position = _vec3(entry.get("position"))
	p.reach_m = min_reach_m + maxf(float(entry.get("radius_m", 0.0)), 0.0) if entry.get("position") is Array else -1.0
	return p


## The bay `entry` of the hardpoints' `bays[]`: its mouth (its `exit`, else its centre), reached within half the mouth's
## diagonal (or a tube's radius) plus `min_reach_m`.
static func bay(entry: Dictionary, hit_points: float, min_reach_m: float) -> CapitalPart:
	var p := CapitalPart.new()
	p.kind = BAY
	p._read(entry, hit_points)
	p.position = _vec3(entry.get("exit", entry.get("position")))
	var mouth: Variant = entry.get("mouth_m")
	var half: float = 0.5 * Vector2(float(mouth[0]), float(mouth[1])).length() if mouth is Array and (mouth as Array).size() == 2 \
			else float(entry.get("radius_m", 0.0))
	p.reach_m = min_reach_m + maxf(half, 0.0) if entry.get("exit", entry.get("position")) is Array else -1.0
	return p


func fraction() -> float:
	return clampf(hp / max_hp, 0.0, 1.0) if max_hp > 0.0 else 0.0


func restore() -> void:
	hp = max_hp
	alive = true


func _read(entry: Dictionary, hit_points: float) -> void:
	name = str(entry.get("name", ""))
	section = str(entry.get("section", ""))
	max_hp = maxf(hit_points, 1.0)
	hp = max_hp


static func _vec3(raw: Variant) -> Vector3:
	return Vector3(float(raw[0]), float(raw[1]), float(raw[2])) if raw is Array and (raw as Array).size() == 3 else Vector3.ZERO
