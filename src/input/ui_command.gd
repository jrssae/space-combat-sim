class_name UiCommand
extends RefCounted
## Player-only requests for one tick, all edges (architecture §6.2). AI pilots never produce these.

var toggle_camera: bool = false
var reset: bool = false
var pause: bool = false
var toggle_overlay: bool = false
var toggle_fallback_mesh: bool = false
var screenshot: bool = false
## Wing orders (keys 1-4, M3-T07): `Main` hands them to the `WingDirector`.
var wing_attack: bool = false
var wing_form: bool = false
var wing_engage: bool = false
var wing_cover: bool = false
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
		"wing_attack": wing_attack, "wing_form": wing_form, "wing_engage": wing_engage, "wing_cover": wing_cover,
		"look_active": look_active, "look_stick": look_stick, "look_mouse_px": look_mouse_px,
	}
