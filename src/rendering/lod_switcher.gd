class_name LodSwitcher
extends Node
## Draws an AI ship as a far dot past `settings.far_ship_dot_m` from the camera (M4-T11, §17.10): `Ship.set_far_dot` hides its hull,
## plumes and markers and the world's `FarDots` draws it; a tenth back inside it shows its detail again. The player's ship is never a
## dot. Nearer than that the textured mesh's own levels of detail (the importer's) do the rest (M4-T31).
##
## The far dot count is read by `RenderStatus`'s `render.far_dots`. Every switcher is decided in one loop a frame, the `FramePasses`
## LOD pass, with the camera and the dot distance read once (M4-T36); this node only holds its ship's state.

## Whether the ship is far enough from the camera to be drawn as a dot (M4-T11).
var far: bool = false

var _ship: Ship = null

static var _live: Array[LodSwitcher] = []


func _ready() -> void:
	_ship = get_parent() as Ship
	if _ship == null:
		push_warning("LodSwitcher: needs a Ship parent; not switching")
		return
	var passes: FramePasses = FramePasses.of(self)
	if passes != null:
		passes.add_switcher(self)


func _enter_tree() -> void:
	_live.append(self)
	if _ship != null:
		var passes: FramePasses = FramePasses.of(self)
		if passes != null:
			passes.add_switcher(self)


func _exit_tree() -> void:
	_live.erase(self)
	var passes: FramePasses = FramePasses.of(self)
	if passes != null:
		passes.remove_switcher(self)


## Decides this frame's dot from the camera's distance and applies it, reading the camera itself (tests; the pass reads it once
## for every ship and calls `decide`).
func update() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d() if get_viewport() != null else null
	if camera != null:
		decide(camera.global_position, float(Settings.get_value(&"far_ship_dot_m")))


## Decides this frame's dot for a camera at `eye` and a dot distance of `far_m`, and applies it.
func decide(eye: Vector3, far_m: float) -> void:
	if not _shown():
		return
	var distance: float = eye.distance_to(_ship.global_position)
	far = not _ship.console_owner and LodSwitcherMath.far_dot(distance, far, far_m)
	_ship.set_far_dot(far)


func _shown() -> bool:
	return _ship != null and _ship.is_inside_tree() and _ship.is_visible_in_tree()


## Ships in play drawn as far dots now: parked (disabled) and hidden ships left out; a paused game still has its ships in play.
static func far_dot_count() -> int:
	var n: int = 0
	for s: LodSwitcher in _live:
		if s._ship != null and s._ship.is_inside_tree() and s._ship.process_mode != Node.PROCESS_MODE_DISABLED \
				and s._ship.is_visible_in_tree() and s._ship.is_far_dot():
			n += 1
	return n
