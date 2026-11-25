class_name CapitalDamage
extends RefCounted
## A capital ship's damage by what a shot hits (M10-T08, D12.5, Q53; M10-T65, Q72). Pure: the manifest's sections and the
## hardpoints in, states and what still works out. No armour: each section holds its share of the hull's points.
##
## - Only the part a shot hits takes its damage. A subsystem (a weapon mount, an engine, a bay within reach of the hit, or the
##   bridge or reactor section itself) takes the full damage and the ship's total `subsystem_hull_share` of it (no section
##   else); any other hit is hull damage, off the section it lands in and the total. A lost section's hits go to the total.
## - A section at 0 is lost with what it holds (mounts, engines, bays). A magazine, fuel or reactor section at 0 blows: the ship
##   is destroyed, a hulk or not. Below `power_stage_at` of its points a reactor gives `power_stage_level` of its power.
## - The bridge at 0, a reactor at or below `reactor_shutdown_at` of its points (Q78), or the total below `hulk_below` of the
##   hull, disables the ship: a hulk with no power (nothing fires, launches or docks; `CapitalShip` puts its lights out). The
##   Vorlons and Shadows explode instead (`CapitalShip`).
##
## `CapitalShip` routes its hits here and acts on the signals; the weapons, bays, helm and HUD read the state.

## A section changed state (`CapitalSection.State`).
signal section_changed(section: String, state: int)
## A weapon mount was lost (shot off, or with its section).
signal mount_lost(mount: String)
## An engine or a bay was lost (shot off, or with its section): its key (`engine:<name>`, `bay:<name>`).
signal part_lost(key: String)
## The thrust it can give changed (an engine lost, the reactor's power down a stage).
signal drive_changed
## It became a hulk: the bridge lost, a reactor shut down, the hull below its last tenth, or scuttled (once per life).
signal disabled
## An explosive section blew: the ship is destroyed (once per life).
signal blew(section: String)

var sections: Dictionary[String, CapitalSection] = {}
var mounts: Dictionary[String, CapitalMount] = {}
## Its engines and bays as parts (by name), with each engine's thrust share and each part's section.
var engines: Dictionary[String, CapitalPart] = {}
var bays: Dictionary[String, CapitalPart] = {}
var engine_shares: Dictionary[String, float] = {}
var engine_sections: Dictionary[String, String] = {}
var bay_sections: Dictionary[String, String] = {}
## The ship's total hull points, which every hit lowers by its hull share (the `HullHealth` takes the same).
var hull_max: float = 1.0
var hull_hp: float = 1.0
var is_disabled: bool = false
var is_destroyed: bool = false
## The section that blew ("" until one does).
var blown: String = ""

var _rules: Dictionary = {}
var _order := PackedStringArray()  # the sections in manifest order (ties go to the earlier)


## The damage model of a hull of `p_hull_max` points from its `sections` (`CapitalSections`) and `hardpoints`.
static func build(p_sections: CapitalSections, hardpoints: Dictionary, p_hull_max: float) -> CapitalDamage:
	return from_entries(p_sections.by_name, hardpoints, p_hull_max)


## The same from section entries by name (`kind`, `piece`, `hull_share`, `aabb_min`, `aabb_max`): a station's too.
static func from_entries(entries: Dictionary, hardpoints: Dictionary, p_hull_max: float) -> CapitalDamage:
	var out := CapitalDamage.new()
	for key: String in CapitalData.SECTION_DEFAULTS:
		out._rules[key] = CapitalData.section_rule(key)
	out.hull_max = maxf(p_hull_max, HullHealth.MIN_MAX_HP)
	out.hull_hp = out.hull_max
	for name: String in entries:
		var raw: Dictionary = entries[name]
		var s := CapitalSection.new()
		s.name = name
		s.kind = str(raw.get("kind", "structure"))
		s.piece = str(raw.get("piece", CapitalSections.HULL))
		s.max_hp = maxf(out.hull_max * float(raw.get("hull_share", 0.0)), HullHealth.MIN_MAX_HP)
		s.hp = s.max_hp
		var lo: Vector3 = _vec3(raw.get("aabb_min"))
		s.box = AABB(lo, _vec3(raw.get("aabb_max")) - lo).abs()
		out.sections[name] = s
		out._order.append(name)
	var reach: float = out._rules["mount_reach_m"]
	for raw: Variant in hardpoints.get("weapons", []):
		if raw is Dictionary:
			var m: CapitalMount = CapitalMount.from_hardpoint(raw, reach)
			out.mounts[m.name] = m
			if out.sections.has(m.section):
				out.sections[m.section].mounts.append(m.name)
	for raw: Variant in hardpoints.get("bays", []):
		if raw is Dictionary:
			var bay: CapitalPart = CapitalPart.bay(raw, out._rules["bay_hit_points"], reach)
			out.bays[bay.name] = bay
			out.bay_sections[bay.name] = bay.section
			if out.sections.has(bay.section):
				out.sections[bay.section].bays.append(bay.name)
	for raw: Variant in hardpoints.get("engines", []):
		if raw is Dictionary:
			var engine: CapitalPart = CapitalPart.engine(raw, out._rules["engine_hit_points"], reach)
			out.engines[engine.name] = engine
			out.engine_shares[engine.name] = maxf(float((raw as Dictionary).get("share", 1.0)), 0.0)
			out.engine_sections[engine.name] = engine.section
			if out.sections.has(engine.section):
				out.sections[engine.section].engines.append(engine.name)
	return out


## A hit of `damage` on section `section_name` at `point` (body frame, rotating pieces at rest): on the subsystem it strikes,
## else on the hull there. Returns the hull points it removed. An unknown section takes the hit on the nearest one.
func hit(section_name: String, point: Vector3, damage: float) -> float:
	if is_destroyed or not (damage > 0.0):
		return 0.0
	var s: CapitalSection = sections.get(section_name)
	if s == null:
		s = nearest(point)
	var part: Object = _part_at(s, point) if s != null and not s.lost() else null
	return _land(s, part, damage)


## A hit of `damage` on subsystem `key` itself (`mount:<name>`, `engine:<name>`, `bay:<name>`, or a section's name: the
## console's and the tests' aimed hits). Returns the hull points it removed; 0 for a key it does not hold.
func hit_part(key: String, damage: float) -> float:
	if is_destroyed or not (damage > 0.0):
		return 0.0
	var part: Object = part_of(key)
	if part != null:
		var s: CapitalSection = sections.get(str(part.get(&"section")))
		return _land(s, part if s == null or not s.lost() else null, damage)
	var section: CapitalSection = sections.get(key)
	return _land(section, null, damage) if section != null else 0.0


## A hit of `damage` on mount `mount_name` itself.
func hit_mount(mount_name: String, damage: float) -> float:
	return hit_part("mount:" + mount_name, damage)


## The mount, engine or bay a key names (`mount:<name>`, `engine:<name>`, `bay:<name>`), or null.
func part_of(key: String) -> Object:
	var at: int = key.find(":")
	if at < 0:
		return null
	var name: String = key.substr(at + 1)
	match key.substr(0, at):
		"mount":
			return mounts.get(name)
		"engine":
			return engines.get(name)
		"bay":
			return bays.get(name)
	return null


## The section nearest `point` (body frame at rest), whatever its state; null with no sections.
func nearest(point: Vector3) -> CapitalSection:
	var best: CapitalSection = null
	var best_d: float = INF
	for name: String in _order:
		var s: CapitalSection = sections[name]
		var d: float = s.distance_to(point)
		if d < best_d:
			best_d = d
			best = s
	return best


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


## The share of full power: 1, or `power_stage_level` while a reactor is below `power_stage_at`; 0 for a hulk or a wreck.
## A hull with no reactor section has full power while it fights. Averaged over several reactors.
func power() -> float:
	if not has_power():
		return 0.0
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


## Whether a reactor still standing is at or below `reactor_shutdown_at` of its points (Q78): it powers the ship down.
func reactor_shut_down() -> bool:
	var at: float = float(_rules["reactor_shutdown_at"])
	for name: String in _order:
		var s: CapitalSection = sections[name]
		if s.kind == CapitalSection.REACTOR and not s.lost() and s.fraction() <= at:
			return true
	return false


## Whether it has power at all: neither a hulk nor destroyed.
func has_power() -> bool:
	return not is_disabled and not is_destroyed


## The ship's hull points left, 0 to 1.
func hull_fraction() -> float:
	return clampf(hull_hp / hull_max, 0.0, 1.0)


## The share of the engines' thrust still standing (0 with no engines).
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
	return engine_share() * power() if has_power() else 0.0


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


## The share of its weapons' rate of fire: 1 while it has power, 0 for a hulk or a wreck.
func fire_rate() -> float:
	return 1.0 if has_power() else 0.0


## Whether weapon mount `mount_name` can fire: alive, its section standing, the ship powered.
func mount_works(mount_name: String) -> bool:
	var m: CapitalMount = mounts.get(mount_name)
	return m != null and m.alive and has_power() and not _section_lost(m.section)


## Whether engine `engine` stands: alive and its section standing (a hulk's drive winds down on its own, `HulkStages`).
func engine_works(engine: String) -> bool:
	var p: CapitalPart = engines.get(engine)
	return p != null and p.alive and not _section_lost(p.section)


## Whether bay `bay` can launch or take a ship in: alive, its section standing, the ship powered.
func bay_works(bay: String) -> bool:
	var p: CapitalPart = bays.get(bay)
	return p != null and p.alive and has_power() and not _section_lost(p.section)


## The mounts, engines and bays that work now, in hardpoint order.
func live_mounts() -> PackedStringArray:
	var out := PackedStringArray()
	for name: String in mounts:
		if mount_works(name):
			out.append(name)
	return out


func live_engines() -> PackedStringArray:
	var out := PackedStringArray()
	for name: String in engines:
		if engine_works(name):
			out.append(name)
	return out


func live_bays() -> PackedStringArray:
	var out := PackedStringArray()
	for name: String in bays:
		if bay_works(name):
			out.append(name)
	return out


## Every section, part and the ship's state whole again.
func restore() -> void:
	for name: String in sections:
		sections[name].restore()
	for name: String in mounts:
		mounts[name].restore()
	for name: String in engines:
		engines[name].restore()
	for name: String in bays:
		bays[name].restore()
	hull_hp = hull_max
	is_disabled = false
	is_destroyed = false
	blown = ""


## One line per section for the console: name, kind, state and points left; then the hull's total.
func describe() -> PackedStringArray:
	var out := PackedStringArray()
	for name: String in _order:
		var s: CapitalSection = sections[name]
		out.append("%s (%s) %s %.0f/%.0f" % [name, s.kind, CapitalSection.state_name(s.state), s.hp, s.max_hp])
	out.append("hull %.0f/%.0f" % [hull_hp, hull_max])
	return out


## The crew scuttles the ship (M10-T10): disabled at once with every section whole, so it stops fighting and winds down into a
## hulk. False when it is already disabled or destroyed.
func scuttle() -> bool:
	if is_disabled or is_destroyed:
		return false
	_disable()
	return true


# Lands `damage` on section `s` (null: the hull alone): on `part` when the hit strikes one (its section untouched: only the part
# hit takes it), else on the section; the hull's share off the total. Returns the hull points removed.
func _land(s: CapitalSection, part: Object, damage: float) -> float:
	var to_hull: float = damage
	var share: float = float(_rules["subsystem_hull_share"])
	if s != null and not s.lost():
		if part != null:
			_wear_part(part, damage)
			to_hull = damage * share
		elif s.is_subsystem():
			_wear_section(s, damage)
			to_hull = damage * share
		else:
			_wear_section(s, damage)
	if is_destroyed:
		return to_hull
	hull_hp = maxf(hull_hp - to_hull, 0.0)
	_check_disabled()
	return to_hull


# The live mount, engine or bay of `s` nearest `point` within its reach, or null.
func _part_at(s: CapitalSection, point: Vector3) -> Object:
	var best: Object = null
	var best_d: float = INF
	for name: String in s.mounts:
		var m: CapitalMount = mounts[name]
		var d: float = m.position.distance_to(point)
		if m.alive and d <= m.reach_m and d < best_d:
			best_d = d
			best = m
	for list: Array in [[s.engines, engines], [s.bays, bays]]:
		for name: String in list[0] as PackedStringArray:
			var p: CapitalPart = (list[1] as Dictionary)[name]
			var d: float = p.position.distance_to(point)
			if p.alive and d <= p.reach_m and d < best_d:
				best_d = d
				best = p
	return best


func _wear_part(part: Object, damage: float) -> void:
	if part is CapitalMount:
		var m := part as CapitalMount
		m.hp = maxf(m.hp - damage, 0.0)
		if m.hp <= 0.0:
			_lose_mount(m)
		return
	var p := part as CapitalPart
	p.hp = maxf(p.hp - damage, 0.0)
	if p.hp <= 0.0:
		_lose_part(p)


func _wear_section(s: CapitalSection, amount: float) -> void:
	var power_before: float = power()
	s.hp = maxf(s.hp - amount, 0.0)
	if s.hp <= 0.0:
		_lose_section(s)
		return
	if s.state == CapitalSection.State.INTACT:
		s.state = CapitalSection.State.DAMAGED
		section_changed.emit(s.name, s.state)
	if power() != power_before:
		drive_changed.emit()


func _lose_mount(m: CapitalMount) -> void:
	if not m.alive:
		return
	m.alive = false
	mount_lost.emit(m.name)


func _lose_part(p: CapitalPart) -> void:
	if not p.alive:
		return
	p.alive = false
	part_lost.emit("%s:%s" % [p.kind, p.name])
	if p.kind == CapitalPart.ENGINE:
		drive_changed.emit()


# Section `s` reached 0: what it holds is lost; an explosive section blows, a lost bridge leaves a hulk.
func _lose_section(s: CapitalSection) -> void:
	s.state = CapitalSection.State.DISABLED
	for name: String in s.mounts:
		_lose_mount(mounts[name])
	for name: String in s.bays:
		_lose_part(bays[name])
	for name: String in s.engines:
		_lose_part(engines[name])
	section_changed.emit(s.name, s.state)
	if s.explosive():
		_blow(s)
		return
	_check_disabled()


func _blow(s: CapitalSection) -> void:
	s.state = CapitalSection.State.DESTROYED
	section_changed.emit(s.name, s.state)
	if is_destroyed:
		return
	is_destroyed = true
	blown = s.name
	blew.emit(s.name)


# A hulk once the bridge is lost, a reactor shuts down or the hull falls below its last tenth; a hull at 0 is destroyed
# instead (`CapitalShip`).
func _check_disabled() -> void:
	if is_disabled or is_destroyed or hull_hp <= 0.0:
		return
	if not has_bridge() or reactor_shut_down() or hull_hp < float(_rules["hulk_below"]) * hull_max:
		_disable()


func _disable() -> void:
	is_disabled = true
	disabled.emit()
	drive_changed.emit()


func _section_lost(name: String) -> bool:
	var s: CapitalSection = sections.get(name)
	return s != null and s.lost()


static func _vec3(raw: Variant) -> Vector3:
	return Vector3(float(raw[0]), float(raw[1]), float(raw[2])) if raw is Array and (raw as Array).size() == 3 else Vector3.ZERO
