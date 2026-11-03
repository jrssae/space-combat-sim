class_name TriggerInputPerformed
extends Trigger
## `input_performed` (D52): the player performed `action` this tick (a name of `PlayerActions.NAMES`, read from the tick's
## `PilotCommand`, never from `Input`). M8's tutorial checks each control with it. Forced, it simply resolves.

var action: StringName = &""


func _init(p_action: StringName = &"") -> void:
	kind = &"input_performed"
	action = p_action


func test(world: MissionWorld) -> bool:
	return world.performed(action)


func describe() -> String:
	return "input_performed %s" % action
