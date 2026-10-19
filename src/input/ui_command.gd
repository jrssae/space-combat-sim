class_name UiCommand
extends RefCounted
## Player-only requests for one tick, all edges (architecture §6.2). AI pilots never produce these.

var toggle_camera: bool = false
var reset: bool = false
var pause: bool = false
var toggle_overlay: bool = false
var toggle_fallback_mesh: bool = false


func to_dict() -> Dictionary:
	return {
		"toggle_camera": toggle_camera, "reset": reset, "pause": pause,
		"toggle_overlay": toggle_overlay, "toggle_fallback_mesh": toggle_fallback_mesh,
	}
