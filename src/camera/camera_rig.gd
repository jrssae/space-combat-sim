class_name CameraRig
extends Node3D
## Owns the cockpit, chase and cinematic cameras and the mode between them (architecture §3, §8, §18 D55).
##
## - `CockpitPivot` is glued to the ship's `CockpitAnchor` by a `RemoteTransform3D` that `setup` adds under it. The
##   `CockpitCamera` sits under the pivot and only carries the free-look rotation (set every rendered frame).
## - `ChaseCamera` is `top_level` (it does not follow this node) and physics interpolation is off for it: every rendered
##   frame `_process` puts it on the ship's interpolated pose times the fixed chase pose (`ChaseCameraMath`), so it is
##   rigidly locked to the ship with no lag. Setting `camera_chase_smoothing_s` > 0 lags its orientation only. It is in
##   group `world_shiftable` so `WorldFrame.rebase` moves it together with the ship.
##
## - `CinematicCamera` (M5-T08) is `top_level`, in `world_shiftable`, with physics interpolation off. `play_shot` switches to it
##   and every rendered frame puts it on the shot's pose (`CinematicShot.pose_at`) for the shot's time, read from the live actors,
##   so a rebase mid-shot moves nothing on screen. The shot's clock runs on physics ticks; at its end, or on `stop_shot`, the
##   rig goes back to the mode it left. While a shot plays, `set_mode` only changes the mode it will go back to.
##
## - The pause backdrop (M5-T42) plays `PauseOrbitPath` on the same cinematic camera while the pause menu is open. The rig runs
##   with process mode always for as long as it plays, since the tree is paused; the phase advances on the frame's `delta`.
##   It blends in from the view in use, and stopping it cuts back to the mode it left, with the chase camera snapped to the ship.
##   Never over a shot, and not for the radial menus.
##
## The rig does not know the ship's class: `setup` takes the pieces it needs (a body to follow, an anchor, an offset,
## a visibility callback), which keeps it testable with plain nodes. Rebase-safe: the only pose kept between frames is
## the chase camera node's own transform, which the rebase shifts; nothing is cached in this script.
##
## Registers the `camera` console provider and command (architecture §6.4).

enum Mode { COCKPIT, CHASE, CINEMATIC }

## Emitted after the active camera has changed (not for a `set_mode` to the mode already active).
signal mode_changed(new_mode: Mode)
## A shot has ended: it ran out, or `stop_shot` cut it.
signal shot_finished(shot_id: StringName)

## How fast the drawn look angles close on the goal, per second (exponential).
const SHOWN_LOOK_RATE_PER_S: float = 30.0
const MODE_CHOICES: Array[StringName] = [&"cockpit", &"chase"]
## Seconds the backdrop takes to blend in from the player's view.
const BACKDROP_BLEND_S: float = 1.0
const _REMOTE_NAME: StringName = &"CockpitCameraRemote"

## Chase pose tunables. `setup` replaces `offset_local` with the ship's chase anchor; `smoothing_s` follows the
## `camera_chase_smoothing_s` setting.
var chase_config: ChaseCameraConfig = ChaseCameraConfig.new()

## Active camera mode. Assigning it is the same as `set_mode`.
var mode: Mode:
	get = get_mode, set = set_mode

var _mode: Mode = Mode.CHASE
## Free look (`CameraLook`): the goal updated each physics tick, and the angles actually shown, eased toward it every frame.
var _look: CameraLook = CameraLook.new()
var _shown_yaw: float = 0.0
var _shown_pitch: float = 0.0
var _target: Node3D = null
var _remote: RemoteTransform3D = null
var _set_interior_visible: Callable = Callable()
# The console's `look` is holding the view.
var _look_held: bool = false
# The shot playing (null when none), how it finds its actors and the origin, its clock (this tick and the one before, for the
# frames between ticks) and the mode to go back to.
var _shot: CinematicShot = null
var _shot_actor_pose: Callable = Callable()
var _shot_origin_to_local: Callable = Callable()
var _shot_time_s: float = 0.0
var _shot_prev_time_s: float = 0.0
var _return_mode: Mode = Mode.CHASE
# The pause backdrop (null when not running), its loop time, phase in [0, 1) and seconds since it started (for the blend in).
var _backdrop: PauseOrbitPath = null
var _backdrop_loop_s: float = 30.0
var _backdrop_phase: float = 0.0
var _backdrop_age_s: float = 0.0
var _backdrop_from: Transform3D = Transform3D.IDENTITY
var _backdrop_process_mode: ProcessMode = Node.PROCESS_MODE_INHERIT

@onready var cockpit_pivot: Node3D = $CockpitPivot
@onready var cockpit_camera: Camera3D = $CockpitPivot/CockpitCamera
@onready var chase_camera: Camera3D = $ChaseCamera
@onready var cinematic_camera: Camera3D = $CinematicCamera


func _ready() -> void:
	_mode = mode_from_name(StringName(str(Settings.get_value(&"camera_default"))))
	_look.set_mode(_mode == Mode.COCKPIT)
	_apply_mode()
	_apply_smoothing_setting()
	Settings.changed.connect(_on_setting_changed)
	DebugConsole.registry.register_provider(&"camera", ConsoleVars.new({
		&"mode": {"get": func() -> StringName: return mode_name(_mode),
				"set": func(value: Variant) -> void: set_mode(mode_from_name(StringName(str(value)))),
				"type": TYPE_STRING_NAME, "choices": MODE_CHOICES,
				"doc": "Active camera: cockpit, chase or cinematic (a shot playing; set it to cockpit or chase for after the shot)"},
		&"fov": {"get": func() -> float: return active_camera().fov, "unit": "deg",
				"doc": "Field of view of the active camera"},
		&"shot": {"get": func() -> String: return String(_shot.id) if _shot != null else "none",
				"doc": "The cinematic shot playing, or none"},
		&"backdrop": {"get": func() -> bool: return _backdrop != null,
				"doc": "The pause menu's camera move is running"},
		&"backdrop_phase": {"get": func() -> float: return backdrop_phase(),
				"doc": "Where the pause menu's camera move is in its loop, 0 to 1"},
		&"shot_time_s": {"get": func() -> float: return _shot_time_s if _shot != null else 0.0, "unit": "s",
				"doc": "Sim time into the shot playing"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"camera",
			"Switch to the cockpit or chase camera; with no argument, toggle",
			[ConsoleArg.enum_optional(&"mode", MODE_CHOICES)]), _cmd_camera, self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"look",
			"Hold the view at yaw and pitch degrees off the nose, for captures; L3 and the mouse do nothing until `look off`",
			[ConsoleArg.string_required(&"yaw"), ConsoleArg.float_optional(&"pitch", 0.0, -80.0, 80.0)]), _cmd_look, self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)
	if Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.disconnect(_on_setting_changed)
	if _remote != null and is_instance_valid(_remote) and not _remote.is_queued_for_deletion():
		_remote.queue_free()
	_remote = null


func _physics_process(delta: float) -> void:
	if _shot == null:
		return
	_shot_prev_time_s = _shot_time_s
	_shot_time_s += delta
	if _shot_time_s >= _shot.duration_s:
		stop_shot()


func _process(delta: float) -> void:
	_ease_shown_look(delta)
	update_chase(delta)
	cockpit_camera.transform = Transform3D(_shown_basis(), Vector3.ZERO)
	if _backdrop != null:
		advance_backdrop(delta)
	if _shot != null:
		update_cinematic(Engine.get_physics_interpolation_fraction())


## Called by Main (M1-T15) with the ship's CockpitAnchor, hardpoints chase_anchor and set_cockpit_interior_visible
##
## `target` is the ship body the chase camera follows (its pose only). `cockpit_anchor` is a Marker3D on the ship:
## a `RemoteTransform3D` is added under it, pointing at `CockpitCamera`. `chase_offset_local` is the hardpoints'
## `chase_anchor`, ship-local (nominal (0, 2.5, 9.0)). `set_interior_visible` is called with `mode == COCKPIT` on
## every mode change, and once here so the interior matches the starting mode.
##
## Both this rig and `cockpit_anchor` must already be in the scene tree (the remote's node path needs both). Calling
## it again replaces the previous wiring.
func setup(target: Node3D, cockpit_anchor: Node3D, chase_offset_local: Vector3, set_interior_visible: Callable) -> void:
	assert(target != null and cockpit_anchor != null, "CameraRig.setup: target and cockpit_anchor are required")
	if not is_inside_tree() or not cockpit_anchor.is_inside_tree():
		push_error("CameraRig.setup: the rig and the cockpit anchor must be in the scene tree first")
		return
	_target = target
	_set_interior_visible = set_interior_visible
	chase_config.offset_local = chase_offset_local

	if _remote != null and is_instance_valid(_remote):
		if _remote.get_parent() != null:
			_remote.get_parent().remove_child(_remote)  # so the new one can take its name
		_remote.queue_free()
	_remote = RemoteTransform3D.new()
	_remote.name = _REMOTE_NAME
	_remote.update_scale = false  # the anchor is a pose, never a scale
	cockpit_anchor.add_child(_remote)
	_remote.remote_path = _remote.get_path_to(cockpit_pivot)
	# The remote only pushes on the anchor's next move; put the pivot on the anchor now.
	cockpit_pivot.global_transform = cockpit_anchor.global_transform
	cockpit_pivot.reset_physics_interpolation()
	cockpit_camera.reset_physics_interpolation()

	snap_chase()
	_notify_interior()


## Free look, called once per physics tick: while `active` (L3 or the middle mouse button held) the camera turns by the look
## stick (absolute, x right, y up) or the mouse travel (pixels, x right, y up) and the ship does not; released, it eases back
## to centre. In the cockpit the pilot turns their head; in the chase view the camera pans around the ship.
func set_look(dt: float, active: bool, stick: Vector2, mouse_px: Vector2) -> void:
	if _look_held or _shot != null or _backdrop != null:
		return
	_look.step(dt, active, stick, mouse_px, float(Settings.get_value(&"mouse_look_deg_per_px")))


## The look angles the view is easing toward, degrees (yaw right, pitch up).
func look_goal() -> Vector2:
	return Vector2(_look.yaw_deg, _look.pitch_deg)


## Switches between the cockpit and chase views; during a shot, the view to go back to.
func toggle() -> void:
	var current: Mode = _return_mode if (_shot != null or _backdrop != null) else _mode
	set_mode(Mode.CHASE if current == Mode.COCKPIT else Mode.COCKPIT)


## The view the player has chosen: the active mode, or the one a shot or the pause backdrop will give back.
func chosen_mode() -> Mode:
	return _return_mode if (_shot != null or _backdrop != null) else _mode


func get_mode() -> Mode:
	return _mode


## The cinematic mode comes only with a shot (`play_shot`); while one plays, any other mode is the one to go back to.
func set_mode(new_mode: Mode) -> void:
	if new_mode == Mode.CINEMATIC and _shot == null:
		push_warning("CameraRig: the cinematic camera needs a shot (play_shot)")
		return
	if (_shot != null or _backdrop != null) and new_mode != Mode.CINEMATIC:
		_return_mode = new_mode
		return
	if new_mode == _mode:
		return
	_mode = new_mode
	_look.reset()
	_look.set_mode(_mode == Mode.COCKPIT)
	_shown_yaw = 0.0
	_shown_pitch = 0.0
	_apply_mode()
	mode_changed.emit(_mode)


func active_camera() -> Camera3D:
	match _mode:
		Mode.COCKPIT:
			return cockpit_camera
		Mode.CINEMATIC:
			return cinematic_camera
	return chase_camera


## Starts the pause backdrop: the camera blends from the view in use onto the figure 8 around the ship and keeps going until
## `stop_backdrop`. `loop_s` is the time of one loop. False (and nothing changes) with no ship, a shot playing or one already running.
func start_backdrop(loop_s: float, hull_radius_m: float) -> bool:
	if _backdrop != null or _shot != null or not _has_target():
		return false
	_backdrop = PauseOrbitPath.create(chase_config.offset_local.length(), hull_radius_m)
	_backdrop_loop_s = maxf(loop_s, 1.0)
	_backdrop_age_s = 0.0
	var view: Camera3D = active_camera()
	_backdrop_from = view.global_transform
	cinematic_camera.fov = view.fov
	var ship_pose: Transform3D = _target.get_global_transform_interpolated()
	_backdrop_phase = _backdrop.nearest_phase(ship_pose.affine_inverse() * _backdrop_from.origin)
	_backdrop_process_mode = process_mode
	process_mode = Node.PROCESS_MODE_ALWAYS
	_return_mode = _mode
	_mode = Mode.CINEMATIC
	cinematic_camera.global_transform = _backdrop_from
	cinematic_camera.reset_physics_interpolation()
	_apply_mode()
	return true


## Ends the backdrop and goes back to the mode it left, the chase camera exactly on the ship. Nothing happens when it is not running.
func stop_backdrop() -> void:
	if _backdrop == null:
		return
	_backdrop = null
	process_mode = _backdrop_process_mode
	_look.reset()
	_shown_yaw = 0.0
	_shown_pitch = 0.0
	_mode = _return_mode
	_look.set_mode(_mode == Mode.COCKPIT)
	if _mode == Mode.CHASE:
		snap_chase()
	_apply_mode()


func is_backdrop_running() -> bool:
	return _backdrop != null


## The phase in [0, 1) of the loop, or 0 when the backdrop is not running.
func backdrop_phase() -> float:
	return _backdrop_phase if _backdrop != null else 0.0


## Moves the backdrop on by `delta` seconds and puts the camera on it. `_process` calls it every frame; public for tests.
func advance_backdrop(delta: float) -> void:
	if _backdrop == null or not _has_target():
		return
	_backdrop_phase = fposmod(_backdrop_phase + delta / _backdrop_loop_s, 1.0)
	_backdrop_age_s += delta
	var goal: Transform3D = _target.get_global_transform_interpolated() * _backdrop.transform_at(_backdrop_phase)
	var w: float = smoothstep(0.0, 1.0, _backdrop_age_s / BACKDROP_BLEND_S)
	var shown := Transform3D(_backdrop_from.basis.orthonormalized().slerp(goal.basis.orthonormalized(), w).orthonormalized(),
			_backdrop_from.origin.lerp(goal.origin, w))
	cinematic_camera.global_transform = shown


## Plays `shot` on the cinematic camera from its start, replacing any shot playing. `actor_pose(name)` and `origin_to_local(offset)`
## place its points every frame (`CinematicShot.pose_at`).
func play_shot(shot: CinematicShot, actor_pose: Callable, origin_to_local: Callable) -> void:
	stop_backdrop()
	if _shot == null:
		_return_mode = _mode
	_shot = shot
	_shot_actor_pose = actor_pose
	_shot_origin_to_local = origin_to_local
	_shot_time_s = 0.0
	_shot_prev_time_s = 0.0
	update_cinematic(1.0)
	cinematic_camera.reset_physics_interpolation()
	set_mode(Mode.CINEMATIC)


## Ends the shot playing now and goes back to the mode it left. Nothing happens with no shot.
func stop_shot() -> void:
	if _shot == null:
		return
	var ended: StringName = _shot.id
	_shot = null
	_shot_actor_pose = Callable()
	_shot_origin_to_local = Callable()
	set_mode(_return_mode)
	if _mode == Mode.CHASE:
		snap_chase()
	shot_finished.emit(ended)


## The shot playing, or null.
func playing_shot() -> CinematicShot:
	return _shot


func is_playing_shot() -> bool:
	return _shot != null


## Sim seconds into the shot playing.
func shot_time_s() -> float:
	return _shot_time_s


## Puts the cinematic camera on the shot's pose, `fraction` of the way from the last tick's time to this one's (the frames between
## ticks). `_process` calls it every frame; public so tests can look right after a rebase. Where the shot cannot be placed (an
## actor is gone) the camera stays where it is.
func update_cinematic(fraction: float) -> void:
	if _shot == null:
		return
	var t: float = lerpf(_shot_prev_time_s, _shot_time_s, clampf(fraction, 0.0, 1.0))
	var pose: CinematicShot.Pose = _shot.pose_at(t, _shot_actor_pose, _shot_origin_to_local)
	if pose == null:
		return
	cinematic_camera.global_transform = pose.transform
	cinematic_camera.fov = pose.fov


## Puts the chase camera on the ship's pose for this frame. `_process` calls it every frame; public so tests (and a
## paused-time tool) can step it with a chosen `delta`, which only matters with smoothing on. Does nothing before `setup`.
func update_chase(delta: float) -> void:
	if not _has_target():
		return
	# The interpolated pose is what the renderer shows for the ship (physics interpolation is on), so the camera is
	# locked to the ship the player sees, not to its last physics tick.
	chase_camera.global_transform = ChaseCameraMath.step(chase_camera.global_transform,
			_target.get_global_transform_interpolated(), delta, chase_config, _chase_look_basis())


## Puts the chase camera exactly on its goal pose with no smoothing. For after the ship is teleported (respawn).
func snap_chase() -> void:
	if not _has_target():
		return
	chase_camera.global_transform = ChaseCameraMath.target_pose(_target.get_global_transform_interpolated(),
			chase_config, _chase_look_basis())


static func mode_name(m: Mode) -> StringName:
	match m:
		Mode.COCKPIT:
			return &"cockpit"
		Mode.CINEMATIC:
			return &"cinematic"
	return &"chase"


## `cockpit` is the cockpit; anything else (including an unknown setting) is the chase camera. The cinematic camera is never
## chosen by name: it comes with a shot.
static func mode_from_name(mode_text: StringName) -> Mode:
	return Mode.COCKPIT if mode_text == &"cockpit" else Mode.CHASE


func _has_target() -> bool:
	return _target != null and is_instance_valid(_target) and _target.is_inside_tree()


# The angles actually drawn follow the physics-tick goal quickly, so the view is smooth at any frame rate.
func _ease_shown_look(delta: float) -> void:
	var k: float = 1.0 - exp(-SHOWN_LOOK_RATE_PER_S * maxf(delta, 0.0))
	_shown_yaw = lerpf(_shown_yaw, _look.yaw_deg, k)
	_shown_pitch = lerpf(_shown_pitch, _look.pitch_deg, k)


func _shown_basis() -> Basis:
	return Basis(Vector3.UP, -deg_to_rad(_shown_yaw)) * Basis(Vector3.RIGHT, deg_to_rad(_shown_pitch))


# The chase camera orbits the ship by the look angles; the cockpit camera turns in place (`_process`).
func _chase_look_basis() -> Basis:
	return _shown_basis()


# Only the camera that should be current is made so: clearing the other would let Godot pick a replacement.
func _apply_mode() -> void:
	if not is_node_ready():
		return  # `_ready` applies the starting mode
	active_camera().make_current()
	_notify_interior()
	_apply_bolt_scale()


func _notify_interior() -> void:
	if _set_interior_visible.is_valid():
		_set_interior_visible.call(_mode == Mode.COCKPIT)


# Bolts look small from the chase camera, which sits further back than the cockpit: draw them larger there, and in a shot.
func _apply_bolt_scale() -> void:
	Projectile.visual_scale = float(Settings.get_value(&"chase_bolt_scale")) if _mode != Mode.COCKPIT else 1.0
	if is_inside_tree():
		get_tree().call_group(Projectile.GROUP, "set_visual_scale", Projectile.visual_scale)


func _apply_smoothing_setting() -> void:
	chase_config.smoothing_s = float(Settings.get_value(&"camera_chase_smoothing_s"))


func _on_setting_changed(key: StringName, _value: Variant) -> void:
	if key == &"camera_chase_smoothing_s":
		_apply_smoothing_setting()
	elif key == &"chase_bolt_scale":
		_apply_bolt_scale()


func _cmd_camera(args: Dictionary) -> ConsoleResult:
	var requested: Variant = args[&"mode"]
	if requested == null:
		toggle()
	else:
		set_mode(mode_from_name(StringName(str(requested))))
	return ConsoleResult.line(ConsoleFormat.key_value("camera.mode", mode_name(_mode)))


func _cmd_look(args: Dictionary) -> ConsoleResult:
	var yaw_text: String = String(args[&"yaw"])
	if yaw_text == "off":
		_look_held = false
		return ConsoleResult.line("the view is free again")
	if not yaw_text.is_valid_float():
		return ConsoleResult.failure("look takes yaw and pitch in degrees, or off, not '%s'" % yaw_text)
	_look_held = true
	_look.yaw_deg = clampf(yaw_text.to_float(), -_look.max_yaw_deg, _look.max_yaw_deg)
	_look.pitch_deg = clampf(float(args[&"pitch"]), -_look.max_pitch_deg, _look.max_pitch_deg)
	return ConsoleResult.line("the view held at yaw %.0f, pitch %.0f" % [_look.yaw_deg, _look.pitch_deg])
