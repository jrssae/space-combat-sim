class_name UiCommand
extends RefCounted
## Player-only requests for one tick, all edges (architecture §6.2). AI pilots never produce these.

var toggle_camera: bool = false
var reset: bool = false
var pause: bool = false
var toggle_overlay: bool = false
var toggle_fallback_mesh: bool = false
var screenshot: bool = false
## Free look (L3 held on a pad, the middle mouse button held): the camera turns, the ship does not. `look_stick` is the right
## stick as an absolute look direction (x right, y up, -1..1); `look_mouse_px` is the mouse travel this tick in pixels
## (x right, y up).
var look_active: bool = false
var look_stick: Vector2 = Vector2.ZERO
var look_mouse_px: Vector2 = Vector2.ZERO


func to_dict() -> Dictionary:
	return {
		"toggle_camera": toggle_camera, "reset": reset, "pause": pause,
		"toggle_overlay": toggle_overlay, "toggle_fallback_mesh": toggle_fallback_mesh, "screenshot": screenshot,
		"look_active": look_active, "look_stick": look_stick, "look_mouse_px": look_mouse_px,
	}
