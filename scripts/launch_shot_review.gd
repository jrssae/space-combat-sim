extends SceneTree
## Starts scripts/launch_shot_review_node.gd (M8-T30). A `-s` script cannot name autoloads, so the work is in a node loaded after they exist.


func _initialize() -> void:
	var node: Node = (load("res://scripts/launch_shot_review_node.gd") as GDScript).new() as Node
	root.add_child.call_deferred(node)
