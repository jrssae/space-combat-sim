class_name AntiAliasing
extends Node
## Applies `settings.anti_aliasing` to the viewport the game is drawn in, live (M4-T38, architecture §7.6). Under TAA it
## also turns on what reprojection needs: the sky's motion vectors (`SkyVelocityEffect`) and bolts that write their own
## (`BoltMesh.set_motion_vectors`); any other mode turns them off, so they cost nothing.
##
## Console (§6.4): `aa [mode]` and provider `aa`.

## The environment whose Compositor holds the sky effect.
@export var world_environment: WorldEnvironment

var _sky: SkyVelocityEffect
var _mode: StringName = AntiAliasingMode.OFF


func _ready() -> void:
	_sky = _find_sky()
	apply_mode(StringName(Settings.get_value(&"anti_aliasing")))
	Settings.changed.connect(_on_setting_changed)
	var viewport: Viewport = get_viewport()
	DebugConsole.registry.register_provider(&"aa", ConsoleVars.new({
		&"mode": {"get": func() -> StringName: return _mode, "doc": "The anti-aliasing mode applied (settings.anti_aliasing)"},
		&"viewport": {"get": func() -> StringName: return AntiAliasingMode.read(viewport),
				"doc": "The mode the viewport's own switches say, custom if something else changed them"},
		&"sky_vectors": {"get": func() -> bool: return _sky != null and _sky.enabled,
				"doc": "The sky's motion vectors are written (on under TAA)"},
		&"bolts_opaque": {"get": func() -> bool: return BoltMesh.motion_vectors(),
				"doc": "Bolts draw opaque and write their motion (on under TAA)"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"aa",
			"Show or set the anti-aliasing mode (%s)" % ", ".join(PackedStringArray(AntiAliasingMode.MODES)),
			[ConsoleArg.enum_optional(&"mode", AntiAliasingMode.MODES)]), _cmd_aa, self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)
	if Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.disconnect(_on_setting_changed)


func sky_effect() -> SkyVelocityEffect:
	return _sky


## Sets the viewport and the motion-vector switches up for `mode`.
func apply_mode(mode: StringName) -> void:
	_mode = mode if AntiAliasingMode.MODES.has(mode) else AntiAliasingMode.OFF
	AntiAliasingMode.apply(get_viewport(), _mode)
	var vectors: bool = AntiAliasingMode.wants_motion_vectors(_mode)
	if _sky != null:
		_sky.enabled = vectors
	BoltMesh.set_motion_vectors(vectors)


func _find_sky() -> SkyVelocityEffect:
	var compositor: Compositor = world_environment.compositor if world_environment != null else null
	if compositor == null:
		return null
	for effect: CompositorEffect in compositor.compositor_effects:
		if effect is SkyVelocityEffect:
			return effect as SkyVelocityEffect
	return null


func _on_setting_changed(key: StringName, value: Variant) -> void:
	if key == &"anti_aliasing":
		apply_mode(StringName(value))


func _cmd_aa(args: Dictionary) -> ConsoleResult:
	var mode: Variant = args[&"mode"]
	if mode == null:
		return ConsoleResult.line("anti_aliasing = %s (%s)" % [_mode, ", ".join(PackedStringArray(AntiAliasingMode.MODES))])
	if Settings.set_value(&"anti_aliasing", StringName(mode)) != OK:
		return ConsoleResult.failure(Settings.get_last_error())
	return ConsoleResult.line("anti_aliasing = %s" % _mode)
