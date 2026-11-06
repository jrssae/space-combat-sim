extends SceneTree
## Starts scripts/aa_compare_node.gd (M4-T38). A `-s` script cannot name autoloads, so the work is in a node loaded after they exist.


func _initialize() -> void:
	var node: Node = (load("res://scripts/aa_compare_node.gd") as GDScript).new() as Node
	root.add_child.call_deferred(node)
