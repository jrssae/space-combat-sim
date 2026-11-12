class_name EncounterEvent
extends RefCounted
## One free-flight encounter as `EncounterPlan` drew it (architecture §18 D58): its kind, its ships and where they come
## from. Positions, velocities and routes are metres and m/s relative to the anchor at the moment it starts: the player for
## patrols and traffic, the raid's target for a raid. Pure data; `EncounterDirector` places it.

## Placed relative to the player.
const ANCHOR_PLAYER: StringName = &"player"
## Placed relative to the raid's target (the player or a civilian, chosen when it starts).
const ANCHOR_TARGET: StringName = &"target"

var index: int = 0
var time_s: float = 0.0
## `EncounterPlan.KINDS`: raid, patrol or traffic.
var kind: StringName = &""
## One entry a ship, in the order they are placed.
var types: Array[StringName] = []
## A Bokmai's pods (0-3); -1 for every other hull.
var cargo_pods: PackedInt32Array = PackedInt32Array()
var positions: PackedVector3Array = PackedVector3Array()
var velocities: PackedVector3Array = PackedVector3Array()
## Each ship's waypoints after its start (empty for a raider).
var routes: Array[PackedVector3Array] = []
var cruise_mps: float = 0.0
## Comes out of a jump point (raids).
var jumps: bool = false
var anchor: StringName = ANCHOR_PLAYER
## A raid that goes for a civilian near the player when there is one, and which one (0..1 into the candidates).
var at_civilian: bool = false
var target_pick: float = 0.0


func count() -> int:
	return types.size()


## Keeps only the first `n` ships (an event bigger than the whole cap).
func trim(n: int) -> void:
	var keep: int = clampi(n, 0, count())
	types.resize(keep)
	cargo_pods.resize(keep)
	positions.resize(keep)
	velocities.resize(keep)
	routes.resize(keep)


## Everything about it, for comparisons and the console.
func describe() -> Dictionary:
	var type_names: Array[String] = []
	for type: StringName in types:
		type_names.append(String(type))
	return {"index": index, "time_s": time_s, "kind": String(kind), "types": type_names, "cargo_pods": cargo_pods,
			"positions": positions, "velocities": velocities, "routes": routes, "cruise_mps": cruise_mps, "jumps": jumps,
			"anchor": String(anchor), "at_civilian": at_civilian, "target_pick": target_pick}


## One line for the console: `#3 raid: 4 raider_fighter, at a civilian`.
func summary() -> String:
	var counts: Dictionary = {}
	for type: StringName in types:
		counts[type] = int(counts.get(type, 0)) + 1
	var parts := PackedStringArray()
	for type: StringName in counts:
		parts.append("%d %s" % [counts[type], type])
	var aim: String = ""
	if kind == &"raid":
		aim = ", at a civilian" if at_civilian else ", at the player"
	return "#%d %s: %s%s" % [index, kind, ", ".join(parts), aim]
