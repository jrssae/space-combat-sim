class_name LodSwitcher
extends Node
## Draws an AI ship as a far dot once it is only a few pixels across (M4-T11, §17.10; by size on screen since M7-T26): its bounding
## radius under `settings.far_ship_dot_px`. `Ship.set_far_dot` hides its hull, plumes and markers and the world's `FarDots` draws it; a
## tenth back inside it shows its mesh again. Until then the textured mesh's own levels of detail (the importer's, picked by size on
## screen) keep its shape with fewer triangles (M4-T31), so a freighter holds its shape ten times farther out than a fighter. The
## player's ship is never a dot.
##
## The far dot count is read by `RenderStatus`'s `render.far_dots`. Every switcher is decided in one loop a frame, the `FramePasses`
## LOD pass, with the camera and the view's scale read once (M4-T36); this node only holds its ship's state.

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


## Decides this frame's dot from the camera and applies it, reading the camera itself (tests; the pass reads it once for every
## ship and calls `decide`).
func update() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d() if get_viewport() != null else null
	if camera != null:
		decide(camera.global_position, dot_scale(camera))


## The dot distance per metre of bounding radius for `camera`'s view (M7-T26): its pixels per radian (at least 1 080 lines' worth)
## over the dot size.
static func dot_scale(camera: Camera3D) -> float:
	return LodSwitcherMath.dot_distance_m(1.0, LodSwitcherMath.view_k(FarProp.k_of(camera), camera.fov),
			float(Settings.get_value(&"far_ship_dot_px")))


## Decides this frame's dot for a camera at `eye` and a dot distance of `m_per_m` per metre of the hull's radius, and applies it.
func decide(eye: Vector3, m_per_m: float) -> void:
	if not _shown():
		return
	var distance: float = eye.distance_to(_ship.global_position)
	far = not _ship.console_owner and not _ship.inside_station \
			and LodSwitcherMath.far_dot(distance, far, _ship.bounding_radius() * m_per_m)
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
