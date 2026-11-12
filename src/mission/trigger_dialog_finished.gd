class_name TriggerDialogFinished
extends Trigger
## `dialog_finished` (D52): the comms line `line_id` has been shown to its end. Forced, the line is marked finished (it is
## logged, not shown).

var line_id: StringName = &""


func _init(p_line_id: StringName = &"") -> void:
	kind = &"dialog_finished"
	line_id = p_line_id


func test(world: MissionWorld) -> bool:
	return world.line_finished(line_id)


func force(world: MissionWorld) -> void:
	world.finish_line(line_id)


func describe() -> String:
	return "dialog_finished %s" % line_id
