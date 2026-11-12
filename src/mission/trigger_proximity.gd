class_name TriggerProximity
extends Trigger
## `proximity` (D52): `actor` is within `radius_m` of another actor (`other`), or of a fixed universe `point`.
## Forced, the actor is placed inside the radius: at the point itself, or half the radius from the other actor on the side it
## came from (never inside its hull).

var actor: String = ""
## Another actor's name, or "" when the goal is `point`.
var other: String = ""
var point: UniversePos = null
var radius_m: float = 100.0


func _init(p_actor: String = "", p_other: String = "", p_point: UniversePos = null, p_radius_m: float = 100.0) -> void:
	kind = &"proximity"
	actor = p_actor
	other = p_other
	point = p_point
	radius_m = p_radius_m


func actors() -> PackedStringArray:
	return PackedStringArray([actor, other]) if not other.is_empty() else PackedStringArray([actor])


func place() -> UniversePos:
	return point


func test(world: MissionWorld) -> bool:
	var from: UniversePos = world.position_of(actor)
	var goal: UniversePos = _goal(world)
	return from != null and goal != null and from.distance_to(goal) <= radius_m


func force(world: MissionWorld) -> void:
	var goal: UniversePos = _goal(world)
	if goal == null:
		return
	if other.is_empty():
		world.place(actor, goal)
		return
	world.place(actor, beside(goal, world.position_of(actor), radius_m * 0.5))


func describe() -> String:
	return "proximity %s within %.0f m of %s" % [actor, radius_m, other if not other.is_empty() else str(point)]


func _goal(world: MissionWorld) -> UniversePos:
	return world.position_of(other) if not other.is_empty() else point


## A point `distance_m` from `goal`, toward `from` (along +X when `from` is unknown or on the goal).
static func beside(goal: UniversePos, from: UniversePos, distance_m: float) -> UniversePos:
	var direction := Vector3.RIGHT
	if from != null and from.distance_to(goal) > 1e-3:
		direction = goal.offset_to(from).normalized()
	return goal.plus_local(direction * distance_m)
