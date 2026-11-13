extends SceneTree
## Starts scripts/starfury_metal_sheet_node.gd (M7-T17). A `-s` script cannot name autoloads, so the work is in a node loaded after
## they exist.


func _initialize() -> void:
	var node: Node = (load("res://scripts/starfury_metal_sheet_node.gd") as GDScript).new() as Node
	root.add_child.call_deferred(node)
