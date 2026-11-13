extends SceneTree
## Starts scripts/planet_sheet_node.gd (M6-T11). A `-s` script cannot name autoloads, so the work is in a node loaded after they exist.


func _initialize() -> void:
	var node: Node = (load("res://scripts/planet_sheet_node.gd") as GDScript).new() as Node
	root.add_child.call_deferred(node)
