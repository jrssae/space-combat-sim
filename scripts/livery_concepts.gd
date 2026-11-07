extends SceneTree
## Starts scripts/livery_concepts_node.gd (M4-T30b). A `-s` script cannot name autoloads, so the work is in a node loaded after they exist.


func _initialize() -> void:
	var node: Node = (load("res://scripts/livery_concepts_node.gd") as GDScript).new() as Node
	root.add_child.call_deferred(node)
