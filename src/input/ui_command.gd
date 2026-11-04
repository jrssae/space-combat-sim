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
## D-pad Left, key 5 (M3-T27): the player's running lights on or off.
var toggle_running_lights: bool = false
## The comms menu (D54, M5-T07): D-pad Right opens it (`comms_open`, an edge); while `InputAdapter.comms_open` is set the four
## D-pad directions give `comms_pick` 0-3 (up, right, down, left; -1 for none) and B gives `comms_close`.
var comms_open: bool = false
var comms_pick: int = -1
var comms_close: bool = false
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
		"toggle_running_lights": toggle_running_lights,
		"comms_open": comms_open, "comms_pick": comms_pick, "comms_close": comms_close,
		"look_active": look_active, "look_stick": look_stick, "look_mouse_px": look_mouse_px,
	}
