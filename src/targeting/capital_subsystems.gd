class_name CapitalSubsystems
extends RefCounted
## What a pilot can pick on a capital ship (M10-T18, Q17; by kind since M10-T65, Q60): its bridge, reactor, engines, launch bays
## and each kind of weapon mount, never one part alone. Picking a kind aims at the nearest of its parts that still stands, picked
## again as parts are lost or the pilot moves, until none is left. Read from the ship's `CapitalDamage`. Pure. An entry is
##     {key, group, label, state, fraction, works, point, part, live, total}
## where `key` is the kind ("engines", "turrets", ...), `part` the part aimed at (`engine:engine_top_r`, `mount:turret_3`, or a
## section's name; "" when none stands), `state` and `fraction` that part's (a `CapitalSection.state_name`, or "destroyed"),
## `works` whether any part stands, `point` the aimed part in the ship's body frame with the rotating pieces at rest, and `live`
## of `total` the parts standing.

const BRIDGE: String = "bridge"
const REACTOR: String = "reactor"
const ENGINES: String = "engines"
const BAYS: String = "bays"
const TURRETS: String = "turrets"
const BEAMS: String = "beams"
const MISSILES: String = "missiles"
## The kinds in ring order: with "whole ship" first they fill the eight slices of a ring exactly.
const GROUPS: Array[String] = [BRIDGE, REACTOR, ENGINES, BAYS, TURRETS, BEAMS, MISSILES]
const GROUP_LABELS: Dictionary = {BRIDGE: "BRIDGE", REACTOR: "REACTOR", ENGINES: "ENGINES", BAYS: "LAUNCH BAYS",
		TURRETS: "TURRETS", BEAMS: "BEAM EMITTERS", MISSILES: "MISSILES"}
## Which kind a weapon mount's hardpoint kind belongs to; a kind left out (mines) cannot be picked.
const MOUNT_GROUPS: Dictionary = {"turret": TURRETS, "interceptor": TURRETS, "beam": BEAMS, "missile": MISSILES}
const STATE_LOST: String = "destroyed"
const WHOLE_LABEL: String = "WHOLE SHIP"


## One entry per kind `damage`'s ship has, in ring order, each aimed at its standing part nearest `from_point` (body frame).
static func list(damage: CapitalDamage, from_point: Vector3 = Vector3.ZERO) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if damage == null:
		return out
	for group: String in GROUPS:
		var parts: Array[Dictionary] = parts_of(damage, group)
		if not parts.is_empty():
			out.append(_entry(group, parts, from_point))
	return out


## The parts of kind `group`: `{part, state, fraction, standing, point}` each, in hardpoint order.
static func parts_of(damage: CapitalDamage, group: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match group:
		BRIDGE, REACTOR:
			for name: String in damage.sections:
				var s: CapitalSection = damage.sections[name]
				if s.kind == group:
					out.append(_part(name, CapitalSection.state_name(s.state), s.fraction(), not s.lost(), s.box.get_center()))
		ENGINES, BAYS:
			var held: Dictionary = damage.engines if group == ENGINES else damage.bays
			for name: String in held:
				var p: CapitalPart = held[name]
				var s: CapitalSection = damage.sections.get(p.section)
				var standing: bool = p.alive and (s == null or not s.lost())
				var point: Vector3 = p.position if p.reach_m >= 0.0 or s == null else s.box.get_center()
				out.append(_part("%s:%s" % [p.kind, name], _state(standing, p.hp < p.max_hp), p.fraction(), standing, point))
		_:
			for name: String in damage.mounts:
				var m: CapitalMount = damage.mounts[name]
				if MOUNT_GROUPS.get(m.kind, "") != group:
					continue
				var s: CapitalSection = damage.sections.get(m.section)
				var standing: bool = m.alive and (s == null or not s.lost())
				var fraction: float = clampf(m.hp / m.max_hp, 0.0, 1.0) if m.max_hp > 0.0 else 0.0
				out.append(_part("mount:%s" % name, _state(standing, m.hp < m.max_hp), fraction, standing, m.position))
	return out


## The entry of kind `key` among `entries`, or an empty dictionary ("" is the whole ship).
static func find(entries: Array[Dictionary], key: String) -> Dictionary:
	for entry: Dictionary in entries:
		if entry["key"] == key:
			return entry
	return {}


## The kind after `key` in `entries`, wrapping through "" (the whole ship) at the end; `step` -1 goes the other way. A key
## that is gone (not on this ship) counts as the whole ship.
static func cycled(entries: Array[Dictionary], key: String, step: int = 1) -> String:
	var at: int = -1
	for i: int in entries.size():
		if entries[i]["key"] == key:
			at = i
	var n: int = entries.size() + 1  # the whole ship is slot 0
	var next: int = posmod(at + 1 + step, n)
	return "" if next == 0 else str(entries[next - 1]["key"])


## "DAMAGED 64%": what the target box and a ring slice say of the aimed part.
static func state_text(entry: Dictionary) -> String:
	return "%s %d%%" % [String(entry["state"]).to_upper(), roundi(float(entry["fraction"]) * 100.0)]


## "TURRET 3": the aimed part as the target box names it; "" for a kind of one part (its label says it) or with none standing.
static func part_label(entry: Dictionary) -> String:
	var part: String = str(entry.get("part", ""))
	if part.is_empty() or int(entry.get("total", 1)) <= 1:
		return ""
	return part.substr(part.find(":") + 1).replace("_", " ").to_upper()


# A kind's entry, aimed at the standing part nearest `from_point`.
static func _entry(group: String, parts: Array[Dictionary], from_point: Vector3) -> Dictionary:
	var aimed: Dictionary = {}
	var live: int = 0
	var best_d: float = INF
	for p: Dictionary in parts:
		if not bool(p["standing"]):
			continue
		live += 1
		var d: float = from_point.distance_squared_to(p["point"])
		if d < best_d:
			best_d = d
			aimed = p
	var label: String = GROUP_LABELS[group]
	if parts.size() > 1:
		label += " %d/%d" % [live, parts.size()]
	return {"key": group, "group": group, "label": label, "state": aimed.get("state", STATE_LOST),
			"fraction": aimed.get("fraction", 0.0), "works": live > 0, "point": aimed.get("point", Vector3.ZERO),
			"part": aimed.get("part", ""), "live": live, "total": parts.size()}


static func _part(key: String, state: String, fraction: float, standing: bool, point: Vector3) -> Dictionary:
	return {"part": key, "state": state, "fraction": fraction, "standing": standing, "point": point}


static func _state(standing: bool, hurt: bool) -> String:
	if not standing:
		return STATE_LOST
	return "damaged" if hurt else "intact"
