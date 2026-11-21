class_name CapitalSubsystems
extends RefCounted
## What a pilot can pick on a capital ship (M10-T18, Q17): its bridge, reactor, engines, launch bays and weapon mounts, each
## with its state and health, read from the ship's `CapitalDamage`. Pure. An entry is
##     {key, group, label, state, fraction, works, point}
## where `key` names it for good ("bridge:bridge", "mount:turret_3"), `state` is a `CapitalSection.state_name` (or a mount's own),
## `fraction` its points 0..1, and `point` where it sits in the ship's body frame with the rotating pieces at rest.

const BRIDGE: String = "bridge"
const REACTOR: String = "reactor"
const ENGINES: String = "engines"
const BAYS: String = "bays"
const TURRETS: String = "turrets"
const BEAMS: String = "beams"
const MISSILES: String = "missiles"
## The groups in ring order: with "whole ship" first they fill the eight slices of a ring exactly.
const GROUPS: Array[String] = [BRIDGE, REACTOR, ENGINES, BAYS, TURRETS, BEAMS, MISSILES]
const GROUP_LABELS: Dictionary = {BRIDGE: "BRIDGE", REACTOR: "REACTOR", ENGINES: "ENGINES", BAYS: "LAUNCH BAYS",
		TURRETS: "TURRETS", BEAMS: "BEAM EMITTERS", MISSILES: "MISSILES"}
## Which group a weapon mount's kind belongs to; a kind left out (mines) cannot be picked.
const MOUNT_GROUPS: Dictionary = {"turret": TURRETS, "interceptor": TURRETS, "beam": BEAMS, "missile": MISSILES}
const STATE_LOST: String = "destroyed"
const WHOLE_LABEL: String = "WHOLE SHIP"


## Every subsystem of `damage`'s ship in group order; mounts nearest to `from_point` (body frame) first, so a ring that cuts a
## long list keeps the ones nearest the pilot.
static func list(damage: CapitalDamage, from_point: Vector3 = Vector3.ZERO) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if damage == null:
		return out
	for group: String in GROUPS:
		var members: Array[Dictionary] = []
		match group:
			BRIDGE, REACTOR:
				for name: String in damage.sections:
					var s: CapitalSection = damage.sections[name]
					if s.kind == group:
						members.append(_of_section("%s:%s" % [group, name], group, s.name.replace("_", " ").to_upper(), s))
			ENGINES:
				for name: String in damage.engine_sections:
					members.append(_of_section("engine:%s" % name, group, name.replace("_", " ").to_upper(),
							damage.sections.get(damage.engine_sections[name]), not damage.engine_works(name)))
			BAYS:
				for name: String in damage.bay_sections:
					members.append(_of_section("bay:%s" % name, group, name.replace("_", " ").to_upper(),
							damage.sections.get(damage.bay_sections[name]), not damage.bay_works(name)))
			_:
				for name: String in damage.mounts:
					var m: CapitalMount = damage.mounts[name]
					if MOUNT_GROUPS.get(m.kind, "") == group:
						members.append(_of_mount(damage, m))
				members.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
					return from_point.distance_squared_to(a["point"]) < from_point.distance_squared_to(b["point"]))
		out.append_array(members)
	return out


## The entry named `key` among `entries`, or an empty dictionary ("" is the whole ship).
static func find(entries: Array[Dictionary], key: String) -> Dictionary:
	for entry: Dictionary in entries:
		if entry["key"] == key:
			return entry
	return {}


## The entries of `group`.
static func members(entries: Array[Dictionary], group: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in entries:
		if entry["group"] == group:
			out.append(entry)
	return out


## The key after `key` in `entries`, wrapping through "" (the whole ship) at the end; `step` -1 goes the other way. A key that
## is gone (blown off, not on this ship) counts as the whole ship.
static func cycled(entries: Array[Dictionary], key: String, step: int = 1) -> String:
	var at: int = -1
	for i: int in entries.size():
		if entries[i]["key"] == key:
			at = i
	var n: int = entries.size() + 1  # the whole ship is slot 0
	var next: int = posmod(at + 1 + step, n)
	return "" if next == 0 else str(entries[next - 1]["key"])


## "BRIDGE  DAMAGED 64%": what the target box and a ring slice say.
static func state_text(entry: Dictionary) -> String:
	return "%s %d%%" % [String(entry["state"]).to_upper(), roundi(float(entry["fraction"]) * 100.0)]


static func _of_section(key: String, group: String, label: String, s: CapitalSection, lost: bool = false) -> Dictionary:
	var state: String = CapitalSection.state_name(s.state) if s != null else STATE_LOST
	return {"key": key, "group": group, "label": label, "state": STATE_LOST if lost and state == "intact" else state,
			"fraction": s.fraction() if s != null else 0.0, "works": s != null and not s.lost() and not lost,
			"point": s.box.get_center() if s != null else Vector3.ZERO}


static func _of_mount(damage: CapitalDamage, m: CapitalMount) -> Dictionary:
	var section: CapitalSection = damage.sections.get(m.section)
	var works: bool = damage.mount_works(m.name)
	var state: String = "intact"
	if not m.alive:
		state = STATE_LOST
	elif section != null and section.lost():
		state = CapitalSection.state_name(section.state)
	elif m.hp < m.max_hp:
		state = "damaged"
	return {"key": "mount:%s" % m.name, "group": MOUNT_GROUPS[m.kind], "label": m.name.replace("_", " ").to_upper(), "state": state,
			"fraction": clampf(m.hp / m.max_hp, 0.0, 1.0) if m.max_hp > 0.0 else 0.0, "works": works, "point": m.position}
