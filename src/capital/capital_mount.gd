class_name CapitalMount
extends RefCounted
## One weapon mount of a capital ship (M10-T08, D12.5, Q53): its own hit points (light 300 to beam emitter 2 500, by its
## weapon's kind), the section that holds it and where it sits, so a hit close to it lands on it too and it can be targeted
## (Q17). It dies at 0 or with its section. Pure.

var name: String = ""
## The hardpoint's kind (`turret`, `beam`, `interceptor`, `missile`, `mine`) and its weapon's id (`ea_plasma_heavy`, ...).
var kind: String = ""
var weapon: String = ""
var section: String = ""
## Body frame with the rotating pieces at rest, m.
var position: Vector3 = Vector3.ZERO
## A hit this close lands on it, m.
var reach_m: float = 10.0
var max_hp: float = 800.0
var hp: float = 800.0
var alive: bool = true


## The mount `entry` of the hardpoints' `weapons[]`, its hit points from `CapitalData`; `reach_m` at least `min_reach_m`.
static func from_hardpoint(entry: Dictionary, min_reach_m: float) -> CapitalMount:
	var m := CapitalMount.new()
	m.name = str(entry.get("name", ""))
	m.kind = str(entry.get("kind", ""))
	m.weapon = str(entry.get("weapon", ""))
	m.section = str(entry.get("section", ""))
	var at: Variant = entry.get("position")
	if at is Array and (at as Array).size() == 3:
		m.position = Vector3(float(at[0]), float(at[1]), float(at[2]))
	m.reach_m = maxf(min_reach_m, float(entry.get("barrel_m", 0.0)))
	m.max_hp = CapitalData.mount_hit_points(m.weapon, m.kind)
	m.hp = m.max_hp
	return m


func restore() -> void:
	hp = max_hp
	alive = true
