class_name StationSections
extends RefCounted
## The station's damage sections (M7-T06, Q5): each has its own health, a hit lowers the section it lands in and no other, and
## a section at zero is lost (once). What a loss does to the station (a hulk, its destruction) is `StationDamage`'s (M10-T65).
## Pure: the sections come from the manifest's hardpoints (`StationHardpoints.damage_sections`), the hits from `Station`.
## The health lives in the native damage store (M10-T75, Q94, `DamageStore`), registered on first use; this is the copy, and
## writing `health` or `max_health` writes the store.

## A section's health when whole (about 830 raider bolts of 6). T07's fix round set it so a 12-raider raid leaves visible
## damage and a cruiser stand-in's whole fight does not lose a section; T10 tunes it again with its raids.
const SECTION_HEALTH: float = 5000.0
## A point this far outside every section's box of its body still lands in the nearest one (a hit on a hull plate's skin).
const SNAP_M: float = 50.0

## A section reached zero (its index); once per loss. A section repaired above zero can be lost again (M7-T35).
signal lost(section: int)

## Per section: `name`, `body` (`drum` or `frame`) and `aabb` (in that body's frame), in the manifest's order.
var sections: Array[Dictionary] = []
var health: PackedFloat64Array = PackedFloat64Array():
	set(value):
		health = value
		_push()
var max_health: PackedFloat64Array = PackedFloat64Array():
	set(value):
		max_health = value
		_push()
## Its ledger's handle in the damage store (-1 until first used), and each body's code there.
var ledger: int = -1
var body_codes: Dictionary = {}


## The sections of a station's hardpoints, each whole at `section_health`.
static func from_hardpoints(hardpoints: StationHardpoints, section_health: float = SECTION_HEALTH) -> StationSections:
	var made := StationSections.new()
	for entry: Dictionary in hardpoints.damage_sections:
		made.sections.append({"name": String(entry["name"]), "body": String(entry["body"]), "aabb": entry["aabb"] as AABB})
		made.max_health.append(section_health)
	made.health = made.max_health.duplicate()
	return made


func count() -> int:
	return sections.size()


## The index of the section called `section_name`, or -1.
func index_of(section_name: String) -> int:
	for i: int in sections.size():
		if sections[i]["name"] == section_name:
			return i
	return -1


## The section a hit at `local` (in `body`'s frame) lands in: the one whose box holds it, else the nearest of that body's within
## `SNAP_M`; -1 when none is near.
func section_at(body: String, local: Vector3) -> int:
	var best: int = -1
	var best_d: float = SNAP_M
	for i: int in sections.size():
		if sections[i]["body"] != body:
			continue
		var box: AABB = sections[i]["aabb"]
		var d: float = (local.clamp(box.position, box.end) - local).length()
		if d < best_d or (d == 0.0 and best_d > 0.0):
			best = i
			best_d = d
		if d == 0.0:
			break
	return best


## Takes `amount` off section `index` (never below zero); true when this hit lost it. Nothing for a section out of range.
func damage(index: int, amount: float) -> bool:
	if index < 0 or index >= health.size() or amount <= 0.0 or health[index] <= 0.0:
		return false
	return replay(DamageStore.store.sections_damage(ensure(), index, amount)) != 0.0


## Adds `amount` to section `index` (never above its full health); true when this brought a lost section back (M7-T35).
func repair(index: int, amount: float) -> bool:
	if index < 0 or index >= health.size() or amount <= 0.0:
		return false
	var out: PackedFloat64Array = DamageStore.store.sections_repair(ensure(), index, amount)
	_take(index, out[1])
	return out[0] != 0.0


func is_whole(index: int) -> bool:
	return index >= 0 and index < health.size() and health[index] >= max_health[index]


## 0..1 health of section `index`.
func fraction(index: int) -> float:
	return health[index] / maxf(max_health[index], 1e-6) if index >= 0 and index < health.size() else 0.0


func is_lost(index: int) -> bool:
	return index >= 0 and index < health.size() and health[index] <= 0.0


## Every section whole again.
func restore() -> void:
	DamageStore.store.sections_restore(ensure())
	var was: bool = DamageStore.quiet
	DamageStore.quiet = true
	health = max_health.duplicate()
	DamageStore.quiet = was


## One line a section: `name health/max`, for the console.
func describe() -> String:
	var parts := PackedStringArray()
	for i: int in sections.size():
		parts.append("%s %.0f/%.0f%s" % [sections[i]["name"], health[i], max_health[i], " LOST" if is_lost(i) else ""])
	return ", ".join(parts)


## Its handle in the damage store, registering the sections as they stand now on first use.
func ensure() -> int:
	if ledger >= 0:
		return ledger
	var bodies := PackedInt32Array()
	var boxes := PackedFloat64Array()
	for entry: Dictionary in sections:
		var body: String = String(entry["body"])
		if not body_codes.has(body):
			body_codes[body] = body_codes.size()
		bodies.append(body_codes[body])
		var box: AABB = entry["aabb"]
		boxes.append_array([box.position.x, box.position.y, box.position.z, box.size.x, box.size.y, box.size.z])
	ledger = int(DamageStore.store.sections_add(bodies, boxes, health, max_health))
	return ledger


## The code body `body` goes by in the store, -1 for one no section sits on.
func body_code(body: String) -> int:
	ensure()
	return int(body_codes.get(body, -1))


## Takes the store's log of a call onto the copy: a section's health, a section lost (`lost`). Its result.
func replay(out: PackedFloat64Array) -> float:
	var i: int = 1
	while i < out.size():
		var code: int = int(out[i])
		if code == DamageStore.ST_SEC_HEALTH:
			_take(int(out[i + 1]), out[i + 2])
		elif code == DamageStore.ST_SEC_LOST:
			lost.emit(int(out[i + 1]))
		i += DamageStore.WIDTH
	return out[0] if not out.is_empty() else 0.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and ledger >= 0 and DamageStore.store != null:
		DamageStore.store.sections_free(ledger)


# Section `index`'s health as the store has it.
func _take(index: int, value: float) -> void:
	var was: bool = DamageStore.quiet
	DamageStore.quiet = true
	health[index] = value
	DamageStore.quiet = was


func _push() -> void:
	if ledger >= 0 and not DamageStore.quiet:
		DamageStore.store.sections_set(ledger, health, max_health)
