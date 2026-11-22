class_name CapitalDamage
extends RefCounted
## A capital ship's damage by section (M10-T08, D12.5, Q53). Pure: the manifest's sections and the hardpoints in, states and
## what still works out. No armour: each section holds its share of the hull's points.
##
## - A hit lands on its section (and on a live mount within reach, whose points count against the section too). A section at
##   0 is lost with everything it holds: its mounts stop, an engine's thrust share goes, a hangar's bays stop launching.
## - A magazine or fuel section at 0 blows: the ship is destroyed. A reactor at 0 shuts down (power gone: disabled) and blows
##   after another `reactor_overload` of its points. Below `power_stage_at` of its points a reactor gives `power_stage_level`.
## - A lost bridge leaves the ship on last orders at `headless_fire_rate`; it is disabled only with every engine gone too.
## - A hit on a lost section passes `pass_on` of itself to the nearest live section; damage past a section's last point does
##   the same.
##
## `CapitalShip` routes its hits here and acts on the signals; T09 to T11 and T16 to T18 read the state.

## A section changed state (`CapitalSection.State`).
signal section_changed(section: String, state: int)
## A weapon mount was lost (shot off, or with its section).
signal mount_lost(mount: String)
## The thrust it can give changed (an engine lost, the reactor's power down a stage).
signal drive_changed
## Power or control is gone (once per life).
signal disabled
## An explosive section blew: the ship is destroyed (once per life).
signal blew(section: String)

var sections: Dictionary[String, CapitalSection] = {}
var mounts: Dictionary[String, CapitalMount] = {}
## Each engine's thrust share and section; each bay's section.
var engine_shares: Dictionary[String, float] = {}
var engine_sections: Dictionary[String, String] = {}
var bay_sections: Dictionary[String, String] = {}
var is_disabled: bool = false
var is_destroyed: bool = false
## The section that blew ("" until one does).
var blown: String = ""

var _rules: Dictionary = {}
var _order := PackedStringArray()  # the sections in manifest order (ties go to the earlier)


## The damage model of a hull of `hull_max` points from its `sections` (`CapitalSections`) and `hardpoints`.
static func build(p_sections: CapitalSections, hardpoints: Dictionary, hull_max: float) -> CapitalDamage:
	var out := CapitalDamage.new()
	for key: String in CapitalData.SECTION_DEFAULTS:
		out._rules[key] = CapitalData.section_rule(key)
	for name: String in p_sections.by_name:
		var raw: Dictionary = p_sections.by_name[name]
		var s := CapitalSection.new()
		s.name = name
		s.kind = str(raw.get("kind", "structure"))
		s.piece = str(raw.get("piece", CapitalSections.HULL))
		s.max_hp = maxf(hull_max * float(raw.get("hull_share", 0.0)), HullHealth.MIN_MAX_HP)
		s.hp = s.max_hp
		var lo: Vector3 = _vec3(raw.get("aabb_min"))
		s.box = AABB(lo, _vec3(raw.get("aabb_max")) - lo).abs()
		out.sections[name] = s
		out._order.append(name)
	for raw: Variant in hardpoints.get("weapons", []):
		if raw is Dictionary:
			var m: CapitalMount = CapitalMount.from_hardpoint(raw, out._rules["mount_reach_m"])
			out.mounts[m.name] = m
			if out.sections.has(m.section):
				out.sections[m.section].mounts.append(m.name)
	for raw: Variant in hardpoints.get("bays", []):
		if raw is Dictionary:
			var bay: String = str((raw as Dictionary).get("name", ""))
			out.bay_sections[bay] = str((raw as Dictionary).get("section", ""))
			if out.sections.has(out.bay_sections[bay]):
				out.sections[out.bay_sections[bay]].bays.append(bay)
	for raw: Variant in hardpoints.get("engines", []):
		if raw is Dictionary:
			var engine: String = str((raw as Dictionary).get("name", ""))
			out.engine_shares[engine] = maxf(float((raw as Dictionary).get("share", 1.0)), 0.0)
			out.engine_sections[engine] = str((raw as Dictionary).get("section", ""))
			if out.sections.has(out.engine_sections[engine]):
				out.sections[out.engine_sections[engine]].engines.append(engine)
	return out


## A hit of `damage` on section `section_name` at `point` (body frame, rotating pieces at rest). Returns the hull points it
## removed (a reactor's overload removes none). An unknown section takes the hit on the nearest live one.
func hit(section_name: String, point: Vector3, damage: float) -> float:
	if is_destroyed or not (damage > 0.0):
		return 0.0
	var s: CapitalSection = sections.get(section_name)
	if s == null:
		s = nearest_live(point, null)
	return _hit_section(s, point, damage, true) if s != null else 0.0


## A hit of `damage` on mount `mount_name` itself (a targeted subsystem): it lands on the mount and its section.
func hit_mount(mount_name: String, damage: float) -> float:
	var m: CapitalMount = mounts.get(mount_name)
	return hit(m.section, m.position, damage) if m != null else 0.0


## The live section nearest `point` (body frame at rest), not `except`; null when every section is lost.
func nearest_live(point: Vector3, except: CapitalSection) -> CapitalSection:
	var best: CapitalSection = null
	var best_d: float = INF
	for name: String in _order:
		var s: CapitalSection = sections[name]
		if s == except or s.lost():
			continue
		var d: float = s.distance_to(point)
		if d < best_d:
			best_d = d
			best = s
	return best


## The share of full power: 1, or `power_stage_level` while a reactor is below `power_stage_at`, 0 with every reactor lost.
## A hull with no reactor section always has full power. Averaged over several reactors.
func power() -> float:
	var total: float = 0.0
	var count: int = 0
	for name: String in _order:
		var s: CapitalSection = sections[name]
		if s.kind != CapitalSection.REACTOR:
			continue
		count += 1
		if s.lost():
			continue
		total += float(_rules["power_stage_level"]) if s.fraction() <= float(_rules["power_stage_at"]) else 1.0
	return total / float(count) if count > 0 else 1.0


## The share of the engines' thrust whose sections still stand (0 with no engines).
func engine_share() -> float:
	var total: float = 0.0
	var live: float = 0.0
	for engine: String in engine_shares:
		total += engine_shares[engine]
		if engine_works(engine):
			live += engine_shares[engine]
	return live / total if total > 0.0 else 0.0


## The share of full thrust it can give now: the live engines' share at the power it has; 0 disabled or destroyed.
func thrust_fraction() -> float:
	if is_disabled or is_destroyed:
		return 0.0
	return engine_share() * power()


## Whether its bridge stands (a hull with no bridge section always has control).
func has_bridge() -> bool:
	var any: bool = false
	for name: String in _order:
		var s: CapitalSection = sections[name]
		if s.kind == CapitalSection.BRIDGE:
			any = true
			if not s.lost():
				return true
	return not any


## The share of its weapons' rate of fire: 1, `headless_fire_rate` on last orders with the bridge lost, 0 disabled or destroyed.
func fire_rate() -> float:
	if is_disabled or is_destroyed:
		return 0.0
	return 1.0 if has_bridge() else float(_rules["headless_fire_rate"])


## Whether weapon mount `mount_name` can fire: alive, its section standing, the ship neither disabled nor destroyed.
func mount_works(mount_name: String) -> bool:
	var m: CapitalMount = mounts.get(mount_name)
	return m != null and m.alive and not is_disabled and not is_destroyed and not _section_lost(m.section)


func engine_works(engine: String) -> bool:
	return engine_shares.has(engine) and not _section_lost(engine_sections[engine])


func bay_works(bay: String) -> bool:
	return bay_sections.has(bay) and not is_disabled and not is_destroyed and not _section_lost(bay_sections[bay])


## The mounts, engines and bays that work now, in hardpoint order.
func live_mounts() -> PackedStringArray:
	var out := PackedStringArray()
	for name: String in mounts:
		if mount_works(name):
			out.append(name)
	return out


func live_engines() -> PackedStringArray:
	var out := PackedStringArray()
	for name: String in engine_shares:
		if engine_works(name):
			out.append(name)
	return out


func live_bays() -> PackedStringArray:
	var out := PackedStringArray()
	for name: String in bay_sections:
		if bay_works(name):
			out.append(name)
	return out


## Every section, mount and the ship's state whole again.
func restore() -> void:
	for name: String in sections:
		sections[name].restore()
	for name: String in mounts:
		mounts[name].restore()
	is_disabled = false
	is_destroyed = false
	blown = ""


## One line per section for the console: name, kind, state, points left and, for a reactor, its overload.
func describe() -> PackedStringArray:
	var out := PackedStringArray()
	for name: String in _order:
		var s: CapitalSection = sections[name]
		var extra: String = " overload %.0f" % s.overload if s.overload > 0.0 else ""
		out.append("%s (%s) %s %.0f/%.0f%s" % [name, s.kind, CapitalSection.state_name(s.state), s.hp, s.max_hp, extra])
	return out


# The hit lands on `s`: on a live section its mount within reach and its points, the rest past its last point treated as a hit
# on the lost section; on a lost one, a reactor's overload or (once per hit) the share passed on.
func _hit_section(s: CapitalSection, point: Vector3, damage: float, may_pass: bool) -> float:
	if s.lost():
		if s.kind == CapitalSection.REACTOR and s.state == CapitalSection.State.DISABLED:
			s.overload += damage
			if s.overload >= float(_rules["reactor_overload"]) * s.max_hp:
				_blow(s)
			return 0.0
		var next: CapitalSection = nearest_live(point, s) if may_pass else null
		return _hit_section(next, point, damage * float(_rules["pass_on"]), false) if next != null else 0.0
	var m: CapitalMount = _mount_at(s, point)
	if m != null:
		m.hp = maxf(m.hp - damage, 0.0)
		if m.hp <= 0.0:
			_lose_mount(m)
	var power_before: float = power()
	var applied: float = minf(damage, s.hp)
	s.hp -= applied
	if s.hp <= 0.0:
		s.hp = 0.0
		_lose_section(s)
		if not is_destroyed and damage > applied:
			applied += _hit_section(s, point, damage - applied, may_pass)  # past its last point: as a hit on the lost section
		return applied
	if s.state == CapitalSection.State.INTACT:
		s.state = CapitalSection.State.DAMAGED
		section_changed.emit(s.name, s.state)
	if power() != power_before:
		drive_changed.emit()
	return applied


# The live mount of `s` nearest `point` within its reach, or null.
func _mount_at(s: CapitalSection, point: Vector3) -> CapitalMount:
	var best: CapitalMount = null
	var best_d: float = INF
	for name: String in s.mounts:
		var m: CapitalMount = mounts[name]
		var d: float = m.position.distance_to(point)
		if m.alive and d <= m.reach_m and d < best_d:
			best_d = d
			best = m
	return best


func _lose_mount(m: CapitalMount) -> void:
	if not m.alive:
		return
	m.alive = false
	mount_lost.emit(m.name)


# Section `s` reached 0: what it holds is lost; a magazine or fuel section blows, a reactor shuts down.
func _lose_section(s: CapitalSection) -> void:
	s.state = CapitalSection.State.DISABLED
	for name: String in s.mounts:
		_lose_mount(mounts[name])
	section_changed.emit(s.name, s.state)
	if s.kind == CapitalSection.MAGAZINE or s.kind == CapitalSection.FUEL:
		_blow(s)
		return
	if not s.engines.is_empty() or s.kind == CapitalSection.REACTOR:
		drive_changed.emit()
	_check_disabled()


func _blow(s: CapitalSection) -> void:
	s.state = CapitalSection.State.DESTROYED
	section_changed.emit(s.name, s.state)
	if is_destroyed:
		return
	is_destroyed = true
	blown = s.name
	blew.emit(s.name)


# Disabled when power is gone, or control: the bridge lost with every engine gone too (D12.5).
func _check_disabled() -> void:
	if is_disabled or is_destroyed:
		return
	if power() <= 0.0 or (not has_bridge() and engine_share() <= 0.0):
		is_disabled = true
		disabled.emit()
		drive_changed.emit()


## The crew scuttles the ship (M10-T10): disabled at once with every section whole, so it stops fighting and winds down into a
## hulk. False when it is already disabled or destroyed.
func scuttle() -> bool:
	if is_disabled or is_destroyed:
		return false
	is_disabled = true
	disabled.emit()
	drive_changed.emit()
	return true


func _section_lost(name: String) -> bool:
	var s: CapitalSection = sections.get(name)
	return s != null and s.lost()


static func _vec3(raw: Variant) -> Vector3:
	return Vector3(float(raw[0]), float(raw[1]), float(raw[2])) if raw is Array and (raw as Array).size() == 3 else Vector3.ZERO
