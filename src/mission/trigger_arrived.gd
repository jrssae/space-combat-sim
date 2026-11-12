class_name TriggerArrived
extends Trigger
## `arrived` (D52): an AI actor reached a universe `point` (within `radius_m`), or, with no point, the end of the route it leads.
## Forced, the actor is placed at the point, or at its route's end with the route marked flown.

var actor: String = ""
## null: the end of the actor's route.
var point: UniversePos = null
var radius_m: float = Route.ARRIVAL_M


func _init(p_actor: String = "", p_point: UniversePos = null, p_radius_m: float = Route.ARRIVAL_M) -> void:
	kind = &"arrived"
	actor = p_actor
	point = p_point
	radius_m = p_radius_m


func actors() -> PackedStringArray:
	return PackedStringArray([actor])


func place() -> UniversePos:
	return point


func test(world: MissionWorld) -> bool:
	if point == null:
		return world.route_done(actor)
	var at: UniversePos = world.position_of(actor)
	return at != null and at.distance_to(point) <= radius_m


func force(world: MissionWorld) -> void:
	if point != null:
		world.place(actor, point)
		return
	var end: UniversePos = world.route_end(actor)
	if end != null:
		world.place(actor, end)
		world.finish_route(actor)


func describe() -> String:
	return "arrived %s at %s" % [actor, str(point) if point != null else "its route's end"]
