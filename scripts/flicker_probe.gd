extends SceneTree
## Runs the flicker probe (scripts/flicker_probe_node.gd) on the main scene.


func _initialize() -> void:
	root.add_child.call_deferred((load("res://scripts/flicker_probe_node.gd") as GDScript).new())
