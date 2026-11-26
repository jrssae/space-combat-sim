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
##
## The points and states live in the native damage store (M10-T75, Q94, `DamageStore`), which applies these rules; this holds
## the ship's read-only copy, replayed from each call's log, and raises the signals where the log says.

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
var hull_hp: float = 1.0:
	set(value):
		hull_hp = value
		_push(DamageStore.HULL_HP, value)
var is_disabled: bool = false:
	set(value):
		is_disabled = value
		_push(DamageStore.FLAG_DISABLED, 1.0 if value else 0.0)
var is_destroyed: bool = false:
	set(value):
		is_destroyed = value
		_push(DamageStore.FLAG_DESTROYED, 1.0 if value else 0.0)
## The section that blew ("" until one does).
var blown: String = "":
	set(value):
		blown = value
		_push(DamageStore.BLOWN, float(_order.find(value)))
## Its ledger's handle in the damage store.
var ledger: int = -1

var _rules: Dictionary = {}
var _order := PackedStringArray()  # the sections in manifest order (ties go to the earlier)
# The store's lists, in its order: the sections, mounts, engines and bays, and each name's place.
var _section_list: Array[CapitalSection] = []
var _mount_list: Array[CapitalMount] = []
var _engine_list: Array[CapitalPart] = []
var _bay_list: Array[CapitalPart] = []
var _slots: Dictionary = {}  # "mount:<name>", "engine:<name>", "bay:<name>" or a section's name -> [list, slot]


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
	out._register()
	return out


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and ledger >= 0 and DamageStore.store != null:
		DamageStore.store.capital_free(ledger)
		DamageStore.forget(DamageStore.ON_CAPITAL, ledger)
		for s: CapitalSection in _section_list:
			s.ledger = -1
		for list: Array in [_mount_list, _engine_list, _bay_list]:
			for p: Object in list:
				p.set(&"ledger", -1)


## A hit of `damage` on section `section_name` at `point` (body frame, rotating pieces at rest): on the subsystem it strikes,
## else on the hull there. Returns the hull points it removed. An unknown section takes the hit on the nearest one.
func hit(section_name: String, point: Vector3, damage: float) -> float:
	if is_destroyed or not (damage > 0.0):
		return 0.0
	var at: Array = _slots.get(section_name, [])
	var section: int = int(at[1]) if not at.is_empty() and int(at[0]) == DamageStore.PART_SECTION else -1
	return replay(DamageStore.store.capital_hit(ledger, section, point, damage))


## A hit of `damage` on subsystem `key` itself (`mount:<name>`, `engine:<name>`, `bay:<name>`, or a section's name: the
## console's and the tests' aimed hits). Returns the hull points it removed; 0 for a key it does not hold.
func hit_part(key: String, damage: float) -> float:
	if is_destroyed or not (damage > 0.0):
		return 0.0
	var at: Array = _slots.get(key, [])
	if at.is_empty():
		return 0.0
	return replay(DamageStore.store.capital_hit_part(ledger, int(at[0]), int(at[1]), damage))


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
	DamageStore.store.capital_restore(ledger)
	var was: bool = DamageStore.quiet
	DamageStore.quiet = true
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
	DamageStore.quiet = was


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
	return replay(DamageStore.store.capital_scuttle(ledger)) != 0.0


# Registers the ledger with the damage store: the rules, then each section, mount, engine and bay in manifest and hardpoint
# order, each told its handle and place.
func _register() -> void:
	var rules := PackedFloat64Array([_rules["subsystem_hull_share"], _rules["power_stage_at"], _rules["power_stage_level"],
			_rules["reactor_shutdown_at"], _rules["hulk_below"]])
	var packed := PackedFloat64Array()
	for name: String in _order:
		var s: CapitalSection = sections[name]
		s.slot = _section_list.size()
		_section_list.append(s)
		_slots[name] = [DamageStore.PART_SECTION, s.slot]
		packed.append_array([_kind_code(s.kind), s.max_hp, s.hp, s.state, s.box.position.x, s.box.position.y,
				s.box.position.z, s.box.size.x, s.box.size.y, s.box.size.z])
	var lists: Array = [[mounts, _mount_list, DamageStore.PART_MOUNT, "mount:"], [engines, _engine_list, DamageStore.PART_ENGINE,
			"engine:"], [bays, _bay_list, DamageStore.PART_BAY, "bay:"]]
	var packs: Array[PackedFloat64Array] = []
	for list: Array in lists:
		var pack := PackedFloat64Array()
		var by_name: Dictionary = list[0]
		for name: String in by_name:
			var p: Object = by_name[name]
			var at: Array = _slots.get(str(p.get(&"section")), [])
			var pos: Vector3 = p.get(&"position")
			p.set(&"slot", (list[1] as Array).size())
			(list[1] as Array).append(p)
			_slots[str(list[3]) + name] = [list[2], p.get(&"slot")]
			pack.append_array([float(at[1]) if not at.is_empty() else -1.0, pos.x, pos.y, pos.z, p.get(&"reach_m"),
					p.get(&"max_hp"), p.get(&"hp"), 1.0 if p.get(&"alive") else 0.0])
		packs.append(pack)
	ledger = int(DamageStore.store.capital_add(rules, packed, packs[0], packs[1], packs[2], hull_max))
	DamageStore.adopt(DamageStore.ON_CAPITAL, ledger, self)
	for s: CapitalSection in _section_list:
		s.ledger = ledger
	for list: Array in [_mount_list, _engine_list, _bay_list]:
		for p: Object in list:
			p.set(&"ledger", ledger)


static func _kind_code(kind: String) -> int:
	match kind:
		CapitalSection.BRIDGE:
			return 1
		CapitalSection.REACTOR:
			return 2
		CapitalSection.MAGAZINE:
			return 3
		CapitalSection.FUEL:
			return 4
	return 0


## The store's slot of section `section_name`, -1 for one it does not hold (the beams' batch names sections by slot).
func section_slot(section_name: String) -> int:
	var at: Array = _slots.get(section_name, [])
	return int(at[1]) if not at.is_empty() and int(at[0]) == DamageStore.PART_SECTION else -1


## The section at store slot `slot`, "" for none.
func section_name(slot: int) -> String:
	return _order[slot] if slot >= 0 and slot < _order.size() else ""


# The part in list `list` at `slot`.
func _part(list: int, slot: int) -> Object:
	match list:
		DamageStore.PART_ENGINE:
			return _engine_list[slot]
		DamageStore.PART_BAY:
			return _bay_list[slot]
	return _mount_list[slot]


## Takes the store's answer onto the copy in its order, raising each signal where the rules raised it; returns its result
## (a call's, or a beam batch's entries through `DamageStore.apply`).
func replay(out: PackedFloat64Array) -> float:
	var was: bool = DamageStore.quiet
	var i: int = 1
	while i < out.size():
		var code: int = int(out[i])
		var a: float = out[i + 1]
		var b: float = out[i + 2]
		var c: float = out[i + 3]
		i += DamageStore.WIDTH
		DamageStore.quiet = true
		match code:
			DamageStore.SEC_HP:
				_section_list[int(a)].hp = b
			DamageStore.SEC_STATE:
				_section_list[int(a)].state = int(b) as CapitalSection.State
			DamageStore.SECTION_CHANGED:
				var s: CapitalSection = _section_list[int(a)]
				s.state = int(b) as CapitalSection.State
				DamageStore.quiet = was
				section_changed.emit(s.name, s.state)
			DamageStore.PART_HP:
				_part(int(a), int(b)).set(&"hp", c)
			DamageStore.PART_LOST:
				var p: Object = _part(int(a), int(b))
				p.set(&"alive", false)
				DamageStore.quiet = was
				if int(a) == DamageStore.PART_MOUNT:
					mount_lost.emit(str(p.get(&"name")))
				else:
					part_lost.emit("%s:%s" % [p.get(&"kind"), p.get(&"name")])
			DamageStore.DRIVE_CHANGED:
				DamageStore.quiet = was
				drive_changed.emit()
			DamageStore.HULL_HP:
				hull_hp = a
			DamageStore.BECAME_DISABLED:
				is_disabled = true
				DamageStore.quiet = was
				disabled.emit()
			DamageStore.BLEW:
				is_destroyed = true
				blown = _order[int(a)]
				DamageStore.quiet = was
				blew.emit(blown)
	DamageStore.quiet = was
	return out[0] if not out.is_empty() else 0.0


## The writes of a beam batch (`DamageStore.take_writes`): entries `from` to `to` of `entries`, six numbers each, no events.
func take_writes(entries: PackedFloat64Array, from: int, to: int) -> void:
	var was: bool = DamageStore.quiet
	DamageStore.quiet = true
	for i: int in range(from, to, DamageStore.OUT_WIDTH):
		var code: int = int(entries[i + 2])
		if code == DamageStore.SEC_HP:
			_section_list[int(entries[i + 3])].hp = entries[i + 4]
		elif code == DamageStore.HULL_HP:
			hull_hp = entries[i + 3]
		elif code == DamageStore.PART_HP:
			var list: int = int(entries[i + 3])
			if list == DamageStore.PART_MOUNT:
				_mount_list[int(entries[i + 4])].hp = entries[i + 5]
			elif list == DamageStore.PART_ENGINE:
				_engine_list[int(entries[i + 4])].hp = entries[i + 5]
			else:
				_bay_list[int(entries[i + 4])].hp = entries[i + 5]
		elif code == DamageStore.SEC_STATE:
			_section_list[int(entries[i + 3])].state = int(entries[i + 4]) as CapitalSection.State
	DamageStore.quiet = was


func _push(code: int, value: float) -> void:
	if ledger >= 0 and not DamageStore.quiet:
		DamageStore.store.capital_set(ledger, code, 0, 0, value)


func _section_lost(name: String) -> bool:
	var s: CapitalSection = sections.get(name)
	return s != null and s.lost()


static func _vec3(raw: Variant) -> Vector3:
	return Vector3(float(raw[0]), float(raw[1]), float(raw[2])) if raw is Array and (raw as Array).size() == 3 else Vector3.ZERO
