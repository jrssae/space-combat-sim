extends SceneTree
## Starts scripts/station_sheet_node.gd (M7-T04). A `-s` script cannot name autoloads, so the work is in a node loaded after they exist.


func _initialize() -> void:
	# A script that fails to load must end the run at once, not leave a fullscreen window open until the timeout (M7-T24).
	var script: GDScript = load("res://scripts/station_sheet_node.gd") as GDScript
	if script == null or not script.can_instantiate():
		push_error("station_sheet: scripts/station_sheet_node.gd failed to load")
		quit(1)
		return
	root.add_child.call_deferred(script.new() as Node)
