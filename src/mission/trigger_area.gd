class_name TriggerArea
extends Trigger
## `area` (D52): `actor` is inside the sphere of `radius_m` around the universe point `centre`. Forced, it is placed at the centre.

var actor: String = ""
var centre: UniversePos = UniversePos.new()
var radius_m: float = 100.0


func _init(p_actor: String = "", p_centre: UniversePos = null, p_radius_m: float = 100.0) -> void:
	kind = &"area"
	actor = p_actor
	centre = p_centre if p_centre != null else UniversePos.new()
	radius_m = p_radius_m


func actors() -> PackedStringArray:
	return PackedStringArray([actor])


func test(world: MissionWorld) -> bool:
	var at: UniversePos = world.position_of(actor)
	return at != null and at.distance_to(centre) <= radius_m


func force(world: MissionWorld) -> void:
	world.place(actor, centre)


func describe() -> String:
	return "area %s inside %.0f m of %s" % [actor, radius_m, centre]
