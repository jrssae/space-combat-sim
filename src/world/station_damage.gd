class_name StationDamage
extends RefCounted
## A station's damage by what a shot hits (M10-T65, Q72), the capitals' rules on Babylon 5's own ledgers: its damage sections
## (`StationSections`) and its grid mounts' health (`GridMountHealth`). Pure.
##
## - A grid mount within reach of the hit takes the full damage and the hull's total `subsystem_hull_share` of it (its section
##   none); a hit in the command (bridge) or reactor section is a hit on that subsystem, in full, with the same share
##   off the total; any other hit is hull damage, off its section and the total; a lost section's hits go to the total.
## - The reactor at 0, or the total at 0, destroys the station; the command section at 0 or the total below `hulk_below` of its
##   points leaves it a hulk with no power (`Station` puts out its lights and stops its grid, launches and docking).
## - The station is always destructible: no mission flag protects it (a mission that needs it fails when it is lost).

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
var hull_hp: float = 1.0
var is_disabled: bool = false
var is_destroyed: bool = false
## The section that blew ("" until one does, or when the hull ran out).
var blown: String = ""
## Wears grid mount `index` by `amount` (the station's grid, so a knocked-out mount stops); null wears `mounts` alone.
var wear_mount: Callable = Callable()

var _share: float = 0.5
var _hulk_below: float = 0.1


## The rules over `p_sections` and `p_mounts` (null: no grid), the sections named in `section_kinds` (name -> kind) being the
## station's bridge and reactor. The hull's total is the sections' points together.
static func make(p_sections: StationSections, p_mounts: GridMountHealth, section_kinds: Dictionary) -> StationDamage:
	var out := StationDamage.new()
	out.sections = p_sections
	out.mounts = p_mounts
	out._share = CapitalData.section_rule("subsystem_hull_share")
	out._hulk_below = CapitalData.section_rule("hulk_below")
	var total: float = 0.0
	for i: int in p_sections.count():
		out.kinds.append(str(section_kinds.get(String(p_sections.sections[i]["name"]), "structure")))
		total += p_sections.max_health[i]
	out.hull_max = maxf(total, HullHealth.MIN_MAX_HP)
	out.hull_hp = out.hull_max
	return out


## A hit of `damage` at `local` in `body`'s frame (`StationHardpoints.FRAME` or `DRUM`). Returns the hull points it removed.
func hit(body: String, local: Vector3, damage: float) -> float:
	if is_destroyed or not (damage > 0.0):
		return 0.0
	var index: int = sections.section_at(body, local)
	var mount: int = mounts.nearest(body, local) if mounts != null and index >= 0 and not sections.is_lost(index) else -1
	return _land(index, mount, damage)


## A hit of `damage` on section `index` itself, no mount struck (the console's). Returns the hull points removed.
func hit_section(index: int, damage: float) -> float:
	if is_destroyed or not (damage > 0.0) or index < 0 or index >= sections.count():
		return 0.0
	return _land(index, -1, damage)


func has_power() -> bool:
	return not is_disabled and not is_destroyed


func hull_fraction() -> float:
	return clampf(hull_hp / hull_max, 0.0, 1.0)


func is_subsystem(index: int) -> bool:
	return index >= 0 and index < kinds.size() and (kinds[index] == BRIDGE or kinds[index] == REACTOR)


## Whole again (the console's heal): the hull, every section and the station's state; the grid's mounts are the grid's to heal.
func restore() -> void:
	sections.restore()
	hull_hp = hull_max
	is_disabled = false
	is_destroyed = false
	blown = ""


## "fighting", "hulk" or "destroyed (reactor blew)", and the hull's points.
func describe() -> String:
	var state: String = "fighting"
	if is_destroyed:
		state = "destroyed (%s)" % ("%s blew" % blown if not blown.is_empty() else "hull gone")
	elif is_disabled:
		state = "hulk"
	return "%s, hull %.0f/%.0f" % [state, hull_hp, hull_max]


# Lands `damage` on section `index` (-1: the hull alone) and on `mount` when the hit strikes one; the hull's share off the
# total. Returns the hull points removed.
func _land(index: int, mount: int, damage: float) -> float:
	var to_hull: float = damage
	if index >= 0 and not sections.is_lost(index):
		if mount >= 0:
			_wear(mount, damage)
			to_hull = damage * _share
		elif is_subsystem(index):
			_wear_section(index, damage)
			to_hull = damage * _share
		else:
			_wear_section(index, damage)
	if is_destroyed:
		return to_hull
	hull_hp = maxf(hull_hp - to_hull, 0.0)
	if hull_hp <= 0.0:
		_destroy("")
	elif not is_disabled and hull_hp < _hulk_below * hull_max:
		_disable()
	return to_hull


func _wear(mount: int, amount: float) -> void:
	if wear_mount.is_valid():
		wear_mount.call(mount, amount)
	else:
		mounts.wear(mount, amount)


func _wear_section(index: int, amount: float) -> void:
	if not sections.damage(index, amount):
		return
	if kinds[index] == REACTOR:
		_destroy(String(sections.sections[index]["name"]))
	elif kinds[index] == BRIDGE and not is_disabled:
		_disable()


func _disable() -> void:
	if is_disabled or is_destroyed:
		return
	is_disabled = true
	disabled.emit()


func _destroy(section: String) -> void:
	if is_destroyed:
		return
	is_destroyed = true
	blown = section
	hull_hp = 0.0
	destroyed.emit(section)
