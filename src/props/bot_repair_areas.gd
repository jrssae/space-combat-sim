class_name BotRepairAreas
extends RefCounted
## What the maintenance crew can repair (M7-T35): the station's damage sections (T06) and then its grid mounts (T07), one area
## each, in that order. It says which are damaged, which first (a knocked-out mount or a lost section before a worn one) and where
## a bot works on each, and hands a bot's work to whoever owns the health (`Station.repair_section`, `StationGrid.repair_some`).
## Pure: the health objects are T06's and T07's own, the side effects go through two callables.

var sections: StationSections = null
var mounts: GridMountHealth = null
## Each mount's hardpoint (`name`, `kind`, `body`, `position`, `up`), in the health's order.
var mount_points: Array[Dictionary] = []
## `repair_section.call(index, amount)` and `repair_mount.call(index, amount)`; by default straight on the health objects.
var repair_section: Callable
var repair_mount: Callable


static func make(p_sections: StationSections, p_mounts: GridMountHealth, p_mount_points: Array[Dictionary]) -> BotRepairAreas:
	var made := BotRepairAreas.new()
	made.sections = p_sections
	made.mounts = p_mounts
	made.mount_points = p_mount_points
	made.repair_section = func(i: int, amount: float) -> void: p_sections.repair(i, amount)
	made.repair_mount = func(i: int, amount: float) -> void:
		if p_mounts != null:
			p_mounts.heal(i, amount)
	return made


func section_count() -> int:
	return sections.count() if sections != null else 0


func count() -> int:
	return section_count() + (mounts.count() if mounts != null else 0)


func is_mount(area: int) -> bool:
	return area >= section_count()


func name_of(area: int) -> String:
	if is_mount(area):
		return "mount %s" % mounts.names[area - section_count()]
	return "section %s" % sections.sections[area]["name"]


func is_damaged(area: int) -> bool:
	if is_mount(area):
		return not mounts.is_whole(area - section_count())
	return not sections.is_whole(area)


## 0 for a mount knocked out or a section lost, 1 for one only worn.
func urgency(area: int) -> int:
	if is_mount(area):
		return 0 if mounts.is_out(area - section_count()) else 1
	return 0 if sections.is_lost(area) else 1


## Health now and full, `[health, max]`.
func health_of(area: int) -> Vector2:
	if is_mount(area):
		var i: int = area - section_count()
		return Vector2(mounts.health[i], mounts.max_health[i])
	return Vector2(sections.health[area], sections.max_health[area])


## The damaged areas, the most urgent first, then in order.
func damaged() -> PackedInt32Array:
	var first := PackedInt32Array()
	var then := PackedInt32Array()
	for a: int in count():
		if is_damaged(a):
			if urgency(a) == 0:
				first.append(a)
			else:
				then.append(a)
	first.append_array(then)
	return first


## Adds `amount` of health to `area`; true when it is whole now.
func repair(area: int, amount: float) -> bool:
	if is_mount(area):
		repair_mount.call(area - section_count(), amount)
	else:
		repair_section.call(area, amount)
	return not is_damaged(area)


## Where a bot works on `area`: `name`, `body` (`frame` or `drum`) and, for a section, its name; for a mount its hardpoint.
func target(area: int) -> Dictionary:
	if is_mount(area):
		var m: Dictionary = mount_points[area - section_count()]
		return {"name": String(m["name"]), "mount": true, "body": String(m["body"]), "kind": String(m.get("kind", "")),
				"position": m["position"] as Vector3, "up": (m.get("up", Vector3.UP) as Vector3).normalized()}
	return {"name": String(sections.sections[area]["name"]), "mount": false, "body": String(sections.sections[area]["body"])}
