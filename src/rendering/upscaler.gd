class_name Upscaler
extends Node
## Applies `settings.upscaler`, `upscale_preset`, `upscale_custom_scale` and `fsr_sharpness` to the viewport the game is drawn
## in, live (M4-T40, architecture §7.7): the 3D renders at the preset's share of the window's height and is enlarged to it; the
## HUD and text draw at the window's own size. While FSR 2.2 is on it holds the anti-aliasing mode off (FSR 2.2 anti-aliases
## and Godot turns TAA off under it anyway) and keeps the motion vectors on. A preset is a share of the window's height, so a
## resize keeps it.
##
## Console (§6.4): `upscale [upscaler] [preset|scale]` and provider `upscale`.

const KEYS: Array[StringName] = [&"upscaler", &"upscale_preset", &"upscale_custom_scale", &"fsr_sharpness"]

## The anti-aliasing node FSR 2.2 holds.
@export var anti_aliasing: AntiAliasing

var _plan: Dictionary = {}


func _ready() -> void:
	var viewport: Viewport = get_viewport()
	apply()
	Settings.changed.connect(_on_setting_changed)
	DebugConsole.registry.register_provider(&"upscale", ConsoleVars.new({
		&"upscaler": {"get": func() -> StringName: return StringName(Settings.get_value(&"upscaler")),
				"doc": "The upscaler setting (settings.upscaler)"},
		&"preset": {"get": func() -> StringName: return StringName(Settings.get_value(&"upscale_preset")),
				"doc": "The internal-resolution preset setting (settings.upscale_preset)"},
		&"applied": {"get": func() -> StringName: return _plan.get("upscaler", &""),
				"doc": "The upscaler in use"},
		&"applied_preset": {"get": func() -> StringName: return _plan.get("preset", &""),
				"doc": "The preset in use (native whatever the setting when the upscaler is native)"},
		&"scale": {"get": func() -> float: return snappedf(viewport.scaling_3d_scale, 0.0001),
				"doc": "The viewport's 3D scale, a share of the window's height"},
		&"mode": {"get": func() -> int: return viewport.scaling_3d_mode,
				"doc": "The viewport's scaling_3d_mode (0 bilinear, 1 FSR 1.0, 2 FSR 2.2)"},
		&"sharpness": {"get": func() -> float: return viewport.fsr_sharpness, "doc": "The viewport's fsr_sharpness"},
		&"window_lines": {"get": func() -> int: return _window_lines(), "doc": "The window's height in pixels"},
		&"internal_lines": {"get": func() -> int: return internal_lines(), "doc": "The lines the 3D renders"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"upscale",
			"Show or set the upscaler (%s) and the preset (%s) or a custom scale (%.2f to 1)" % [
				", ".join(PackedStringArray(Upscaling.UPSCALERS)), ", ".join(PackedStringArray(Upscaling.PRESETS)), Upscaling.MIN_SCALE],
			[ConsoleArg.enum_optional(&"upscaler", Upscaling.UPSCALERS), ConsoleArg.string_optional(&"preset")]), _cmd_upscale, self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)
	if Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.disconnect(_on_setting_changed)
	if anti_aliasing != null and is_instance_valid(anti_aliasing):
		anti_aliasing.set_held(false)


## The plan in use: the resolved upscaler and preset, the Godot mode and the scale (`Upscaling.plan`).
func current_plan() -> Dictionary:
	return _plan.duplicate()


## The lines the 3D renders in this window.
func internal_lines() -> int:
	return Upscaling.internal_lines(_window_lines(), get_viewport().scaling_3d_scale)


## Sets the viewport up for the settings.
func apply() -> void:
	_plan = Upscaling.plan(StringName(Settings.get_value(&"upscaler")), StringName(Settings.get_value(&"upscale_preset")),
			float(Settings.get_value(&"upscale_custom_scale")))
	Upscaling.apply(get_viewport(), _plan, float(Settings.get_value(&"fsr_sharpness")))
	if anti_aliasing != null:
		anti_aliasing.set_held(Upscaling.temporal(_plan["upscaler"]))


func _window_lines() -> int:
	return roundi(get_viewport().get_visible_rect().size.y)


func _on_setting_changed(key: StringName, _value: Variant) -> void:
	if KEYS.has(key):
		apply()


func _cmd_upscale(args: Dictionary) -> ConsoleResult:
	var upscaler: Variant = args[&"upscaler"]
	var preset: Variant = args[&"preset"]
	if upscaler == null:
		return ConsoleResult.line(_describe())
	var custom: float = -1.0
	if preset != null:
		var text: String = String(preset)
		if text.is_valid_float():
			custom = text.to_float()
			if custom < Upscaling.MIN_SCALE or custom > 1.0:
				return ConsoleResult.failure("a custom scale is %.2f to 1, got %s" % [Upscaling.MIN_SCALE, text])
		elif not Upscaling.PRESETS.has(StringName(text)):
			return ConsoleResult.failure("unknown preset '%s' (%s, or a scale)" % [text, ", ".join(PackedStringArray(Upscaling.PRESETS))])
	if custom > 0.0:
		Settings.set_value(&"upscale_custom_scale", custom)
		Settings.set_value(&"upscale_preset", Upscaling.CUSTOM)
	elif preset != null:
		Settings.set_value(&"upscale_preset", StringName(preset))
	if Settings.set_value(&"upscaler", StringName(upscaler)) != OK:
		return ConsoleResult.failure(Settings.get_last_error())
	return ConsoleResult.line(_describe())


func _describe() -> String:
	return "upscaler = %s, preset = %s (applied: %s at %s, scale %.4f, %d of %d lines, sharpness %.2f)" % [
			Settings.get_value(&"upscaler"), Settings.get_value(&"upscale_preset"), _plan.get("upscaler", &""),
			_plan.get("preset", &""), get_viewport().scaling_3d_scale, internal_lines(), _window_lines(), get_viewport().fsr_sharpness]
