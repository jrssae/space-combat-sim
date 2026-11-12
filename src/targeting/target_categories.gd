class_name TargetCategories
extends RefCounted
## The target menu's categories (architecture §18.19, M5-T25), pure: which category a candidate falls in for a pilot of a given
## faction at a given place, the nearest few of a category, and the target button's tap. Built from a candidate list on demand
## (the menu opening, a tap), never per tick.
##
## A contact is identified within `IDENT_RANGE_M` (the AI's sensor range) or when it broadcasts (allies, civilians and nav
## buoys carry transponders); anything else is UNKNOWN whatever it really is. An identified contact is a nav beacon
## (NAVIGATION), hostile (ENEMIES), a civilian ship or one of a neutral people (CIVILIAN), or friendly (ALLIES). OBJECTIVES
## holds no candidates: the menu fills it from the mission.

enum Category { ENEMIES, ALLIES, CIVILIAN, UNKNOWN, NAVIGATION, OBJECTIVES }

## Beyond this a contact with no transponder cannot be told apart, m (`ContactScan.SENSOR_RANGE_M`).
const IDENT_RANGE_M: float = 5000.0
## Entries a category's ring shows besides "none".
const RING_SIZE: int = 5
## The first ring, clockwise from the top.
const ORDER: Array[Category] = [Category.ENEMIES, Category.ALLIES, Category.CIVILIAN, Category.UNKNOWN, Category.NAVIGATION,
		Category.OBJECTIVES]
const NAMES: Dictionary = {Category.ENEMIES: "ENEMIES", Category.ALLIES: "ALLIES", Category.CIVILIAN: "CIVILIAN",
		Category.UNKNOWN: "UNKNOWN", Category.NAVIGATION: "NAVIGATION", Category.OBJECTIVES: "OBJECTIVES"}
const COLORS: Dictionary = {Category.ENEMIES: Factions.HOSTILE_COLOR, Category.ALLIES: Factions.FRIENDLY_COLOR,
		Category.CIVILIAN: Color(1.0, 0.72, 0.3), Category.UNKNOWN: Factions.UNIDENTIFIED_COLOR,
		Category.NAVIGATION: Color(0.33, 0.9, 0.9), Category.OBJECTIVES: Color(1.0, 0.85, 0.29)}


## Whether a contact at `range_m` with this broadcast range can be told apart.
static func is_identified(range_m: float, broadcast_range_m: float, ident_range_m: float = IDENT_RANGE_M) -> bool:
	return range_m <= ident_range_m or broadcast_range_m > 0.0


## The category of `info` for a pilot of `own_faction` at `own_position`.
static func category_of(info: TargetInfo, own_position: Vector3, own_faction: StringName,
		ident_range_m: float = IDENT_RANGE_M) -> Category:
	return _category(info, TargetingSystem.range_between(own_position, info.position), own_faction, ident_range_m)


## Every candidate by category, each list nearest first (ties by id): `{Category: Array[TargetInfo]}`, every category present.
static func sort_all(candidates: Array[TargetInfo], own_position: Vector3, own_faction: StringName,
		ident_range_m: float = IDENT_RANGE_M) -> Dictionary:
	var ranges: Dictionary = {}
	var out: Dictionary = {}
	for category: Category in ORDER:
		var empty: Array[TargetInfo] = []
		out[category] = empty
	for info: TargetInfo in candidates:
		var r: float = TargetingSystem.range_between(own_position, info.position)
		ranges[info.id] = r
		(out[_category(info, r, own_faction, ident_range_m)] as Array[TargetInfo]).append(info)
	for category: Category in ORDER:
		(out[category] as Array[TargetInfo]).sort_custom(func(a: TargetInfo, b: TargetInfo) -> bool:
			var ra: float = ranges[a.id]
			var rb: float = ranges[b.id]
			return ra < rb or (ra == rb and a.id < b.id))
	return out


## The count of every category and its nearest `limit` candidates, nearest first (ties by id), in one pass with no full sort:
## `{"counts": {Category: int}, "nearest": {Category: Array[TargetInfo]}}`. What the menu and the tap read.
static func summarise(candidates: Array[TargetInfo], own_position: Vector3, own_faction: StringName, limit: int = RING_SIZE,
		ident_range_m: float = IDENT_RANGE_M) -> Dictionary:
	var counts: Dictionary = {}
	var nearest_of: Dictionary = {}
	var ranges_of: Dictionary = {}
	for category: Category in ORDER:
		var empty: Array[TargetInfo] = []
		counts[category] = 0
		nearest_of[category] = empty
		ranges_of[category] = PackedFloat64Array()
	var hostile: Dictionary = {}  # faction -> relation to `own_faction`, looked up once per faction
	for info: TargetInfo in candidates:
		var r: float = TargetingSystem.range_between(own_position, info.position)
		if not hostile.has(info.faction):
			hostile[info.faction] = Factions.relation(own_faction, info.faction)
		var category: Category = _category_for(info, r, hostile[info.faction], ident_range_m)
		counts[category] += 1
		var kept: Array[TargetInfo] = nearest_of[category]
		var ranges: PackedFloat64Array = ranges_of[category]
		# Its place among the nearest kept so far; beyond the last of a full list it is dropped.
		var at: int = kept.size()
		while at > 0 and (r < ranges[at - 1] or (r == ranges[at - 1] and info.id < kept[at - 1].id)):
			at -= 1
		if at >= limit:
			continue
		kept.insert(at, info)
		ranges.insert(at, r)
		if kept.size() > limit:
			kept.pop_back()
			ranges.remove_at(limit)
		ranges_of[category] = ranges
	return {"counts": counts, "nearest": nearest_of}


## The nearest `limit` candidates of `category`, nearest first.
static func nearest(candidates: Array[TargetInfo], category: Category, own_position: Vector3, own_faction: StringName,
		limit: int = RING_SIZE, ident_range_m: float = IDENT_RANGE_M) -> Array[TargetInfo]:
	return summarise(candidates, own_position, own_faction, maxi(limit, 0), ident_range_m)["nearest"][category]


## The target button's tap: the id of the nearest enemy, or of the 2nd nearest when the nearest is already selected (the next
## tap goes back to the nearest). With no identified enemy the unknown contacts stand in, so a tap is never dead while
## something is out there. `TargetingSystem.NO_TARGET` when there is neither.
static func tap_pick(candidates: Array[TargetInfo], own_position: Vector3, own_faction: StringName, selected_id: int,
		ident_range_m: float = IDENT_RANGE_M) -> int:
	var nearest_of: Dictionary = summarise(candidates, own_position, own_faction, 2, ident_range_m)["nearest"]
	var pool: Array[TargetInfo] = nearest_of[Category.ENEMIES]
	if pool.is_empty():
		pool = nearest_of[Category.UNKNOWN]
	if pool.is_empty():
		return TargetingSystem.NO_TARGET
	if pool.size() > 1 and pool[0].id == selected_id:
		return pool[1].id
	return pool[0].id


static func _category(info: TargetInfo, range_m: float, own_faction: StringName, ident_range_m: float) -> Category:
	return _category_for(info, range_m, Factions.relation(own_faction, info.faction), ident_range_m)


static func _category_for(info: TargetInfo, range_m: float, relation: Factions.Relation, ident_range_m: float) -> Category:
	if not is_identified(range_m, info.broadcast_range_m, ident_range_m):
		return Category.UNKNOWN
	if info.role == Targetable.Role.BEACON:
		return Category.NAVIGATION
	if relation == Factions.Relation.HOSTILE:
		return Category.ENEMIES
	if info.role == Targetable.Role.CIVILIAN or relation != Factions.Relation.FRIENDLY:
		return Category.CIVILIAN
	return Category.ALLIES
