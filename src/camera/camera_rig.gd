class_name CameraRig
extends Node3D
## Owns the two cameras and the mode between them (architecture §3, §8).
##
## - `CockpitCamera` is glued to the ship's `CockpitAnchor` by a `RemoteTransform3D` that `setup` adds under it.
## - `ChaseCamera` is `top_level` (it does not follow this node), eased toward its goal pose in `_process` by
##   `ChaseCameraMath`, and in group `world_shiftable` so `WorldFrame.rebase` moves it together with the ship.
##
## The rig does not know the ship's class: `setup` takes the pieces it needs (a body to follow, an anchor, an offset,
## a visibility callback), which keeps it testable with plain nodes. Rebase-safe: the only pose kept between frames is
## the chase camera node's own transform, which the rebase shifts; nothing is cached in this script.
##
## Registers the `camera` console provider and command (architecture §6.4).

enum Mode { COCKPIT, CHASE }

## Emitted after the active camera has changed (not for a `set_mode` to the mode already active).
signal mode_changed(new_mode: Mode)

const MODE_CHOICES: Array[StringName] = [&"cockpit", &"chase"]
const _REMOTE_NAME: StringName = &"CockpitCameraRemote"

## Chase pose tunables. `setup` replaces `offset_local` with the ship's chase anchor.
var chase_config: ChaseCameraConfig = ChaseCameraConfig.new()

## Active camera mode. Assigning it is the same as `set_mode`.
var mode: Mode:
	get = get_mode, set = set_mode

var _mode: Mode = Mode.CHASE
var _target: Node3D = null
var _remote: RemoteTransform3D = null
var _set_interior_visible: Callable = Callable()

@onready var cockpit_camera: Camera3D = $CockpitCamera
@onready var chase_camera: Camera3D = $ChaseCamera


func _ready() -> void:
	_mode = mode_from_name(StringName(str(Settings.get_value(&"camera_default"))))
	_apply_mode()
	DebugConsole.registry.register_provider(&"camera", ConsoleVars.new({
		&"mode": {"get": func() -> StringName: return mode_name(_mode),
				"set": func(value: Variant) -> void: set_mode(mode_from_name(StringName(str(value)))),
				"type": TYPE_STRING_NAME, "choices": MODE_CHOICES, "doc": "Active camera: cockpit or chase"},
		&"fov": {"get": func() -> float: return active_camera().fov, "unit": "deg",
				"doc": "Field of view of the active camera"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"camera",
			"Switch to the cockpit or chase camera; with no argument, toggle",
			[ConsoleArg.enum_optional(&"mode", MODE_CHOICES)]), _cmd_camera, self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)
	if _remote != null and is_instance_valid(_remote) and not _remote.is_queued_for_deletion():
		_remote.queue_free()
	_remote = null


func _process(delta: float) -> void:
	update_chase(delta)


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
	_remote.remote_path = _remote.get_path_to(cockpit_camera)
	# The remote only pushes on the anchor's next move; put the camera on the anchor now.
	cockpit_camera.global_transform = cockpit_anchor.global_transform
	cockpit_camera.reset_physics_interpolation()

	snap_chase()
	_notify_interior()


func toggle() -> void:
	set_mode(Mode.CHASE if _mode == Mode.COCKPIT else Mode.COCKPIT)


func get_mode() -> Mode:
	return _mode


func set_mode(new_mode: Mode) -> void:
	if new_mode == _mode:
		return
	_mode = new_mode
	_apply_mode()
	mode_changed.emit(_mode)


func active_camera() -> Camera3D:
	return cockpit_camera if _mode == Mode.COCKPIT else chase_camera


## One smoothing step of the chase camera toward its goal behind the ship. `_process` calls it every frame; public so
## tests (and a paused-time tool) can step it with a chosen `delta`. Does nothing before `setup`.
func update_chase(delta: float) -> void:
	if not _has_target():
		return
	# The interpolated pose is what the renderer shows for the ship (physics interpolation is on), so the camera
	# eases toward the same ship the player sees rather than toward the last physics tick.
	chase_camera.global_transform = ChaseCameraMath.step(chase_camera.global_transform,
			_target.get_global_transform_interpolated(), delta, chase_config)


## Puts the chase camera exactly on its goal pose with no easing. For after the ship is teleported (respawn).
func snap_chase() -> void:
	if not _has_target():
		return
	chase_camera.global_transform = ChaseCameraMath.target_pose(_target.get_global_transform_interpolated(),
			chase_config)


static func mode_name(m: Mode) -> StringName:
	return &"cockpit" if m == Mode.COCKPIT else &"chase"


## `cockpit` is the cockpit; anything else (including an unknown setting) is the chase camera.
static func mode_from_name(mode_text: StringName) -> Mode:
	return Mode.COCKPIT if mode_text == &"cockpit" else Mode.CHASE


func _has_target() -> bool:
	return _target != null and is_instance_valid(_target) and _target.is_inside_tree()


# Only the camera that should be current is made so: clearing the other would let Godot pick a replacement.
func _apply_mode() -> void:
	if not is_node_ready():
		return  # `_ready` applies the starting mode
	active_camera().make_current()
	_notify_interior()


func _notify_interior() -> void:
	if _set_interior_visible.is_valid():
		_set_interior_visible.call(_mode == Mode.COCKPIT)


func _cmd_camera(args: Dictionary) -> ConsoleResult:
	var requested: Variant = args[&"mode"]
	if requested == null:
		toggle()
	else:
		set_mode(mode_from_name(StringName(str(requested))))
	return ConsoleResult.line(ConsoleFormat.key_value("camera.mode", mode_name(_mode)))
