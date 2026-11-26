class_name StationDamage
extends RefCounted
## A station's damage by what a shot hits (M10-T65, Q72), the capitals' rules on Babylon 5's own ledgers: its damage sections
## (`StationSections`) and its grid mounts' health (`GridMountHealth`). Pure.
##
## - A grid mount within reach of the hit takes the full damage and the hull's total `subsystem_hull_share` of it (its section
##   none); a hit in the command (bridge) or reactor section is a hit on that subsystem, in full, with the same share
##   off the total; any other hit is hull damage, off its section and the total; a lost section's hits go to the total.
## - The reactor at 0, or the total at 0, destroys the station, a hulk or not; the command section at 0, the reactor at or below
##   `reactor_shutdown_at` of its points (Q78) or the total below `hulk_below` of its points leaves it a hulk with no power
##   (`Station` puts out its lights and stops its grid, launches and docking, and docking under way aborts).
## - The station is always destructible: no mission flag protects it (a mission that needs it fails when it is lost).
##
## The points live in the native damage store (M10-T75, Q94, `DamageStore`), which applies these rules; this holds the copy,
## replayed from each call's log with the signals where the log raises them.

## It became a hulk (once per life).
signal disabled
## It is destroyed (once per life): the section that blew, or "" when the hull ran out.
signal destroyed(section: String)

const BRIDGE: String = CapitalSection.BRIDGE
const REACTOR: String = CapitalSection.REACTOR

var sections: StationSections = null
var mounts: GridMountHealth = null
## Each section's kind, in `sections`' order: `bridge`, `reactor` or `structure`.
var kinds := PackedStringArray()
var hull_max: float = 1.0
var hull_hp: float = 1.0:
	set(value):
		hull_hp = value
		_push()
var is_disabled: bool = false:
	set(value):
		is_disabled = value
		_push()
var is_destroyed: bool = false:
	set(value):
		is_destroyed = value
		_push()
## The section that blew ("" until one does, or when the hull ran out).
var blown: String = "":
	set(value):
		blown = value
		_push()
## Told grid mount `index` was knocked out by a hit (the station's grid, so the mount stops); nothing when not set.
var mount_out: Callable = Callable()
## Its ledger's handle in the damage store.
var ledger: int = -1

var _share: float = 0.5
var _hulk_below: float = 0.1
var _shutdown_at: float = 0.1


## The rules over `p_sections` and `p_mounts` (null: no grid), the sections named in `section_kinds` (name -> kind) being the
## station's bridge and reactor. The hull's total is the sections' points together.
static func make(p_sections: StationSections, p_mounts: GridMountHealth, section_kinds: Dictionary) -> StationDamage:
	var out := StationDamage.new()
	out.sections = p_sections
	out.mounts = p_mounts
	out._share = CapitalData.section_rule("subsystem_hull_share")
	out._hulk_below = CapitalData.section_rule("hulk_below")
	out._shutdown_at = CapitalData.section_rule("reactor_shutdown_at")
	var total: float = 0.0
	for i: int in p_sections.count():
		out.kinds.append(str(section_kinds.get(String(p_sections.sections[i]["name"]), "structure")))
		total += p_sections.max_health[i]
	out.hull_max = maxf(total, HullHealth.MIN_MAX_HP)
	out.hull_hp = out.hull_max
	var codes := PackedInt32Array()
	for kind: String in out.kinds:
		codes.append(1 if kind == BRIDGE else (2 if kind == REACTOR else 0))
	var at: int = p_sections.ensure()
	var grid: int = p_mounts.register(p_sections.body_codes) if p_mounts != null else -1
	out.ledger = int(DamageStore.store.station_add(at, grid, codes, PackedFloat64Array([out._share, out._hulk_below,
			out._shutdown_at]), out.hull_max))
	return out


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and ledger >= 0 and DamageStore.store != null:
		DamageStore.store.station_free(ledger)


## A hit of `damage` at `local` in `body`'s frame (`StationHardpoints.FRAME` or `DRUM`). Returns the hull points it removed.
func hit(body: String, local: Vector3, damage: float) -> float:
	if is_destroyed or not (damage > 0.0):
		return 0.0
	return _replay(DamageStore.store.station_hit(ledger, sections.body_code(body), local, damage))


## A hit of `damage` on section `index` itself, no mount struck (the console's). Returns the hull points removed.
func hit_section(index: int, damage: float) -> float:
	if is_destroyed or not (damage > 0.0) or index < 0 or index >= sections.count():
		return 0.0
	return _replay(DamageStore.store.station_hit_section(ledger, index, damage))


func has_power() -> bool:
	return not is_disabled and not is_destroyed


func hull_fraction() -> float:
	return clampf(hull_hp / hull_max, 0.0, 1.0)


func is_subsystem(index: int) -> bool:
	return index >= 0 and index < kinds.size() and (kinds[index] == BRIDGE or kinds[index] == REACTOR)


## Whole again (the console's heal): the hull, every section and the station's state; the grid's mounts are the grid's to heal.
func restore() -> void:
	DamageStore.store.station_restore(ledger)
	var was: bool = DamageStore.quiet
	DamageStore.quiet = true
	sections.health = sections.max_health.duplicate()
	hull_hp = hull_max
	is_disabled = false
	is_destroyed = false
	blown = ""
	DamageStore.quiet = was


## "fighting", "hulk" or "destroyed (reactor blew)", and the hull's points.
func describe() -> String:
	var state: String = "fighting"
	if is_destroyed:
		state = "destroyed (%s)" % ("%s blew" % blown if not blown.is_empty() else "hull gone")
	elif is_disabled:
		state = "hulk"
	return "%s, hull %.0f/%.0f" % [state, hull_hp, hull_max]


# Takes the store's answer onto the copy in its order (sections, grid mounts, the hull), raising each signal where the rules
# raised it; returns its result.
func _replay(out: PackedFloat64Array) -> float:
	var was: bool = DamageStore.quiet
	var i: int = 1
	while i < out.size():
		var code: int = int(out[i])
		var a: float = out[i + 1]
		var b: float = out[i + 2]
		i += DamageStore.WIDTH
		DamageStore.quiet = true
		match code:
			DamageStore.ST_SEC_HEALTH:
				sections.health[int(a)] = b
			DamageStore.ST_SEC_LOST:
				DamageStore.quiet = was
				sections.lost.emit(int(a))
			DamageStore.ST_MOUNT_HEALTH:
				mounts.health[int(a)] = b
			DamageStore.ST_MOUNT_OUT:
				DamageStore.quiet = was
				if mount_out.is_valid():
					mount_out.call(int(a))
			DamageStore.ST_HULL_HP:
				hull_hp = a
			DamageStore.ST_DISABLED:
				is_disabled = true
				DamageStore.quiet = was
				disabled.emit()
			DamageStore.ST_DESTROYED:
				is_destroyed = true
				blown = String(sections.sections[int(a)]["name"]) if a >= 0.0 else ""
				hull_hp = 0.0
				DamageStore.quiet = was
				destroyed.emit(blown)
	DamageStore.quiet = was
	return out[0] if not out.is_empty() else 0.0


func _push() -> void:
	if ledger >= 0 and not DamageStore.quiet:
		DamageStore.store.station_set(ledger, hull_hp, is_disabled, is_destroyed, sections.index_of(blown) if not blown.is_empty() else -1)
