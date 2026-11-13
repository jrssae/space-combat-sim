class_name StationSections
extends RefCounted
## The station's damage sections (M7-T06, Q5): each has its own health, a hit lowers the section it lands in and no other, and
## a section at zero is lost (once). The station itself is never destroyed or disabled in M7: a lost section only says so.
## Pure: the sections come from the manifest's hardpoints (`StationHardpoints.damage_sections`), the hits from `Station`.

## A section's health when whole. A starting number (about 3 300 raider bolts of 6): T07 and T10 tune it with the raids.
const SECTION_HEALTH: float = 20000.0
## A point this far outside every section's box of its body still lands in the nearest one (a hit on a hull plate's skin).
const SNAP_M: float = 50.0

## A section reached zero (its index); once per loss.
signal lost(section: int)

## Per section: `name`, `body` (`drum` or `frame`) and `aabb` (in that body's frame), in the manifest's order.
var sections: Array[Dictionary] = []
var health: PackedFloat64Array = PackedFloat64Array()
var max_health: PackedFloat64Array = PackedFloat64Array()


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
	health[index] = maxf(health[index] - amount, 0.0)
	if health[index] > 0.0:
		return false
	lost.emit(index)
	return true


## 0..1 health of section `index`.
func fraction(index: int) -> float:
	return health[index] / maxf(max_health[index], 1e-6) if index >= 0 and index < health.size() else 0.0


func is_lost(index: int) -> bool:
	return index >= 0 and index < health.size() and health[index] <= 0.0


## Every section whole again.
func restore() -> void:
	health = max_health.duplicate()


## One line a section: `name health/max`, for the console.
func describe() -> String:
	var parts := PackedStringArray()
	for i: int in sections.size():
		parts.append("%s %.0f/%.0f%s" % [sections[i]["name"], health[i], max_health[i], " LOST" if is_lost(i) else ""])
	return ", ".join(parts)
