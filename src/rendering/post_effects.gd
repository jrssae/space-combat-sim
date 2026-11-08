class_name PostEffects
extends Node
## Switches and feeds the two screen effects on the WorldEnvironment's Compositor (architecture §7.5): the lens flare from the
## vendored add-on (`addons/lens_effects/`, untouched) and our `MotionBlurEffect`. The add-on expects its own script on the
## WorldEnvironment to tell it where the star is; this node does that job instead, so the add-on stays as vendored.
##
## `settings.lens_flare`, `settings.motion_blur` and `settings.motion_blur_strength` apply live. A disabled effect does no work
## (and the blur then asks the renderer for no motion vectors). A rebase blanks the blur for the frames around it
## (`MotionBlurGate`).
##
## Console (§6.4): provider `post` and commands `flare [on|off]`, `blur [on|off]`.

## The environment whose Compositor holds the effects.
@export var world_environment: WorldEnvironment
## The key star: the flare follows its direction.
@export var sun: DirectionalLight3D

## How bright the flare's tint is, the add-on's own default level.
const FLARE_LEVEL: float = 0.39

var _flare: LensFlareEffect
var _blur: MotionBlurEffect
var _gate: MotionBlurGate = MotionBlurGate.new()
var _world: WorldFrame
var _sun_uv: Vector2 = Vector2(0.5, 0.5)
var _sun_facing: float = 1.0


func _ready() -> void:
	_find_effects()
	apply_settings()
	Settings.changed.connect(_on_setting_changed)
	DebugConsole.registry.register_provider(&"post", ConsoleVars.new({
		&"flare": {"get": func() -> bool: return _flare != null and _flare.enabled,
				"doc": "The lens flare effect is on (settings.lens_flare)"},
		&"blur": {"get": func() -> bool: return _blur != null and _blur.enabled,
				"doc": "The motion blur effect is on (settings.motion_blur)"},
		&"blur_strength": {"get": func() -> float: return _blur.strength if _blur != null else 0.0,
				"doc": "Strength the blur was last given: 0 while a rebase's frames are blanked"},
		&"blur_skipping": {"get": _gate.skipping, "doc": "Frames the blur is still blanked after a rebase"},
		&"sun_uv": {"get": func() -> Vector2: return _sun_uv, "doc": "Where the star is in the picture, 0-1 (y down)"},
		&"sun_facing": {"get": func() -> float: return _sun_facing, "doc": "1 looking at the star, -1 looking away"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"flare",
			"Toggle or set the star's lens flare", [ConsoleArg.bool_optional(&"state")]), _cmd_flare, self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"blur",
			"Toggle or set motion blur on fast turns", [ConsoleArg.bool_optional(&"state")]), _cmd_blur, self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)
	if Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.disconnect(_on_setting_changed)
	if _world != null and _world.rebased.is_connected(_on_rebased):
		_world.rebased.disconnect(_on_rebased)


func _process(_delta: float) -> void:
	_update_blur()
	_update_flare()


## Blanks the blur around the rebases of `world`.
func watch_world(world: WorldFrame) -> void:
	if _world != null and _world.rebased.is_connected(_on_rebased):
		_world.rebased.disconnect(_on_rebased)
	_world = world
	if _world != null:
		_world.rebased.connect(_on_rebased)


## Tints the flare to the star. `color` is linear, as the picture the flare is added to.
func set_star_color(color: Color) -> void:
	if _flare != null:
		_flare.sun_color = Color(color.r * FLARE_LEVEL, color.g * FLARE_LEVEL, color.b * FLARE_LEVEL)


func flare_effect() -> LensFlareEffect:
	return _flare


func blur_effect() -> MotionBlurEffect:
	return _blur


func blur_gate() -> MotionBlurGate:
	return _gate


## Pushes the three settings into the effects; a flare whose shader failed stays off.
func apply_settings() -> void:
	if _flare != null:
		var usable: bool = not (_flare is SceneLensFlareEffect) or (_flare as SceneLensFlareEffect).usable
		_flare.enabled = usable and bool(Settings.get_value(&"lens_flare"))
	if _blur != null:
		_blur.enabled = bool(Settings.get_value(&"motion_blur"))
		_blur.strength = float(Settings.get_value(&"motion_blur_strength"))


func _find_effects() -> void:
	_flare = null
	_blur = null
	var compositor: Compositor = world_environment.compositor if world_environment != null else null
	if compositor == null:
		return
	for effect: CompositorEffect in compositor.compositor_effects:
		if effect is LensFlareEffect and _flare == null:
			_flare = effect as LensFlareEffect
		elif effect is MotionBlurEffect and _blur == null:
			_blur = effect as MotionBlurEffect


## Tells the flare where the star is, so it follows the star and fades looking away from it.
func _update_flare() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if _flare == null or not _flare.enabled or sun == null or camera == null:
		return
	var to_sun: Vector3 = sun.global_basis.z
	_sun_uv = LensFlareAim.sun_uv(camera, to_sun)
	_sun_facing = LensFlareAim.facing(-camera.global_basis.z, to_sun)
	_flare.sun_position = _sun_uv
	_flare.sun_dir_sign = _sun_facing


## The gate ages every frame, blur on or off, so a rebase's blank frames never outlast it.
func _update_blur() -> void:
	if _blur == null:
		return
	var wanted: float = float(Settings.get_value(&"motion_blur_strength")) if _blur.enabled else 0.0
	_blur.strength = _gate.take(wanted)


func _on_rebased(_offset: Vector3) -> void:
	_gate.note_rebase()


func _on_setting_changed(key: StringName, _value: Variant) -> void:
	if key == &"lens_flare" or key == &"motion_blur" or key == &"motion_blur_strength":
		apply_settings()


func _cmd_flare(args: Dictionary) -> ConsoleResult:
	return DebugConsole.registry.toggle("settings.lens_flare", args[&"state"])


func _cmd_blur(args: Dictionary) -> ConsoleResult:
	return DebugConsole.registry.toggle("settings.motion_blur", args[&"state"])
