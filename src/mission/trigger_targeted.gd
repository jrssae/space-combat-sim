class_name TriggerTargeted
extends Trigger
## `targeted` (M8-T33): the player has `actor` selected as the target. Forced, the actor is selected for the player, as
## flying the step would have left it.

var actor: String = ""


func _init(p_actor: String = "") -> void:
	kind = &"targeted"
	actor = p_actor


func actors() -> PackedStringArray:
	return PackedStringArray([actor])


func test(world: MissionWorld) -> bool:
	return world.is_targeted(actor)


func force(world: MissionWorld) -> void:
	world.target(actor)


func describe() -> String:
	return "targeted %s" % actor
